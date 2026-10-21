alter table public.commander_movements add column contact_territory_id int;

create function public.are_allied(p_a int, p_b int)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.diplomacy d
    where d.status = 'allied'
      and d.player_a_id = least(p_a, p_b)
      and d.player_b_id = greatest(p_a, p_b)
  );
$$;

create function public.is_friendly_territory(p_player_id int, p_territory_id int)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select gt.owner_player_id is not null
       and (gt.owner_player_id = p_player_id or public.are_allied(p_player_id, gt.owner_player_id))
    from public.game_territories gt
    where gt.id = p_territory_id
  ), false);
$$;

create function public.has_hostile_siege(p_player_id int, p_territory_id int)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.commanders c
    where c.current_territory_id = p_territory_id
      and c.status = 'sieging'
      and c.owner_player_id <> p_player_id
      and not public.are_allied(p_player_id, c.owner_player_id)
  );
$$;

create function public.movement_position(p_movement_id int, p_tick int)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_m public.commander_movements%rowtype;
  v_n int;
  v_i int := 1;
  v_x1 float8; v_y1 float8; v_x2 float8; v_y2 float8;
  v_denom int;
  v_f float8;
begin
  select * into v_m from public.commander_movements where id = p_movement_id;
  if not found then
    return null;
  end if;
  v_n := array_length(v_m.path, 1);

  if p_tick >= v_m.path_arrival_ticks[v_n] then
    select x, y into v_x1, v_y1 from public.game_territories where id = v_m.path[v_n];
    return jsonb_build_object('x', v_x1, 'y', v_y1, 'segment_from', v_m.path[v_n], 'segment_to', v_m.path[v_n]);
  end if;

  while v_i < v_n - 1 and v_m.path_arrival_ticks[v_i + 1] <= p_tick loop
    v_i := v_i + 1;
  end loop;

  select x, y into v_x1, v_y1 from public.game_territories where id = v_m.path[v_i];
  select x, y into v_x2, v_y2 from public.game_territories where id = v_m.path[v_i + 1];
  v_denom := v_m.path_arrival_ticks[v_i + 1] - v_m.path_arrival_ticks[v_i];
  v_f := case
    when v_denom <= 0 then 1
    else least(1, greatest(0, (p_tick - v_m.path_arrival_ticks[v_i])::float8 / v_denom))
  end;

  return jsonb_build_object(
    'x', v_x1 + (v_x2 - v_x1) * v_f,
    'y', v_y1 + (v_y2 - v_y1) * v_f,
    'segment_from', v_m.path[v_i],
    'segment_to', v_m.path[v_i + 1]
  );
end;
$$;

create function public.continue_route(p_commander_id int, p_node int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_c public.commanders%rowtype;
  v_route public.commander_routes%rowtype;
  v_stops int;
  v_next int;
  v_tick int;
begin
  select * into v_c from public.commanders where id = p_commander_id;
  select * into v_route
  from public.commander_routes
  where commander_id = p_commander_id and status in ('active', 'recalled')
  order by id desc
  limit 1;
  if not found then
    return;
  end if;

  if v_route.status = 'recalled' then
    update public.commander_routes set status = 'completed' where id = v_route.id;
    if v_route.origin_territory_id is not null and p_node <> v_route.origin_territory_id then
      begin
        perform public.launch_leg(v_c.owner_player_id, v_c.id, v_route.origin_territory_id, 'assault');
      exception when others then
        null;
      end;
    end if;
    return;
  end if;

  v_stops := jsonb_array_length(v_route.stops);
  if p_node <> (v_route.stops -> v_route.next_stop_index ->> 'territory_id')::int then
    update public.commander_routes set status = 'aborted' where id = v_route.id;
    return;
  end if;

  v_next := v_route.next_stop_index + 1;
  if v_next >= v_stops then
    update public.commander_routes set status = 'completed', next_stop_index = v_next where id = v_route.id;
    return;
  end if;

  begin
    perform public.launch_leg(
      v_c.owner_player_id, v_c.id,
      (v_route.stops -> v_next ->> 'territory_id')::int,
      v_route.stops -> v_next ->> 'march_type'
    );
    update public.commander_routes set next_stop_index = v_next where id = v_route.id;
  exception when others then
    update public.commander_routes set status = 'aborted' where id = v_route.id;
    select current_tick into v_tick from public.games where id = v_c.game_id;
    insert into public.player_inbox (game_id, player_id, type, title, body, tick)
    values (
      v_c.game_id, v_c.owner_player_id, 'system', 'Route cancelled',
      jsonb_build_object('kind', 'route_cancelled', 'commander_id', v_c.id, 'at_territory_id', p_node, 'reason', sqlerrm),
      v_tick
    );
  end;
end;
$$;

create function public.advance_movements(p_game_id int, p_tick int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m public.commander_movements%rowtype;
  v_owner int;
  v_n int;
  v_i int;
  v_stop int;
  v_node int;
  v_arrivals int := 0;
  v_contacts int := 0;
begin
  for v_m in
    select * from public.commander_movements
    where game_id = p_game_id and contact_territory_id is null
    order by arrival_tick, id
  loop
    select owner_player_id into v_owner from public.commanders where id = v_m.commander_id;
    v_n := array_length(v_m.path, 1);
    v_stop := null;

    for v_i in 2 .. v_n loop
      exit when v_m.path_arrival_ticks[v_i] > p_tick;
      v_node := v_m.path[v_i];
      if v_i = v_n
         or not public.is_friendly_territory(v_owner, v_node)
         or public.has_hostile_siege(v_owner, v_node) then
        v_stop := v_i;
        exit;
      end if;
    end loop;

    continue when v_stop is null;
    v_node := v_m.path[v_stop];

    if public.is_friendly_territory(v_owner, v_node) and not public.has_hostile_siege(v_owner, v_node) then
      update public.commanders set status = 'idle', current_territory_id = v_node where id = v_m.commander_id;
      delete from public.commander_movements where id = v_m.id;
      perform public.continue_route(v_m.commander_id, v_node);
      v_arrivals := v_arrivals + 1;
    else
      update public.commander_movements
      set path = v_m.path[1:v_stop],
          path_arrival_ticks = v_m.path_arrival_ticks[1:v_stop],
          to_territory_id = v_node,
          arrival_tick = v_m.path_arrival_ticks[v_stop],
          contact_territory_id = v_node
      where id = v_m.id;
      v_contacts := v_contacts + 1;
    end if;
  end loop;

  return jsonb_build_object('arrivals', v_arrivals, 'contacts', v_contacts);
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
  v_moves jsonb;
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

  v_moves := public.advance_movements(p_game_id, v_tick);

  return jsonb_build_object(
    'tick', v_tick,
    'troops_added', v_troops,
    'gold_added', v_gold,
    'cycle', v_cycle,
    'arrivals', v_moves -> 'arrivals',
    'contacts', v_moves -> 'contacts'
  );
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
    'combats', 0,
    'combat_events', '[]'::jsonb
  );
end;
$$;

revoke execute on function public.are_allied(int, int) from public, anon, authenticated;
revoke execute on function public.is_friendly_territory(int, int) from public, anon, authenticated;
revoke execute on function public.has_hostile_siege(int, int) from public, anon, authenticated;
revoke execute on function public.movement_position(int, int) from public, anon, authenticated;
revoke execute on function public.continue_route(int, int) from public, anon, authenticated;
revoke execute on function public.advance_movements(int, int) from public, anon, authenticated;
revoke execute on function public.run_tick(int) from public, anon, authenticated;
revoke execute on function public.process_game(int) from public, anon, authenticated;
