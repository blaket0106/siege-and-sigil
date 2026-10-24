create or replace function public.plan_march(p_player_id integer, p_commander_id integer, p_to_territory_id integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_c public.commanders%rowtype;
  v_ids int[];
  v_owner int[];
  v_road boolean[];
  v_allies int[];
  v_friendly boolean[];
  v_junction boolean[];
  v_pos int[];
  v_m int;
  v_ea int[];
  v_eb int[];
  v_ew float8[];
  v_er float8[];
  v_deg int[];
  v_ptr int[];
  v_fill int[];
  v_nb int[];
  v_nr float8[];
  v_nw float8[];
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
  v_road_div float8;
  v_maxid int;
  v_open int[];
  v_oi int;
begin
  select * into v_c from public.commanders where id = p_commander_id;
  if not found or v_c.owner_player_id <> p_player_id or v_c.status = 'dead' then
    raise exception 'commander not found';
  end if;
  if v_c.current_territory_id is null then
    raise exception 'commander is not at a territory';
  end if;

  if (select free_travel from public.games where id = v_c.game_id) then
    return public.plan_march_free(p_player_id, p_commander_id, p_to_territory_id);
  end if;

  select array_agg(id order by id), array_agg(owner_player_id order by id), array_agg(has_road or is_junction order by id), array_agg(is_junction order by id), max(id)
  into v_ids, v_owner, v_road, v_junction, v_maxid
  from public.game_territories where game_id = v_c.game_id;
  v_n := array_length(v_ids, 1);

  v_pos := array_fill(0, array[v_maxid]);
  for v_i in 1 .. v_n loop
    v_pos[v_ids[v_i]] := v_i;
  end loop;

  v_src := v_pos[v_c.current_territory_id];
  v_dst := case when p_to_territory_id between 1 and v_maxid then nullif(v_pos[p_to_territory_id], 0) else null end;
  if v_dst is null then
    raise exception 'unknown destination territory';
  end if;
  if v_junction[v_dst] then
    raise exception 'a crossroads is not a destination';
  end if;
  if v_src = v_dst then
    raise exception 'commander is already there';
  end if;
  if v_owner[v_dst] is not null and public.are_truced(p_player_id, v_owner[v_dst]) then
    raise exception 'you have a truce with that player until tick %', (
      select d.truce_ends_tick from public.diplomacy d
      where d.game_id = v_c.game_id and d.player_a_id = least(p_player_id, v_owner[v_dst]) and d.player_b_id = greatest(p_player_id, v_owner[v_dst])
    );
  end if;

  select coalesce(array_agg(case when d.player_a_id = p_player_id then d.player_b_id else d.player_a_id end), '{}')
  into v_allies
  from public.diplomacy d
  where d.game_id = v_c.game_id
    and d.status = 'allied'
    and p_player_id in (d.player_a_id, d.player_b_id);

  v_friendly := array_fill(false, array[v_n]);
  for v_i in 1 .. v_n loop
    v_friendly[v_i] := v_junction[v_i] or (v_owner[v_i] is not null and (v_owner[v_i] = p_player_id or v_owner[v_i] = any (v_allies)));
  end loop;

  v_road_div := sqrt(3 + coalesce((select ra.level from public.realm_areas ra where ra.player_id = p_player_id and ra.area = 'stables'), 0));

  select count(*) into v_m from public.territory_edges where game_id = v_c.game_id;
  v_ea := array_fill(0, array[greatest(v_m, 1)]);
  v_eb := array_fill(0, array[greatest(v_m, 1)]);
  v_ew := array_fill(0::float8, array[greatest(v_m, 1)]);
  v_er := array_fill(0::float8, array[greatest(v_m, 1)]);
  v_deg := array_fill(0, array[v_n]);
  v_k := 0;
  for v_e in
    select e.from_territory_id as f, e.to_territory_id as t, e.length * e.move_cost_mult as w
    from public.territory_edges e
    where e.game_id = v_c.game_id
  loop
    v_k := v_k + 1;
    v_a := v_pos[v_e.f];
    v_b := v_pos[v_e.t];
    v_ea[v_k] := v_a;
    v_eb[v_k] := v_b;
    v_ew[v_k] := v_e.w;
    v_er[v_k] := case when v_road[v_a] and v_road[v_b] then v_e.w / v_road_div else v_e.w end;
    v_deg[v_a] := v_deg[v_a] + 1;
    v_deg[v_b] := v_deg[v_b] + 1;
  end loop;
  v_m := v_k;

  v_ptr := array_fill(0, array[v_n + 1]);
  v_ptr[1] := 1;
  for v_i in 1 .. v_n loop
    v_ptr[v_i + 1] := v_ptr[v_i] + v_deg[v_i];
  end loop;
  v_fill := array_fill(0, array[v_n]);
  v_nb := array_fill(0, array[greatest(2 * v_m, 1)]);
  v_nr := array_fill(0::float8, array[greatest(2 * v_m, 1)]);
  v_nw := array_fill(0::float8, array[greatest(2 * v_m, 1)]);
  for v_k in 1 .. v_m loop
    v_a := v_ea[v_k];
    v_b := v_eb[v_k];
    v_x := v_ptr[v_a] + v_fill[v_a];
    v_nb[v_x] := v_b;
    v_nr[v_x] := v_er[v_k];
    v_nw[v_x] := v_ew[v_k];
    v_fill[v_a] := v_fill[v_a] + 1;
    v_x := v_ptr[v_b] + v_fill[v_b];
    v_nb[v_x] := v_a;
    v_nr[v_x] := v_er[v_k];
    v_nw[v_x] := v_ew[v_k];
    v_fill[v_b] := v_fill[v_b] + 1;
  end loop;

  v_dist := array_fill('Infinity'::float8, array[v_n]);
  v_prev := array_fill(0, array[v_n]);
  v_done := array_fill(false, array[v_n]);
  v_dist[v_src] := 0;

  v_open := array[v_src];
  loop
    v_u := 0;
    v_oi := 0;
    v_best := 'Infinity'::float8;
    for v_i in 1 .. coalesce(array_length(v_open, 1), 0) loop
      v_x := v_open[v_i];
      if v_dist[v_x] < v_best or (v_dist[v_x] = v_best and v_x < v_u) then
        v_best := v_dist[v_x];
        v_u := v_x;
        v_oi := v_i;
      end if;
    end loop;
    exit when v_u = 0;
    v_open[v_oi] := v_open[array_length(v_open, 1)];
    v_open := v_open[1 : array_length(v_open, 1) - 1];
    v_done[v_u] := true;
    exit when v_u = v_dst;
    continue when v_u <> v_src and not v_friendly[v_u];

    for v_k in v_ptr[v_u] .. v_ptr[v_u + 1] - 1 loop
      v_x := v_nb[v_k];
      if not v_done[v_x] and v_dist[v_u] + v_nr[v_k] < v_dist[v_x] then
        if v_dist[v_x] = 'Infinity'::float8 then
          v_open := v_open || v_x;
        end if;
        v_dist[v_x] := v_dist[v_u] + v_nr[v_k];
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
      for v_k in v_ptr[v_a] .. v_ptr[v_a + 1] - 1 loop
        if v_nb[v_k] = v_x then
          v_cum := v_cum + v_nr[v_k];
          v_raw := v_raw + v_nw[v_k];
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
  v_range := case when (select g.travel_mode from public.games g where g.id = v_c.game_id) = 'trails'
    then (300 + 120 * coalesce(v_stables, 0)) * (select g.world_scale from public.games g where g.id = v_c.game_id)
    else 90 + 60 * coalesce(v_stables, 0) end;

  return jsonb_build_object(
    'from_territory_id', v_c.current_territory_id,
    'to_territory_id', p_to_territory_id,
    'path', to_jsonb(v_path_ids),
    'offsets', to_jsonb(v_offsets),
    'travel_ticks', v_offsets[array_length(v_offsets, 1)],
    'raw_length', round(v_raw::numeric, 3),
    'speed', v_speed,
    'range', v_range,
    'hops', (select count(*)::int from unnest(v_path_ids) pid join public.game_territories jt on jt.id = pid where not jt.is_junction) - 1,
    'in_range', ((select count(*) from unnest(v_path_ids) pid join public.game_territories jt on jt.id = pid where not jt.is_junction) = 2 or v_raw <= v_range)
  );
end;
$function$;
