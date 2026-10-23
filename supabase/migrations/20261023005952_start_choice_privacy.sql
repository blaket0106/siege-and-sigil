revoke select on public.game_territories from authenticated, anon;
revoke select on public.territory_edges from authenticated, anon;

create or replace function public.get_game_edges(p_game_id integer)
returns table(game_id integer, from_territory_id integer, to_territory_id integer, kind text, length double precision, move_cost_mult double precision, defense_mult double precision)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_g public.games%rowtype;
  v_exp text;
begin
  if (select auth.uid()) is null then
    raise exception 'not signed in';
  end if;
  if not public.is_game_member(p_game_id) then
    raise exception 'you are not in this game';
  end if;
  select * into v_g from public.games where id = p_game_id;
  if v_g.status = 'picking' and v_g.fog_dark then
    return;
  end if;
  if v_g.status = 'active' and v_g.fog_of_war and v_g.fog_dark then
    select gp.explored into v_exp from public.game_players gp where gp.game_id = p_game_id and gp.user_id = (select auth.uid());
    return query
      select e.game_id, e.from_territory_id, e.to_territory_id, e.kind, e.length, e.move_cost_mult, e.defense_mult
      from public.territory_edges e
      join public.game_territories a on a.id = e.from_territory_id
      join public.game_territories b on b.id = e.to_territory_id
      where e.game_id = p_game_id
        and coalesce(substr(v_exp, 1 + least(47, floor(a.x / v_g.map_w * 48)::int) + 48 * least(47, floor(a.y / v_g.map_h * 48)::int), 1), '0') = '1'
        and coalesce(substr(v_exp, 1 + least(47, floor(b.x / v_g.map_w * 48)::int) + 48 * least(47, floor(b.y / v_g.map_h * 48)::int), 1), '0') = '1';
  else
    return query
      select e.game_id, e.from_territory_id, e.to_territory_id, e.kind, e.length, e.move_cost_mult, e.defense_mult
      from public.territory_edges e where e.game_id = p_game_id;
  end if;
end;
$function$;

revoke all on function public.get_game_edges(integer) from public, anon;
grant execute on function public.get_game_edges(integer) to authenticated;

alter table public.games
  add column if not exists start_selection text not null default 'random' check (start_selection in ('random', 'choose')),
  add column if not exists pick_minutes int not null default 15 check (pick_minutes between 1 and 1440),
  add column if not exists pick_deadline timestamptz;
alter table public.games drop constraint if exists games_status_check;
alter table public.games add constraint games_status_check check (status in ('lobby', 'picking', 'active', 'finished'));
grant select (start_selection, pick_minutes, pick_deadline) on public.games to authenticated;

create table if not exists public.start_seats (
  game_id integer not null references public.games (id) on delete cascade,
  seat integer not null,
  capital_territory_id integer not null,
  territory_ids integer[] not null,
  player_id integer references public.game_players (id) on delete set null,
  primary key (game_id, seat)
);
alter table public.start_seats enable row level security;
revoke all on public.start_seats from authenticated, anon;

create or replace function public.begin_start_picking(p_game_id integer)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  insert into public.start_seats (game_id, seat, capital_territory_id, territory_ids)
  select p_game_id, (row_number() over (order by gp.id))::int - 1, gp.capital_territory_id,
         (select array_agg(t.id order by t.id) from public.game_territories t where t.owner_player_id = gp.id)
  from public.game_players gp
  where gp.game_id = p_game_id;

  update public.game_territories set owner_player_id = null where game_id = p_game_id and owner_player_id is not null;
  update public.game_players set capital_territory_id = null where game_id = p_game_id;
  update public.games
  set status = 'picking', pick_deadline = now() + make_interval(mins => pick_minutes)
  where id = p_game_id;
end;
$function$;

create or replace function public.finalize_start(p_game_id integer)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_game public.games%rowtype;
  v_p public.game_players%rowtype;
  v_i int;
  v_school text;
  v_target int;
  v_ai_needed int;
  v_seats int[];
  v_players int[];
  v_k int;
