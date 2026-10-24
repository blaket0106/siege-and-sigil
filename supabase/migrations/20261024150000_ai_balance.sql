create function public.dominant_house(p_game_id int)
returns int
language plpgsql
stable
security definer
set search_path = ''
as $f$
declare
  v_win_at int := (public.game_standing(p_game_id) ->> 'win_at')::int;
  v_first int;
  v_first_n int;
  v_second_n int;
begin
  select q.id, q.n into v_first, v_first_n
  from (
    select gp.id, public.castle_count(gp.id) as n
    from public.game_players gp
    where gp.game_id = p_game_id and gp.eliminated_at_tick is null
  ) q
  order by q.n desc, q.id
  limit 1;
  select max(public.castle_count(gp.id)) into v_second_n
  from public.game_players gp
  where gp.game_id = p_game_id and gp.eliminated_at_tick is null and gp.id <> v_first;
  if v_first is null or v_first_n < 0.3 * v_win_at or v_first_n < 1.35 * coalesce(v_second_n, 0) then
    return null;
  end if;
  return v_first;
end;
$f$;

create function public.ai_reinforce(p_game_id int, p_player_id int, p_difficulty int)
returns void
language plpgsql
security definer
set search_path = ''
as $f$
declare
  v_tick int;
  v_t record;
  v_c record;
  v_threat int;
  v_eta int;
  v_have int;
  v_incoming int;
  v_need int;
  v_plan jsonb;
  v_path int[];
  v_n int;
  v_stops jsonb;
  v_i int;
  v_take int;
  v_carry int;
  v_travel int;
  v_reserve int := greatest(4, 10 - p_difficulty);
  v_margin float8 := 1.25 + 0.1 * (p_difficulty - 2);
  v_sent int := 0;
  v_per_target int;
begin
  if p_difficulty < 2 then
    return;
  end if;
  select current_tick into v_tick from public.games where id = p_game_id;

  for v_t in
    select gt.id, gt.troops
    from public.game_territories gt
    where gt.game_id = p_game_id and gt.owner_player_id = p_player_id and not gt.is_junction
    order by gt.tier desc, gt.id
  loop
    exit when v_sent >= 4;

    select coalesce(sum(c.troops), 0),
           coalesce(min(case when c.status = 'sieging' then 0 else greatest(0, m.arrival_tick - v_tick) end), 0)
    into v_threat, v_eta
    from public.commanders c
    left join public.commander_movements m on m.commander_id = c.id
    where c.game_id = p_game_id and c.status in ('sieging', 'moving') and c.owner_player_id <> p_player_id
      and not public.are_allied(p_player_id, c.owner_player_id)
      and not public.are_truced(p_player_id, c.owner_player_id)
      and ((c.status = 'sieging' and c.current_territory_id = v_t.id) or (c.status = 'moving' and m.to_territory_id = v_t.id));
    continue when v_threat <= 0;

    select v_t.troops + coalesce(sum(c.troops), 0) into v_have
    from public.commanders c
    where c.current_territory_id = v_t.id and c.status = 'idle' and c.owner_player_id = p_player_id;

    select coalesce(sum(c.troops), 0) into v_incoming
    from public.commanders c
    where c.game_id = p_game_id and c.owner_player_id = p_player_id and c.status = 'moving'
      and (exists (select 1 from public.commander_movements m where m.commander_id = c.id and m.to_territory_id = v_t.id)
           or exists (select 1 from public.commander_routes r where r.commander_id = c.id and r.status = 'active'
                      and (r.stops -> (jsonb_array_length(r.stops) - 1) ->> 'territory_id')::int = v_t.id));

    v_need := ceil(v_threat * v_margin)::int - v_have - v_incoming;
    continue when v_need <= 0;

    v_per_target := 0;
    for v_c in
      select c.id, c.troops, c.current_territory_id as at_id, gt.troops as at_troops
      from public.commanders c
      join public.game_territories gt on gt.id = c.current_territory_id
      where c.game_id = p_game_id and c.owner_player_id = p_player_id and c.status = 'idle' and c.role <> 'king'
        and c.current_territory_id <> v_t.id and gt.owner_player_id = p_player_id
        and not exists (select 1 from public.game_territories g2 where g2.garrison_commander_id = c.id)
        and not exists (select 1 from public.commander_routes r where r.commander_id = c.id and r.status = 'active')
      order by (c.troops + greatest(0, gt.troops - v_reserve)) desc, c.id
      limit 10
    loop
      exit when v_need <= 0 or v_per_target >= 3 or v_sent >= 4;
      begin
        v_plan := public.plan_march(p_player_id, v_c.id, v_t.id);
        v_travel := coalesce((v_plan ->> 'travel_ticks')::int, 999);
        continue when v_travel > 40 or (v_eta > 0 and v_travel > v_eta + 3);
        select array_agg(e.x::int order by e.ord) into v_path
        from jsonb_array_elements_text(v_plan -> 'path') with ordinality as e(x, ord)
        join public.game_territories jt on jt.id = e.x::int
        where not jt.is_junction;
        v_n := array_length(v_path, 1);
        continue when v_n is null or v_n < 2;

        v_take := least(greatest(0, v_c.at_troops - v_reserve), greatest(0, v_need - v_c.troops));
        if v_take > 0 then
          perform public.transfer_troops_core(p_game_id, p_player_id, v_c.id, v_take);
        end if;
        v_carry := v_c.troops + v_take;
        continue when v_carry < 8;

        v_stops := '[]'::jsonb;
        for v_i in 2 .. v_n loop
          v_stops := v_stops || jsonb_build_object('territory_id', v_path[v_i], 'march_type', 'assault',
            'action', case when v_i = v_n then 'drop_all' else 'nothing' end, 'amount', 0, 'delay', 0);
        end loop;
        insert into public.commander_routes (game_id, commander_id, stops, created_tick, origin_territory_id, looping)
        values (p_game_id, v_c.id, v_stops, v_tick, v_c.at_id, false);
        perform public.launch_leg(p_player_id, v_c.id, v_path[2], 'assault');
        v_need := v_need - v_carry;
        v_per_target := v_per_target + 1;
        v_sent := v_sent + 1;
      exception when others then
        null;
      end;
    end loop;
  end loop;
