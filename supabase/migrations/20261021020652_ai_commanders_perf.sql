create or replace function public.ai_commanders(p_game_id integer, p_player_id integer, p_difficulty integer)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_game public.games%rowtype;
  v_margin float8;
  v_reserve int;
  v_armory int;
  v_c record;
  v_t record;
  v_plan jsonb;
  v_gar int;
  v_att int;
  v_ids int[];
  v_def_est float8;
  v_atk_dmg int;
  v_def_dmg int;
  v_ra int;
  v_rd int;
  v_score float8;
  v_best int;
  v_best_score float8;
  v_dest int;
  v_allies int[];
  v_friendly int[];
  v_frontier int[];
  v_own_ids int[];
  v_own_dist float8[];
begin
  select * into v_game from public.games where id = p_game_id;
  v_margin := case p_difficulty when 1 then 1.6 when 2 then 1.4 when 3 then 1.2 when 4 then 1.1 else 1.0 end;
  v_reserve := 8 - p_difficulty;
  v_armory := public.armory_level(p_player_id);

  select coalesce(array_agg(case when d.player_a_id = p_player_id then d.player_b_id else d.player_a_id end), '{}')
  into v_allies
  from public.diplomacy d
  where d.game_id = p_game_id and d.status = 'allied' and p_player_id in (d.player_a_id, d.player_b_id);

  select coalesce(array_agg(gt.id), '{}') into v_friendly
  from public.game_territories gt
  where gt.game_id = p_game_id
    and gt.owner_player_id is not null
    and (gt.owner_player_id = p_player_id or gt.owner_player_id = any (v_allies));

  select coalesce(array_agg(distinct gt.id), '{}') into v_frontier
  from public.game_territories gt
  join public.territory_edges e on e.game_id = gt.game_id and (e.from_territory_id = gt.id or e.to_territory_id = gt.id)
  where gt.game_id = p_game_id
    and not (gt.id = any (v_friendly))
    and case when e.from_territory_id = gt.id then e.to_territory_id else e.from_territory_id end = any (v_friendly);

  select array_agg(o.id order by o.id),
         array_agg((select min(sqrt((h.x - o.x) ^ 2 + (h.y - o.y) ^ 2))
                    from public.game_territories h
                    where h.game_id = o.game_id and not (h.id = any (v_friendly))) order by o.id)
  into v_own_ids, v_own_dist
  from public.game_territories o
  where o.game_id = p_game_id and o.owner_player_id = p_player_id;

  for v_c in
    select c.id, c.current_territory_id
    from public.commanders c
    join public.game_territories gt on gt.id = c.current_territory_id and gt.owner_player_id = p_player_id
    where c.game_id = p_game_id
      and c.owner_player_id = p_player_id
      and c.status = 'idle'
      and not exists (select 1 from public.game_territories g2 where g2.garrison_commander_id = c.id)
    order by c.troops desc, c.id
  loop
    select troops into v_gar from public.game_territories where id = v_c.current_territory_id;
    if v_gar - v_reserve > 0 then
      perform public.transfer_troops_core(p_game_id, p_player_id, v_c.id, v_gar - v_reserve);
    end if;

    select troops into v_att from public.commanders where id = v_c.id;
    continue when v_att < 6;

    v_best := null;
    v_best_score := -1e9;

    for v_t in
      select gt.*
      from public.game_territories gt
      where gt.id = any (v_frontier)
      order by gt.id
    loop
      begin
        v_plan := public.plan_march(p_player_id, v_c.id, v_t.id);
      exception when others then
        continue;
      end;
      continue when not (v_plan ->> 'in_range')::boolean;

      select coalesce(array_agg(c2.id order by c2.id), '{}') into v_ids
      from public.commanders c2
      where v_t.owner_player_id is not null
        and c2.current_territory_id = v_t.id
        and c2.status = 'idle'
        and (c2.owner_player_id = v_t.owner_player_id or public.are_allied(v_t.owner_player_id, c2.owner_player_id));

      v_def_est := v_t.troops
        + coalesce((select sum(troops) from public.commanders where id = any (v_ids)), 0)
        + (v_plan ->> 'travel_ticks')::int * (v_t.industry_level * 5.0 / v_game.production_cycle_ticks);
      if p_difficulty <= 2 then
        v_def_est := v_def_est * (0.75 + random() * 0.5);
      end if;
      v_def_est := v_def_est * v_margin;

      v_atk_dmg := greatest(1, v_armory + public.side_valor(array[v_c.id], null));
      v_def_dmg := greatest(1,
        case when v_t.owner_player_id is null then 1 else public.armory_level(v_t.owner_player_id) end
        + public.side_valor(v_ids, v_t.garrison_commander_id) + 1
      );
      v_ra := ceil(v_att::float8 / v_def_dmg)::int;
      v_rd := ceil(v_def_est / v_atk_dmg)::int;
      continue when v_def_est > 0 and v_ra <= v_rd;

      v_score := v_t.tier * 3
        + case when v_t.owner_player_id is null then 2 else 0 end
        + v_t.gold_level
        - (v_plan ->> 'travel_ticks')::int * 0.2
        + random();
      if v_score > v_best_score then
        v_best := v_t.id;
        v_best_score := v_score;
      end if;
    end loop;

    if v_best is not null then
      begin
        perform public.launch_leg(p_player_id, v_c.id, v_best, 'assault');
      exception when others then
        null;
      end;
    else
      select gt.id into v_dest
      from unnest(v_own_ids, v_own_dist) as d(id, dist)
      join public.game_territories gt on gt.id = d.id
      order by d.dist asc nulls last, gt.troops desc, gt.id
      limit 1;

      if v_dest is not null and v_dest <> v_c.current_territory_id then
        begin
          perform public.launch_leg(p_player_id, v_c.id, v_dest, 'assault');
        exception when others then
          null;
        end;
      end if;
    end if;
  end loop;
end;
$function$;
