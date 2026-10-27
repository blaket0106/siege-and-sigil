create or replace function public.march_range(p_game_id integer, p_stables integer)
returns float8
language sql
stable
set search_path = ''
as $f$
  select coalesce(g.gap, 3780) * (0.8 + 0.2 * p_stables)
  from public.games g
  where g.id = p_game_id
$f$;
