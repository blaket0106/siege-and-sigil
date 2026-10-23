alter table public.commander_routes
  add column if not exists loop boolean not null default false,
  add column if not exists origin_order jsonb,
  add column if not exists resume_tick int;

create or replace function public.route_stop(p_route public.commander_routes, p_index integer)
returns jsonb
language sql
immutable
set search_path = ''
as $function$
  select case
    when p_index < jsonb_array_length(p_route.stops) then p_route.stops -> p_index
    else jsonb_build_object('territory_id', p_route.origin_territory_id, 'march_type', 'assault') || coalesce(p_route.origin_order, '{}'::jsonb)
  end;
$function$;

create or replace function public.route_size(p_route public.commander_routes)
returns integer
language sql
immutable
set search_path = ''
as $function$
  select jsonb_array_length(p_route.stops) + case when p_route.loop and p_route.origin_territory_id is not null then 1 else 0 end;
$function$;

create or replace function public.apply_stop_action(p_commander_id integer, p_node integer, p_stop jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_c public.commanders%rowtype;
  v_t public.game_territories%rowtype;
  v_act text := coalesce(p_stop ->> 'action', 'nothing');
  v_n int := coalesce((p_stop ->> 'amount')::int, 0);
  v_move int;
begin
  if v_act = 'nothing' then
    return;
  end if;
  select * into v_c from public.commanders where id = p_commander_id;
  select * into v_t from public.game_territories where id = p_node;
  if v_t.owner_player_id is distinct from v_c.owner_player_id then
    return;
  end if;
  v_move := case v_act
    when 'collect_all' then v_t.troops
    when 'drop_all' then - v_c.troops
    when 'collect' then least(v_n, v_t.troops)
    when 'drop' then - least(v_n, v_c.troops)
    when 'collect_all_but' then greatest(v_t.troops - v_n, 0)
    when 'drop_all_but' then - greatest(v_c.troops - v_n, 0)
    when 'garrison' then case when v_t.troops < v_n then - least(v_n - v_t.troops, v_c.troops) else v_t.troops - v_n end
    else 0
  end;
  if v_move <> 0 then
    perform public.transfer_troops_core(v_c.game_id, v_c.owner_player_id, v_c.id, v_move);
  end if;
end;
$function$;

create or replace function public.advance_route(p_route_id integer)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_route public.commander_routes%rowtype;
  v_c public.commanders%rowtype;
  v_stop jsonb;
  v_tick int;
begin
  select * into v_route from public.commander_routes where id = p_route_id;
  select * into v_c from public.commanders where id = v_route.commander_id;
  v_stop := public.route_stop(v_route, v_route.next_stop_index);
  begin
    perform public.launch_leg(v_c.owner_player_id, v_c.id, (v_stop ->> 'territory_id')::int, coalesce(v_stop ->> 'march_type', 'assault'));
    update public.commander_routes set resume_tick = null where id = v_route.id;
  exception when others then
    update public.commander_routes set status = 'aborted', resume_tick = null where id = v_route.id;
    select current_tick into v_tick from public.games where id = v_c.game_id;
    insert into public.player_inbox (game_id, player_id, type, title, body, tick)
    values (
      v_c.game_id, v_c.owner_player_id, 'system', 'Route cancelled',
      jsonb_build_object('kind', 'route_cancelled', 'commander_id', v_c.id, 'at_territory_id', v_c.current_territory_id, 'reason', sqlerrm),
      v_tick
    );
  end;
end;
$function$;

create or replace function public.resume_routes(p_game_id integer, p_tick integer)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_id int;
begin
  for v_id in
    select id from public.commander_routes
    where game_id = p_game_id and status = 'active' and resume_tick is not null and resume_tick <= p_tick
    order by id
  loop
    perform public.advance_route(v_id);
  end loop;
end;
$function$;

create or replace function public.continue_route(p_commander_id integer, p_node integer)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_c public.commanders%rowtype;
  v_route public.commander_routes%rowtype;
  v_stop jsonb;
  v_size int;
  v_next int;
  v_delay int;
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

  v_size := public.route_size(v_route);
  v_stop := public.route_stop(v_route, v_route.next_stop_index);
  if p_node <> (v_stop ->> 'territory_id')::int then
    update public.commander_routes set status = 'aborted' where id = v_route.id;
    return;
  end if;

  begin
    perform public.apply_stop_action(v_c.id, p_node, v_stop);
  exception when others then
    null;
  end;

  v_next := v_route.next_stop_index + 1;
  if v_next >= v_size then
    if not v_route.loop then
      update public.commander_routes set status = 'completed', next_stop_index = v_next where id = v_route.id;
      return;
    end if;
    v_next := 0;
  end if;

  select current_tick into v_tick from public.games where id = v_c.game_id;
  v_delay := coalesce((v_stop ->> 'delay')::int, 0);
  update public.commander_routes
  set next_stop_index = v_next, resume_tick = case when v_delay > 0 then v_tick + v_delay end
  where id = v_route.id;
  if v_delay = 0 then
    perform public.advance_route(v_route.id);
  end if;
end;
$function$;

drop function if exists public.send_on_route(integer, integer, jsonb, text);

create function public.send_on_route(p_game_id integer, p_commander_id integer, p_stops jsonb, p_march_type text default 'assault', p_options jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
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
  v_loop boolean := coalesce((p_options ->> 'loop')::boolean, false);
  v_origin jsonb := '{}'::jsonb;
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
    v_stops := v_stops || (jsonb_build_object('territory_id', v_territory, 'march_type', v_type) || public.clean_stop_order(v_stop));
    v_prev := v_territory;
  end loop;

  if p_options ? 'origin_order' then
    v_origin := public.clean_stop_order(p_options -> 'origin_order');
  end if;
  if v_loop and v_prev = v_c.current_territory_id then
    raise exception 'a looping route must end somewhere other than where it starts';
  end if;

  select current_tick into v_tick from public.games where id = p_game_id;

  insert into public.commander_routes (game_id, commander_id, stops, created_tick, origin_territory_id, loop, origin_order)
  values (p_game_id, v_c.id, v_stops, v_tick, v_c.current_territory_id, v_loop, nullif(v_origin, '{}'::jsonb))
  returning id into v_route_id;

  v_leg := public.launch_leg(
    v_player.id, v_c.id,
    (v_stops -> 0 ->> 'territory_id')::int,
    v_stops -> 0 ->> 'march_type'
  );

  return v_leg || jsonb_build_object('route_id', v_route_id, 'stops', jsonb_array_length(v_stops), 'loop', v_loop);
end;
$function$;

create or replace function public.clean_stop_order(p_stop jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_act text := coalesce(p_stop ->> 'action', 'nothing');
  v_n int := coalesce((p_stop ->> 'amount')::int, 0);
  v_delay int := coalesce((p_stop ->> 'delay')::int, 0);
begin
  if v_act not in ('nothing', 'collect_all', 'drop_all', 'collect', 'drop', 'collect_all_but', 'drop_all_but', 'garrison') then
    raise exception 'unknown action: %', v_act;
  end if;
  if v_n < 0 or v_n > 100000 then
    raise exception 'amount must be between 0 and 100000';
  end if;
  if v_delay < 0 or v_delay > 240 then
    raise exception 'delay must be between 0 and 240 ticks';
  end if;
  return jsonb_build_object('action', v_act, 'amount', v_n, 'delay', v_delay);
end;
$function$;

create or replace function public.set_route_loop(p_game_id integer, p_commander_id integer, p_loop boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_player public.game_players;
  v_route public.commander_routes%rowtype;
  v_last int;
begin
  v_player := public.acting_player(p_game_id);

  if not exists (
    select 1 from public.commanders where id = p_commander_id and game_id = p_game_id and owner_player_id = v_player.id
  ) then
    raise exception 'commander not found';
  end if;

  select * into v_route from public.commander_routes
  where commander_id = p_commander_id and status = 'active'
  order by id desc limit 1;
  if not found then
    raise exception 'commander has no active route';
  end if;

  v_last := (v_route.stops -> (jsonb_array_length(v_route.stops) - 1) ->> 'territory_id')::int;
  if p_loop and v_last = v_route.origin_territory_id then
    raise exception 'a looping route must end somewhere other than where it starts';
  end if;

  update public.commander_routes set loop = p_loop where id = v_route.id;
  return jsonb_build_object('route_id', v_route.id, 'loop', p_loop);
end;
$function$;

revoke all on function public.route_stop(public.commander_routes, integer), public.route_size(public.commander_routes), public.apply_stop_action(integer, integer, jsonb), public.advance_route(integer), public.resume_routes(integer, integer), public.continue_route(integer, integer), public.clean_stop_order(jsonb) from public, anon, authenticated;
revoke all on function public.send_on_route(integer, integer, jsonb, text, jsonb), public.set_route_loop(integer, integer, boolean) from public, anon;
grant execute on function public.send_on_route(integer, integer, jsonb, text, jsonb), public.set_route_loop(integer, integer, boolean) to authenticated;

do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.run_tick(integer)'::regprocedure) into v_def;
  v_new := replace(v_def, '  v_events := public.resolve_tick_events(p_game_id, v_tick);', '  perform public.resume_routes(p_game_id, v_tick);' || chr(10) || '  v_events := public.resolve_tick_events(p_game_id, v_tick);');
  if v_new = v_def or v_new not like '%resume_routes%' then
    raise exception 'run_tick patch did not apply';
  end if;
  execute v_new;
end;
$patch$;
