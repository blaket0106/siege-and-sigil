do $patch$
declare
  v_def text;
  v_new text;
  v_a text := '''fog_dark'', ''map_shape'',';
  v_b text := '      fog_dark = coalesce((p_settings ->> ''fog_dark'')::boolean, g.fog_dark),';
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'create_game' and p.pronamespace = 'public'::regnamespace;
  if position(v_a in v_def) = 0 or position(v_b in v_def) = 0 then
    raise exception 'create_game patch did not match';
  end if;
  v_new := replace(v_def, v_a, '''fog_dark'', ''neutral_armory'', ''map_shape'',');
  v_new := replace(v_new, v_b, v_b || chr(10) || '      neutral_armory = coalesce((p_settings ->> ''neutral_armory'')::int, g.neutral_armory),');
  execute v_new;
end;
$patch$;
