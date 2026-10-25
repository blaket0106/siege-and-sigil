create function public.soak_time(p_game int, p_n int)
returns text
language plpgsql
security definer
set search_path = ''
as $f$
declare
  t0 timestamptz := clock_timestamp();
  i int;
begin
  for i in 1 .. p_n loop
    perform public.run_tick(p_game);
  end loop;
  return format('tick %s, %s ms per tick', (select current_tick from public.games where id = p_game), round(extract(epoch from clock_timestamp() - t0) * 1000 / p_n));
end;
$f$;
revoke execute on function public.soak_time(int, int) from public, anon, authenticated;
