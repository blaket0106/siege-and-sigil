create function public.armory_level(p_player_id int)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select level from public.realm_areas where player_id = p_player_id and area = 'armory'
  ), 1);
$$;

create function public.side_valor(p_commander_ids int[], p_garrison_commander_id int)
returns int
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_leader int;
  v_leader_valor int := 0;
  v_king_valor int := 0;
begin
  if p_commander_ids is null or array_length(p_commander_ids, 1) is null then
    return 0;
  end if;

  select c.id into v_leader
  from public.commanders c
  where c.id = any (p_commander_ids)
  order by
    (c.id = p_garrison_commander_id) desc nulls last,
    (select coalesce(sum(ca.level), 0) from public.commander_abilities ca where ca.commander_id = c.id) desc,
    (c.role = 'king') desc,
    c.id
  limit 1;

  select coalesce(ca.level, 0) into v_leader_valor
  from public.commander_abilities ca
  where ca.commander_id = v_leader and ca.ability = 'valor';

  select coalesce(max(ca.level), 0) into v_king_valor
  from public.commanders k
  join public.games g on g.id = k.game_id
  join public.commander_abilities ca on ca.commander_id = k.id and ca.ability = 'valor'
  where k.id = any (p_commander_ids)
    and k.role = 'king'
    and (k.coronation_tick is null or k.coronation_tick <= g.current_tick);

  return greatest(coalesce(v_leader_valor, 0), v_king_valor);
end;
$$;

create function public.split_survivors(p_total int, p_weights int[])
returns int[]
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_sum int;
  v_out int[] := '{}';
  v_i int;
  v_alloc int := 0;
  v_max int := 1;
begin
  if p_weights is null or array_length(p_weights, 1) is null then
    return '{}';
  end if;
  select coalesce(sum(w), 0) into v_sum from unnest(p_weights) as w;
  if v_sum = 0 then
    return array_fill(0, array[array_length(p_weights, 1)]);
  end if;
  for v_i in 1 .. array_length(p_weights, 1) loop
    v_out := v_out || floor(p_total::float8 * p_weights[v_i] / v_sum)::int;
    v_alloc := v_alloc + v_out[v_i];
    if p_weights[v_i] > p_weights[v_max] then
      v_max := v_i;
    end if;
  end loop;
  v_out[v_max] := v_out[v_max] + (p_total - v_alloc);
  return v_out;
end;
$$;

