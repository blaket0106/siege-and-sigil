alter table public.games add column if not exists neutral_armory int not null default 1 check (neutral_armory between 0 and 3);
grant select (neutral_armory) on public.games to authenticated;

do $patch$
declare
  v_def text;
  v_new text;
  v_fn text;
  v_old text;
  v_rep text;
begin
  for v_fn, v_old, v_rep in
    select * from (values
      ('fight_castle', E'    when v_owner is null then 1\n', E'    when v_owner is null then (select g.neutral_armory from public.games g where g.id = p_game_id)\n'),
      ('ai_sieges', 'case when v_t.owner_player_id is null then 1 else', 'case when v_t.owner_player_id is null then (select g.neutral_armory from public.games g where g.id = p_game_id) else'),
      ('ai_commanders', 'case when v_t.owner_player_id is null then 1 else', 'case when v_t.owner_player_id is null then (select g.neutral_armory from public.games g where g.id = p_game_id) else')
    ) as t(fn, o, r)
  loop
    select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = v_fn and p.pronamespace = 'public'::regnamespace order by p.oid limit 1;
    if position(v_old in v_def) = 0 then
      raise exception '% patch did not match', v_fn;
    end if;
    v_new := replace(v_def, v_old, v_rep);
    execute v_new;
  end loop;
end;
$patch$;
