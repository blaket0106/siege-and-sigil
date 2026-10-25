create function public.ai_muster(p_game_id int, p_player_id int, p_difficulty int)
returns void
language plpgsql
security definer
set search_path = ''
as $f$
declare
  v_style text;
  v_game public.games%rowtype;
  v_allies int[];
  v_prey int[];
  v_sc int;
  v_hub int;
  v_hx float8;
  v_hy float8;
  v_sc_troops int;
  v_hub_troops int;
  v_t public.game_territories%rowtype;
  v_defenders float8;
  v_atk int;
  v_def int;
  v_need float8;
  v_force float8;
  v_c record;
  v_plan jsonb;
  v_path int[];
  v_n int;
  v_stops jsonb;
  v_i int;
  v_sent int := 0;
  v_tick int;
begin
  select ai_style into v_style from public.game_players where id = p_player_id;
  select * into v_game from public.games where id = p_game_id;
  v_tick := v_game.current_tick;
  if v_style = 'defensive' and public.castle_count(p_player_id) < 14 then
    return;
  end if;
  if v_style = 'balanced' and (v_tick < 40 or public.castle_count(p_player_id) < 6) then
    return;
  end if;
  if v_style = 'aggressive' and v_tick < 20 then
    return;
  end if;

  select coalesce(array_agg(case when d.player_a_id = p_player_id then d.player_b_id else d.player_a_id end), '{}') into v_allies
  from public.diplomacy d
  where d.game_id = p_game_id and d.status = 'allied' and p_player_id in (d.player_a_id, d.player_b_id);
  select coalesce(array_agg(gp.id), '{}') into v_prey
  from public.game_players gp
  where gp.game_id = p_game_id and gp.id <> p_player_id and gp.eliminated_at_tick is null
    and public.castle_count(gp.id) < 0.8 * public.castle_count(p_player_id);

  select c.id, ct.id, ct.x, ct.y, c.troops, ct.troops into v_sc, v_hub, v_hx, v_hy, v_sc_troops, v_hub_troops
  from public.commanders c
  join public.game_territories ct on ct.id = c.current_territory_id and ct.owner_player_id = p_player_id
  where c.game_id = p_game_id and c.owner_player_id = p_player_id and c.status = 'idle'
    and not exists (select 1 from public.game_territories g2 where g2.garrison_commander_id = c.id)
    and not exists (select 1 from public.commander_routes r where r.commander_id = c.id and r.status = 'active')
  order by (select min(((ct.x - r.x) ^ 2 + (ct.y - r.y) ^ 2) * (case when r.owner_player_id = any (v_prey) then 0.5 else 1 end))
            from public.game_territories r
            where r.game_id = p_game_id and r.owner_player_id is not null and r.owner_player_id <> p_player_id
              and not (r.owner_player_id = any (v_allies)) and not r.is_junction) nulls last, c.id
  limit 1;
  if v_sc is null then
    return;
  end if;

  select t.* into v_t
  from public.game_territories t
  where t.game_id = p_game_id and t.owner_player_id is not null and t.owner_player_id <> p_player_id
    and not (t.owner_player_id = any (v_allies)) and not t.is_junction
    and not public.are_truced(p_player_id, t.owner_player_id)
  order by ((t.x - v_hx) ^ 2 + (t.y - v_hy) ^ 2) * (case when t.owner_player_id = any (v_prey) then 0.5 else 1 end)
  limit 1;
  if v_t.id is null or sqrt((v_t.x - v_hx) ^ 2 + (v_t.y - v_hy) ^ 2) > 5 * 150 * v_game.world_scale then
    return;
  end if;

  begin
    v_plan := public.plan_march(p_player_id, v_sc, v_t.id);
  exception when others then
    return;
  end;
  if not (v_plan ->> 'in_range')::boolean then
    return;
  end if;

  v_defenders := v_t.troops + coalesce((select sum(c2.troops) from public.commanders c2
    where c2.current_territory_id = v_t.id and c2.status = 'idle' and c2.owner_player_id = v_t.owner_player_id), 0);
  v_atk := greatest(1, public.armory_level(p_player_id) + public.side_valor(array[v_sc], null));
  v_def := greatest(1, public.armory_level(v_t.owner_player_id) + public.side_valor(array[]::int[], v_t.garrison_commander_id) + 1 + case when v_t.terrain = 'mountain' then 1 else 0 end);
  v_need := v_def * ceil(v_defenders * 1.2 / v_atk) + 1;
  v_force := v_sc_troops + greatest(0, v_hub_troops - 2);
  if v_force >= v_need then
    return;
  end if;

  for v_c in
    select c.id, c.troops, c.current_territory_id as at_id
    from public.commanders c
    join public.game_territories ct on ct.id = c.current_territory_id and ct.owner_player_id = p_player_id
    where c.game_id = p_game_id and c.owner_player_id = p_player_id and c.status = 'idle'
      and c.id <> v_sc and c.role <> 'king' and c.troops >= 4 and ct.id <> v_hub
      and not exists (select 1 from public.game_territories g2 where g2.garrison_commander_id = c.id)
      and not exists (select 1 from public.commander_routes r where r.commander_id = c.id and r.status = 'active')
    order by c.troops desc, c.id
    limit 8
  loop
    exit when v_force >= v_need or v_sent >= 4;
    begin
      v_plan := public.plan_march(p_player_id, v_c.id, v_hub);
      continue when (v_plan ->> 'travel_ticks')::int > 14;
      select array_agg(e.x::int order by e.ord) into v_path
      from jsonb_array_elements_text(v_plan -> 'path') with ordinality as e(x, ord)
      join public.game_territories jt on jt.id = e.x::int
      where not jt.is_junction;
      v_n := array_length(v_path, 1);
      continue when v_n is null or v_n < 2;
      v_stops := '[]'::jsonb;
      for v_i in 2 .. v_n loop
        v_stops := v_stops || jsonb_build_object('territory_id', v_path[v_i], 'march_type', 'assault',
          'action', case when v_i = v_n then 'drop_all' else 'nothing' end, 'amount', 0, 'delay', 0);
      end loop;
      insert into public.commander_routes (game_id, commander_id, stops, created_tick, origin_territory_id, looping)
      values (p_game_id, v_c.id, v_stops, v_tick, v_c.at_id, false);
      perform public.launch_leg(p_player_id, v_c.id, v_path[2], 'assault');
      v_force := v_force + v_c.troops;
      v_sent := v_sent + 1;
    exception when others then
      null;
    end;
  end loop;
