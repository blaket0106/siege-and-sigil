alter table public.games add column if not exists seasons_enabled boolean not null default false;
alter table public.games add column if not exists season_length_ticks integer not null default 48 check (season_length_ticks between 12 and 240);
alter table public.games add column if not exists events_enabled boolean not null default false;
alter table public.games add column if not exists mercenaries_enabled boolean not null default true;
grant select (seasons_enabled, season_length_ticks, events_enabled, mercenaries_enabled) on public.games to authenticated;

alter table public.commanders add column if not exists mercenary boolean not null default false;
alter table public.commanders add column if not exists contract_ends_tick integer;

create table if not exists public.world_events (
  id serial primary key,
  game_id integer not null references public.games (id) on delete cascade,
  kind text not null check (kind in ('plague', 'rebellion')),
  territory_id integer not null references public.game_territories (id) on delete cascade,
  player_id integer not null,
  cost integer not null,
  created_tick integer not null,
  expires_tick integer not null,
  status text not null default 'open' check (status in ('open', 'responded', 'resolved')),
  foreign key (game_id, player_id) references public.game_players (game_id, id) on delete cascade
);
create index if not exists world_events_game_idx on public.world_events (game_id, status);
alter table public.world_events enable row level security;
revoke all on public.world_events from anon, authenticated;

create or replace function public.season_of(p_game_id integer, p_tick integer)
returns text
language sql
stable
security definer
set search_path = ''
as $function$
  select case when g.seasons_enabled
    then (array['spring', 'summer', 'autumn', 'winter'])[1 + (p_tick / g.season_length_ticks) % 4]
    else null end
  from public.games g where g.id = p_game_id;
$function$;

create or replace function public.season_troop_factor(p_game_id integer, p_territory_id integer, p_tick integer)
returns float8
language sql
stable
security definer
set search_path = ''
as $function$
  select case
    when public.season_of(p_game_id, p_tick) = 'winter'
      then case when t.y < g.map_h / 3.0 then 0.6 else 0.8 end
    else 1.0 end
  from public.game_territories t
  join public.games g on g.id = t.game_id
  where t.id = p_territory_id;
$function$;

create or replace function public.season_gold_factor(p_game_id integer, p_tick integer)
returns float8
language sql
stable
security definer
set search_path = ''
as $function$
  select case when public.season_of(p_game_id, p_tick) = 'autumn' then 1.15 else 1.0 end;
$function$;

create or replace function public.season_move_factor(p_game_id integer, p_tick integer)
returns float8
language sql
stable
security definer
set search_path = ''
as $function$
  select case when public.season_of(p_game_id, p_tick) = 'winter' then 0.8 else 1.0 end;
$function$;

create or replace function public.expire_mercenaries(p_game_id integer, p_tick integer)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_c record;
begin
  for v_c in
    select c.id, c.name, c.owner_player_id from public.commanders c
    where c.game_id = p_game_id and c.mercenary and c.status <> 'dead' and c.contract_ends_tick <= p_tick
    order by c.id
  loop
    perform public.kill_commanders(p_game_id, array[v_c.id], p_tick);
    perform public.notify_players(
      p_game_id, p_tick, array[v_c.owner_player_id], v_c.name || ' disbanded',
      jsonb_build_object('kind', 'mercenary_expired', 'commander_id', v_c.id, 'name', v_c.name)
    );
  end loop;
end;
$function$;