begin
  select * into v_game from public.games where id = p_game_id for update;

  if exists (select 1 from public.start_seats where game_id = p_game_id) then
    select array_agg(ss.seat order by hashtext(ss.seat::text || p_game_id::text)) into v_seats
    from public.start_seats ss where ss.game_id = p_game_id and ss.player_id is null;
    select array_agg(gp.id order by hashtext(gp.id::text || p_game_id::text)) into v_players
    from public.game_players gp
    where gp.game_id = p_game_id and not exists (select 1 from public.start_seats ss where ss.game_id = p_game_id and ss.player_id = gp.id);
    for v_k in 1 .. coalesce(array_length(v_seats, 1), 0) loop
      update public.start_seats set player_id = v_players[v_k] where game_id = p_game_id and seat = v_seats[v_k];
    end loop;

    update public.game_territories t
    set owner_player_id = ss.player_id
    from public.start_seats ss
    where ss.game_id = p_game_id and t.id = any (ss.territory_ids);
    update public.game_players gp
    set capital_territory_id = ss.capital_territory_id
    from public.start_seats ss
    where ss.game_id = p_game_id and ss.player_id = gp.id;
    delete from public.start_seats where game_id = p_game_id;
  end if;

  select count(*) into v_target from public.game_players where game_id = p_game_id;
  select count(*) into v_ai_needed from public.game_players where game_id = p_game_id and is_ai;

  for v_p in select * from public.game_players where game_id = p_game_id order by id loop
    update public.game_players set gold = v_game.starting_gold where id = v_p.id;

    if v_game.starting_gold > 0 then
      insert into public.ledger (game_id, player_id, tick, type, amount)
      values (p_game_id, v_p.id, 0, 'starting_gold', v_game.starting_gold);
    end if;

    insert into public.realm_areas (game_id, player_id, area, level, is_active)
    select p_game_id, v_p.id, a, greatest(1, coalesce((v_game.area_start_levels ->> a)::int, 1)), a = 'armory'
    from unnest(array['armory', 'mint', 'barracks', 'guildhall', 'watchtowers', 'library', 'stables']) as a;

    perform public.refresh_effective_influence(p_game_id, v_p.id);
    for v_i in 1 .. 1 + v_game.starting_commanders loop
      v_school := case
        when v_p.starting_schools is not null
         and array_length(v_p.starting_schools, 1) = 1 + v_game.starting_commanders
        then v_p.starting_schools[v_i]
        else (array['battleschool', 'university', 'rangers'])[1 + floor(random() * 3)::int]
      end;
      perform public.create_commander(
        p_game_id, v_p.id, v_school,
        case when v_i = 1 then 'king' else 'commander' end,
        v_p.capital_territory_id, 0
      );
    end loop;
  end loop;

  insert into public.diplomacy (game_id, player_a_id, player_b_id)
  select p_game_id, a.id, b.id
  from public.game_players a
  join public.game_players b on b.game_id = a.game_id and b.id > a.id
  where a.game_id = p_game_id;

  insert into public.game_moments (game_id, tick, type, payload)
  values (
    p_game_id, 0, 'game_started',
    jsonb_build_object('players', (
      select jsonb_agg(jsonb_build_object('player_id', id, 'faction', faction_slug, 'is_ai', is_ai) order by id)
      from public.game_players where game_id = p_game_id
    ))
  );

  insert into public.game_events (game_id, tick, type, payload)
  values (p_game_id, 0, 'game_started', jsonb_build_object('players', v_target, 'ai_players', v_ai_needed));

  insert into public.player_inbox (game_id, player_id, type, title, body, tick)
  select p_game_id, id, 'system', 'The realm awaits', jsonb_build_object('kind', 'game_started'), 0
  from public.game_players
  where game_id = p_game_id and not is_ai;

  update public.games
  set status = 'active',
      current_tick = 0,
      last_tick_processed_at = now(),
      pick_deadline = null,
      current_turn_ends_at = case
        when tick_speed = 'turn_based' then now() + make_interval(mins => turn_timeout_minutes)
        else null
      end
  where id = p_game_id;
end;
$function$;

revoke all on function public.begin_start_picking(integer), public.finalize_start(integer) from public, anon, authenticated;

create or replace function public.pick_start(p_game_id integer, p_seat integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_game public.games%rowtype;
  v_me public.game_players%rowtype;
  v_taken int;
  v_all boolean;
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;
  select * into v_game from public.games where id = p_game_id for update;
  if not found or v_game.status <> 'picking' then
    raise exception 'this game is not choosing start locations';
  end if;
  select * into v_me from public.game_players where game_id = p_game_id and user_id = v_uid;
  if not found then
    raise exception 'you are not in this game';
  end if;
  select player_id into v_taken from public.start_seats where game_id = p_game_id and seat = p_seat for update;
  if not found then
    raise exception 'unknown start location';
  end if;
  if v_taken is not null and v_taken <> v_me.id then
    raise exception 'that start location is already taken';
  end if;

  update public.start_seats set player_id = null where game_id = p_game_id and player_id = v_me.id;
  update public.start_seats set player_id = v_me.id where game_id = p_game_id and seat = p_seat;

  v_all := not exists (
    select 1 from public.game_players gp
    where gp.game_id = p_game_id and not gp.is_ai
      and not exists (select 1 from public.start_seats ss where ss.game_id = p_game_id and ss.player_id = gp.id)
  );
  if v_all then
    perform public.finalize_start(p_game_id);
  end if;
  return jsonb_build_object('seat', p_seat, 'started', v_all);
end;
$function$;

create or replace function public.get_start_options(p_game_id integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_g public.games%rowtype;
  v_me int;
begin
  if (select auth.uid()) is null then
    raise exception 'not signed in';
  end if;
  select * into v_g from public.games where id = p_game_id;
  select gp.id into v_me from public.game_players gp where gp.game_id = p_game_id and gp.user_id = (select auth.uid());
  if v_me is null then
    raise exception 'you are not in this game';
  end if;
  return jsonb_build_object(
    'status', v_g.status,
    'deadline', v_g.pick_deadline,
    'fog_dark', v_g.fog_dark,
    'map_w', v_g.map_w,
    'me', v_me,
    'seats', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'seat', ss.seat, 'x', t.x, 'y', t.y, 'name', t.name, 'player_id', ss.player_id,
        'display_name', gp.display_name, 'faction_slug', gp.faction_slug
      ) order by ss.seat), '[]'::jsonb)
      from public.start_seats ss
      join public.game_territories t on t.id = ss.capital_territory_id
      left join public.game_players gp on gp.id = ss.player_id
      where ss.game_id = p_game_id
    ),
    'castles', case when v_g.fog_dark then '[]'::jsonb else (
      select coalesce(jsonb_agg(jsonb_build_object('x', t.x, 'y', t.y, 'tier', t.tier)), '[]'::jsonb)
      from public.game_territories t where t.game_id = p_game_id
    ) end
  );
