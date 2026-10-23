delete from public.territory_edges where kind = 'wormhole';
alter table public.territory_edges drop constraint if exists territory_edges_kind_check;
alter table public.territory_edges add constraint territory_edges_kind_check check (kind in ('land', 'river', 'pass', 'sea'));
alter table public.games drop column if exists wormholes;

do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.create_game(jsonb)'::regprocedure) into v_def;
  v_new := replace(v_def, '''home_distance'', ''wormholes'', ''anonymity'',', '''home_distance'', ''anonymity'',');
  v_new := replace(v_new, '      wormholes = coalesce(p_settings ->> ''wormholes'', g.wormholes),
', '');
  if v_new = v_def or v_new like '%wormholes%' then
    raise exception 'create_game patch did not apply';
  end if;
  execute v_new;
end;
$patch$;