create or replace function public.hire_mercenaries(p_game_id integer, p_territory_id integer, p_troops integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_player public.game_players;
  v_game public.games%rowtype;
  v_cost int;
  v_id int;
  v_name text;
begin
  v_player := public.acting_player(p_game_id);
  select * into v_game from public.games where id = p_game_id;
  if not v_game.mercenaries_enabled then
    raise exception 'mercenaries are disabled in this game';
  end if;
  if p_troops is null or p_troops < 10 or p_troops > 60 then
    raise exception 'a company is 10 to 60 troops';
  end if;
  if not exists (select 1 from public.game_territories where id = p_territory_id and game_id = p_game_id and owner_player_id = v_player.id) then
    raise exception 'you do not own that castle';
  end if;
  if (select count(*) from public.commanders where game_id = p_game_id and owner_player_id = v_player.id and mercenary and status <> 'dead') >= 2 then
    raise exception 'you can field at most 2 mercenary companies';
  end if;
  v_cost := 5 * p_troops;
  if v_player.gold < v_cost then
    raise exception 'a company of % costs % gold', p_troops, v_cost;
  end if;

  update public.game_players set gold = gold - v_cost where id = v_player.id;
  insert into public.ledger (game_id, player_id, tick, type, amount) values (p_game_id, v_player.id, v_game.current_tick, 'recruit', -v_cost);

  v_id := public.create_commander(p_game_id, v_player.id, 'battleschool', 'commander', p_territory_id, v_game.current_tick);
  update public.commander_abilities set level = 0, xp = 0 where commander_id = v_id;
  select 'Company of ' || name into v_name from public.commanders where id = v_id;
  update public.commanders
  set mercenary = true, contract_ends_tick = v_game.current_tick + 48, troops = p_troops, name = v_name
  where id = v_id;
  return jsonb_build_object('commander_id', v_id, 'name', v_name, 'contract_ends_tick', v_game.current_tick + 48, 'cost', v_cost);
end;
$function$;

create or replace function public.draw_world_event(p_game_id integer, p_tick integer)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_roll float8 := random();
  v_t record;
  v_gold int;
  v_p record;
  v_area text;
begin
  if v_roll < 0.30 then
    select t.id, t.name, t.owner_player_id into v_t
    from public.game_territories t
    where t.game_id = p_game_id and t.owner_player_id is not null and t.troops >= 10
    order by random() limit 1;
    if not found then return; end if;
    insert into public.world_events (game_id, kind, territory_id, player_id, cost, created_tick, expires_tick)
    values (p_game_id, 'plague', v_t.id, v_t.owner_player_id, 60, p_tick, p_tick + 6);
    insert into public.game_moments (game_id, tick, type, payload)
    values (p_game_id, p_tick, 'world_event', jsonb_build_object('kind', 'plague', 'territory', v_t.name, 'player_id', v_t.owner_player_id));
    perform public.notify_players(p_game_id, p_tick, array[v_t.owner_player_id], 'Plague at ' || v_t.name,
      jsonb_build_object('kind', 'world_event', 'event', 'plague', 'territory', v_t.name, 'cost', 60, 'expires_tick', p_tick + 6));

  elsif v_roll < 0.55 then
    select t.id, t.name, t.owner_player_id into v_t
    from public.game_territories t
    where t.game_id = p_game_id and t.owner_player_id is not null
    order by random() limit 1;
    if not found then return; end if;
    insert into public.world_events (game_id, kind, territory_id, player_id, cost, created_tick, expires_tick)
    values (p_game_id, 'rebellion', v_t.id, v_t.owner_player_id, 80, p_tick, p_tick + 6);
    insert into public.game_moments (game_id, tick, type, payload)
    values (p_game_id, p_tick, 'world_event', jsonb_build_object('kind', 'rebellion', 'territory', v_t.name, 'player_id', v_t.owner_player_id));
    perform public.notify_players(p_game_id, p_tick, array[v_t.owner_player_id], 'Unrest at ' || v_t.name,
      jsonb_build_object('kind', 'world_event', 'event', 'rebellion', 'territory', v_t.name, 'cost', 80, 'expires_tick', p_tick + 6));

  elsif v_roll < 0.80 then
    select t.id, t.name, t.owner_player_id, t.gold_level into v_t
    from public.game_territories t
    where t.game_id = p_game_id and t.owner_player_id is not null
    order by random() limit 1;
    if not found then return; end if;
    v_gold := 40 + 20 * v_t.gold_level;
    update public.game_players set gold = gold + v_gold where id = v_t.owner_player_id;
    insert into public.ledger (game_id, player_id, tick, type, amount) values (p_game_id, v_t.owner_player_id, p_tick, 'production', v_gold);
    insert into public.game_moments (game_id, tick, type, payload)
    values (p_game_id, p_tick, 'world_event', jsonb_build_object('kind', 'harvest', 'territory', v_t.name, 'player_id', v_t.owner_player_id, 'gold', v_gold));
    perform public.notify_players(p_game_id, p_tick, array[v_t.owner_player_id], 'Bumper harvest at ' || v_t.name,
      jsonb_build_object('kind', 'world_event', 'event', 'harvest', 'territory', v_t.name, 'gold', v_gold));

  else
    for v_p in select id from public.game_players where game_id = p_game_id and eliminated_at_tick is null order by id loop
      select area into v_area from public.realm_areas where player_id = v_p.id and is_active;
      perform public.add_area_prestige(p_game_id, v_p.id, coalesce(v_area, 'armory'), 40);
    end loop;
    insert into public.game_moments (game_id, tick, type, payload)
    values (p_game_id, p_tick, 'world_event', jsonb_build_object('kind', 'comet'));
  end if;
end;
$function$;

create or replace function public.advance_world_events(p_game_id integer, p_tick integer)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_e record;
  v_t public.game_territories%rowtype;
  v_track text;
begin
  for v_e in
    select * from public.world_events where game_id = p_game_id and status = 'open' and expires_tick <= p_tick order by id
  loop
    update public.world_events set status = 'resolved' where id = v_e.id;
    select * into v_t from public.game_territories where id = v_e.territory_id;
    continue when v_t.owner_player_id is distinct from v_e.player_id;

    if v_e.kind = 'plague' then
      update public.game_territories set troops = troops - floor(troops * 0.3)::int where id = v_t.id;
    else
      update public.game_territories set troops = troops - floor(troops * 0.5)::int where id = v_t.id;
      select tr into v_track
      from (values ('treasury', v_t.gold_level), ('recruitment', v_t.industry_level), ('prestige', v_t.prestige_level)) as x(tr, lv)
      where lv > 0 order by random() limit 1;
      if v_track is not null then
        update public.game_territories
        set gold_level = gold_level - case when v_track = 'treasury' then 1 else 0 end,
            industry_level = industry_level - case when v_track = 'recruitment' then 1 else 0 end,
            prestige_level = prestige_level - case when v_track = 'prestige' then 1 else 0 end
        where id = v_t.id;
      end if;
    end if;
    perform public.notify_players(p_game_id, p_tick, array[v_e.player_id], case v_e.kind when 'plague' then 'The plague at ' else 'The rebellion at ' end || v_t.name || ' took its toll',
      jsonb_build_object('kind', 'world_event_resolved', 'event', v_e.kind, 'territory', v_t.name));
  end loop;
end;
$function$;

create or replace function public.respond_event_core(p_event_id integer, p_player_id integer, p_tick integer)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_e public.world_events%rowtype;
begin
  select * into v_e from public.world_events where id = p_event_id and player_id = p_player_id and status = 'open' for update;
  if not found then
    raise exception 'that event is not open';
  end if;
  if (select gold from public.game_players where id = p_player_id) < v_e.cost then
    raise exception 'you need % gold to respond', v_e.cost;
  end if;
  update public.game_players set gold = gold - v_e.cost where id = p_player_id;
  insert into public.ledger (game_id, player_id, tick, type, amount) values (v_e.game_id, p_player_id, p_tick, 'recruit', -v_e.cost);
  update public.world_events set status = 'responded' where id = v_e.id;
end;
$function$;

create or replace function public.respond_event(p_game_id integer, p_event_id integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_player public.game_players;
begin
  v_player := public.acting_player(p_game_id);
  perform public.respond_event_core(p_event_id, v_player.id, (select current_tick from public.games where id = p_game_id));
  return jsonb_build_object('status', 'responded');
end;
$function$;

create or replace function public.my_world_events(p_game_id integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_me int;
begin
  select id into v_me from public.game_players where game_id = p_game_id and user_id = (select auth.uid());
  if v_me is null then
    raise exception 'you are not in this game';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', e.id, 'kind', e.kind, 'territory_id', e.territory_id, 'territory', t.name, 'cost', e.cost, 'expires_tick', e.expires_tick
    ) order by e.id)
    from public.world_events e join public.game_territories t on t.id = e.territory_id
    where e.game_id = p_game_id and e.player_id = v_me and e.status = 'open'
  ), '[]'::jsonb);
