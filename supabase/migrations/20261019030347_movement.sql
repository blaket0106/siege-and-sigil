alter table public.commander_routes add column origin_territory_id int;

create function public.ability_level(p_commander_id int, p_ability text)
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
    case
      when p_ability in ('muster', 'steward', 'scholar', 'pace', 'scout', 'plunder') then coalesce((
        select greatest(kca.level - 1, 0)
        from public.commanders me
        join public.commanders k
          on k.owner_player_id = me.owner_player_id and k.role = 'king' and k.status <> 'dead'
        join public.games g on g.id = k.game_id
        join public.commander_abilities kca on kca.commander_id = k.id and kca.ability = p_ability
        where me.id = p_commander_id
          and (k.coronation_tick is null or k.coronation_tick <= g.current_tick)
        limit 1
      ), 0)
      else 0
    end
  );
$$;

create function public.march_speed(p_commander_id int)
returns float8
language sql
stable
security definer
set search_path = ''
as $$
  select 17.5 * g.commander_speed_mult * (1 + 0.10 * public.ability_level(c.id, 'pace'))
  from public.commanders c
  join public.games g on g.id = c.game_id
  where c.id = p_commander_id;
$$;

create function public.plan_march(p_player_id int, p_commander_id int, p_to_territory_id int)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_c public.commanders%rowtype;
  v_ids int[];
  v_owner int[];
  v_road boolean[];
  v_allies int[];
  v_friendly boolean[];
  v_ea int[] := '{}';
  v_eb int[] := '{}';
  v_ew float8[] := '{}';
  v_er float8[] := '{}';
  v_dist float8[];
  v_prev int[];
  v_done boolean[];
  v_n int;
  v_src int;
  v_dst int;
  v_u int;
  v_best float8;
  v_i int;
  v_k int;
  v_x int;
  v_e record;
  v_a int;
  v_b int;
  v_speed float8;
  v_stables int;
  v_range float8;
  v_rev int[] := '{}';
  v_path_ids int[] := '{}';
  v_offsets int[] := '{}';
  v_cum float8 := 0;
  v_raw float8 := 0;
  v_prev_offset int := 0;
  v_off int;
