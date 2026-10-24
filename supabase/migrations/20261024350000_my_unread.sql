create function public.my_unread()
returns table(game_id int, unread int)
language sql
stable
security definer
set search_path = ''
as $f$
  select gp.game_id, count(*) filter (where not i.is_read)::int
  from public.game_players gp
  join public.player_inbox i on i.player_id = gp.id
  where gp.user_id = (select auth.uid())
  group by gp.game_id
$f$;
revoke execute on function public.my_unread() from public, anon;
grant execute on function public.my_unread() to authenticated;
