alter table public.games add column if not exists gap float8;

create or replace function public.compute_gap(p_game_id integer)
returns float8
language sql
stable
set search_path = ''
as $f$
  select coalesce(
    (
      select percentile_cont(0.5) within group (order by e.length)
      from public.territory_edges e
      join public.game_territories a on a.id = e.from_territory_id and not a.is_junction
      join public.game_territories b on b.id = e.to_territory_id and not b.is_junction
      where e.game_id = p_game_id
    ),
    (
      select percentile_cont(0.5) within group (order by d.m)
      from (
        select min(sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)) as m
        from public.game_territories a
        join public.game_territories b on b.game_id = a.game_id and b.id <> a.id and not b.is_junction
        where a.game_id = p_game_id and not a.is_junction
        group by a.id
      ) d
    )
  )
$f$;

create or replace function public.march_range(p_game_id integer, p_stables integer)
returns float8
language sql
stable
set search_path = ''
as $f$
  select coalesce(g.gap, 3780) * (0.6 + 0.2 * p_stables)
  from public.games g
  where g.id = p_game_id
$f$;

update public.games g set gap = public.compute_gap(g.id) where g.gap is null;

do $patch$
declare
  v_fn text;
  v_def text;
  v_new text;
begin
  foreach v_fn in array array['plan_march', 'plan_march_from'] loop
    select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = v_fn and p.pronamespace = 'public'::regnamespace;
    v_new := replace(v_def, '(75 + 75 * coalesce(v_stables, 1)) * (select g.unit_scale from public.games g where g.id = v_c.game_id)', 'public.march_range(v_c.game_id, coalesce(v_stables, 1))');
    if v_new = v_def then
      raise exception '% patch did not match', v_fn;
    end if;
    execute v_new;
  end loop;

  select pg_get_functiondef('public.commit_world'::regproc) into v_def;
  v_new := replace(v_def, 'map_art = p_layout -> ''art''', 'map_art = p_layout -> ''art'', gap = public.compute_gap(p_game_id)');
  if v_new = v_def then
    raise exception 'commit_world patch did not match';
  end if;
  execute v_new;
end;
$patch$;