begin
  select * into v_c from public.commanders where id = p_commander_id;
  if not found or v_c.owner_player_id <> p_player_id or v_c.status = 'dead' then
    raise exception 'commander not found';
  end if;
  if v_c.current_territory_id is null then
    raise exception 'commander is not at a territory';
  end if;

  select array_agg(id order by id), array_agg(owner_player_id order by id), array_agg(has_road order by id)
  into v_ids, v_owner, v_road
  from public.game_territories where game_id = v_c.game_id;
  v_n := array_length(v_ids, 1);

  v_src := array_position(v_ids, v_c.current_territory_id);
  v_dst := array_position(v_ids, p_to_territory_id);
  if v_dst is null then
    raise exception 'unknown destination territory';
  end if;
  if v_src = v_dst then
    raise exception 'commander is already there';
  end if;

  select coalesce(array_agg(case when d.player_a_id = p_player_id then d.player_b_id else d.player_a_id end), '{}')
  into v_allies
  from public.diplomacy d
  where d.game_id = v_c.game_id
    and d.status = 'allied'
    and p_player_id in (d.player_a_id, d.player_b_id);

  v_friendly := array_fill(false, array[v_n]);
  for v_i in 1 .. v_n loop
    v_friendly[v_i] := v_owner[v_i] is not null and (v_owner[v_i] = p_player_id or v_owner[v_i] = any (v_allies));
  end loop;

  for v_e in
    select e.from_territory_id as f, e.to_territory_id as t, e.length * e.move_cost_mult as w
    from public.territory_edges e
    where e.game_id = v_c.game_id
  loop
    v_a := array_position(v_ids, v_e.f);
    v_b := array_position(v_ids, v_e.t);
    v_ea := v_ea || v_a;
    v_eb := v_eb || v_b;
    v_ew := v_ew || v_e.w;
    v_er := v_er || case when v_road[v_a] and v_road[v_b] then v_e.w / 3.0 else v_e.w end;
  end loop;

  v_dist := array_fill('Infinity'::float8, array[v_n]);
  v_prev := array_fill(0, array[v_n]);
  v_done := array_fill(false, array[v_n]);
  v_dist[v_src] := 0;

  loop
    v_u := 0;
    v_best := 'Infinity'::float8;
    for v_i in 1 .. v_n loop
      if not v_done[v_i] and v_dist[v_i] < v_best then
        v_best := v_dist[v_i];
        v_u := v_i;
      end if;
    end loop;
    exit when v_u = 0;
    v_done[v_u] := true;
    exit when v_u = v_dst;
    continue when v_u <> v_src and not v_friendly[v_u];

    for v_k in 1 .. coalesce(array_length(v_ea, 1), 0) loop
      if v_ea[v_k] = v_u then
        v_x := v_eb[v_k];
      elsif v_eb[v_k] = v_u then
        v_x := v_ea[v_k];
      else
        continue;
      end if;
      if not v_done[v_x] and v_dist[v_u] + v_er[v_k] < v_dist[v_x] then
        v_dist[v_x] := v_dist[v_u] + v_er[v_k];
        v_prev[v_x] := v_u;
      end if;
    end loop;
  end loop;

  if v_dist[v_dst] = 'Infinity'::float8 then
    raise exception 'no route: the destination is not reachable through friendly territory';
  end if;

  v_x := v_dst;
  while v_x <> 0 loop
    v_rev := v_rev || v_x;
    v_x := v_prev[v_x];
  end loop;

  v_speed := public.march_speed(p_commander_id);

  for v_i in reverse array_length(v_rev, 1) .. 1 loop
    v_x := v_rev[v_i];
    v_path_ids := v_path_ids || v_ids[v_x];
    if v_i < array_length(v_rev, 1) then
      v_a := v_rev[v_i + 1];
      for v_k in 1 .. array_length(v_ea, 1) loop
        if (v_ea[v_k] = v_a and v_eb[v_k] = v_x) or (v_ea[v_k] = v_x and v_eb[v_k] = v_a) then
          v_cum := v_cum + v_er[v_k];
          v_raw := v_raw + v_ew[v_k];
          exit;
        end if;
      end loop;
    end if;
    v_off := greatest(v_prev_offset, ceil(v_cum / v_speed)::int);
    if v_i = 1 then
      v_off := greatest(v_off, 1);
    end if;
    v_offsets := v_offsets || v_off;
    v_prev_offset := v_off;
  end loop;

  select coalesce(level, 0) into v_stables
  from public.realm_areas where player_id = p_player_id and area = 'stables';
  v_range := 90 + 60 * coalesce(v_stables, 0);

  return jsonb_build_object(
    'from_territory_id', v_c.current_territory_id,
    'to_territory_id', p_to_territory_id,
    'path', to_jsonb(v_path_ids),
    'offsets', to_jsonb(v_offsets),
    'travel_ticks', v_offsets[array_length(v_offsets, 1)],
    'raw_length', round(v_raw::numeric, 3),
    'speed', v_speed,
    'range', v_range,
    'hops', array_length(v_path_ids, 1) - 1,
    'in_range', (array_length(v_path_ids, 1) = 2 or v_raw <= v_range)
  );
end;
$$;

create function public.launch_leg(p_player_id int, p_commander_id int, p_to_territory_id int, p_march_type text)
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
  if v_c.status <> 'idle' then
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

