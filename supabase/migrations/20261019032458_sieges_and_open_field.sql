alter table public.game_territories add column starve_accum float8 not null default 0 check (starve_accum >= 0);

create function public.side_ability(p_commander_ids int[], p_garrison_commander_id int, p_ability text)
returns int
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_leader int;
  v_leader_level int := 0;
  v_king_level int := 0;
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

  select coalesce(ca.level, 0) into v_leader_level
  from public.commander_abilities ca
  where ca.commander_id = v_leader and ca.ability = p_ability;

  select coalesce(max(ca.level), 0) into v_king_level
  from public.commanders k
  join public.games g on g.id = k.game_id
  join public.commander_abilities ca on ca.commander_id = k.id and ca.ability = p_ability
  where k.id = any (p_commander_ids)
    and k.role = 'king'
    and (k.coronation_tick is null or k.coronation_tick <= g.current_tick);

  return greatest(coalesce(v_leader_level, 0), v_king_level);
end;
$$;

create function public.side_best_realm(p_commander_ids int[], p_area text)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(max(coalesce(ra.level, 1)), 1)
  from public.commanders c
  left join public.realm_areas ra on ra.player_id = c.owner_player_id and ra.area = p_area
  where c.id = any (p_commander_ids);
$$;

create function public.hostile_siegers(p_player_id int, p_territory_id int)
returns int[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(c.id order by c.id), '{}')
  from public.commanders c
  where c.current_territory_id = p_territory_id
    and c.status = 'sieging'
    and (
      p_player_id is null
      or (c.owner_player_id <> p_player_id and not public.are_allied(p_player_id, c.owner_player_id))
    );
$$;

create function public.duel(p_first_troops int, p_first_dmg int, p_second_troops int, p_second_dmg int)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_fd int := greatest(p_first_dmg, 1);
  v_sd int := greatest(p_second_dmg, 1);
  v_rf int;
  v_rs int;
begin
  if p_second_troops <= 0 then
    return jsonb_build_object('first_wins', true, 'survivors', p_first_troops);
  end if;
  if p_first_troops <= 0 then
    return jsonb_build_object('first_wins', false, 'survivors', p_second_troops);
  end if;
  v_rf := ceil(p_second_troops::float8 / v_fd)::int;
  v_rs := ceil(p_first_troops::float8 / v_sd)::int;
  if v_rf <= v_rs then
    return jsonb_build_object('first_wins', true, 'survivors', p_first_troops - (v_rf - 1) * v_sd);
  end if;
  return jsonb_build_object('first_wins', false, 'survivors', p_second_troops - v_rs * v_fd);
end;
$$;

