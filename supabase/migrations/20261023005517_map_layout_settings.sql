alter table public.games
  add column if not exists star_scatter text not null default 'random' check (star_scatter in ('random', 'twin_rings')),
  add column if not exists mirrored boolean not null default false;
grant select (star_scatter, mirrored) on public.games to authenticated;

do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.create_game(jsonb)'::regprocedure) into v_def;
  v_new := replace(v_def, '''password'', ''resource_richness''', '''password'', ''resource_richness'', ''star_scatter'', ''mirrored''');
  v_new := replace(v_new, 'resource_richness = coalesce(p_settings ->> ''resource_richness'', g.resource_richness),',
    'resource_richness = coalesce(p_settings ->> ''resource_richness'', g.resource_richness),
      star_scatter = coalesce(p_settings ->> ''star_scatter'', g.star_scatter),
      mirrored = coalesce((p_settings ->> ''mirrored'')::boolean, g.mirrored),');
  v_new := replace(v_new, '  v_faction := p_settings ->> ''faction_slug'';',
    '  if v_game.mirrored and v_game.max_players not in (2, 4, 8) then
    raise exception ''mirrored stars need 2, 4 or 8 players'';
  end if;
  v_faction := p_settings ->> ''faction_slug'';');
  if v_new = v_def or v_new not like '%star_scatter = coalesce%' or v_new not like '%mirrored stars need%' or v_new not like '%''star_scatter'', ''mirrored''%' then
    raise exception 'create_game patch did not apply';
  end if;
  execute v_new;
end;
$patch$;
