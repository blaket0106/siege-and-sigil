alter table public.commander_routes rename column loop to looping;

do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.route_size(public.commander_routes)'::regprocedure) into v_def;
  v_new := replace(v_def, 'p_route.loop', 'p_route.looping');
  if v_new = v_def then raise exception 'route_size patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.continue_route(integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def, 'v_route.loop', 'v_route.looping');
  if v_new = v_def then raise exception 'continue_route patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.send_on_route(integer,integer,jsonb,text,jsonb)'::regprocedure) into v_def;
  v_new := replace(v_def, 'origin_territory_id, loop, origin_order', 'origin_territory_id, looping, origin_order');
  if v_new = v_def then raise exception 'send_on_route patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.set_route_loop(integer,integer,boolean)'::regprocedure) into v_def;
  v_new := replace(v_def, 'set loop = p_loop', 'set looping = p_loop');
  if v_new = v_def then raise exception 'set_route_loop patch did not apply'; end if;
  execute v_new;
end;
$patch$;
