do $patch$
declare
  v_def text;
  v_new text;
  v_pairs text[];
  v_fn text;
  i int;
begin
  for v_fn, v_pairs in
    select * from (values
      ('ai_spend', array[
        '  v_loops int;' || chr(10) || 'begin',
        '  v_loops int;' || chr(10) || '  v_cheap int;' || chr(10) || 'begin',
        '  v_budget := floor((v_gold - v_reserve) * (0.3 + 0.1 * (p_difficulty - 1)))::int;',
        '  v_reserve := least(v_reserve, 150);' || chr(10)
          || '  v_budget := floor((v_gold - v_reserve) * (0.5 + 0.1 * (p_difficulty - 1)))::int;' || chr(10)
          || '  select min(public.infra_cost(tp.t, case tp.t when ''recruitment'' then gt.industry_level else gt.treasury_level end, gt.resources, v_game.infra_cost_mult * public.infra_type_mult(p_game_id, tp.t)))' || chr(10)
          || '  into v_cheap from public.game_territories gt cross join (values (''recruitment''), (''treasury'')) as tp(t) where gt.owner_player_id = p_player_id;' || chr(10)
          || '  if v_cheap is not null and v_gold - v_reserve >= v_cheap and v_budget < v_cheap then v_budget := v_cheap; end if;'
      ]),
      ('ai_sieges', array[
        '  v_tick int;' || chr(10) || 'begin',
        '  v_tick int;' || chr(10) || '  v_n int;' || chr(10) || '  v_hope boolean;' || chr(10) || '  v_def_n float8;' || chr(10) || 'begin',
        '    continue when v_def_est > 0 and v_ra <= v_rd;',
        '    if v_def_est > 0 and v_ra <= v_rd then' || chr(10)
          || '      v_hope := false;' || chr(10)
          || '      for v_n in 1 .. 40 loop' || chr(10)
          || '        v_def_n := (v_t.troops * power(0.97, v_n) + coalesce((select sum(troops) from public.commanders where id = any (v_def)), 0)) * v_margin;' || chr(10)
          || '        if v_ra > ceil(v_def_n / v_atk_dmg)::int then v_hope := true; exit; end if;' || chr(10)
          || '      end loop;' || chr(10)
          || '      if not v_hope then' || chr(10)
          || '        update public.commanders set status = ''idle'' where id = any (v_ids) and status = ''sieging'';' || chr(10)
          || '      end if;' || chr(10)
          || '      continue;' || chr(10)
          || '    end if;'
      ])
    ) as t(fn, pairs)
  loop
    select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = v_fn and p.pronamespace = 'public'::regnamespace order by p.oid limit 1;
    v_new := v_def;
    for i in 1 .. array_length(v_pairs, 1) / 2 loop
      if position(v_pairs[2 * i - 1] in v_new) = 0 then
        raise exception '% patch % did not match', v_fn, i;
      end if;
      v_new := replace(v_new, v_pairs[2 * i - 1], v_pairs[2 * i]);
    end loop;
    execute v_new;
  end loop;
end;
$patch$;
