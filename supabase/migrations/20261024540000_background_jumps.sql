alter table public.games add column if not exists jump_remaining int not null default 0;
grant select (jump_remaining) on public.games to authenticated;

drop function if exists public.admin_jump_ticks(int, int);
create function public.admin_jump_ticks(p_game_id int, p_ticks int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $f$
declare
  v_g public.games%rowtype;
begin
  if (select auth.uid()) is null then
    raise exception 'not signed in';
  end if;
  if p_ticks is null or p_ticks not between 1 and 24 then
    raise exception 'jump 1 to 24 ticks';
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
  update public.games set jump_remaining = least(48, jump_remaining + p_ticks) where id = p_game_id;
  insert into public.game_events (game_id, tick, type, payload)
  values (p_game_id, v_g.current_tick, 'admin_jump', jsonb_build_object('ticks', p_ticks));
  return jsonb_build_object('queued', p_ticks, 'tick', v_g.current_tick, 'remaining', least(48, v_g.jump_remaining + p_ticks));
end;
$f$;
revoke execute on function public.admin_jump_ticks(int, int) from public, anon;
grant execute on function public.admin_jump_ticks(int, int) to authenticated;

create function public.process_jumps()
returns int
language plpgsql
security definer
set search_path = ''
as $f$
declare
  v_g record;
  v_done int := 0;
  v_i int;
  v_n int;
  v_status text;
begin
  for v_g in
    select g.id, g.jump_remaining from public.games g
    where g.jump_remaining > 0 and g.status = 'active'
    order by g.id
    for update skip locked
  loop
    v_n := least(v_g.jump_remaining, 5);
    for v_i in 1 .. v_n loop
      perform public.run_tick(v_g.id);
      v_done := v_done + 1;
      update public.games set jump_remaining = greatest(jump_remaining - 1, 0) where id = v_g.id;
      select status into v_status from public.games where id = v_g.id;
      exit when v_status <> 'active';
    end loop;
    if v_status is not null and v_status <> 'active' then
      update public.games set jump_remaining = 0 where id = v_g.id;
    end if;
  end loop;
  return v_done;
end;
$f$;
revoke execute on function public.process_jumps() from public, anon, authenticated;

select cron.schedule('process-jumps', '3 seconds', 'select public.process_jumps()');