end;
$function$;

revoke all on function public.pick_start(integer, integer), public.get_start_options(integer) from public, anon;
grant execute on function public.pick_start(integer, integer), public.get_start_options(integer) to authenticated;

create or replace function public.finalize_due_picks()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_g record;
  v_n int := 0;
begin
  for v_g in select id from public.games where status = 'picking' and pick_deadline <= now() order by id loop
    perform public.finalize_start(v_g.id);
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$function$;

revoke all on function public.finalize_due_picks() from public, anon, authenticated;
select cron.schedule('finalize-due-picks', '* * * * *', 'select public.finalize_due_picks()');

create extension if not exists pg_net;

create or replace function public.auto_start_when_full()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_g public.games%rowtype;
begin
  select * into v_g from public.games where id = new.game_id;
  if v_g.auto_start and v_g.status = 'lobby'
     and (select count(*) from public.game_players where game_id = new.game_id) >= v_g.max_players then
    perform net.http_post(
      url := 'https://gyofddvzluokqvrcspxq.supabase.co/functions/v1/start-game',
      headers := '{"Content-Type": "application/json"}'::jsonb,
      body := jsonb_build_object('game_id', new.game_id)
    );
  end if;
  return new;
end;
$function$;

revoke all on function public.auto_start_when_full() from public, anon, authenticated;
drop trigger if exists auto_start_when_full on public.game_players;
create trigger auto_start_when_full after insert on public.game_players
  for each row execute function public.auto_start_when_full();

do $patch$
declare
  v_def text;
  v_new text;
  v_i1 int;
  v_i2 int;
begin
  select pg_get_functiondef('public.start_game(integer,jsonb)'::regprocedure) into v_def;
  v_i1 := position('for v_p in select * from public.game_players where game_id = p_game_id order by id loop' in v_def);
  v_i2 := position(E'  return jsonb_build_object(\n    ''game_id'', p_game_id,' in v_def);
  if v_i1 = 0 or v_i2 = 0 or v_i2 < v_i1 then raise exception 'start_game markers not found'; end if;
  v_new := substr(v_def, 1, v_i1 - 1)
    || E'if v_game.start_selection = ''choose'' then\n    perform public.begin_start_picking(p_game_id);\n  else\n    perform public.finalize_start(p_game_id);\n  end if;\n\n'
    || substr(v_def, v_i2);
  execute v_new;

  select pg_get_functiondef('public.get_game_view(integer)'::regprocedure) into v_def;
  v_new := replace(v_def, 'and (not (v_fog and v_g.fog_dark) or v.seen', 'and (v_g.status <> ''picking'' or not v_g.fog_dark) and (not (v_fog and v_g.fog_dark) or v.seen');
  if v_new = v_def then raise exception 'get_game_view patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.create_game(jsonb)'::regprocedure) into v_def;
  v_new := replace(v_def, '''star_scatter'', ''mirrored''', '''star_scatter'', ''mirrored'', ''start_selection'', ''pick_minutes''');
  v_new := replace(v_new, 'star_scatter = coalesce(p_settings ->> ''star_scatter'', g.star_scatter),',
    'star_scatter = coalesce(p_settings ->> ''star_scatter'', g.star_scatter),
      start_selection = coalesce(p_settings ->> ''start_selection'', g.start_selection),
      pick_minutes = coalesce((p_settings ->> ''pick_minutes'')::int, g.pick_minutes),');
  if v_new = v_def or v_new not like '%start_selection = coalesce%' or v_new not like '%''start_selection'', ''pick_minutes''%' then
    raise exception 'create_game patch did not apply';
  end if;
  execute v_new;
end;
$patch$;
