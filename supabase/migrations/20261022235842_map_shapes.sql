alter table public.games add column if not exists map_shape text not null default 'continent' check (map_shape in ('continent', 'round', 'ring', 'twin', 'archipelago', 'rift'));
grant select (map_shape) on public.games to authenticated;

do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.create_game(jsonb)'::regprocedure) into v_def;
  v_new := replace(v_def, '''world_scale'', ''free_travel'', ''fog_dark'',', '''world_scale'', ''free_travel'', ''fog_dark'', ''map_shape'',');
  v_new := replace(v_new, 'fog_dark = coalesce((p_settings ->> ''fog_dark'')::boolean, g.fog_dark),', 'map_shape = coalesce(p_settings ->> ''map_shape'', g.map_shape),
      fog_dark = coalesce((p_settings ->> ''fog_dark'')::boolean, g.fog_dark),');
  if v_new = v_def or v_new not like '%''map_shape'',%' or v_new not like '%map_shape = coalesce%' then
    raise exception 'create_game patch did not apply';
  end if;
  execute v_new;
end;
$patch$;
