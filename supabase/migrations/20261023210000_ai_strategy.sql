do $patch$
declare
  v_def text;
  v_new text;
  v_pairs text[];
  i int;
begin
  v_pairs := array[
    '  v_done boolean;' || chr(10) || 'begin',
    '  v_done boolean;' || chr(10) || '  v_free int;' || chr(10) || '  v_total int;' || chr(10) || '  v_my_troops float8;' || chr(10) || '  v_their_troops float8;' || chr(10) || '  v_st text;' || chr(10) || '  v_lock int;' || chr(10) || '  v_scale float8;' || chr(10) || '  v_aggr float8;' || chr(10) || 'begin',
    '  if v_done then' || chr(10) || '    return;' || chr(10) || '  end if;',
    '  if not v_done and p_difficulty >= 2 then' || chr(10)
    || '    select count(*) filter (where owner_player_id is null and not is_junction), count(*) filter (where not is_junction)' || chr(10)
    || '    into v_free, v_total from public.game_territories where game_id = p_game_id;' || chr(10)
    || '    select world_scale into v_scale from public.games where id = p_game_id;' || chr(10)
    || '    v_aggr := case p_difficulty when 2 then 0.004 when 3 then 0.01 when 4 then 0.02 else 0.04 end;' || chr(10)
    || '    if v_free <= 0.15 * v_total and random() < v_aggr then' || chr(10)
    || '      select coalesce(sum(t), 0) into v_my_troops from (' || chr(10)
    || '        select troops as t from public.game_territories where game_id = p_game_id and owner_player_id = p_player_id' || chr(10)
    || '        union all select troops from public.commanders where game_id = p_game_id and owner_player_id = p_player_id and status <> ''dead'') q;' || chr(10)
    || '      v_best := null;' || chr(10)
    || '      v_best_score := -1e9;' || chr(10)
    || '      for v_c in' || chr(10)
    || '        select gp.id from public.game_players gp' || chr(10)
    || '        where gp.game_id = p_game_id and gp.id <> p_player_id and gp.eliminated_at_tick is null' || chr(10)
    || '      loop' || chr(10)
    || '        select d.status, d.locked_until_tick into v_st, v_lock from public.diplomacy d' || chr(10)
    || '        where d.game_id = p_game_id and d.player_a_id = least(v_c.id, p_player_id) and d.player_b_id = greatest(v_c.id, p_player_id);' || chr(10)
    || '        continue when v_st is null or v_st not in (''neutral'', ''allied'');' || chr(10)
    || '        continue when v_st = ''allied'' and v_lock is not null and v_lock > v_tick;' || chr(10)
    || '        select coalesce(sum(t), 0) into v_their_troops from (' || chr(10)
    || '          select troops as t from public.game_territories where game_id = p_game_id and owner_player_id = v_c.id' || chr(10)
    || '          union all select troops from public.commanders where game_id = p_game_id and owner_player_id = v_c.id and status <> ''dead'') q;' || chr(10)
    || '        continue when v_my_troops < 0.7 * v_their_troops;' || chr(10)
    || '        select min(sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)) into v_dist' || chr(10)
    || '        from public.game_territories a join public.game_territories b on b.game_id = a.game_id' || chr(10)
    || '        where a.game_id = p_game_id and a.owner_player_id = p_player_id and b.owner_player_id = v_c.id;' || chr(10)
    || '        v_score := 6.0 * public.castle_count(v_c.id) / greatest(v_win_at, 1)' || chr(10)
    || '          + 3.0 * (v_my_troops - v_their_troops) / greatest(v_my_troops, 1)' || chr(10)
    || '          - coalesce(v_dist, 1000) / (150.0 * v_scale * 4)' || chr(10)
    || '          - case when v_st = ''allied'' then 1.0 else 0 end' || chr(10)
    || '          + random();' || chr(10)
    || '        if v_score > v_best_score then' || chr(10)
    || '          v_best := v_c.id;' || chr(10)
    || '          v_best_score := v_score;' || chr(10)
    || '        end if;' || chr(10)
    || '      end loop;' || chr(10)
    || '      if v_best is not null and (select status from public.diplomacy where game_id = p_game_id and player_a_id = least(v_best, p_player_id) and player_b_id = greatest(v_best, p_player_id)) = ''allied'' then' || chr(10)
    || '        perform public.break_alliance_core(p_game_id, p_player_id, v_best, v_tick);' || chr(10)
    || '        v_done := true;' || chr(10)
    || '      end if;' || chr(10)
    || '    end if;' || chr(10)
    || '  end if;' || chr(10)
    || '  if v_done then' || chr(10) || '    return;' || chr(10) || '  end if;'
  ];
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'ai_diplomacy' and p.pronamespace = 'public'::regnamespace;
  v_new := v_def;
  for i in 1 .. array_length(v_pairs, 1) / 2 loop
    if position(v_pairs[2 * i - 1] in v_new) = 0 then
      raise exception 'ai_diplomacy patch % did not match', i;
    end if;
    v_new := replace(v_new, v_pairs[2 * i - 1], v_pairs[2 * i]);
  end loop;
  execute v_new;

  v_pairs := array[
    '  v_src int;' || chr(10) || 'begin',
    '  v_src int;' || chr(10) || '  v_leader int;' || chr(10) || '  v_leader_ahead boolean;' || chr(10) || '  v_prio float8;' || chr(10) || '  v_min_prio_need float8;' || chr(10) || '  v_goal float8;' || chr(10) || 'begin',
    '  select coalesce(array_agg(gt.id), ''{}'') into v_friendly',
    '  select gp.id into v_leader from public.game_players gp' || chr(10) || '  where gp.game_id = p_game_id and gp.id <> p_player_id and gp.eliminated_at_tick is null' || chr(10) || '  order by public.castle_count(gp.id) desc, gp.id limit 1;' || chr(10) || '  v_leader_ahead := coalesce(public.castle_count(v_leader) > public.castle_count(p_player_id), false);' || chr(10) || '  select coalesce(array_agg(gt.id), ''{}'') into v_friendly',
    '    v_min_need := 1e18;',
    '    v_min_need := 1e18;' || chr(10) || '    v_min_prio_need := 1e18;',
    '      v_need := v_def_dmg * v_rd + 1;' || chr(10) || '      if v_need < v_min_need then',
    '      v_prio := case when v_t.owner_player_id is not null and v_t.owner_player_id = v_leader and v_leader_ahead then 4 else 0 end' || chr(10) || '        + case when v_t.owner_player_id is not null and exists (select 1 from public.diplomacy w where w.game_id = p_game_id and w.status = ''war'' and w.player_a_id = least(p_player_id, v_t.owner_player_id) and w.player_b_id = greatest(p_player_id, v_t.owner_player_id)) then 3 else 0 end;' || chr(10) || '      v_need := v_def_dmg * v_rd + 1;' || chr(10) || '      if v_prio > 0 and v_need < v_min_prio_need then' || chr(10) || '        v_min_prio_need := v_need;' || chr(10) || '      end if;' || chr(10) || '      if v_need < v_min_need then',
    '          v_score := v_t.tier * 3 + case when v_t.owner_player_id is null then 2 else 0 end + v_t.treasury_level' || chr(10) || '            - (v_plan ->> ''travel_ticks'')::int * 0.2 + random();',
    '          v_score := v_t.tier * 3 + case when v_t.owner_player_id is null then 2 else 0 end + v_t.treasury_level' || chr(10) || '            - (v_plan ->> ''travel_ticks'')::int * 0.2 + random() + v_prio;',
    '        - (v_plan ->> ''travel_ticks'')::int * 0.2' || chr(10) || '        + random();',
    '        - (v_plan ->> ''travel_ticks'')::int * 0.2' || chr(10) || '        + random() + v_prio;',
    '        if v_pool >= v_min_need then',
    '        v_goal := case when v_min_prio_need < 1e17 then v_min_prio_need else v_min_need end;' || chr(10) || '        if v_pool >= v_goal then'
  ];
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'ai_commanders' and p.pronamespace = 'public'::regnamespace;
  v_new := v_def;
  for i in 1 .. array_length(v_pairs, 1) / 2 loop
    if position(v_pairs[2 * i - 1] in v_new) = 0 then
      raise exception 'ai_commanders strategy patch % did not match', i;
    end if;
    v_new := replace(v_new, v_pairs[2 * i - 1], v_pairs[2 * i]);
  end loop;
  execute v_new;
end;
$patch$;
