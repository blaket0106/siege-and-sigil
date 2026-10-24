do $patch$
declare
  v_def text;
  v_new text;
  v_pairs text[] := array[
    '    select c.id, c.current_territory_id' || chr(10) || '    from public.commanders c' || chr(10) || '    join public.game_territories gt on gt.id = c.current_territory_id and gt.owner_player_id = p_player_id',
    '    select c.id, c.current_territory_id, gt.owner_player_id as terr_owner' || chr(10) || '    from public.commanders c' || chr(10) || '    join public.game_territories gt on gt.id = c.current_territory_id and (gt.owner_player_id = p_player_id or gt.owner_player_id = any (v_allies))',
    '    if v_gar - v_reserve > 0 then',
    '    if v_c.terr_owner = p_player_id and v_gar - v_reserve > 0 then'
  ];
  i int;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'ai_commanders' and p.pronamespace = 'public'::regnamespace;
  v_new := v_def;
  for i in 1 .. array_length(v_pairs, 1) / 2 loop
    if position(v_pairs[2 * i - 1] in v_new) = 0 then
      raise exception 'ai_commanders allied patch % did not match', i;
    end if;
    v_new := replace(v_new, v_pairs[2 * i - 1], v_pairs[2 * i]);
  end loop;
  execute v_new;
end;
$patch$;
