alter table public.game_players add column ai_difficulty smallint check (ai_difficulty between 1 and 5);

alter table public.games drop constraint games_tick_speed_check;
alter table public.games add constraint games_tick_speed_check check (tick_speed = any (array['slow', 'normal', 'fast', 'quad', 'blitz', 'turn_based']));
alter table public.games alter column production_cycle_ticks set default 24;
alter table public.games alter column season_length_ticks set default 96;

create function public.add_ai_seat(p_game_id integer, p_difficulty integer default 3, p_faction text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  g public.games;
  v_faction text;
  v_name text;
  v_id integer;
begin
  select * into g from public.games where id = p_game_id and created_by = (select auth.uid()) for update;
  if not found then
    raise exception 'Only the host can change the seats';
  end if;
  if g.status <> 'lobby' then
    raise exception 'The game has already started';
  end if;
  if (select count(*) from public.game_players gp where gp.game_id = p_game_id) >= g.max_players then
    raise exception 'There is no open seat';
  end if;
  if p_faction is null then
    select f.slug, f.name into v_faction, v_name from public.factions f
    where not exists (select 1 from public.game_players gp where gp.game_id = p_game_id and gp.faction_slug = f.slug)
    order by random() limit 1;
  else
    select f.slug, f.name into v_faction, v_name from public.factions f where f.slug = p_faction;
    if v_faction is null then
      raise exception 'Unknown house';
    end if;
    if exists (select 1 from public.game_players gp where gp.game_id = p_game_id and gp.faction_slug = v_faction) then
      raise exception 'That house is already taken';
    end if;
  end if;
  if v_faction is null then
    raise exception 'No free house is left';
  end if;
  insert into public.game_players (game_id, faction_slug, display_name, is_ai, ai_difficulty)
  values (p_game_id, v_faction, 'AI ' || v_name, true, greatest(1, least(5, coalesce(p_difficulty, 3))))
  returning id into v_id;
  return v_id;
end;
$function$;

create function public.set_ai_seat(p_game_id integer, p_player_id integer, p_difficulty integer, p_faction text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  g public.games;
  v_name text;
begin
  select * into g from public.games where id = p_game_id and created_by = (select auth.uid()) for update;
  if not found then
    raise exception 'Only the host can change the seats';
  end if;
  if g.status <> 'lobby' then
    raise exception 'The game has already started';
  end if;
  if not exists (select 1 from public.game_players gp where gp.id = p_player_id and gp.game_id = p_game_id and gp.is_ai) then
    raise exception 'That seat is not an AI';
  end if;
  update public.game_players set ai_difficulty = greatest(1, least(5, coalesce(p_difficulty, 3))) where id = p_player_id;
  if p_faction is not null then
    select f.name into v_name from public.factions f where f.slug = p_faction;
    if v_name is null then
      raise exception 'Unknown house';
    end if;
    if exists (select 1 from public.game_players gp where gp.game_id = p_game_id and gp.faction_slug = p_faction and gp.id <> p_player_id) then
      raise exception 'That house is already taken';
    end if;
    update public.game_players set faction_slug = p_faction, display_name = 'AI ' || v_name where id = p_player_id;
  end if;
end;
$function$;

create function public.remove_ai_seat(p_game_id integer, p_player_id integer)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  g public.games;
begin
  select * into g from public.games where id = p_game_id and created_by = (select auth.uid()) for update;
  if not found then
    raise exception 'Only the host can change the seats';
  end if;
  if g.status <> 'lobby' then
    raise exception 'The game has already started';
  end if;
  delete from public.game_players where id = p_player_id and game_id = p_game_id and is_ai;
end;
$function$;

grant execute on function public.add_ai_seat(integer, integer, text), public.set_ai_seat(integer, integer, integer, text), public.remove_ai_seat(integer, integer) to authenticated;
revoke execute on function public.add_ai_seat(integer, integer, text), public.set_ai_seat(integer, integer, integer, text), public.remove_ai_seat(integer, integer) from anon, public;

create or replace function public.room_players(p_game_id integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_g public.games;
begin
  if not public.is_game_member(p_game_id) then
    raise exception 'you are not in this game';
  end if;
  select * into v_g from public.games where id = p_game_id;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', gp.id, 'game_id', gp.game_id, 'faction_slug', gp.faction_slug, 'display_name', gp.display_name,
      'is_ai', gp.is_ai, 'ai_difficulty', gp.ai_difficulty, 'eliminated_at_tick', gp.eliminated_at_tick, 'created_at', gp.created_at,
      'is_me', gp.user_id = (select auth.uid()),
      'is_host', gp.user_id = v_g.created_by and not (v_g.anonymity = 'extra' and v_g.status <> 'finished')
    ) order by gp.id)
    from public.game_players gp
    where gp.game_id = p_game_id
  ), '[]'::jsonb);
end;
$function$;

do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.ai_take_turn(integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def, 'select ai_difficulty into v_difficulty from public.games where id = p_game_id;',
    'select coalesce((select gp.ai_difficulty from public.game_players gp where gp.id = p_player_id), g.ai_difficulty) into v_difficulty from public.games g where g.id = p_game_id;');
  if v_new = v_def then raise exception 'ai_take_turn patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.run_ai_players(integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def, '  select case ai_difficulty when 1 then 6 when 2 then 4 when 3 then 3 when 4 then 2 else 1 end
  into v_interval
  from public.games where id = p_game_id;

  for v_p in
    select id from public.game_players
    where game_id = p_game_id and is_ai and eliminated_at_tick is null
    order by id
  loop
    continue when (p_tick + v_p.id) % v_interval <> 0;',
'  for v_p in
    select gp.id, coalesce(gp.ai_difficulty, g.ai_difficulty) as diff
    from public.game_players gp join public.games g on g.id = gp.game_id
    where gp.game_id = p_game_id and gp.is_ai and gp.eliminated_at_tick is null
    order by gp.id
  loop
    v_interval := case v_p.diff when 1 then 6 when 2 then 4 when 3 then 3 when 4 then 2 else 1 end;
    continue when (p_tick + v_p.id) % v_interval <> 0;');
  if v_new = v_def then raise exception 'run_ai_players patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.get_game_view(integer)'::regprocedure) into v_def;
  v_new := replace(v_def, 'when ''quad'' then 900000', 'when ''quad'' then 900000 when ''blitz'' then 300000');
  if v_new = v_def then raise exception 'get_game_view patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.process_game(integer)'::regprocedure) into v_def;
  v_new := replace(v_def, 'when ''fast'' then 1800 else 900 end', 'when ''fast'' then 1800 when ''blitz'' then 300 else 900 end');
  if v_new = v_def then raise exception 'process_game patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.process_due_games()'::regprocedure) into v_def;
  v_new := replace(v_def, 'when ''fast'' then 1800 else 900 end', 'when ''fast'' then 1800 when ''blitz'' then 300 else 900 end');
  if v_new = v_def then raise exception 'process_due_games patch did not apply'; end if;
  execute v_new;
end;
$patch$;
