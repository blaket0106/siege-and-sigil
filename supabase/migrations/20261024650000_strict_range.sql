do $patch$
declare
  v_fn text;
  v_def text;
  v_new text;
begin
  foreach v_fn in array array['plan_march', 'plan_march_from'] loop
    select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = v_fn and p.pronamespace = 'public'::regnamespace;
    v_new := regexp_replace(v_def, '\(\(select count\(\*\)\s+from\s+unnest\(v_path_ids\)\s+pid\s+join\s+public\.game_territories\s+jt\s+on\s+jt\.id\s*=\s*pid\s+where\s+not\s+jt\.is_junction\)\s*=\s*2\s+or\s+v_raw\s*<=\s*v_range\)', 'v_raw <= v_range');
    if v_new = v_def then
      raise exception '% patch did not match', v_fn;
    end if;
    execute v_new;
  end loop;
end;
$patch$;
