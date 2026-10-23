do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.send_on_route(integer,integer,jsonb,text,jsonb)'::regprocedure) into v_def;
  v_new := replace(v_def, '  select current_tick into v_tick from public.games where id = p_game_id;' || chr(10) || chr(10) || '  insert into public.commander_routes', '  select current_tick into v_tick from public.games where id = p_game_id;' || chr(10) || chr(10) || '  update public.commander_routes set status = ''aborted'', resume_tick = null where commander_id = v_c.id and status = ''active'';' || chr(10) || chr(10) || '  insert into public.commander_routes');
  if v_new = v_def then
    raise exception 'send_on_route patch did not apply';
  end if;
  execute v_new;
end;
$patch$;
