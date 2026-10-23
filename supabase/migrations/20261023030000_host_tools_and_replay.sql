alter table public.games add column if not exists paused_at timestamptz;
grant select (paused_at) on public.games to authenticated;

do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.process_game(integer)'::regprocedure) into v_def;
  v_new := replace(v_def, '  if v_game.tick_speed = ''turn_based'' then' || chr(10) || '    v_ready := not exists (', '  if v_game.paused_at is not null then' || chr(10) || '    return jsonb_build_object(' || chr(10) || '      ''pending_ticks'', 0, ''ticks_processed'', 0, ''gold_added'', 0, ''troops_added'', 0, ''cycles_fired'', 0,' || chr(10) || '      ''arrivals'', 0, ''contacts'', 0, ''combats'', 0, ''combat_events'', ''[]''::jsonb,' || chr(10) || '      ''game_status'', v_game.status, ''winner_player_id'', v_game.winner_player_id' || chr(10) || '    );' || chr(10) || '  end if;' || chr(10) || chr(10) || '  if v_game.tick_speed = ''turn_based'' then' || chr(10) || '    v_ready := not exists (');
  if v_new = v_def or v_new not like '%paused_at is not null%' then
    raise exception 'process_game patch did not apply';
  end if;
  execute v_new;
end;
$patch$;

create function public.admin_set_paused(p_game_id integer, p_paused boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_g public.games%rowtype;
  v_shift interval;
begin
  if (select auth.uid()) is null then
    raise exception 'not signed in';
  end if;
  select * into v_g from public.games where id = p_game_id for update;
  if not found or v_g.created_by <> (select auth.uid()) then
    raise exception 'only the host can pause the game';
  end if;
  if v_g.status <> 'active' then
    raise exception 'the game is not in progress';
  end if;

  if p_paused and v_g.paused_at is null then
    update public.games set paused_at = now() where id = p_game_id;
  elsif not p_paused and v_g.paused_at is not null then
    v_shift := now() - v_g.paused_at;
    update public.games
    set paused_at = null,
        last_tick_processed_at = last_tick_processed_at + v_shift,
        current_turn_ends_at = current_turn_ends_at + v_shift
    where id = p_game_id;
  end if;
  return jsonb_build_object('paused', p_paused);
end;
$function$;

create function public.admin_jump_ticks(p_game_id integer, p_ticks integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_g public.games%rowtype;
  v_i int;
  v_status text;
begin
  if (select auth.uid()) is null then
    raise exception 'not signed in';
  end if;
  if p_ticks is null or p_ticks not between 1 and 5 then
    raise exception 'jump 1 to 5 ticks';
  end if;
  select * into v_g from public.games where id = p_game_id for update;
  if not found or v_g.created_by <> (select auth.uid()) then
    raise exception 'only the host can jump ticks';
  end if;
  if v_g.status <> 'active' then
    raise exception 'the game is not in progress';
  end if;
  if exists (select 1 from public.game_players gp where gp.game_id = p_game_id and not gp.is_ai and gp.user_id is distinct from v_g.created_by) then
    raise exception 'jumping ticks is only available while you are the only human in the game';
  end if;

  for v_i in 1 .. p_ticks loop
    perform public.run_tick(p_game_id);
    select status into v_status from public.games where id = p_game_id;
    exit when v_status <> 'active';
  end loop;

  insert into public.game_events (game_id, tick, type, payload)
  select p_game_id, g.current_tick, 'admin_jump', jsonb_build_object('ticks', p_ticks)
  from public.games g where g.id = p_game_id;

  return jsonb_build_object('tick', (select current_tick from public.games where id = p_game_id), 'status', v_status);
end;
$function$;

revoke all on function public.admin_set_paused(integer, boolean), public.admin_jump_ticks(integer, integer) from public, anon;
grant execute on function public.admin_set_paused(integer, boolean), public.admin_jump_ticks(integer, integer) to authenticated;

create table public.territory_owner_log (
  game_id integer not null references public.games (id) on delete cascade,
  tick integer not null,
  territory_id integer not null,
  owner_player_id integer,
  primary key (game_id, tick, territory_id)
);
alter table public.territory_owner_log enable row level security;
revoke all on public.territory_owner_log from anon, authenticated;

create function public.log_territory_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  insert into public.territory_owner_log (game_id, tick, territory_id, owner_player_id)
  values (new.game_id, coalesce((select g.current_tick from public.games g where g.id = new.game_id), 0), new.id, new.owner_player_id)
  on conflict (game_id, tick, territory_id) do update set owner_player_id = excluded.owner_player_id;
  return new;
end;
$function$;

create trigger territory_owner_log_insert after insert on public.game_territories
  for each row execute function public.log_territory_owner();
create trigger territory_owner_log_update after update of owner_player_id on public.game_territories
  for each row when (old.owner_player_id is distinct from new.owner_player_id) execute function public.log_territory_owner();

create function public.get_replay(p_game_id integer)
returns table(tick integer, territory_id integer, owner_player_id integer)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if (select auth.uid()) is null then
    raise exception 'not signed in';
  end if;
  if not public.is_game_member(p_game_id) then
    raise exception 'you are not in this game';
  end if;
  if not exists (select 1 from public.games g where g.id = p_game_id and g.status = 'finished') then
    raise exception 'the replay opens when the game ends';
  end if;
  return query
    select l.tick, l.territory_id, l.owner_player_id
    from public.territory_owner_log l
    where l.game_id = p_game_id
    order by l.tick, l.territory_id;
end;
$function$;

revoke all on function public.get_replay(integer) from public, anon;
grant execute on function public.get_replay(integer) to authenticated;
