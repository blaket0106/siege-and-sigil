alter table public.game_players add column if not exists last_active_at timestamptz not null default now();

create or replace function public.touch_activity(p_game_id integer)
returns void
language sql
security definer
set search_path = ''
as $function$
  update public.game_players
  set last_active_at = now()
  where game_id = p_game_id and user_id = (select auth.uid());
$function$;

revoke all on function public.touch_activity(integer) from public, anon;
grant execute on function public.touch_activity(integer) to authenticated;

create or replace function public.auto_concede_inactive()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_p record;
  v_count int := 0;
begin
  for v_p in
    select gp.id, gp.game_id, g.current_tick
    from public.game_players gp
    join public.games g on g.id = gp.game_id
    where g.status = 'active'
      and gp.user_id is not null
      and not gp.is_ai
      and gp.eliminated_at_tick is null
      and gp.last_active_at < now() - interval '72 hours'
    order by gp.game_id, gp.id
  loop
    continue when not exists (select 1 from public.games where id = v_p.game_id and status = 'active');
    perform public.eliminate_player(v_p.game_id, v_p.id, v_p.current_tick, 'inactive');
    perform public.evaluate_game_end(v_p.game_id, v_p.current_tick);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

revoke all on function public.auto_concede_inactive() from public, anon, authenticated;

select cron.schedule('auto-concede-inactive', '23 * * * *', 'select public.auto_concede_inactive()');
