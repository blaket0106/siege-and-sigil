do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.ai_commanders(integer,integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def, '    continue when v_att < 6;', '    if v_att < 6 then
      for v_t in
        select gt.id
        from public.game_territories gt
        where gt.game_id = p_game_id
          and gt.owner_player_id = p_player_id
          and gt.id <> v_c.current_territory_id
          and gt.troops - v_reserve + v_att >= 6
        order by gt.troops desc, gt.id
      loop
        begin
          perform public.launch_leg(p_player_id, v_c.id, v_t.id, ''assault'');
          exit;
        exception when others then
          null;
        end;
      end loop;
      continue;
    end if;');
  if v_new = v_def then
    raise exception 'ai_commanders patch did not apply';
  end if;
  execute v_new;
end;
$patch$;
