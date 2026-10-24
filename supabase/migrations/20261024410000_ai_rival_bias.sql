do $patch$
declare
  v_def text;
  v_new text;
  v_pairs text[] := array[
    'case v_style when ''aggressive'' then 0.8 when ''balanced'' then 0.3 else 0 end * greatest(0, 10 - coalesce(',
    'case v_style when ''aggressive'' then 1.5 when ''balanced'' then 0.6 else 0 end * greatest(0, 16 - coalesce(',
    E'), gt.id\n      limit 12',
    E'), gt.id\n      limit (case v_style when ''aggressive'' then 20 when ''balanced'' then 16 else 12 end)'
  ];
  i int;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'ai_commanders' and p.pronamespace = 'public'::regnamespace order by p.oid limit 1;
  v_new := v_def;
  for i in 1 .. array_length(v_pairs, 1) / 2 loop
    if position(v_pairs[2 * i - 1] in v_new) = 0 then
      raise exception 'ai_commanders bias patch % did not match', i;
    end if;
    v_new := replace(v_new, v_pairs[2 * i - 1], v_pairs[2 * i]);
  end loop;
  execute v_new;
end;
$patch$;
