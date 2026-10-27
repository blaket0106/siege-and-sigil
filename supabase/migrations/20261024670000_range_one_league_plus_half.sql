do $patch$
declare
  v_fn text;
  v_def text;
  v_new text;
begin
  foreach v_fn in array array['plan_march', 'plan_march_from'] loop
    select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = v_fn and p.pronamespace = 'public'::regnamespace;
    v_new := replace(v_def, '(300 + 120 * coalesce(v_stables, 0))', '(75 + 75 * coalesce(v_stables, 1))');
    if v_new = v_def then
      raise exception '% patch did not match', v_fn;
    end if;
    execute v_new;
  end loop;
end;
$patch$;
