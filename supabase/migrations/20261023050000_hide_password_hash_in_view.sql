do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.get_game_view(integer)'::regprocedure) into v_def;
  v_new := replace(v_def, '- ''world_seed'' - ''generator_version'' - ''map_art''', '- ''world_seed'' - ''generator_version'' - ''map_art'' - ''password_hash''');
  if v_new = v_def then
    raise exception 'get_game_view patch did not apply';
  end if;
  execute v_new;
end;
$patch$;
