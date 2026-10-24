alter table public.game_territories add column choke smallint not null default 0;

do $patch$
declare
  v_def text;
  v_new text;
  v_pairs text[];
  i int;
begin
  v_pairs := array[
    'has_road, crossing_kind, river_idx, is_junction',
    'has_road, crossing_kind, river_idx, is_junction, choke',
    'coalesce((v_t ->> ''junction'')::boolean, false)',
    'coalesce((v_t ->> ''junction'')::boolean, false), coalesce((v_t ->> ''choke'')::smallint, 0)'
  ];
  select pg_get_functiondef('public.commit_world(integer,jsonb)'::regprocedure) into v_def;
  v_new := v_def;
  for i in 1 .. array_length(v_pairs, 1) / 2 loop
    if position(v_pairs[2 * i - 1] in v_new) = 0 then
      raise exception 'commit_world patch % did not match', i;
    end if;
    v_new := replace(v_new, v_pairs[2 * i - 1], v_pairs[2 * i]);
  end loop;
  execute v_new;

  v_pairs := array[
    '''is_junction'', t.is_junction,',
    '''is_junction'', t.is_junction, ''choke'', t.choke,'
  ];
  select pg_get_functiondef('public.get_game_view(integer)'::regprocedure) into v_def;
  v_new := v_def;
  for i in 1 .. array_length(v_pairs, 1) / 2 loop
    if position(v_pairs[2 * i - 1] in v_new) = 0 then
      raise exception 'get_game_view patch % did not match', i;
    end if;
    v_new := replace(v_new, v_pairs[2 * i - 1], v_pairs[2 * i]);
  end loop;
  execute v_new;

  v_pairs := array[
    '  v_goal float8;' || chr(10) || 'begin',
    '  v_goal float8;' || chr(10) || '  v_r int;' || chr(10) || '  v_res_ids int[];' || chr(10) || '  v_res_vals int[];' || chr(10) || '  v_strat float8;' || chr(10) || '  v_caps int[];' || chr(10) || 'begin',
    '  where o.game_id = p_game_id and o.owner_player_id = p_player_id;',
    '  where o.game_id = p_game_id and o.owner_player_id = p_player_id;' || chr(10) || chr(10)
    || '  select coalesce(array_agg(gp.capital_territory_id), ''{}'') into v_caps' || chr(10)
    || '  from public.game_players gp' || chr(10)
    || '  where gp.game_id = p_game_id and gp.id <> p_player_id and gp.eliminated_at_tick is null and gp.capital_territory_id is not null;' || chr(10) || chr(10)
    || '  with recursive adj(a, b) as (' || chr(10)
    || '    select e.from_territory_id, e.to_territory_id from public.territory_edges e where e.game_id = p_game_id' || chr(10)
    || '    union all' || chr(10)
    || '    select e.to_territory_id, e.from_territory_id from public.territory_edges e where e.game_id = p_game_id' || chr(10)
    || '  ), reach(src, node, depth) as (' || chr(10)
    || '    select adj.a, adj.b, 1 from adj where adj.a = any (v_own_ids)' || chr(10)
    || '    union all' || chr(10)
    || '    select r.src, adj.b, r.depth + 1 from reach r' || chr(10)
    || '    join adj on adj.a = r.node' || chr(10)
    || '    join public.game_territories jt on jt.id = r.node and jt.is_junction' || chr(10)
    || '    where r.depth < 4 and adj.b <> r.src' || chr(10)
    || '  ), threat as (' || chr(10)
    || '    select r.src, sum(case when t.owner_player_id is not null and t.owner_player_id <> p_player_id and not (t.owner_player_id = any (v_allies))' || chr(10)
    || '      then t.troops * 0.15 + coalesce((select sum(c.troops) from public.commanders c where c.current_territory_id = t.id and c.status = ''idle'' and c.owner_player_id = t.owner_player_id), 0) * 0.35' || chr(10)
    || '      else 0 end) as stat' || chr(10)
    || '    from reach r join public.game_territories t on t.id = r.node and not t.is_junction' || chr(10)
    || '    group by r.src' || chr(10)
    || '  ), incoming as (' || chr(10)
    || '    select m.to_territory_id as dst, sum(c.troops) as inc' || chr(10)
    || '    from public.commander_movements m join public.commanders c on c.id = m.commander_id' || chr(10)
    || '    where m.game_id = p_game_id and c.owner_player_id <> p_player_id and not (c.owner_player_id = any (v_allies))' || chr(10)
    || '    group by m.to_territory_id' || chr(10)
    || '  )' || chr(10)
    || '  select array_agg(o.id order by o.id), array_agg((v_reserve + ceil(coalesce(th.stat, 0) + 0.8 * coalesce(i.inc, 0)))::int order by o.id)' || chr(10)
    || '  into v_res_ids, v_res_vals' || chr(10)
    || '  from public.game_territories o' || chr(10)
    || '  left join threat th on th.src = o.id' || chr(10)
    || '  left join incoming i on i.dst = o.id' || chr(10)
    || '  where o.game_id = p_game_id and o.owner_player_id = p_player_id;',
    '    if v_c.terr_owner = p_player_id and v_gar - v_reserve > 0 then' || chr(10) || '      perform public.transfer_troops_core(p_game_id, p_player_id, v_c.id, v_gar - v_reserve);',
    '    v_r := coalesce(v_res_vals[array_position(v_res_ids, v_c.current_territory_id)], v_reserve);' || chr(10) || '    if v_c.terr_owner = p_player_id and v_gar - v_r > 0 then' || chr(10) || '      perform public.transfer_troops_core(p_game_id, p_player_id, v_c.id, v_gar - v_r);',
    '          and gt.troops - v_reserve + v_att >= 6',
    '          and gt.troops - coalesce(v_res_vals[array_position(v_res_ids, gt.id)], v_reserve) + v_att >= 6',
    '        select coalesce(sum(greatest(gt.troops - v_reserve, 0)), 0) + v_att into v_pool',
    '        select coalesce(sum(greatest(gt.troops - coalesce(v_res_vals[array_position(v_res_ids, gt.id)], v_reserve), 0)), 0) + v_att into v_pool',
    '            and gt.troops - v_reserve >= 12',
    '            and gt.troops - coalesce(v_res_vals[array_position(v_res_ids, gt.id)], v_reserve) >= 12',
    '      v_need := v_def_dmg * v_rd + 1;',
    '      v_strat := coalesce(v_t.choke, 0) * 1.5 + case when v_t.id = any (v_caps) then 5 else 0 end;' || chr(10) || '      v_need := v_def_dmg * v_rd + 1;',
    '            - (v_plan ->> ''travel_ticks'')::int * 0.2 + random() + v_prio;',
    '            - (v_plan ->> ''travel_ticks'')::int * 0.2 + random() + v_prio + v_strat;',
    '        + random() + v_prio;',
    '        + random() + v_prio + v_strat;'
  ];
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'ai_commanders' and p.pronamespace = 'public'::regnamespace;
  v_new := v_def;
  for i in 1 .. array_length(v_pairs, 1) / 2 loop
    if position(v_pairs[2 * i - 1] in v_new) = 0 then
      raise exception 'ai_commanders threat patch % did not match', i;
    end if;
    v_new := replace(v_new, v_pairs[2 * i - 1], v_pairs[2 * i]);
  end loop;
  execute v_new;
end;
$patch$;
