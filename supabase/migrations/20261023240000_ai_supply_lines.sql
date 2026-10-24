create or replace function public.ai_hire(p_game_id integer, p_player_id integer, p_difficulty integer)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_game public.games%rowtype;
  v_gold int;
  v_owned int;
  v_want int;
  v_living int;
  v_free int;
  v_terr int;
  v_ratio float8;
  v_hired int := 0;
  v_roll float8;
begin
  select * into v_game from public.games where id = p_game_id;
  select count(*) into v_owned from public.game_territories where owner_player_id = p_player_id;
  v_ratio := case p_difficulty when 1 then 0.15 when 2 then 0.25 when 3 then 0.35 when 4 then 0.45 else 0.55 end;
  v_want := least(60, greatest(3, ceil(v_owned * v_ratio)::int));

  select t.id into v_terr
  from public.game_territories t
  where t.owner_player_id = p_player_id
  order by t.troops desc, t.id
  limit 1;
  if v_terr is null then
    return;
  end if;

  loop
    select count(*) into v_living from public.commanders where owner_player_id = p_player_id and status <> 'dead';
    select count(*) into v_free
    from public.commanders c
    where c.owner_player_id = p_player_id and c.status <> 'dead' and c.role <> 'king'
      and not exists (select 1 from public.game_territories g2 where g2.garrison_commander_id = c.id);
    select gold into v_gold from public.game_players where id = p_player_id;
    exit when v_hired >= 3 or v_gold < v_game.commander_cost;
    exit when v_living >= v_want + 2;
    exit when v_living >= v_want and v_free >= 1;
    exit when v_living >= 4 and v_gold < v_game.commander_cost + 100;
    v_roll := random();
    perform public.hire_commander_core(
      p_game_id, p_player_id, v_terr,
      case when v_roll < 0.5 then 'battleschool' when v_roll < 0.8 then 'rangers' else 'university' end
    );
    v_hired := v_hired + 1;
  end loop;
end;
$function$;

create or replace function public.ai_logistics(p_game_id integer, p_player_id integer, p_difficulty integer)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_game public.games%rowtype;
  v_reserve int := 8 - p_difficulty;
  v_allies int[];
  v_own int[];
  v_front int[];
  v_castles int;
  v_loops int;
  v_want int;
  v_target int;
  v_r record;
  v_cmd int;
  v_hire jsonb;
  v_plan jsonb;
  v_path int[];
  v_stops jsonb;
  v_n int;
  v_i int;
  v_gold int;
