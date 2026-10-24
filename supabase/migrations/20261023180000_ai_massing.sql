do $patch$
declare
  v_def text;
  v_new text;
  v_pairs text[] := array[
    '  v_hop int;' || chr(10) || 'begin',
    '  v_hop int;' || chr(10) || '  v_need float8;' || chr(10) || '  v_min_need float8;' || chr(10) || '  v_pool float8;' || chr(10) || '  v_src int;' || chr(10) || 'begin',
    '    v_far_score := -1e9;',
    '    v_far_score := -1e9;' || chr(10) || '    v_min_need := 1e18;',
    '      v_rd := ceil(v_def_est / v_atk_dmg)::int;',
    '      v_rd := ceil(v_def_est / v_atk_dmg)::int;' || chr(10) || '      v_need := v_def_dmg * v_rd + 1;' || chr(10) || '      if v_need < v_min_need then' || chr(10) || '        v_min_need := v_need;' || chr(10) || '      end if;',
    '    else' || chr(10) || '      select gt.id into v_dest',
    '    else' || chr(10) || '      v_src := null;' || chr(10) || '      if v_min_need < 1e17 then' || chr(10) || '        select coalesce(sum(greatest(gt.troops - v_reserve, 0)), 0) + v_att into v_pool' || chr(10) || '        from public.game_territories gt' || chr(10) || '        where gt.game_id = p_game_id and gt.owner_player_id = p_player_id and gt.id <> v_c.current_territory_id;' || chr(10) || '        if v_pool >= v_min_need then' || chr(10) || '          select gt.id into v_src' || chr(10) || '          from public.game_territories gt' || chr(10) || '          where gt.game_id = p_game_id and gt.owner_player_id = p_player_id and gt.id <> v_c.current_territory_id' || chr(10) || '            and gt.troops - v_reserve >= 12' || chr(10) || '          order by gt.troops desc, gt.id' || chr(10) || '          limit 1;' || chr(10) || '        end if;' || chr(10) || '      end if;' || chr(10) || '      if v_src is not null then' || chr(10) || '        begin' || chr(10) || '          v_plan := public.plan_march(p_player_id, v_c.id, v_src);' || chr(10) || '          select (e.value)::int into v_hop' || chr(10) || '          from jsonb_array_elements_text(v_plan -> ''path'') with ordinality as e(value, ord)' || chr(10) || '          join public.game_territories jt on jt.id = (e.value)::int' || chr(10) || '          where e.ord >= 2 and not jt.is_junction' || chr(10) || '          order by e.ord limit 1;' || chr(10) || '          perform public.launch_leg(p_player_id, v_c.id, v_hop, ''assault'');' || chr(10) || '        exception when others then' || chr(10) || '          null;' || chr(10) || '        end;' || chr(10) || '      else' || chr(10) || '      select gt.id into v_dest',
    '      end if;' || chr(10) || '    end if;' || chr(10) || '  end loop;' || chr(10) || 'end;',
    '      end if;' || chr(10) || '      end if;' || chr(10) || '    end if;' || chr(10) || '  end loop;' || chr(10) || 'end;'
  ];
  i int;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'ai_commanders' and p.pronamespace = 'public'::regnamespace;
  v_new := v_def;
  for i in 1 .. array_length(v_pairs, 1) / 2 loop
    if position(v_pairs[2 * i - 1] in v_new) = 0 then
      raise exception 'ai_commanders massing patch % did not match', i;
    end if;
    v_new := replace(v_new, v_pairs[2 * i - 1], v_pairs[2 * i]);
  end loop;
  execute v_new;
end;
$patch$;
