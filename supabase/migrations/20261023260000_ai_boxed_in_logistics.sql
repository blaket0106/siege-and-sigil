do $patch$
declare
  v_def text;
  v_new text;
  v_pairs text[];
  i int;
begin
  v_pairs := array[
    '  v_gold int;' || chr(10) || 'begin',
    '  v_gold int;' || chr(10) || '  v_tt int;' || chr(10) || '  v_keep int;' || chr(10) || '  v_min_gold int;' || chr(10) || 'begin',
    '  for v_r in' || chr(10) || '    select gt.id, gt.troops',
    '  select troops into v_tt from public.game_territories where id = v_target;' || chr(10) || '  for v_r in' || chr(10) || '    select gt.id, gt.troops',
    '      and not (gt.id = any (v_front))' || chr(10) || '      and gt.troops - v_reserve >= 15' || chr(10),
    '      and gt.id <> v_target' || chr(10) || '      and gt.troops - v_reserve >= 15' || chr(10) || '      and (not (gt.id = any (v_front)) or gt.troops >= 2 * v_tt + 30)' || chr(10),
    '    order by gt.troops desc, gt.id' || chr(10) || '    limit 2',
    '    order by (gt.id = any (v_front)), gt.troops desc, gt.id' || chr(10) || '    limit 2',
    '    v_cmd := null;' || chr(10) || '    select c.id into v_cmd',
    '    v_keep := v_reserve + 10;' || chr(10) || '    if v_r.id = any (v_front) then' || chr(10) || '      v_keep := greatest(v_keep, v_r.troops / 2);' || chr(10) || '    end if;' || chr(10) || '    v_cmd := null;' || chr(10) || '    select c.id into v_cmd',
    '      if v_gold >= v_game.commander_cost + 100 then',
    '      v_min_gold := 100;' || chr(10) || '      if v_loops < 2 then' || chr(10) || '        v_min_gold := 0;' || chr(10) || '      end if;' || chr(10) || '      if v_gold >= v_game.commander_cost + v_min_gold then',
    '''amount'', case when v_i = 1 then v_reserve + 10 else 0 end',
    '''amount'', case when v_i = 1 then v_keep else 0 end',
    '      if v_r.troops - (v_reserve + 10) > 0 then' || chr(10) || '        perform public.transfer_troops_core(p_game_id, p_player_id, v_cmd, v_r.troops - (v_reserve + 10));',
    '      if v_r.troops - v_keep > 0 then' || chr(10) || '        perform public.transfer_troops_core(p_game_id, p_player_id, v_cmd, v_r.troops - v_keep);'
  ];
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'ai_logistics' and p.pronamespace = 'public'::regnamespace;
  v_new := v_def;
  for i in 1 .. array_length(v_pairs, 1) / 2 loop
    if position(v_pairs[2 * i - 1] in v_new) = 0 then
      raise exception 'ai_logistics patch % did not match', i;
    end if;
    v_new := replace(v_new, v_pairs[2 * i - 1], v_pairs[2 * i]);
  end loop;
  execute v_new;
end;
$patch$;
