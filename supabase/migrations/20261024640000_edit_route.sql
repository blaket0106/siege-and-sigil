create function public.edit_route(p_game_id int, p_commander_id int, p_stops jsonb, p_options jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $f$
declare
  v_player public.game_players;
  v_c public.commanders%rowtype;
  v_route public.commander_routes%rowtype;
  v_game public.games%rowtype;
  v_stop jsonb;
  v_locked jsonb;
  v_kept jsonb := '[]'::jsonb;
  v_new jsonb := '[]'::jsonb;
  v_all jsonb;
  v_moving boolean;
  v_type text;
  v_to int;
  v_from int;
  v_prev int;
  v_i int;
  v_n int;
  v_k int;
  v_loop boolean;
  v_origin jsonb;
  v_stables int;
  v_d float8;
  v_pm jsonb;
begin
  v_player := public.acting_player(p_game_id);
  select * into v_c from public.commanders where id = p_commander_id and game_id = p_game_id;
  if not found or v_c.owner_player_id <> v_player.id or v_c.status = 'dead' then
    raise exception 'commander not found';
  end if;
  select * into v_route from public.commander_routes where commander_id = v_c.id and status = 'active' order by id desc limit 1;
  if not found then
    raise exception 'commander has no active route';
  end if;
  if p_stops is null or jsonb_typeof(p_stops) <> 'array' or jsonb_array_length(p_stops) not between 1 and 10 then
    raise exception 'stops must be a list of 1 to 10 destinations';
  end if;
  v_moving := v_c.status = 'moving';
  if not v_moving and (v_route.resume_tick is null or v_c.current_territory_id is null) then
    raise exception 'the route can be edited while the army is on the road or waiting at a stop';
  end if;
  if v_moving and v_route.next_stop_index >= jsonb_array_length(v_route.stops) then
    raise exception 'the army is on its way back to the start; edit the route after it arrives';
  end if;
  select * into v_game from public.games where id = p_game_id;
  select coalesce(level, 0) into v_stables from public.realm_areas where player_id = v_player.id and area = 'stables';
  v_stables := coalesce(v_stables, 0);
  v_loop := coalesce((p_options ->> 'loop')::boolean, v_route.looping);
  v_origin := case when p_options ? 'origin_order' then public.clean_stop_order(p_options -> 'origin_order') else v_route.origin_order end;

  for v_k in 0 .. v_route.next_stop_index - 1 loop
    v_kept := v_kept || jsonb_build_array(v_route.stops -> v_k);
  end loop;

  v_locked := case when v_moving then v_route.stops -> v_route.next_stop_index end;
  v_prev := case when v_moving then null else v_c.current_territory_id end;
  v_i := 0;
  for v_stop in select e from jsonb_array_elements(p_stops) as t(e) loop
    v_to := (v_stop ->> 'territory_id')::int;
    v_type := coalesce(v_stop ->> 'march_type', 'assault');
    if v_type not in ('assault', 'siege') then
      raise exception 'march_type must be assault or siege';
    end if;
    if not exists (select 1 from public.game_territories where id = v_to and game_id = p_game_id) then
      raise exception 'unknown territory: %', v_to;
    end if;
    if v_i = 0 and v_moving then
      if v_to <> (v_locked ->> 'territory_id')::int then
        raise exception 'the first stop is locked: the army is already on its way to %', (select name from public.game_territories where id = (v_locked ->> 'territory_id')::int);
      end if;
      v_type := coalesce(v_locked ->> 'march_type', 'assault');
    end if;
    if v_prev is not null and v_to = v_prev then
      raise exception 'consecutive stops must differ';
    end if;
    v_new := v_new || jsonb_build_array(jsonb_build_object('territory_id', v_to, 'march_type', v_type) || public.clean_stop_order(v_stop));
    v_prev := v_to;
    v_i := v_i + 1;
  end loop;
  v_n := jsonb_array_length(v_new);
  if jsonb_array_length(v_kept) + v_n > 20 then
    raise exception 'a route can hold at most 20 stops in all';
  end if;
  if v_loop and v_prev = v_route.origin_territory_id then
    raise exception 'a looping route must end somewhere other than where it starts';
  end if;

  v_from := case when v_moving then (v_new -> 0 ->> 'territory_id')::int else v_c.current_territory_id end;
  for v_i in (case when v_moving then 1 else 0 end) .. v_n - 1 + (case when v_loop then 1 else 0 end) loop
    v_to := (v_new -> (v_i % v_n) ->> 'territory_id')::int;
    if v_to <> v_from then
    if v_game.free_travel then
      select sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) into v_d from public.game_territories a, public.game_territories b where a.id = v_from and b.id = v_to;
      if v_d > (210 + 60 * v_stables) * v_game.unit_scale then
        raise exception 'stop % is out of range of the stop before it', v_i + 1;
      end if;
    else
      begin
        v_pm := public.plan_march_from(v_player.id, v_c.id, v_from, v_to);
      exception when others then
        raise exception 'stop %: %', v_i + 1, sqlerrm;
      end;
      if not (v_pm ->> 'in_range')::boolean then
        raise exception 'stop % is out of range of the stop before it (% needed, % available)', v_i + 1, v_pm ->> 'raw_length', v_pm ->> 'range';
      end if;
    end if;
    end if;
    v_from := v_to;
  end loop;

  v_all := v_kept || v_new;
  update public.commander_routes set stops = v_all, looping = v_loop, origin_order = nullif(v_origin, '{}'::jsonb) where id = v_route.id;
  return jsonb_build_object('route_id', v_route.id, 'stops', jsonb_array_length(v_all), 'loop', v_loop);
end;
$f$;
revoke execute on function public.edit_route(int, int, jsonb, jsonb) from public, anon;
grant execute on function public.edit_route(int, int, jsonb, jsonb) to authenticated;

do $patch$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'send_on_route' and p.pronamespace = 'public'::regnamespace;
  if position('v_to := (v_stops -> (v_i % v_n) ->> ''territory_id'')::int;' in v_def) = 0 then
    raise exception 'send_on_route patch did not match';
  end if;
  execute replace(v_def, 'v_to := (v_stops -> (v_i % v_n) ->> ''territory_id'')::int;', 'v_to := case when v_i >= v_n then v_c.current_territory_id else (v_stops -> v_i ->> ''territory_id'')::int end;');
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'edit_route' and p.pronamespace = 'public'::regnamespace;
  if position('v_to := (v_new -> (v_i % v_n) ->> ''territory_id'')::int;' in v_def) = 0 then
    raise exception 'edit_route patch did not match';
  end if;
  execute replace(v_def, 'v_to := (v_new -> (v_i % v_n) ->> ''territory_id'')::int;', 'v_to := case when v_i >= v_n then v_route.origin_territory_id else (v_new -> v_i ->> ''territory_id'')::int end;');
end;
$patch$;