end;
$function$;

create or replace function public.ai_events(p_game_id integer, p_player_id integer)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_e record;
  v_tick int;
begin
  select current_tick into v_tick from public.games where id = p_game_id;
  for v_e in select id, cost from public.world_events where game_id = p_game_id and player_id = p_player_id and status = 'open' order by id loop
    if (select gold from public.game_players where id = p_player_id) >= v_e.cost * 2 then
      begin
        perform public.respond_event_core(v_e.id, p_player_id, v_tick);
      exception when others then
        null;
      end;
    end if;
  end loop;
end;
$function$;

do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.run_tick(integer)'::regprocedure) into v_def;
  v_new := replace(v_def, '* public.morale_factor(gt.owner_player_id, v_tick) as total', '* public.morale_factor(gt.owner_player_id, v_tick) * public.season_troop_factor(p_game_id, gt.id, v_tick) as total');
  v_new := replace(v_new, '          * public.morale_factor(gp.id, v_tick)
        ), 0))::int as gold', '          * public.morale_factor(gp.id, v_tick) * public.season_gold_factor(p_game_id, v_tick)
        ), 0))::int as gold');
  if v_new = v_def or v_new not like '%season_gold_factor%' or v_new not like '%season_troop_factor%' then raise exception 'run_tick patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.march_speed(integer)'::regprocedure) into v_def;
  v_new := replace(v_def, '* (1 + 0.10 * public.ability_level(c.id, ''pace''))', '* (1 + 0.10 * public.ability_level(c.id, ''pace'')) * public.season_move_factor(g.id, g.current_tick)');
  if v_new = v_def then raise exception 'march_speed patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.resolve_tick_events(integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def, '  perform public.advance_offers(p_game_id, p_tick);', '  perform public.advance_offers(p_game_id, p_tick);
  perform public.expire_mercenaries(p_game_id, p_tick);
  perform public.advance_world_events(p_game_id, p_tick);');
  v_new := replace(v_new, '    perform public.process_captives(p_game_id, p_tick);', '    perform public.process_captives(p_game_id, p_tick);
    if (select events_enabled from public.games where id = p_game_id) and random() < 0.4 then
      perform public.draw_world_event(p_game_id, p_tick);
    end if;');
  if v_new = v_def or v_new not like '%draw_world_event%' or v_new not like '%expire_mercenaries%' then raise exception 'resolve_tick_events patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.ai_take_turn(integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def, '  perform public.ai_captives(p_game_id, p_player_id, v_difficulty);', '  perform public.ai_captives(p_game_id, p_player_id, v_difficulty);
  perform public.ai_events(p_game_id, p_player_id);');
  if v_new = v_def then raise exception 'ai_take_turn patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.kill_or_capture(integer,integer[],integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def, 'if not v_captor_alive or p_captor = v_c.owner_player_id then', 'if not v_captor_alive or p_captor = v_c.owner_player_id or exists (select 1 from public.commanders m where m.id = v_c.id and m.mercenary) then');
  if v_new = v_def then raise exception 'kill_or_capture patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.promote_veterans(integer[])'::regprocedure) into v_def;
  v_new := replace(v_def, 'and not c.promoted and c.wins >= 5', 'and not c.promoted and not c.mercenary and c.wins >= 5');
  if v_new = v_def then raise exception 'promote_veterans patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.create_game(jsonb)'::regprocedure) into v_def;
  v_new := replace(v_def, '''grace_period_ticks'', ''time_limit_ticks''
  ];', '''grace_period_ticks'', ''time_limit_ticks'',
    ''seasons_enabled'', ''season_length_ticks'', ''events_enabled'', ''mercenaries_enabled''
  ];');
  v_new := replace(v_new, 'world_seed = coalesce((p_settings ->> ''world_seed'')::bigint, g.world_seed)', 'seasons_enabled = coalesce((p_settings ->> ''seasons_enabled'')::boolean, g.seasons_enabled),
      season_length_ticks = coalesce((p_settings ->> ''season_length_ticks'')::int, g.season_length_ticks),
      events_enabled = coalesce((p_settings ->> ''events_enabled'')::boolean, g.events_enabled),
      mercenaries_enabled = coalesce((p_settings ->> ''mercenaries_enabled'')::boolean, g.mercenaries_enabled),
      world_seed = coalesce((p_settings ->> ''world_seed'')::bigint, g.world_seed)');
  if v_new = v_def or v_new not like '%season_length_ticks = coalesce%' or v_new not like '%''mercenaries_enabled'']%' and v_new not like '%mercenaries_enabled''%' then raise exception 'create_game patch did not apply'; end if;
  execute v_new;
end
$patch$;

do $grants$
declare
  r record;
begin
  for r in
    select oid::regprocedure as sig from pg_proc
    where pronamespace = 'public'::regnamespace
      and proname in ('season_of', 'season_troop_factor', 'season_gold_factor', 'season_move_factor', 'expire_mercenaries', 'draw_world_event', 'advance_world_events', 'respond_event_core', 'ai_events')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
  end loop;
  for r in
    select oid::regprocedure as sig from pg_proc
    where pronamespace = 'public'::regnamespace
      and proname in ('hire_mercenaries', 'respond_event', 'my_world_events')
  loop
    execute format('revoke all on function %s from public, anon', r.sig);
    execute format('grant execute on function %s to authenticated', r.sig);
  end loop;
end
$grants$;