begin
  if p_difficulty < 2 then
    return;
  end if;
  select * into v_game from public.games where id = p_game_id;
  select coalesce(array_agg(case when d.player_a_id = p_player_id then d.player_b_id else d.player_a_id end), '{}') into v_allies
  from public.diplomacy d
  where d.game_id = p_game_id and d.status = 'allied' and p_player_id in (d.player_a_id, d.player_b_id);
  select coalesce(array_agg(id), '{}'), count(*) into v_own, v_castles
  from public.game_territories where game_id = p_game_id and owner_player_id = p_player_id;
  if v_castles < 4 then
    return;
  end if;

  v_want := least(16, ceil(v_castles / 4.0)::int);
  select count(*) into v_loops
  from public.commander_routes r join public.commanders c on c.id = r.commander_id
  where r.game_id = p_game_id and c.owner_player_id = p_player_id and r.status = 'active' and r.looping;
  if v_loops >= v_want then
    return;
  end if;

  with recursive adj(a, b) as (
    select e.from_territory_id, e.to_territory_id from public.territory_edges e where e.game_id = p_game_id
    union all
    select e.to_territory_id, e.from_territory_id from public.territory_edges e where e.game_id = p_game_id
  ), reach(src, node, depth) as (
    select adj.a, adj.b, 1 from adj where adj.a = any (v_own)
    union all
    select r.src, adj.b, r.depth + 1 from reach r
    join adj on adj.a = r.node
    join public.game_territories jt on jt.id = r.node and jt.is_junction
    where r.depth < 4 and adj.b <> r.src
  )
  select coalesce(array_agg(distinct r.src), '{}') into v_front
  from reach r join public.game_territories t on t.id = r.node and not t.is_junction
  where t.owner_player_id is null or (t.owner_player_id <> p_player_id and not (t.owner_player_id = any (v_allies)));
  if coalesce(array_length(v_front, 1), 0) = 0 then
    return;
  end if;

  select s.id into v_target
  from public.game_territories s
  where s.id = any (v_front)
  order by (select count(*) from public.commander_routes r
            where r.game_id = p_game_id and r.status = 'active' and r.looping
              and r.stops @> jsonb_build_array(jsonb_build_object('territory_id', s.id))), s.troops, s.id
  limit 1;

  for v_r in
    select gt.id, gt.troops
    from public.game_territories gt
    where gt.game_id = p_game_id and gt.owner_player_id = p_player_id
      and not (gt.id = any (v_front))
      and gt.troops - v_reserve >= 15
      and not exists (select 1 from public.commander_routes r
                      where r.game_id = p_game_id and r.status = 'active' and r.looping
                        and r.stops @> jsonb_build_array(jsonb_build_object('territory_id', gt.id)))
    order by gt.troops desc, gt.id
    limit 2
  loop
    v_cmd := null;
    select c.id into v_cmd
    from public.commanders c
    where c.owner_player_id = p_player_id and c.current_territory_id = v_r.id and c.status = 'idle' and c.role <> 'king'
      and not exists (select 1 from public.game_territories g2 where g2.garrison_commander_id = c.id)
      and not exists (select 1 from public.commander_routes r where r.commander_id = c.id and r.status = 'active')
    order by c.troops, c.id
    limit 1;
    if v_cmd is null then
      select gold into v_gold from public.game_players where id = p_player_id;
      if v_gold >= v_game.commander_cost + 100 then
        begin
          v_hire := public.hire_commander_core(p_game_id, p_player_id, v_r.id, 'battleschool');
          v_cmd := (v_hire ->> 'commander_id')::int;
        exception when others then
          v_cmd := null;
        end;
      end if;
    end if;
    continue when v_cmd is null;

    begin
      v_plan := public.plan_march(p_player_id, v_cmd, v_target);
      select array_agg(e.x::int order by e.ord) into v_path
      from jsonb_array_elements_text(v_plan -> 'path') with ordinality as e(x, ord)
      join public.game_territories jt on jt.id = e.x::int
      where not jt.is_junction;
      v_n := array_length(v_path, 1);
      if v_n is null or v_n < 2 then
        raise exception 'no route';
      end if;
      v_stops := '[]'::jsonb;
      for v_i in 2 .. v_n loop
        v_stops := v_stops || jsonb_build_object('territory_id', v_path[v_i], 'march_type', 'assault',
          'action', case when v_i = v_n then 'drop_all' else 'nothing' end, 'amount', 0, 'delay', 0);
      end loop;
      for v_i in reverse (v_n - 1) .. 1 loop
        v_stops := v_stops || jsonb_build_object('territory_id', v_path[v_i], 'march_type', 'assault',
          'action', case when v_i = 1 then 'collect_all_but' else 'nothing' end,
          'amount', case when v_i = 1 then v_reserve + 10 else 0 end, 'delay', 0);
      end loop;
      if v_r.troops - (v_reserve + 10) > 0 then
        perform public.transfer_troops_core(p_game_id, p_player_id, v_cmd, v_r.troops - (v_reserve + 10));
      end if;
      insert into public.commander_routes (game_id, commander_id, stops, created_tick, origin_territory_id, looping)
      values (p_game_id, v_cmd, v_stops, v_game.current_tick, v_r.id, true);
      perform public.launch_leg(p_player_id, v_cmd, v_path[2], 'assault');
    exception when others then
      null;
    end;
  end loop;
end;
$function$;

revoke execute on function public.ai_hire(integer, integer, integer), public.ai_logistics(integer, integer, integer) from public, anon, authenticated;

do $patch$
declare
  v_def text;
  v_new text;
  v_pairs text[];
  i int;