end;
$f$;

revoke execute on function public.dominant_house(int) from public, anon, authenticated;
revoke execute on function public.ai_reinforce(int, int, int) from public, anon, authenticated;

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
      ('ai_diplomacy', array[
        '  v_aggr float8;' || chr(10) || 'begin',
        '  v_aggr float8;' || chr(10) || '  v_dom int;' || chr(10) || 'begin',
        'if public.castle_count(v_d.proposed_by_player_id) >= 0.7 * v_win_at or random() >= v_chance then',
        'if public.castle_count(v_d.proposed_by_player_id) >= 0.7 * v_win_at or v_d.proposed_by_player_id is not distinct from public.dominant_house(p_game_id) or random() >= v_chance then',
        '    if random() < v_pc then' || chr(10) || '      perform public.accept_peace_core(',
        '    v_dom := public.dominant_house(p_game_id);' || chr(10)
          || '    if v_dom is not null and v_d.proposed_by_player_id = v_dom then' || chr(10)
          || '      v_pc := 0.1;' || chr(10)
          || '    elsif v_dom is not null and p_player_id <> v_dom then' || chr(10)
          || '      v_pc := greatest(v_pc, 0.85);' || chr(10)
          || '    end if;' || chr(10)
          || '    if random() < v_pc then' || chr(10) || '      perform public.accept_peace_core(',
        'if public.castle_count(v_other) >= 0.7 * v_win_at and random() < v_betray then',
        'if (public.castle_count(v_other) >= 0.7 * v_win_at or v_other is not distinct from public.dominant_house(p_game_id)) and random() < v_betray then',
        'and v_my < 0.8 * public.castle_count(v_other) and random() < 0.5 then',
        'and v_my < 0.8 * public.castle_count(v_other) and v_other is distinct from public.dominant_house(p_game_id) and random() < 0.5 then'
      ]),
      ('ai_commanders', array[
        '  v_goal float8;',
        '  v_goal float8;' || chr(10) || '  v_dom int;',
        '  v_leader_ahead := coalesce(public.castle_count(v_leader) > public.castle_count(p_player_id), false);',
        '  v_leader_ahead := coalesce(public.castle_count(v_leader) > public.castle_count(p_player_id), false);' || chr(10) || '  v_dom := public.dominant_house(p_game_id);',
        'and v_t.owner_player_id = v_leader and v_leader_ahead then 4 else 0 end',
        'and v_t.owner_player_id = v_leader and v_leader_ahead then (case when v_leader is not distinct from v_dom then 8 else 4 end) else 0 end'
      ]),
      ('ai_take_turn', array[
        '  perform public.ai_defend(p_game_id, p_player_id, v_difficulty);',
        '  perform public.ai_defend(p_game_id, p_player_id, v_difficulty);' || chr(10) || '  perform public.ai_reinforce(p_game_id, p_player_id, v_difficulty);'
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
