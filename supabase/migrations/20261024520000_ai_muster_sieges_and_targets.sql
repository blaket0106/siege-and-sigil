create or replace function public.ai_muster(p_game_id int, p_player_id int, p_difficulty int)
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
  v_t record;
  v_best_t int;
  v_best_need float8 := 1e18;
  v_defenders float8;
  v_atk int;
  v_def int;
  v_assault float8;
  v_lo int;
  v_hi int;
  v_mid int;
  v_eff float8;
  v_force float8;
  v_c record;
  v_plan jsonb;
  v_path int[];
  v_n int;
  v_stops jsonb;
  v_i int;
  v_sent int := 0;
  v_tick int;
  v_margin float8;
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
  v_margin := case v_style when 'aggressive' then 1.05 when 'balanced' then 1.15 else 1.3 end;

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

  v_atk := greatest(1, public.armory_level(p_player_id) + public.side_valor(array[v_sc], null));

  for v_t in
    select t.*
    from public.game_territories t
    where t.game_id = p_game_id and t.owner_player_id is not null and t.owner_player_id <> p_player_id
      and not (t.owner_player_id = any (v_allies)) and not t.is_junction
      and not public.are_truced(p_player_id, t.owner_player_id)
      and sqrt((t.x - v_hx) ^ 2 + (t.y - v_hy) ^ 2) <= 8 * 150 * v_game.world_scale
    order by ((t.x - v_hx) ^ 2 + (t.y - v_hy) ^ 2) * (case when t.owner_player_id = any (v_prey) then 0.5 else 1 end) * (case when exists (select 1 from public.game_players hp where hp.id = t.owner_player_id and not hp.is_ai) then 0.7 else 1 end)
    limit 6
  loop
    begin
      v_plan := public.plan_march(p_player_id, v_sc, v_t.id);
    exception when others then
      continue;
    end;
    continue when not (v_plan ->> 'in_range')::boolean;
    v_defenders := v_t.troops + coalesce((select sum(c2.troops) from public.commanders c2
      where c2.current_territory_id = v_t.id and c2.status = 'idle' and c2.owner_player_id = v_t.owner_player_id), 0);
    v_def := greatest(1, public.armory_level(v_t.owner_player_id) + public.side_valor(array[]::int[], v_t.garrison_commander_id) + 1 + case when v_t.terrain = 'mountain' then 1 else 0 end);
    v_assault := v_def * ceil(v_defenders * v_margin / v_atk) + 1;
    v_eff := v_assault;
    if p_difficulty >= 3 then
      v_lo := 1;
      v_hi := least(greatest(v_assault::int, 2), 400);
      while v_lo < v_hi loop
        v_mid := (v_lo + v_hi) / 2;
        if public.siege_can_win(v_mid, v_def, v_atk, v_t.troops, 28) then
          v_hi := v_mid;
        else
          v_lo := v_mid + 1;
        end if;
      end loop;
      if public.siege_can_win(v_lo, v_def, v_atk, v_t.troops, 28) then
        v_eff := least(v_assault, v_lo * 1.15 + 2);
      end if;
    end if;
    if v_eff < v_best_need then
      v_best_need := v_eff;
      v_best_t := v_t.id;
    end if;
  end loop;
  if v_best_t is null then
    return;
  end if;

  v_force := v_sc_troops + greatest(0, v_hub_troops - 2);
  if v_force >= v_best_need then
    return;
  end if;

  for v_c in
    select c.id, c.troops, c.current_territory_id as at_id, ct.troops as at_troops
    from public.commanders c
    join public.game_territories ct on ct.id = c.current_territory_id and ct.owner_player_id = p_player_id
    where c.game_id = p_game_id and c.owner_player_id = p_player_id and c.status = 'idle'
      and c.id <> v_sc and c.role <> 'king' and (c.troops + greatest(0, ct.troops - 2)) >= 6 and ct.id <> v_hub
      and not exists (select 1 from public.game_territories g2 where g2.garrison_commander_id = c.id)
      and not exists (select 1 from public.commander_routes r where r.commander_id = c.id and r.status = 'active')
    order by (c.troops + ct.troops) desc, c.id
    limit 12
  loop
    exit when v_force >= v_best_need or v_sent >= 6;
    begin
      v_plan := public.plan_march(p_player_id, v_c.id, v_hub);
      continue when (v_plan ->> 'travel_ticks')::int > 16;
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
      perform public.transfer_troops_core(p_game_id, p_player_id, v_c.id, greatest(0, v_c.at_troops - 2));
      insert into public.commander_routes (game_id, commander_id, stops, created_tick, origin_territory_id, looping)
      values (p_game_id, v_c.id, v_stops, v_tick, v_c.at_id, false);
      perform public.launch_leg(p_player_id, v_c.id, v_path[2], 'assault');
      v_force := v_force + v_c.troops + greatest(0, v_c.at_troops - 2);
      v_sent := v_sent + 1;
    exception when others then
      null;
    end;
  end loop;
end;
$f$;
