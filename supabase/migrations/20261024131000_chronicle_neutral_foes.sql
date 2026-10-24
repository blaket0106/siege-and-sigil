do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'log_battle_history' and p.pronamespace = 'public'::regnamespace;
  if position('coalesce(public.house_name(v_enemy), ''the enemy'')' in v_def) = 0 then
    raise exception 'log_battle_history patch did not match';
  end if;
  v_new := replace(v_def, 'coalesce(public.house_name(v_enemy), ''the enemy'')', 'coalesce(''House '' || public.house_name(v_enemy), ''the free garrison'')');
  v_new := replace(v_new, 'House %s', '%s');
  execute v_new;
end;
$patch$;