create function public.kill_commanders(p_game_id int, p_ids int[], p_tick int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_ids is null or array_length(p_ids, 1) is null then
    return;
  end if;

  insert into public.game_moments (game_id, tick, type, payload)
  select p_game_id, p_tick, 'king_killed',
         jsonb_build_object('commander_id', c.id, 'name', c.name, 'player_id', c.owner_player_id)
  from public.commanders c
  where c.id = any (p_ids) and c.role = 'king' and c.status <> 'dead';

  update public.commanders
  set status = 'dead', died_tick = p_tick, troops = 0, current_territory_id = null
  where id = any (p_ids) and status <> 'dead';

  delete from public.commander_movements where commander_id = any (p_ids);

  update public.commander_routes set status = 'aborted'
  where commander_id = any (p_ids) and status in ('active', 'recalled');

  update public.game_territories set garrison_commander_id = null
  where garrison_commander_id = any (p_ids);
end;
$$;

create function public.resolve_assault(p_game_id int, p_territory_id int, p_player_id int, p_tick int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_t public.game_territories%rowtype;
  v_owner int;
  v_att_ids int[];
  v_def_ids int[] := '{}';
  v_att_troops int;
  v_def_troops int;
  v_gar int;
  v_att_armory int;
  v_def_armory int;
  v_att_valor int;
  v_def_valor int;
  v_atk int;
  v_def int;
  v_ra int;
  v_rd int;
  v_attacker_wins boolean;
  v_surv int;
  v_alloc int[];
  v_weights int[];
  v_cid int;
  v_i int;
  v_plunder int := 0;
  v_salvage int := 0;
  v_old_gold_level int;
begin
  select * into v_t from public.game_territories where id = p_territory_id for update;
  v_owner := v_t.owner_player_id;

  select array_agg(m.commander_id order by m.id) into v_att_ids
  from public.commander_movements m
  join public.commanders c on c.id = m.commander_id
  where m.game_id = p_game_id
    and m.contact_territory_id = p_territory_id
    and m.march_type = 'assault'
    and c.owner_player_id = p_player_id;

  if v_att_ids is null then
    return null;
  end if;

  if public.is_friendly_territory(p_player_id, p_territory_id) then
    foreach v_cid in array v_att_ids loop
      update public.commanders set status = 'idle', current_territory_id = p_territory_id where id = v_cid;
      delete from public.commander_movements where commander_id = v_cid;
      perform public.continue_route(v_cid, p_territory_id);
    end loop;
    return jsonb_build_object('territory_id', p_territory_id, 'arrived', true);
  end if;

  select coalesce(sum(troops), 0) into v_att_troops from public.commanders where id = any (v_att_ids);

  if v_owner is not null then
    select coalesce(array_agg(c.id order by c.id), '{}') into v_def_ids
    from public.commanders c
    where c.current_territory_id = p_territory_id
      and c.status = 'idle'
      and (c.owner_player_id = v_owner or public.are_allied(v_owner, c.owner_player_id));
  end if;

  v_gar := v_t.troops;
  select v_gar + coalesce(sum(troops), 0) into v_def_troops from public.commanders where id = any (v_def_ids);

  v_att_armory := public.armory_level(p_player_id);
  v_def_armory := case
    when v_owner is null then 1
    else greatest(
      public.armory_level(v_owner),
      coalesce((select max(public.armory_level(c.owner_player_id)) from public.commanders c where c.id = any (v_def_ids)), 0)
    )
  end;
  v_att_valor := public.side_valor(v_att_ids, null);
  v_def_valor := public.side_valor(v_def_ids, v_t.garrison_commander_id);
  v_atk := greatest(1, v_att_armory + v_att_valor);
  v_def := greatest(1, v_def_armory + v_def_valor + 1);

  if v_def_troops = 0 then
    v_attacker_wins := true;
    v_surv := v_att_troops;
  elsif v_att_troops = 0 then
    v_attacker_wins := false;
    v_surv := v_def_troops;
  else
    v_ra := ceil(v_att_troops::float8 / v_def)::int;
    v_rd := ceil(v_def_troops::float8 / v_atk)::int;
    if v_ra <= v_rd then
      v_attacker_wins := false;
      v_surv := v_def_troops - (v_ra - 1) * v_atk;
    else
      v_attacker_wins := true;
      v_surv := v_att_troops - v_rd * v_def;
    end if;
  end if;

  if v_attacker_wins then
    select array_agg(c.troops order by u.ord) into v_weights
    from unnest(v_att_ids) with ordinality as u(id, ord)
    join public.commanders c on c.id = u.id;
    v_alloc := public.split_survivors(v_surv, v_weights);

    select coalesce(max(public.ability_level(x, 'plunder')), 0) into v_plunder from unnest(v_att_ids) as x;
    v_old_gold_level := v_t.gold_level;
    v_salvage := floor(10 * v_old_gold_level * (1 + 0.25 * v_plunder))::int;

    perform public.kill_commanders(p_game_id, v_def_ids, p_tick);

    update public.game_territories
    set owner_player_id = p_player_id,
        troops = 0,
        troop_accum = 0,
        gold_level = 0,
        garrison_commander_id = null
    where id = p_territory_id;

    perform public.refresh_effective_influence(p_game_id, p_player_id);
    if v_owner is not null then
      perform public.refresh_effective_influence(p_game_id, v_owner);
    end if;

    if v_salvage > 0 then
      update public.game_players set gold = gold + v_salvage where id = p_player_id;
      insert into public.ledger (game_id, player_id, tick, type, amount)
      values (p_game_id, p_player_id, p_tick, 'salvage', v_salvage);
    end if;

    for v_i in 1 .. array_length(v_att_ids, 1) loop
      update public.commanders
      set troops = v_alloc[v_i], status = 'idle', current_territory_id = p_territory_id
      where id = v_att_ids[v_i];
      delete from public.commander_movements where commander_id = v_att_ids[v_i];
    end loop;

    insert into public.game_moments (game_id, tick, type, payload)
    values (
      p_game_id, p_tick, 'castle_captured',
      jsonb_build_object('territory_id', p_territory_id, 'territory', v_t.name, 'from_player_id', v_owner, 'to_player_id', p_player_id)
    );

    foreach v_cid in array v_att_ids loop
      perform public.continue_route(v_cid, p_territory_id);
    end loop;
  else
    perform public.kill_commanders(p_game_id, v_att_ids, p_tick);

    select array_agg(w order by ord) into v_weights
    from (
      select 0 as ord, v_gar as w
      union all
      select u.ord, c.troops
      from unnest(v_def_ids) with ordinality as u(id, ord)
      join public.commanders c on c.id = u.id
    ) parts;
    v_alloc := public.split_survivors(v_surv, v_weights);

    update public.game_territories set troops = v_alloc[1] where id = p_territory_id;
    for v_i in 1 .. coalesce(array_length(v_def_ids, 1), 0) loop
      update public.commanders set troops = v_alloc[v_i + 1] where id = v_def_ids[v_i];
    end loop;
  end if;

  insert into public.game_events (game_id, tick, type, payload)
  values (
    p_game_id, p_tick, 'battle',
    jsonb_build_object(
      'territory_id', p_territory_id,
      'attacker_player_id', p_player_id,
      'defender_player_id', v_owner,
      'attacker_troops', v_att_troops,
      'defender_troops', v_def_troops,
      'attacker_damage', v_atk,
      'defender_damage', v_def,
      'winner', case when v_attacker_wins then 'attacker' else 'defender' end,
      'survivors', v_surv,
      'salvage', v_salvage
    )
  );

  insert into public.player_inbox (game_id, player_id, type, title, body, tick)
  select p_game_id, pid, 'combat',
         'Battle at ' || v_t.name || ': ' ||
           case when (pid = p_player_id) = v_attacker_wins then 'victory' else 'defeat' end,
         jsonb_build_object(
           'territory_id', p_territory_id,
           'territory', v_t.name,
           'role', case when pid = p_player_id then 'attacker' else 'defender' end,
           'attacker_troops', v_att_troops,
           'defender_troops', v_def_troops,
           'attacker_damage', v_atk,
           'defender_damage', v_def,
           'winner', case when v_attacker_wins then 'attacker' else 'defender' end,
           'survivors', v_surv,
           'captured', v_attacker_wins,
           'salvage', case when pid = p_player_id then v_salvage else 0 end
         ),
         p_tick
  from (select p_player_id as pid union select v_owner where v_owner is not null) as involved;

  return jsonb_build_object(
    'territory_id', p_territory_id,
    'attacker_player_id', p_player_id,
    'defender_player_id', v_owner,
    'winner', case when v_attacker_wins then 'attacker' else 'defender' end,
    'captured', v_attacker_wins,
    'survivors', v_surv,
    'salvage', v_salvage
  );
end;
$$;

create function public.resolve_contacts(p_game_id int, p_tick int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_x int;
  v_player int;
  v_res jsonb;
  v_events jsonb := '[]'::jsonb;
  v_battles int := 0;
  v_captures int := 0;
  v_guard int := 0;
begin
  loop
    v_guard := v_guard + 1;
    exit when v_guard > 500;

    select m.contact_territory_id, c.owner_player_id into v_x, v_player
    from public.commander_movements m
    join public.commanders c on c.id = m.commander_id
    where m.game_id = p_game_id
      and m.contact_territory_id is not null
      and m.march_type = 'assault'
      and not (
        public.is_friendly_territory(c.owner_player_id, m.contact_territory_id)
        and public.has_hostile_siege(c.owner_player_id, m.contact_territory_id)
      )
    order by m.arrival_tick, m.id
    limit 1;
    exit when not found;

    v_res := public.resolve_assault(p_game_id, v_x, v_player, p_tick);
    exit when v_res is null;

    if v_res ->> 'winner' is not null then
      v_battles := v_battles + 1;
      if (v_res ->> 'captured')::boolean then
        v_captures := v_captures + 1;
      end if;
      v_events := v_events || jsonb_build_array(v_res);
    end if;
  end loop;

  return jsonb_build_object('combats', v_battles, 'captures', v_captures, 'combat_events', v_events);
end;
$$;

create function public.resolve_tick_events(p_game_id int, p_tick int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_moves jsonb;
  v_combat jsonb;
begin
  v_moves := public.advance_movements(p_game_id, p_tick);
  v_combat := public.resolve_contacts(p_game_id, p_tick);
  return v_moves || v_combat;
end;
$$;

create or replace function public.run_tick(p_game_id int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_game public.games%rowtype;
  v_tick int;
  v_cycle boolean;
  v_troops int := 0;
  v_gold int := 0;
  v_p record;
  v_amount int;
  v_area text;
  v_events jsonb;
begin
  update public.games set current_tick = current_tick + 1 where id = p_game_id returning * into v_game;
  v_tick := v_game.current_tick;
  v_cycle := v_tick % v_game.production_cycle_ticks = 0;

  with rate as (
    select
      gt.id,
      gt.troop_accum
        + gt.industry_level * (coalesce(ra.level, 1) + 4)
          * (1 + 0.10 * public.territory_ability(gt.id, 'muster'))
          / v_game.production_cycle_ticks as total
    from public.game_territories gt
    left join public.realm_areas ra on ra.player_id = gt.owner_player_id and ra.area = 'barracks'
    where gt.game_id = p_game_id and gt.owner_player_id is not null
  ), upd as (
    update public.game_territories gt
    set troops = gt.troops + floor(r.total)::int,
        troop_accum = r.total - floor(r.total)
    from rate r
    where gt.id = r.id
    returning floor(r.total)::int as added
  )
  select coalesce(sum(added), 0) into v_troops from upd;

  for v_p in
    select
      gp.id as player_id,
      gp.prestige_accum
        + coalesce(sum(gt.prestige_level * (1 + 0.10 * public.territory_ability(gt.id, 'scholar'))), 0) as total
    from public.game_players gp
    left join public.game_territories gt on gt.owner_player_id = gp.id
    where gp.game_id = p_game_id and gp.eliminated_at_tick is null
    group by gp.id, gp.prestige_accum
  loop
    v_amount := floor(v_p.total)::int;
    update public.game_players set prestige_accum = v_p.total - v_amount where id = v_p.player_id;
    if v_amount > 0 then
      select area into v_area from public.realm_areas where player_id = v_p.player_id and is_active;
      perform public.add_area_prestige(p_game_id, v_p.player_id, coalesce(v_area, 'armory'), v_amount);
    end if;
  end loop;

  if v_cycle then
    for v_p in
      select
        gp.id as player_id,
        floor(coalesce(sum(
          gt.gold_level * (10 + 2 * coalesce(mint.level, 1))
          * (1 + 0.10 * public.territory_ability(gt.id, 'steward'))
        ), 0))::int as gold
      from public.game_players gp
      left join public.realm_areas mint on mint.player_id = gp.id and mint.area = 'mint'
      left join public.game_territories gt on gt.owner_player_id = gp.id
      where gp.game_id = p_game_id and gp.eliminated_at_tick is null
      group by gp.id, mint.level
    loop
      if v_p.gold > 0 then
        update public.game_players set gold = gold + v_p.gold where id = v_p.player_id;
        insert into public.ledger (game_id, player_id, tick, type, amount)
        values (p_game_id, v_p.player_id, v_tick, 'production', v_p.gold);
        v_gold := v_gold + v_p.gold;
      end if;
    end loop;

    for v_p in
      select ra.player_id, ra.level
      from public.realm_areas ra
      join public.game_players gp on gp.id = ra.player_id
      where ra.game_id = p_game_id and ra.area = 'library' and gp.eliminated_at_tick is null
    loop
      select area into v_area
      from public.realm_areas
      where player_id = v_p.player_id and not is_active
      order by random()
      limit 1;
      if v_area is not null then
        perform public.add_area_prestige(p_game_id, v_p.player_id, v_area, 72 * v_p.level);
      end if;
    end loop;

    perform public.record_intel_snapshot(p_game_id);
  end if;

  v_events := public.resolve_tick_events(p_game_id, v_tick);

  return jsonb_build_object(
    'tick', v_tick,
    'troops_added', v_troops,
    'gold_added', v_gold,
    'cycle', v_cycle
  ) || v_events;
end;
$$;

create or replace function public.process_game(p_game_id int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_game public.games%rowtype;
  v_interval int;
  v_pending int := 0;
  v_n int := 0;
  v_i int;
  v_res jsonb;
  v_gold int := 0;
  v_troops int := 0;
  v_cycles int := 0;
  v_arrivals int := 0;
  v_contacts int := 0;
  v_combats int := 0;
  v_combat_events jsonb := '[]'::jsonb;
  v_ready boolean;
begin
  select * into v_game from public.games where id = p_game_id for update;
  if not found or v_game.status <> 'active' then
    return jsonb_build_object('pending_ticks', 0, 'ticks_processed', 0, 'gold_added', 0, 'troops_added', 0, 'cycles_fired', 0, 'arrivals', 0, 'contacts', 0, 'combats', 0, 'combat_events', '[]'::jsonb);
  end if;

  if v_game.tick_speed = 'turn_based' then
    v_ready := not exists (
      select 1 from public.game_players gp
      where gp.game_id = p_game_id and not gp.is_ai and gp.eliminated_at_tick is null and not gp.turn_submitted
    ) or (v_game.current_turn_ends_at is not null and now() >= v_game.current_turn_ends_at);
    v_pending := case when v_ready then v_game.ticks_per_turn else 0 end;
    v_n := v_pending;
  else
    v_interval := case v_game.tick_speed when 'slow' then 7200 when 'normal' then 3600 when 'fast' then 1800 else 900 end;
    v_pending := greatest(floor(extract(epoch from (now() - v_game.last_tick_processed_at)) / v_interval)::int, 0);
    v_n := least(v_pending, 200);
  end if;

  for v_i in 1 .. v_n loop
    v_res := public.run_tick(p_game_id);
    v_gold := v_gold + (v_res ->> 'gold_added')::int;
    v_troops := v_troops + (v_res ->> 'troops_added')::int;
    v_arrivals := v_arrivals + (v_res ->> 'arrivals')::int;
    v_contacts := v_contacts + (v_res ->> 'contacts')::int;
    v_combats := v_combats + (v_res ->> 'combats')::int;
    v_combat_events := v_combat_events || (v_res -> 'combat_events');
    if (v_res ->> 'cycle')::boolean then
      v_cycles := v_cycles + 1;
    end if;
  end loop;

  if v_n > 0 then
    if v_game.tick_speed = 'turn_based' then
      update public.game_players set turn_submitted = false where game_id = p_game_id;
      update public.games
      set last_tick_processed_at = now(),
          current_turn_ends_at = now() + make_interval(mins => turn_timeout_minutes)
      where id = p_game_id;
    else
      update public.games
      set last_tick_processed_at = last_tick_processed_at + make_interval(secs => v_n * v_interval)
      where id = p_game_id;
    end if;
  end if;

  return jsonb_build_object(
    'pending_ticks', v_pending,
    'ticks_processed', v_n,
    'gold_added', v_gold,
    'troops_added', v_troops,
    'cycles_fired', v_cycles,
    'arrivals', v_arrivals,
    'contacts', v_contacts,
    'combats', v_combats,
    'combat_events', v_combat_events
  );
end;
$$;

revoke execute on function public.armory_level(int) from public, anon, authenticated;
revoke execute on function public.side_valor(int[], int) from public, anon, authenticated;
revoke execute on function public.split_survivors(int, int[]) from public, anon, authenticated;
revoke execute on function public.kill_commanders(int, int[], int) from public, anon, authenticated;
revoke execute on function public.resolve_assault(int, int, int, int) from public, anon, authenticated;
revoke execute on function public.resolve_contacts(int, int) from public, anon, authenticated;
revoke execute on function public.resolve_tick_events(int, int) from public, anon, authenticated;
revoke execute on function public.run_tick(int) from public, anon, authenticated;
revoke execute on function public.process_game(int) from public, anon, authenticated;
