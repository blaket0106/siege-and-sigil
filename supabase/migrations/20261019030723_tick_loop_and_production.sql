alter table public.game_players add column prestige_accum float8 not null default 0 check (prestige_accum >= 0);

create function public.king_floor(p_player_id int, p_ability text)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_ability in ('muster', 'steward', 'scholar', 'pace', 'scout', 'plunder') then coalesce((
      select greatest(kca.level - 1, 0)
      from public.commanders k
      join public.games g on g.id = k.game_id
      join public.commander_abilities kca on kca.commander_id = k.id and kca.ability = p_ability
      where k.owner_player_id = p_player_id
        and k.role = 'king'
        and k.status <> 'dead'
        and (k.coronation_tick is null or k.coronation_tick <= g.current_tick)
      limit 1
    ), 0)
    else 0
  end;
$$;

create or replace function public.ability_level(p_commander_id int, p_ability text)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select greatest(
    coalesce((
      select ca.level
      from public.commander_abilities ca
      where ca.commander_id = p_commander_id and ca.ability = p_ability
    ), 0),
    coalesce((
      select public.king_floor(c.owner_player_id, p_ability)
      from public.commanders c
      where c.id = p_commander_id
    ), 0)
  );
$$;

create function public.territory_ability(p_territory_id int, p_ability text)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select greatest(
    coalesce((
      select ca.level
      from public.game_territories gt
      join public.commanders c on c.id = gt.garrison_commander_id and c.status <> 'dead'
      join public.commander_abilities ca on ca.commander_id = c.id and ca.ability = p_ability
      where gt.id = p_territory_id
    ), 0),
    coalesce((
      select public.king_floor(gt.owner_player_id, p_ability)
      from public.game_territories gt
      where gt.id = p_territory_id and gt.owner_player_id is not null
    ), 0)
  );
$$;

create function public.record_intel_snapshot(p_game_id int)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.intel_snapshots (game_id, tick, payload)
  select
    g.id,
    g.current_tick,
    jsonb_build_object('players', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'player_id', gp.id,
          'territories', (select count(*) from public.game_territories gt where gt.owner_player_id = gp.id),
          'gold', gp.gold,
          'garrison_troops', (select coalesce(sum(gt.troops), 0) from public.game_territories gt where gt.owner_player_id = gp.id),
          'commander_troops', (select coalesce(sum(c.troops), 0) from public.commanders c where c.owner_player_id = gp.id and c.status <> 'dead'),
          'commanders', (select count(*) from public.commanders c where c.owner_player_id = gp.id and c.status <> 'dead'),
          'gold_levels', (select coalesce(sum(gt.gold_level), 0) from public.game_territories gt where gt.owner_player_id = gp.id),
          'industry_levels', (select coalesce(sum(gt.industry_level), 0) from public.game_territories gt where gt.owner_player_id = gp.id),
          'prestige_levels', (select coalesce(sum(gt.prestige_level), 0) from public.game_territories gt where gt.owner_player_id = gp.id),
          'areas', (select coalesce(jsonb_object_agg(ra.area, ra.level), '{}'::jsonb) from public.realm_areas ra where ra.player_id = gp.id)
        )
        order by gp.id
      )
      from public.game_players gp
      where gp.game_id = g.id
    ), '[]'::jsonb))
  from public.games g
  where g.id = p_game_id
  on conflict (game_id, tick) do nothing;
$$;

create function public.run_tick(p_game_id int)
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

  return jsonb_build_object('tick', v_tick, 'troops_added', v_troops, 'gold_added', v_gold, 'cycle', v_cycle);
end;
$$;

create function public.process_game(p_game_id int)
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
  v_ready boolean;
begin
  select * into v_game from public.games where id = p_game_id for update;
  if not found or v_game.status <> 'active' then
    return jsonb_build_object('pending_ticks', 0, 'ticks_processed', 0, 'gold_added', 0, 'troops_added', 0, 'cycles_fired', 0, 'combats', 0, 'combat_events', '[]'::jsonb);
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
    'combats', 0,
    'combat_events', '[]'::jsonb
  );
end;
$$;

create function public.process_ticks(p_game_id int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'not signed in';
  end if;
  if not public.is_game_member(p_game_id) then
    raise exception 'you are not in this game';
  end if;
  return public.process_game(p_game_id);
end;
$$;

create function public.process_due_games()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_g record;
  v_count int := 0;
begin
  for v_g in
    select g.id
    from public.games g
    where g.status = 'active'
      and (
        (g.tick_speed <> 'turn_based' and g.last_tick_processed_at
          + make_interval(secs => case g.tick_speed when 'slow' then 7200 when 'normal' then 3600 when 'fast' then 1800 else 900 end) <= now())
        or (g.tick_speed = 'turn_based' and g.current_turn_ends_at <= now())
      )
    order by g.id
  loop
    begin
      perform public.process_game(v_g.id);
      v_count := v_count + 1;
    exception when others then
      insert into public.game_events (game_id, tick, type, payload)
      select v_g.id, current_tick, 'tick_error', jsonb_build_object('message', sqlerrm)
      from public.games where id = v_g.id;
    end;
  end loop;
  return v_count;
end;
$$;

create function public.submit_turn(p_game_id int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.game_players;
  v_speed text;
  v_all boolean;
  v_result jsonb;
begin
  v_player := public.acting_player(p_game_id);

  select tick_speed into v_speed from public.games where id = p_game_id;
  if v_speed <> 'turn_based' then
    raise exception 'this game is not turn based';
  end if;

  update public.game_players set turn_submitted = true where id = v_player.id;

  v_all := not exists (
    select 1 from public.game_players gp
    where gp.game_id = p_game_id and not gp.is_ai and gp.eliminated_at_tick is null and not gp.turn_submitted
  );

  if v_all then
    v_result := public.process_game(p_game_id);
  end if;

  return jsonb_build_object('all_submitted', v_all, 'processed', coalesce(v_result, '{}'::jsonb));
end;
$$;

revoke execute on function public.king_floor(int, text) from public, anon, authenticated;
revoke execute on function public.ability_level(int, text) from public, anon, authenticated;
revoke execute on function public.territory_ability(int, text) from public, anon, authenticated;
revoke execute on function public.record_intel_snapshot(int) from public, anon, authenticated;
revoke execute on function public.run_tick(int) from public, anon, authenticated;
revoke execute on function public.process_game(int) from public, anon, authenticated;
revoke execute on function public.process_due_games() from public, anon, authenticated;

revoke execute on function public.process_ticks(int) from public, anon;
grant execute on function public.process_ticks(int) to authenticated;
revoke execute on function public.submit_turn(int) from public, anon;
grant execute on function public.submit_turn(int) to authenticated;
