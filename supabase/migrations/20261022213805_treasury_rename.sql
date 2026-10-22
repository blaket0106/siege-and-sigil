alter table public.game_territories rename column gold_level to treasury_level;
alter table public.games rename column starting_gold_level to starting_treasury_level;
alter table public.game_territories rename constraint game_territories_gold_level_check to game_territories_treasury_level_check;
alter table public.games rename constraint games_starting_gold_level_check to games_starting_treasury_level_check;

do $patch$
declare
  r record;
  v_def text;
begin
  for r in
    select p.oid
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f'
      and pg_get_functiondef(p.oid) like '%gold_level%'
  loop
    v_def := replace(pg_get_functiondef(r.oid), 'gold_level', 'treasury_level');
    execute v_def;
  end loop;
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and pg_get_functiondef(p.oid) like '%gold_level%' and p.prokind = 'f'
  ) then
    raise exception 'gold_level still referenced';
  end if;
end;
$patch$;
