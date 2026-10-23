alter table public.games
  add column if not exists home_distance text not null default 'medium' check (home_distance in ('close', 'medium', 'far')),
  add column if not exists wormholes text not null default 'none' check (wormholes in ('none', 'rare', 'common'));
grant select (home_distance, wormholes) on public.games to authenticated;

alter table public.territory_edges drop constraint if exists territory_edges_kind_check;
alter table public.territory_edges add constraint territory_edges_kind_check check (kind in ('land', 'river', 'pass', 'sea', 'wormhole'));

do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.create_game(jsonb)'::regprocedure) into v_def;
  v_new := replace(v_def, '''travel_mode'', ''map_preset'',', '''travel_mode'', ''map_preset'', ''home_distance'', ''wormholes'',');
  v_new := replace(v_new, 'map_preset = coalesce(p_settings ->> ''map_preset'', g.map_preset),', 'map_preset = coalesce(p_settings ->> ''map_preset'', g.map_preset),
      home_distance = coalesce(p_settings ->> ''home_distance'', g.home_distance),
      wormholes = coalesce(p_settings ->> ''wormholes'', g.wormholes),');
  if v_new = v_def or v_new not like '%''home_distance'', ''wormholes'',%' or v_new not like '%wormholes = coalesce%' then
    raise exception 'create_game patch did not apply';
  end if;
  execute v_new;
end;
$patch$;