begin
  v_pairs := array[
    '  perform public.ai_commanders(p_game_id, p_player_id, v_difficulty);',
    '  perform public.ai_logistics(p_game_id, p_player_id, v_difficulty);' || chr(10) || '  perform public.ai_commanders(p_game_id, p_player_id, v_difficulty);'
  ];
  select pg_get_functiondef('public.ai_take_turn(integer,integer)'::regprocedure) into v_def;
  v_new := v_def;
  for i in 1 .. array_length(v_pairs, 1) / 2 loop
    if position(v_pairs[2 * i - 1] in v_new) = 0 then
      raise exception 'ai_take_turn patch % did not match', i;
    end if;
    v_new := replace(v_new, v_pairs[2 * i - 1], v_pairs[2 * i]);
  end loop;
  execute v_new;

  v_pairs := array[
    '      and c.status = ''idle''' || chr(10) || '      and c.role <> ''king''',
    '      and c.status = ''idle''' || chr(10) || '      and c.role <> ''king''' || chr(10) || '      and not exists (select 1 from public.commander_routes r where r.commander_id = c.id and r.status = ''active'')'
  ];
  select pg_get_functiondef('public.ai_garrison(integer,integer)'::regprocedure) into v_def;
  v_new := v_def;
  for i in 1 .. array_length(v_pairs, 1) / 2 loop
    if position(v_pairs[2 * i - 1] in v_new) = 0 then
      raise exception 'ai_garrison patch % did not match', i;
    end if;
    v_new := replace(v_new, v_pairs[2 * i - 1], v_pairs[2 * i]);
  end loop;
  execute v_new;

  v_pairs := array[
    '  v_caps int[];' || chr(10) || 'begin',
    '  v_caps int[];' || chr(10) || '  v_targeted int[];' || chr(10) || '  v_best_need float8;' || chr(10) || '  v_n_cmds int := 0;' || chr(10) || 'begin',
    '  for v_c in' || chr(10) || '    select c.id, c.current_territory_id, gt.owner_player_id as terr_owner',
    '  select coalesce(array_agg(m.to_territory_id), ''{}'') into v_targeted' || chr(10) || '  from public.commander_movements m join public.commanders mc on mc.id = m.commander_id' || chr(10) || '  where m.game_id = p_game_id and mc.owner_player_id = p_player_id;' || chr(10) || chr(10) || '  for v_c in' || chr(10) || '    select c.id, c.current_territory_id, gt.owner_player_id as terr_owner',
    '      and not exists (select 1 from public.game_territories g2 where g2.garrison_commander_id = c.id)' || chr(10) || '    order by c.troops desc, c.id',
    '      and not exists (select 1 from public.game_territories g2 where g2.garrison_commander_id = c.id)' || chr(10) || '      and not exists (select 1 from public.commander_routes r where r.commander_id = c.id and r.status = ''active'')' || chr(10) || '    order by c.troops desc, c.id',
    '  loop' || chr(10) || '    select troops into v_gar from public.game_territories where id = v_c.current_territory_id;',
    '  loop' || chr(10) || '    v_n_cmds := v_n_cmds + 1;' || chr(10) || '    exit when v_n_cmds > 6 + p_difficulty;' || chr(10) || '    select troops into v_gar from public.game_territories where id = v_c.current_territory_id;',
    '      order by gt.id' || chr(10) || '    loop',
    '        and not (gt.id = any (v_targeted))' || chr(10) || '      order by (select (t0.x - gt.x) ^ 2 + (t0.y - gt.y) ^ 2 from public.game_territories t0 where t0.id = v_c.current_territory_id), gt.id' || chr(10) || '      limit 12' || chr(10) || '    loop',
    '        v_best := v_t.id;' || chr(10) || '        v_best_score := v_score;',
    '        v_best := v_t.id;' || chr(10) || '        v_best_score := v_score;' || chr(10) || '        v_best_need := v_need;',
    '    if v_best is not null then' || chr(10) || '      begin' || chr(10) || '        perform public.launch_leg(p_player_id, v_c.id, v_best, ''assault'');',
    '    if v_best is not null then' || chr(10) || '      if v_c.terr_owner = p_player_id and v_att > 2.2 * v_best_need + 30 then' || chr(10) || '        begin' || chr(10) || '          perform public.transfer_troops_core(p_game_id, p_player_id, v_c.id, - (v_att - ceil(1.6 * v_best_need + 20)::int));' || chr(10) || '        exception when others then' || chr(10) || '          null;' || chr(10) || '        end;' || chr(10) || '      end if;' || chr(10) || '      begin' || chr(10) || '        perform public.launch_leg(p_player_id, v_c.id, v_best, ''assault'');' || chr(10) || '        v_targeted := v_targeted || v_best;',
    '        perform public.launch_leg(p_player_id, v_c.id, v_best_siege, ''siege'');',
    '        perform public.launch_leg(p_player_id, v_c.id, v_best_siege, ''siege'');' || chr(10) || '        v_targeted := v_targeted || v_best_siege;'
  ];
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'ai_commanders' and p.pronamespace = 'public'::regnamespace;
  v_new := v_def;
  for i in 1 .. array_length(v_pairs, 1) / 2 loop
    if position(v_pairs[2 * i - 1] in v_new) = 0 then
      raise exception 'ai_commanders supply patch % did not match', i;
    end if;
    v_new := replace(v_new, v_pairs[2 * i - 1], v_pairs[2 * i]);
  end loop;
  execute v_new;
end;
$patch$;
