do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.run_ai_players(integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def, 'v_interval := case v_p.diff when 1 then 6 when 2 then 4 when 3 then 3 when 4 then 2 else 1 end;', 'v_interval := 1;');
  if v_new = v_def then
    raise exception 'run_ai_players patch did not apply';
  end if;
  execute v_new;
end;
$patch$;