end;
$f$;
revoke execute on function public.ai_muster(int, int, int) from public, anon, authenticated;

do $patch$
declare
  v_def text;
  v_new text;
  v_fn text;
  v_pairs text[];
  i int;
begin
  for v_fn, v_pairs in
    select * from (values
      ('ai_commanders', array[
        'exit when v_n_cmds > 6 + p_difficulty;',
        'exit when v_n_cmds > 12 + 2 * p_difficulty;',
        'v_reserve := greatest(2, 8 - p_difficulty + case v_style when ''defensive'' then 6 when ''aggressive'' then -3 else 0 end);',
        'v_reserve := case v_style when ''defensive'' then 6 when ''aggressive'' then 1 else 2 end;',
        '(v_style = ''aggressive'' and v_game.current_tick >= 30) or (v_style = ''balanced'' and v_game.current_tick >= 90 and public.castle_count(p_player_id) >= 10)',
        '(v_style = ''aggressive'' and v_game.current_tick >= 20) or (v_style = ''balanced'' and v_game.current_tick >= 40 and public.castle_count(p_player_id) >= 6) or (v_style = ''defensive'' and public.castle_count(p_player_id) >= 14)'
      ]),
      ('ai_hire', array[
        'v_want := least(60, greatest(3, ceil(v_owned * v_ratio)::int));',
        'v_want := least(60, greatest(5, ceil(v_owned * v_ratio)::int));',
        'case p_difficulty when 1 then 0.15 when 2 then 0.25 when 3 then 0.35 when 4 then 0.45 else 0.55 end',
        'case p_difficulty when 1 then 0.25 when 2 then 0.4 when 3 then 0.6 when 4 then 0.7 else 0.8 end',
        'exit when v_hired >= 3 or',
        'exit when v_hired >= 5 or'
      ]),
      ('ai_spend', array[
        'v_budget := floor((v_gold - v_reserve) * (0.5 + 0.1 * (p_difficulty - 1)))::int;',
        'v_budget := floor((v_gold - v_reserve) * least(1.0, 0.5 + 0.1 * (p_difficulty - 1) + case (select gp.ai_style from public.game_players gp where gp.id = p_player_id) when ''aggressive'' then 0.25 when ''defensive'' then -0.1 else 0 end))::int;'
      ]),
      ('ai_take_turn', array[
        '  perform public.ai_commanders(p_game_id, p_player_id, v_difficulty);',
        E'  perform public.ai_commanders(p_game_id, p_player_id, v_difficulty);\n  perform public.ai_muster(p_game_id, p_player_id, v_difficulty);'
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
