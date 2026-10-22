alter table public.games add column if not exists map_art jsonb;
grant select (map_art) on public.games to authenticated;

alter table public.game_territories drop constraint if exists game_territories_terrain_check;
alter table public.game_territories add constraint game_territories_terrain_check
  check (terrain = any (array['plains', 'forest', 'hills', 'mountain', 'coast']));

do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.commit_world(integer,jsonb)'::regprocedure) into v_def;
  v_new := replace(v_def, 'game_id, slug, name, tier, base_influence, x, y, owner_player_id,', 'game_id, slug, name, tier, base_influence, x, y, owner_player_id, terrain,');
  v_new := replace(v_new, '      v_owner,
      case when v_owner is null then (v_t ->> ''troops'')::int', '      v_owner,
      coalesce(v_t ->> ''terrain'', ''plains''),
      case when v_owner is null then (v_t ->> ''troops'')::int');
  v_new := replace(v_new, 'generator_version = (p_layout ->> ''generator_version'')::int', 'generator_version = (p_layout ->> ''generator_version'')::int,
      map_art = p_layout -> ''art''');
  if v_new = v_def or v_new not like '%owner_player_id, terrain,%' or v_new not like '%map_art = p_layout%' or v_new not like '%coalesce(v_t ->> ''terrain''%' then raise exception 'commit_world patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.get_game_view(integer)'::regprocedure) into v_def;
  v_new := replace(v_def, '- ''world_seed'' - ''generator_version''', '- ''world_seed'' - ''generator_version'' - ''map_art''');
  if v_new = v_def then raise exception 'get_game_view patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.fight_castle(integer,integer,integer,integer[],integer)'::regprocedure) into v_def;
  v_new := replace(v_def, 'v_def := greatest(1, v_def_armory + v_def_valor + 1);', 'v_def := greatest(1, v_def_armory + v_def_valor + 1 + case when v_t.terrain = ''mountain'' then 1 else 0 end);');
  if v_new = v_def then raise exception 'fight_castle patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.ai_commanders(integer,integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def, '+ public.side_valor(v_ids, v_t.garrison_commander_id) + 1', '+ public.side_valor(v_ids, v_t.garrison_commander_id) + 1 + case when v_t.terrain = ''mountain'' then 1 else 0 end');
  if v_new = v_def then raise exception 'ai_commanders patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.ai_sieges(integer,integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def, '+ public.side_valor(v_def, v_t.garrison_commander_id) + 1', '+ public.side_valor(v_def, v_t.garrison_commander_id) + 1 + case when v_t.terrain = ''mountain'' then 1 else 0 end');
  if v_new = v_def then raise exception 'ai_sieges patch did not apply'; end if;
  execute v_new;
end
$patch$;
