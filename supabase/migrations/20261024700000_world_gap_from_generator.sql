do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.commit_world'::regproc) into v_def;
  v_new := replace(v_def, 'gap = public.compute_gap(p_game_id)', 'gap = coalesce((p_layout ->> ''gap'')::float8, public.compute_gap(p_game_id))');
  if v_new = v_def then
    raise exception 'commit_world patch did not match';
  end if;
  execute v_new;
end;
$patch$;