create function public.truncate_movement(p_commander_id int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m public.commander_movements%rowtype;
  v_tick int;
  v_i int;
  v_keep int;
begin
  select * into v_m from public.commander_movements where commander_id = p_commander_id for update;
  if not found then
    return null;
  end if;
  select current_tick into v_tick from public.games where id = v_m.game_id;

  v_i := 1;
  while v_i < array_length(v_m.path, 1) and v_m.path_arrival_ticks[v_i + 1] <= v_tick loop
    v_i := v_i + 1;
  end loop;

  v_keep := least(v_i + 1, array_length(v_m.path, 1));

  update public.commander_movements
  set path = v_m.path[1:v_keep],
      path_arrival_ticks = v_m.path_arrival_ticks[1:v_keep],
      to_territory_id = v_m.path[v_keep],
      arrival_tick = greatest(v_m.path_arrival_ticks[v_keep], v_tick + 1)
  where id = v_m.id;

  return jsonb_build_object(
    'halts_at_territory_id', v_m.path[v_keep],
    'arrival_tick', greatest(v_m.path_arrival_ticks[v_keep], v_tick + 1)
  );
end;
$$;

create function public.send_on_route(p_game_id int, p_commander_id int, p_stops jsonb, p_march_type text default 'assault')
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
  if v_c.status <> 'idle' or v_c.current_territory_id is null then
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

create function public.march_commander(p_game_id int, p_commander_id int, p_to_territory_id int, p_march_type text default 'assault')
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select public.send_on_route(
    p_game_id, p_commander_id,
    jsonb_build_array(jsonb_build_object('territory_id', p_to_territory_id, 'march_type', p_march_type)),
    p_march_type
  );
$$;

create function public.preview_march(p_game_id int, p_commander_id int, p_to_territory_id int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.game_players;
  v_plan jsonb;
  v_tick int;
begin
  v_player := public.acting_player(p_game_id);
  v_plan := public.plan_march(v_player.id, p_commander_id, p_to_territory_id);
  select current_tick into v_tick from public.games where id = p_game_id;
  return v_plan || jsonb_build_object('arrival_tick', v_tick + (v_plan ->> 'travel_ticks')::int);
end;
$$;

create function public.abort_route(p_game_id int, p_commander_id int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.game_players;
  v_halt jsonb;
begin
  v_player := public.acting_player(p_game_id);

  if not exists (
    select 1 from public.commanders where id = p_commander_id and game_id = p_game_id and owner_player_id = v_player.id
  ) then
    raise exception 'commander not found';
  end if;

  update public.commander_routes set status = 'aborted'
  where commander_id = p_commander_id and status = 'active';
  if not found then
    raise exception 'commander has no active route';
  end if;

  v_halt := public.truncate_movement(p_commander_id);
  return coalesce(v_halt, '{}'::jsonb);
end;
$$;

create function public.recall_route(p_game_id int, p_commander_id int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.game_players;
  v_halt jsonb;
  v_origin int;
begin
  v_player := public.acting_player(p_game_id);

  if not exists (
    select 1 from public.commanders where id = p_commander_id and game_id = p_game_id and owner_player_id = v_player.id
  ) then
    raise exception 'commander not found';
  end if;

  update public.commander_routes set status = 'recalled'
  where commander_id = p_commander_id and status = 'active'
  returning origin_territory_id into v_origin;
  if not found then
    raise exception 'commander has no active route';
  end if;

  v_halt := public.truncate_movement(p_commander_id);
  return coalesce(v_halt, '{}'::jsonb) || jsonb_build_object('returns_to_territory_id', v_origin);
end;
$$;

revoke execute on function public.ability_level(int, text) from public, anon, authenticated;
revoke execute on function public.march_speed(int) from public, anon, authenticated;
revoke execute on function public.plan_march(int, int, int) from public, anon, authenticated;
revoke execute on function public.launch_leg(int, int, int, text) from public, anon, authenticated;
revoke execute on function public.truncate_movement(int) from public, anon, authenticated;

revoke execute on function public.send_on_route(int, int, jsonb, text) from public, anon;
grant execute on function public.send_on_route(int, int, jsonb, text) to authenticated;
revoke execute on function public.march_commander(int, int, int, text) from public, anon;
grant execute on function public.march_commander(int, int, int, text) to authenticated;
revoke execute on function public.preview_march(int, int, int) from public, anon;
grant execute on function public.preview_march(int, int, int) to authenticated;
revoke execute on function public.abort_route(int, int) from public, anon;
grant execute on function public.abort_route(int, int) to authenticated;
revoke execute on function public.recall_route(int, int) from public, anon;
grant execute on function public.recall_route(int, int) to authenticated;