create function public.open_field_outcome(
  p_a_troops int, p_a_dmg int, p_a_init int,
  p_b_troops int, p_b_dmg int, p_b_init int,
  p_tie_first text
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_first text;
  v_r jsonb;
  v_winner text;
begin
  v_first := case
    when p_a_init > p_b_init then 'a'
    when p_b_init > p_a_init then 'b'
    else p_tie_first
  end;
  if v_first = 'a' then
    v_r := public.duel(p_a_troops, p_a_dmg, p_b_troops, p_b_dmg);
    v_winner := case when (v_r ->> 'first_wins')::boolean then 'a' else 'b' end;
  else
    v_r := public.duel(p_b_troops, p_b_dmg, p_a_troops, p_a_dmg);
    v_winner := case when (v_r ->> 'first_wins')::boolean then 'b' else 'a' end;
  end if;
  return jsonb_build_object('winner', v_winner, 'survivors', (v_r ->> 'survivors')::int, 'first', v_first);
end;
$$;

create function public.notify_players(p_game_id int, p_tick int, p_players int[], p_title text, p_body jsonb)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.player_inbox (game_id, player_id, type, title, body, tick)
  select p_game_id, p, 'combat', p_title, p_body, p_tick
  from (select distinct unnest(p_players) as p) x
  where p is not null;
$$;

create function public.fight_castle(p_game_id int, p_territory_id int, p_player_id int, p_att_ids int[], p_tick int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_t public.game_territories%rowtype;
  v_owner int;
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
begin
  select * into v_t from public.game_territories where id = p_territory_id for update;
  v_owner := v_t.owner_player_id;

  select coalesce(sum(troops), 0) into v_att_troops from public.commanders where id = any (p_att_ids);

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
  v_att_valor := public.side_valor(p_att_ids, null);
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
    from unnest(p_att_ids) with ordinality as u(id, ord)
    join public.commanders c on c.id = u.id;
    v_alloc := public.split_survivors(v_surv, v_weights);

    select coalesce(max(public.ability_level(x, 'plunder')), 0) into v_plunder from unnest(p_att_ids) as x;
    v_salvage := floor(10 * v_t.gold_level * (1 + 0.25 * v_plunder))::int;

    perform public.kill_commanders(p_game_id, v_def_ids, p_tick);

    update public.game_territories
    set owner_player_id = p_player_id,
        troops = 0,
        troop_accum = 0,
        starve_accum = 0,
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

    for v_i in 1 .. array_length(p_att_ids, 1) loop
      update public.commanders
      set troops = v_alloc[v_i], status = 'idle', current_territory_id = p_territory_id
      where id = p_att_ids[v_i];
      delete from public.commander_movements where commander_id = p_att_ids[v_i];
    end loop;

    insert into public.game_moments (game_id, tick, type, payload)
    values (
      p_game_id, p_tick, 'castle_captured',
      jsonb_build_object('territory_id', p_territory_id, 'territory', v_t.name, 'from_player_id', v_owner, 'to_player_id', p_player_id)
    );

    foreach v_cid in array p_att_ids loop
      perform public.continue_route(v_cid, p_territory_id);
    end loop;
  else
    perform public.kill_commanders(p_game_id, p_att_ids, p_tick);

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

create or replace function public.resolve_assault(p_game_id int, p_territory_id int, p_player_id int, p_tick int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_att_ids int[];
  v_cid int;
begin
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

  return public.fight_castle(p_game_id, p_territory_id, p_player_id, v_att_ids, p_tick);
end;
$$;

create function public.begin_siege(p_game_id int, p_territory_id int, p_player_id int, p_tick int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ids int[];
  v_owner int;
  v_name text;
begin
  select array_agg(m.commander_id order by m.id) into v_ids
  from public.commander_movements m
  join public.commanders c on c.id = m.commander_id
  where m.game_id = p_game_id
    and m.contact_territory_id = p_territory_id
    and m.march_type = 'siege'
    and c.owner_player_id = p_player_id;
  if v_ids is null then
    return null;
  end if;

  select owner_player_id, name into v_owner, v_name from public.game_territories where id = p_territory_id;

  update public.commanders set status = 'sieging', current_territory_id = p_territory_id where id = any (v_ids);
  delete from public.commander_movements where commander_id = any (v_ids);
  update public.commander_routes set status = 'completed' where commander_id = any (v_ids) and status = 'active';

  insert into public.game_events (game_id, tick, type, payload)
  values (p_game_id, p_tick, 'siege_started', jsonb_build_object('territory_id', p_territory_id, 'player_id', p_player_id, 'commanders', to_jsonb(v_ids)));
  insert into public.game_moments (game_id, tick, type, payload)
  values (p_game_id, p_tick, 'siege_started', jsonb_build_object('territory_id', p_territory_id, 'territory', v_name, 'by_player_id', p_player_id, 'owner_player_id', v_owner));

  perform public.notify_players(
    p_game_id, p_tick, array[v_owner, p_player_id],
    v_name || ' is under siege',
    jsonb_build_object('kind', 'siege_started', 'territory_id', p_territory_id, 'territory', v_name, 'by_player_id', p_player_id)
  );

  return jsonb_build_object('siege_started', true, 'territory_id', p_territory_id, 'player_id', p_player_id);
end;
$$;

create function public.resolve_relief(p_game_id int, p_territory_id int, p_player_id int, p_tick int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_arr int[];
  v_sg int[];
  v_owner int;
  v_name text;
  v_a_troops int;
  v_b_troops int;
  v_a_dmg int;
  v_b_dmg int;
  v_out jsonb;
  v_a_wins boolean;
  v_surv int;
  v_weights int[];
  v_alloc int[];
  v_i int;
  v_cid int;
  v_sg_players int[];
begin
  select array_agg(m.commander_id order by m.id) into v_arr
  from public.commander_movements m
  join public.commanders c on c.id = m.commander_id
  where m.game_id = p_game_id and m.contact_territory_id = p_territory_id and c.owner_player_id = p_player_id;
  if v_arr is null then
    return null;
  end if;

  v_sg := public.hostile_siegers(p_player_id, p_territory_id);
  select owner_player_id, name into v_owner, v_name from public.game_territories where id = p_territory_id;

  if array_length(v_sg, 1) is null then
    foreach v_cid in array v_arr loop
      update public.commanders set status = 'idle', current_territory_id = p_territory_id where id = v_cid;
      delete from public.commander_movements where commander_id = v_cid;
      perform public.continue_route(v_cid, p_territory_id);
    end loop;
    return jsonb_build_object('territory_id', p_territory_id, 'arrived', true);
  end if;

  select coalesce(sum(troops), 0) into v_a_troops from public.commanders where id = any (v_arr);
  select coalesce(sum(troops), 0) into v_b_troops from public.commanders where id = any (v_sg);
  select array_agg(distinct owner_player_id) into v_sg_players from public.commanders where id = any (v_sg);

  v_a_dmg := greatest(1, public.armory_level(p_player_id) + public.side_valor(v_arr, null));
  v_b_dmg := greatest(1, public.side_best_realm(v_sg, 'armory') + public.side_valor(v_sg, null));

  v_out := public.open_field_outcome(
    v_a_troops, v_a_dmg,
    coalesce((select level from public.realm_areas where player_id = p_player_id and area = 'watchtowers'), 1) + public.side_ability(v_arr, null, 'tactics'),
    v_b_troops, v_b_dmg,
    public.side_best_realm(v_sg, 'watchtowers') + public.side_ability(v_sg, null, 'tactics'),
    'b'
  );
  v_a_wins := v_out ->> 'winner' = 'a';
  v_surv := (v_out ->> 'survivors')::int;

  if v_a_wins then
    select array_agg(c.troops order by u.ord) into v_weights
    from unnest(v_arr) with ordinality as u(id, ord) join public.commanders c on c.id = u.id;
    v_alloc := public.split_survivors(v_surv, v_weights);

    perform public.kill_commanders(p_game_id, v_sg, p_tick);
    for v_i in 1 .. array_length(v_arr, 1) loop
      update public.commanders
      set troops = v_alloc[v_i], status = 'idle', current_territory_id = p_territory_id
      where id = v_arr[v_i];
      delete from public.commander_movements where commander_id = v_arr[v_i];
    end loop;

    insert into public.game_moments (game_id, tick, type, payload)
    values (p_game_id, p_tick, 'siege_lifted', jsonb_build_object('territory_id', p_territory_id, 'territory', v_name, 'by', 'relief', 'player_id', p_player_id));

    foreach v_cid in array v_arr loop
      perform public.continue_route(v_cid, p_territory_id);
    end loop;
  else
    select array_agg(c.troops order by u.ord) into v_weights
    from unnest(v_sg) with ordinality as u(id, ord) join public.commanders c on c.id = u.id;
    v_alloc := public.split_survivors(v_surv, v_weights);

    perform public.kill_commanders(p_game_id, v_arr, p_tick);
    for v_i in 1 .. array_length(v_sg, 1) loop
      update public.commanders set troops = v_alloc[v_i] where id = v_sg[v_i];
    end loop;
  end if;

  insert into public.game_events (game_id, tick, type, payload)
  values (
    p_game_id, p_tick, 'relief',
    jsonb_build_object(
      'territory_id', p_territory_id, 'relief_player_id', p_player_id,
      'relief_troops', v_a_troops, 'siege_troops', v_b_troops,
      'relief_damage', v_a_dmg, 'siege_damage', v_b_dmg,
      'winner', case when v_a_wins then 'relief' else 'siege' end, 'survivors', v_surv
    )
  );

  perform public.notify_players(
    p_game_id, p_tick, array[p_player_id, v_owner] || v_sg_players,
    'Relief of ' || v_name || ': ' || case when v_a_wins then 'siege lifted' else 'relief force destroyed' end,
    jsonb_build_object('kind', 'relief', 'territory_id', p_territory_id, 'territory', v_name, 'winner', case when v_a_wins then 'relief' else 'siege' end, 'survivors', v_surv)
  );

  return jsonb_build_object(
    'territory_id', p_territory_id,
    'kind', 'relief',
    'winner', case when v_a_wins then 'relief' else 'siege' end,
    'captured', false,
    'survivors', v_surv
  );
end;
$$;

create function public.resolve_siege_contacts(p_game_id int, p_tick int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_x int;
  v_player int;
  v_friendly boolean;
  v_besieged boolean;
  v_ids int[];
  v_cid int;
  v_res jsonb;
  v_events jsonb := '[]'::jsonb;
  v_combats int := 0;
  v_started int := 0;
  v_guard int := 0;
begin
  loop
    v_guard := v_guard + 1;
    exit when v_guard > 500;

    select m.contact_territory_id, c.owner_player_id,
           public.is_friendly_territory(c.owner_player_id, m.contact_territory_id),
           public.has_hostile_siege(c.owner_player_id, m.contact_territory_id)
    into v_x, v_player, v_friendly, v_besieged
    from public.commander_movements m
    join public.commanders c on c.id = m.commander_id
    where m.game_id = p_game_id
      and m.contact_territory_id is not null
      and (
        m.march_type = 'siege'
        or (
          public.is_friendly_territory(c.owner_player_id, m.contact_territory_id)
          and public.has_hostile_siege(c.owner_player_id, m.contact_territory_id)
        )
      )
    order by m.arrival_tick, m.id
    limit 1;
    exit when not found;

    if not v_friendly then
      v_res := public.begin_siege(p_game_id, v_x, v_player, p_tick);
      exit when v_res is null;
      v_started := v_started + 1;
    elsif v_besieged then
      v_res := public.resolve_relief(p_game_id, v_x, v_player, p_tick);
      exit when v_res is null;
      if v_res ->> 'winner' is not null then
        v_combats := v_combats + 1;
        v_events := v_events || jsonb_build_array(v_res);
      end if;
    else
      select array_agg(m.commander_id order by m.id) into v_ids
      from public.commander_movements m
      join public.commanders c on c.id = m.commander_id
      where m.game_id = p_game_id and m.contact_territory_id = v_x and m.march_type = 'siege' and c.owner_player_id = v_player;
      exit when v_ids is null;
      foreach v_cid in array v_ids loop
        update public.commanders set status = 'idle', current_territory_id = v_x where id = v_cid;
        delete from public.commander_movements where commander_id = v_cid;
        perform public.continue_route(v_cid, v_x);
      end loop;
    end if;
  end loop;

  return jsonb_build_object('combats', v_combats, 'sieges_started', v_started, 'combat_events', v_events);
end;
$$;

create function public.apply_siege_attrition(p_game_id int, p_tick int, p_cycle boolean)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_t record;
  v_sg int[];
  v_def int[];
  v_rate float8;
  v_loss float8;
  v_whole int;
  v_track text;
  v_count int := 0;
begin
  for v_t in
    select gt.*
    from public.game_territories gt
    where gt.game_id = p_game_id
      and array_length(public.hostile_siegers(gt.owner_player_id, gt.id), 1) is not null
  loop
    v_count := v_count + 1;
    v_sg := public.hostile_siegers(v_t.owner_player_id, v_t.id);

    select coalesce(array_agg(c.id order by c.id), '{}') into v_def
    from public.commanders c
    where v_t.owner_player_id is not null
      and c.current_territory_id = v_t.id
      and c.status = 'idle'
      and (c.owner_player_id = v_t.owner_player_id or public.are_allied(v_t.owner_player_id, c.owner_player_id));

    v_rate := greatest(
      0,
      3 + 1.0 * public.side_ability(v_sg, null, 'siegecraft') - 0.5 * public.side_ability(v_def, v_t.garrison_commander_id, 'siegecraft')
    );
    v_loss := v_t.troops * v_rate / 100.0 + v_t.starve_accum;
    v_whole := least(v_t.troops, floor(v_loss)::int);

    update public.game_territories
    set troops = troops - v_whole,
        starve_accum = case when v_whole >= v_t.troops then 0 else v_loss - v_whole end
    where id = v_t.id;

    if p_cycle and v_t.owner_player_id is not null then
      select tr into v_track
      from (values ('treasury', v_t.gold_level), ('recruitment', v_t.industry_level), ('prestige', v_t.prestige_level)) as x(tr, lv)
      where lv > 0
      order by random()
      limit 1;

      if v_track is not null then
        update public.game_territories
        set gold_level = gold_level - case when v_track = 'treasury' then 1 else 0 end,
            industry_level = industry_level - case when v_track = 'recruitment' then 1 else 0 end,
            prestige_level = prestige_level - case when v_track = 'prestige' then 1 else 0 end
        where id = v_t.id;

        perform public.notify_players(
          p_game_id, p_tick, array[v_t.owner_player_id],
          v_t.name || ' suffers under siege',
          jsonb_build_object('kind', 'siege_damage', 'territory_id', v_t.id, 'territory', v_t.name, 'track', v_track)
        );
      end if;
    end if;
  end loop;

  return v_count;
end;
$$;

create function public.end_stale_sieges(p_game_id int)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.commanders c
  set status = 'idle'
  where c.game_id = p_game_id
    and c.status = 'sieging'
    and public.is_friendly_territory(c.owner_player_id, c.current_territory_id);
$$;

create function public.resolve_intercepts(p_game_id int, p_tick int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r record;
  v_p0 jsonb;
  v_p1 jsonb;
  v_mid int[] := '{}';
  v_cmd int[] := '{}';
  v_own int[] := '{}';
  v_dep int[] := '{}';
  v_ax float8[] := '{}';
  v_ay float8[] := '{}';
  v_bx float8[] := '{}';
  v_by float8[] := '{}';
  v_dead boolean[];
  v_n int;
  v_i int;
  v_j int;
  v_d0x float8; v_d0y float8; v_dx float8; v_dy float8; v_len2 float8; v_tt float8; v_dist float8;
  v_ta int; v_tb int;
  v_out jsonb;
  v_tie text;
  v_w int;
  v_l int;
  v_events jsonb := '[]'::jsonb;
  v_combats int := 0;
  v_surv int;
begin
  for v_r in
    select m.id as mid, m.commander_id as cid, c.owner_player_id as pid, m.departed_tick as dep
    from public.commander_movements m
    join public.commanders c on c.id = m.commander_id
    where m.game_id = p_game_id and m.contact_territory_id is null and c.troops > 0 and c.status = 'moving'
    order by m.id
  loop
    v_p0 := public.movement_position(v_r.mid, p_tick - 1);
    v_p1 := public.movement_position(v_r.mid, p_tick);
    v_mid := v_mid || v_r.mid;
    v_cmd := v_cmd || v_r.cid;
    v_own := v_own || v_r.pid;
    v_dep := v_dep || v_r.dep;
    v_ax := v_ax || (v_p0 ->> 'x')::float8;
    v_ay := v_ay || (v_p0 ->> 'y')::float8;
    v_bx := v_bx || (v_p1 ->> 'x')::float8;
    v_by := v_by || (v_p1 ->> 'y')::float8;
  end loop;

  v_n := coalesce(array_length(v_mid, 1), 0);
  if v_n < 2 then
    return jsonb_build_object('combats', 0, 'combat_events', '[]'::jsonb);
  end if;
  v_dead := array_fill(false, array[v_n]);

  for v_i in 1 .. v_n - 1 loop
    for v_j in v_i + 1 .. v_n loop
      continue when v_dead[v_i] or v_dead[v_j];
      continue when v_own[v_i] = v_own[v_j] or public.are_allied(v_own[v_i], v_own[v_j]);

      v_d0x := v_ax[v_i] - v_ax[v_j];
      v_d0y := v_ay[v_i] - v_ay[v_j];
      v_dx := (v_bx[v_i] - v_bx[v_j]) - v_d0x;
      v_dy := (v_by[v_i] - v_by[v_j]) - v_d0y;
      v_len2 := v_dx * v_dx + v_dy * v_dy;
      v_tt := case when v_len2 = 0 then 0 else greatest(0, least(1, - (v_d0x * v_dx + v_d0y * v_dy) / v_len2)) end;
      v_dist := sqrt((v_d0x + v_tt * v_dx) ^ 2 + (v_d0y + v_tt * v_dy) ^ 2);
      continue when v_dist > 20.2;

      select troops into v_ta from public.commanders where id = v_cmd[v_i];
      select troops into v_tb from public.commanders where id = v_cmd[v_j];
      continue when v_ta <= 0 or v_tb <= 0;

      v_tie := case when v_dep[v_i] <= v_dep[v_j] then 'a' else 'b' end;
      v_out := public.open_field_outcome(
        v_ta, greatest(1, public.armory_level(v_own[v_i]) + public.side_valor(array[v_cmd[v_i]], null)),
        coalesce((select level from public.realm_areas where player_id = v_own[v_i] and area = 'watchtowers'), 1) + public.side_ability(array[v_cmd[v_i]], null, 'tactics'),
        v_tb, greatest(1, public.armory_level(v_own[v_j]) + public.side_valor(array[v_cmd[v_j]], null)),
        coalesce((select level from public.realm_areas where player_id = v_own[v_j] and area = 'watchtowers'), 1) + public.side_ability(array[v_cmd[v_j]], null, 'tactics'),
        v_tie
      );

      v_w := case when v_out ->> 'winner' = 'a' then v_i else v_j end;
      v_l := case when v_out ->> 'winner' = 'a' then v_j else v_i end;
      v_surv := (v_out ->> 'survivors')::int;

      perform public.kill_commanders(p_game_id, array[v_cmd[v_l]], p_tick);
      update public.commanders set troops = v_surv where id = v_cmd[v_w];
      v_dead[v_l] := true;
      v_combats := v_combats + 1;

      insert into public.game_events (game_id, tick, type, payload)
      values (
        p_game_id, p_tick, 'intercept',
        jsonb_build_object('winner_commander_id', v_cmd[v_w], 'loser_commander_id', v_cmd[v_l], 'survivors', v_surv,
                           'winner_player_id', v_own[v_w], 'loser_player_id', v_own[v_l])
      );
      perform public.notify_players(
        p_game_id, p_tick, array[v_own[v_w]],
        'Intercepted an enemy march: victory',
        jsonb_build_object('kind', 'intercept', 'winner', true, 'survivors', v_surv)
      );
      perform public.notify_players(
        p_game_id, p_tick, array[v_own[v_l]],
        'Intercepted by an enemy march: defeat',
        jsonb_build_object('kind', 'intercept', 'winner', false)
      );
      v_events := v_events || jsonb_build_array(jsonb_build_object('kind', 'intercept', 'winner', 'a', 'captured', false, 'survivors', v_surv));
    end loop;
  end loop;

  return jsonb_build_object('combats', v_combats, 'combat_events', v_events);
end;
$$;

create or replace function public.resolve_tick_events(p_game_id int, p_tick int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cycle boolean;
  v_moves jsonb;
  v_inter jsonb;
  v_combat jsonb;
  v_siege jsonb;
begin
  select p_tick % production_cycle_ticks = 0 into v_cycle from public.games where id = p_game_id;

  perform public.apply_siege_attrition(p_game_id, p_tick, v_cycle);
  v_moves := public.advance_movements(p_game_id, p_tick);
  v_inter := public.resolve_intercepts(p_game_id, p_tick);
  v_combat := public.resolve_contacts(p_game_id, p_tick);
  v_siege := public.resolve_siege_contacts(p_game_id, p_tick);
  perform public.end_stale_sieges(p_game_id);

  return jsonb_build_object(
    'arrivals', v_moves -> 'arrivals',
    'contacts', v_moves -> 'contacts',
    'captures', v_combat -> 'captures',
    'sieges_started', v_siege -> 'sieges_started',
    'combats', (v_inter ->> 'combats')::int + (v_combat ->> 'combats')::int + (v_siege ->> 'combats')::int,
    'combat_events', (v_inter -> 'combat_events') || (v_combat -> 'combat_events') || (v_siege -> 'combat_events')
  );
end;
$$;

create or replace function public.launch_leg(p_player_id int, p_commander_id int, p_to_territory_id int, p_march_type text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_c public.commanders%rowtype;
  v_plan jsonb;
  v_tick int;
  v_path int[];
  v_offsets int[];
  v_arrivals int[];
begin
  select * into v_c from public.commanders where id = p_commander_id for update;
  if not found or v_c.owner_player_id <> p_player_id or v_c.status = 'dead' then
    raise exception 'commander not found';
  end if;
  if v_c.status not in ('idle', 'sieging') then
    raise exception 'commander is not idle';
  end if;
  if exists (select 1 from public.game_territories where garrison_commander_id = v_c.id) then
    raise exception 'unassign the garrison commander before marching';
  end if;
  if p_march_type not in ('assault', 'siege') then
    raise exception 'march_type must be assault or siege';
  end if;

  v_plan := public.plan_march(p_player_id, p_commander_id, p_to_territory_id);
  if not (v_plan ->> 'in_range')::boolean then
    raise exception 'out of range: % needed, % available', v_plan ->> 'raw_length', v_plan ->> 'range';
  end if;

  select current_tick into v_tick from public.games where id = v_c.game_id;

  select array_agg(x::int order by ord) into v_path from jsonb_array_elements_text(v_plan -> 'path') with ordinality as t(x, ord);
  select array_agg(x::int order by ord) into v_offsets from jsonb_array_elements_text(v_plan -> 'offsets') with ordinality as t(x, ord);
  select array_agg(v_tick + o order by ord) into v_arrivals from unnest(v_offsets) with ordinality as t(o, ord);
  v_arrivals[1] := v_tick;

  insert into public.commander_movements (
    game_id, commander_id, from_territory_id, to_territory_id, path, path_arrival_ticks,
    departed_tick, arrival_tick, march_type
  ) values (
    v_c.game_id, v_c.id, v_c.current_territory_id, p_to_territory_id, v_path, v_arrivals,
    v_tick, v_arrivals[array_length(v_arrivals, 1)], p_march_type
  );

  update public.commanders set status = 'moving', current_territory_id = null where id = v_c.id;

  return jsonb_build_object(
    'path', to_jsonb(v_path),
    'departed_tick', v_tick,
    'arrival_tick', v_arrivals[array_length(v_arrivals, 1)],
    'travel_ticks', v_plan -> 'travel_ticks'
  );
end;
$$;

create or replace function public.send_on_route(p_game_id int, p_commander_id int, p_stops jsonb, p_march_type text default 'assault')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.game_players;
  v_c public.commanders%rowtype;
  v_stops jsonb := '[]'::jsonb;
  v_stop jsonb;
  v_territory int;
  v_type text;
  v_prev int;
  v_tick int;
  v_route_id int;
  v_leg jsonb;
begin
  v_player := public.acting_player(p_game_id);

  if p_stops is null or jsonb_typeof(p_stops) <> 'array' or jsonb_array_length(p_stops) not between 1 and 10 then
    raise exception 'stops must be a list of 1 to 10 destinations';
  end if;

  select * into v_c from public.commanders where id = p_commander_id and game_id = p_game_id;
  if not found or v_c.owner_player_id <> v_player.id or v_c.status = 'dead' then
    raise exception 'commander not found';
  end if;
  if v_c.status not in ('idle', 'sieging') or v_c.current_territory_id is null then
    raise exception 'commander is not idle';
  end if;

  v_prev := v_c.current_territory_id;
  for v_stop in select e from jsonb_array_elements(p_stops) as t(e) loop
    v_territory := (v_stop ->> 'territory_id')::int;
    v_type := coalesce(v_stop ->> 'march_type', p_march_type);
    if v_type not in ('assault', 'siege') then
      raise exception 'march_type must be assault or siege';
    end if;
    if not exists (select 1 from public.game_territories where id = v_territory and game_id = p_game_id) then
      raise exception 'unknown territory: %', v_territory;
    end if;
    if v_territory = v_prev then
      raise exception 'consecutive stops must differ';
    end if;
    v_stops := v_stops || jsonb_build_object('territory_id', v_territory, 'march_type', v_type);
    v_prev := v_territory;
  end loop;

  select current_tick into v_tick from public.games where id = p_game_id;

  insert into public.commander_routes (game_id, commander_id, stops, created_tick, origin_territory_id)
  values (p_game_id, v_c.id, v_stops, v_tick, v_c.current_territory_id)
  returning id into v_route_id;

  v_leg := public.launch_leg(
    v_player.id, v_c.id,
    (v_stops -> 0 ->> 'territory_id')::int,
    v_stops -> 0 ->> 'march_type'
  );

  return v_leg || jsonb_build_object('route_id', v_route_id, 'stops', jsonb_array_length(v_stops));
end;
$$;

create function public.sally_out(p_game_id int, p_territory_id int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.game_players;
  v_t public.game_territories%rowtype;
  v_sg int[];
  v_def int[];
  v_tick int;
  v_a_troops int;
  v_b_troops int;
  v_a_dmg int;
  v_b_dmg int;
  v_out jsonb;
  v_a_wins boolean;
  v_surv int;
  v_weights int[];
  v_alloc int[];
  v_i int;
  v_sg_players int[];
begin
  v_player := public.acting_player(p_game_id);

  select * into v_t from public.game_territories where id = p_territory_id and game_id = p_game_id for update;
  if not found or v_t.owner_player_id is distinct from v_player.id then
    raise exception 'you do not own that territory';
  end if;

  v_sg := public.hostile_siegers(v_player.id, p_territory_id);
  if array_length(v_sg, 1) is null then
    raise exception 'that territory is not under siege';
  end if;

  select current_tick into v_tick from public.games where id = p_game_id;

  select coalesce(array_agg(c.id order by c.id), '{}') into v_def
  from public.commanders c
  where c.current_territory_id = p_territory_id
    and c.status = 'idle'
    and (c.owner_player_id = v_player.id or public.are_allied(v_player.id, c.owner_player_id));

  select v_t.troops + coalesce(sum(troops), 0) into v_a_troops from public.commanders where id = any (v_def);
  if v_a_troops = 0 then
    raise exception 'there is nothing to sally with';
  end if;
  select coalesce(sum(troops), 0) into v_b_troops from public.commanders where id = any (v_sg);
  select array_agg(distinct owner_player_id) into v_sg_players from public.commanders where id = any (v_sg);

  v_a_dmg := greatest(1, greatest(public.armory_level(v_player.id), public.side_best_realm(v_def, 'armory')) + public.side_valor(v_def, v_t.garrison_commander_id));
  v_b_dmg := greatest(1, public.side_best_realm(v_sg, 'armory') + public.side_valor(v_sg, null));

  v_out := public.open_field_outcome(
    v_a_troops, v_a_dmg,
    greatest(coalesce((select level from public.realm_areas where player_id = v_player.id and area = 'watchtowers'), 1), public.side_best_realm(v_def, 'watchtowers'))
      + public.side_ability(v_def, v_t.garrison_commander_id, 'tactics'),
    v_b_troops, v_b_dmg,
    public.side_best_realm(v_sg, 'watchtowers') + public.side_ability(v_sg, null, 'tactics'),
    'b'
  );
  v_a_wins := v_out ->> 'winner' = 'a';
  v_surv := (v_out ->> 'survivors')::int;

  if v_a_wins then
    select array_agg(w order by ord) into v_weights
    from (
      select 0 as ord, v_t.troops as w
      union all
      select u.ord, c.troops
      from unnest(v_def) with ordinality as u(id, ord) join public.commanders c on c.id = u.id
    ) parts;
    v_alloc := public.split_survivors(v_surv, v_weights);

    perform public.kill_commanders(p_game_id, v_sg, v_tick);
    update public.game_territories set troops = v_alloc[1], starve_accum = 0 where id = p_territory_id;
    for v_i in 1 .. coalesce(array_length(v_def, 1), 0) loop
      update public.commanders set troops = v_alloc[v_i + 1] where id = v_def[v_i];
    end loop;

    insert into public.game_moments (game_id, tick, type, payload)
    values (p_game_id, v_tick, 'siege_lifted', jsonb_build_object('territory_id', p_territory_id, 'territory', v_t.name, 'by', 'sally', 'player_id', v_player.id));
  else
    select array_agg(c.troops order by u.ord) into v_weights
    from unnest(v_sg) with ordinality as u(id, ord) join public.commanders c on c.id = u.id;
    v_alloc := public.split_survivors(v_surv, v_weights);

    perform public.kill_commanders(p_game_id, v_def, v_tick);
    update public.game_territories set troops = 0 where id = p_territory_id;
    for v_i in 1 .. array_length(v_sg, 1) loop
      update public.commanders set troops = v_alloc[v_i] where id = v_sg[v_i];
    end loop;
  end if;

  insert into public.game_events (game_id, tick, type, payload)
  values (
    p_game_id, v_tick, 'sally',
    jsonb_build_object(
      'territory_id', p_territory_id, 'player_id', v_player.id,
      'sally_troops', v_a_troops, 'siege_troops', v_b_troops,
      'sally_damage', v_a_dmg, 'siege_damage', v_b_dmg,
      'winner', case when v_a_wins then 'sally' else 'siege' end, 'survivors', v_surv
    )
  );

  perform public.notify_players(
    p_game_id, v_tick, array[v_player.id] || v_sg_players,
    'Sally from ' || v_t.name || ': ' || case when v_a_wins then 'siege broken' else 'sally destroyed' end,
    jsonb_build_object('kind', 'sally', 'territory_id', p_territory_id, 'territory', v_t.name, 'winner', case when v_a_wins then 'sally' else 'siege' end, 'survivors', v_surv)
  );

  return jsonb_build_object(
    'winner', case when v_a_wins then 'sally' else 'siege' end,
    'survivors', v_surv,
    'sally_troops', v_a_troops,
    'siege_troops', v_b_troops
  );
end;
$$;

create function public.break_siege_and_assault(p_game_id int, p_territory_id int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.game_players;
  v_ids int[];
  v_tick int;
begin
  v_player := public.acting_player(p_game_id);

  select coalesce(array_agg(c.id order by c.id), '{}') into v_ids
  from public.commanders c
  where c.game_id = p_game_id
    and c.owner_player_id = v_player.id
    and c.status = 'sieging'
    and c.current_territory_id = p_territory_id;
  if array_length(v_ids, 1) is null then
    raise exception 'you have no besieging commanders there';
  end if;
  if public.is_friendly_territory(v_player.id, p_territory_id) then
    raise exception 'that territory is no longer an enemy';
  end if;

  select current_tick into v_tick from public.games where id = p_game_id;
  return public.fight_castle(p_game_id, p_territory_id, v_player.id, v_ids, v_tick);
end;
$$;

revoke execute on function public.side_ability(int[], int, text) from public, anon, authenticated;
revoke execute on function public.side_best_realm(int[], text) from public, anon, authenticated;
revoke execute on function public.hostile_siegers(int, int) from public, anon, authenticated;
revoke execute on function public.duel(int, int, int, int) from public, anon, authenticated;
revoke execute on function public.open_field_outcome(int, int, int, int, int, int, text) from public, anon, authenticated;
revoke execute on function public.notify_players(int, int, int[], text, jsonb) from public, anon, authenticated;
revoke execute on function public.fight_castle(int, int, int, int[], int) from public, anon, authenticated;
revoke execute on function public.resolve_assault(int, int, int, int) from public, anon, authenticated;
revoke execute on function public.begin_siege(int, int, int, int) from public, anon, authenticated;
revoke execute on function public.resolve_relief(int, int, int, int) from public, anon, authenticated;
revoke execute on function public.resolve_siege_contacts(int, int) from public, anon, authenticated;
revoke execute on function public.apply_siege_attrition(int, int, boolean) from public, anon, authenticated;
revoke execute on function public.end_stale_sieges(int) from public, anon, authenticated;
revoke execute on function public.resolve_intercepts(int, int) from public, anon, authenticated;
revoke execute on function public.resolve_tick_events(int, int) from public, anon, authenticated;
revoke execute on function public.launch_leg(int, int, int, text) from public, anon, authenticated;

revoke execute on function public.send_on_route(int, int, jsonb, text) from public, anon;
grant execute on function public.send_on_route(int, int, jsonb, text) to authenticated;
revoke execute on function public.sally_out(int, int) from public, anon;
grant execute on function public.sally_out(int, int) to authenticated;
revoke execute on function public.break_siege_and_assault(int, int) from public, anon;
grant execute on function public.break_siege_and_assault(int, int) to authenticated;
