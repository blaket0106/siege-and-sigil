create function public.hire_commander_core(p_game_id int, p_player_id int, p_territory_id int, p_school text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.game_players%rowtype;
  v_game public.games%rowtype;
  v_owner int;
  v_role text;
  v_id int;
  v_name text;
begin
  select * into v_player from public.game_players where id = p_player_id for update;
  select * into v_game from public.games where id = p_game_id;

  select owner_player_id into v_owner
  from public.game_territories
  where id = p_territory_id and game_id = p_game_id;
  if v_owner is distinct from p_player_id then
    raise exception 'you do not own that territory';
  end if;

  if v_player.gold < v_game.commander_cost then
    raise exception 'not enough gold: % needed, % available', v_game.commander_cost, v_player.gold;
  end if;

  v_role := case
    when exists (
      select 1 from public.commanders c where c.owner_player_id = p_player_id and c.status <> 'dead'
    ) then 'commander'
    else 'king'
  end;

  update public.game_players set gold = gold - v_game.commander_cost where id = p_player_id;

  insert into public.ledger (game_id, player_id, tick, type, amount)
  values (p_game_id, p_player_id, v_game.current_tick, 'recruit', -v_game.commander_cost);

  v_id := public.create_commander(p_game_id, p_player_id, p_school, v_role, p_territory_id, v_game.current_tick);

  if v_role = 'king' then
    update public.commanders
    set coronation_tick = v_game.current_tick + v_game.coronation_ticks
    where id = v_id;
  end if;

  select name into v_name from public.commanders where id = v_id;

  return jsonb_build_object(
    'commander_id', v_id,
    'name', v_name,
    'school', p_school,
    'role', v_role,
    'cost', v_game.commander_cost,
    'gold', v_player.gold - v_game.commander_cost
  );
end;
$$;

create or replace function public.hire_commander(p_game_id int, p_territory_id int, p_school text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.game_players;
begin
  v_player := public.acting_player(p_game_id);
  return public.hire_commander_core(p_game_id, v_player.id, p_territory_id, p_school);
end;
$$;

create function public.transfer_troops_core(p_game_id int, p_player_id int, p_commander_id int, p_amount int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_c public.commanders%rowtype;
  v_t public.game_territories%rowtype;
begin
  if p_amount is null or p_amount = 0 then
    raise exception 'amount must not be zero';
  end if;

  select * into v_c from public.commanders where id = p_commander_id and game_id = p_game_id for update;
  if not found or v_c.owner_player_id <> p_player_id or v_c.status = 'dead' then
    raise exception 'commander not found';
  end if;
  if v_c.status <> 'idle' or v_c.current_territory_id is null then
    raise exception 'commander must be idle at a territory';
  end if;

  select * into v_t from public.game_territories where id = v_c.current_territory_id for update;
  if v_t.owner_player_id is distinct from p_player_id then
    raise exception 'commander is not at one of your territories';
  end if;

  if p_amount > 0 and v_t.troops < p_amount then
    raise exception 'garrison has only % troops', v_t.troops;
  end if;
  if p_amount < 0 and v_c.troops < - p_amount then
    raise exception 'commander carries only % troops', v_c.troops;
  end if;

  update public.commanders set troops = troops + p_amount where id = v_c.id;
  update public.game_territories set troops = troops - p_amount where id = v_t.id;

  return jsonb_build_object(
    'commander_troops', v_c.troops + p_amount,
    'garrison_troops', v_t.troops - p_amount
  );
end;
$$;

create or replace function public.transfer_troops(p_game_id int, p_commander_id int, p_amount int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.game_players;
begin
  v_player := public.acting_player(p_game_id);
  return public.transfer_troops_core(p_game_id, v_player.id, p_commander_id, p_amount);
end;
$$;

create function public.upgrade_infrastructure_core(p_game_id int, p_player_id int, p_territory_id int, p_type text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.game_players%rowtype;
  v_game public.games%rowtype;
  v_t public.game_territories%rowtype;
  v_level int;
  v_cost int;
begin
  if p_type not in ('treasury', 'recruitment', 'prestige') then
    raise exception 'unknown infrastructure type: %', p_type;
  end if;

  select * into v_player from public.game_players where id = p_player_id for update;
  select * into v_game from public.games where id = p_game_id;
  select * into v_t from public.game_territories where id = p_territory_id and game_id = p_game_id for update;
  if not found or v_t.owner_player_id is distinct from p_player_id then
    raise exception 'you do not own that territory';
  end if;

  v_level := case p_type when 'treasury' then v_t.gold_level when 'recruitment' then v_t.industry_level else v_t.prestige_level end;
  v_cost := public.infra_cost(p_type, v_level, v_t.effective_influence, v_game.infra_cost_mult);
  if v_player.gold < v_cost then
    raise exception 'not enough gold: % needed, % available', v_cost, v_player.gold;
  end if;

  update public.game_players set gold = gold - v_cost where id = p_player_id;
  update public.game_territories
  set gold_level = gold_level + case when p_type = 'treasury' then 1 else 0 end,
      industry_level = industry_level + case when p_type = 'recruitment' then 1 else 0 end,
      prestige_level = prestige_level + case when p_type = 'prestige' then 1 else 0 end
  where id = v_t.id;

  insert into public.ledger (game_id, player_id, tick, type, amount)
  values (p_game_id, p_player_id, v_game.current_tick, 'upgrade', - v_cost);

  return jsonb_build_object('type', p_type, 'level', v_level + 1, 'cost', v_cost, 'gold', v_player.gold - v_cost);
end;
$$;

create or replace function public.upgrade_infrastructure(p_game_id int, p_territory_id int, p_type text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.game_players;
begin
  v_player := public.acting_player(p_game_id);
  return public.upgrade_infrastructure_core(p_game_id, v_player.id, p_territory_id, p_type);
end;
$$;

create function public.ai_pick_area(p_player_id int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_area text;
begin
  select area into v_area
  from public.realm_areas
  where player_id = p_player_id
  order by level, array_position(array['mint', 'barracks', 'armory', 'guildhall', 'stables', 'watchtowers', 'library'], area)
  limit 1;
  if v_area is null then
    return;
  end if;
  update public.realm_areas set is_active = false where player_id = p_player_id and is_active;
  update public.realm_areas set is_active = true where player_id = p_player_id and area = v_area;
end;
$$;

create function public.ai_crown(p_game_id int, p_player_id int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_game public.games%rowtype;
  v_id int;
begin
  if exists (
    select 1 from public.commanders c
    where c.owner_player_id = p_player_id and c.role = 'king' and c.status <> 'dead'
  ) then
    return;
  end if;

  select c.id into v_id
  from public.commanders c
  where c.owner_player_id = p_player_id and c.status <> 'dead'
  order by (select coalesce(sum(ca.level), 0) from public.commander_abilities ca where ca.commander_id = c.id) desc, c.id
  limit 1;
  if v_id is null then
    return;
  end if;

  select * into v_game from public.games where id = p_game_id;
  update public.commanders
  set role = 'king', coronation_tick = v_game.current_tick + v_game.coronation_ticks
  where id = v_id;
end;
$$;

create function public.ai_hire(p_game_id int, p_player_id int, p_difficulty int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_game public.games%rowtype;
  v_gold int;
  v_owned int;
  v_want int;
  v_living int;
  v_terr int;
  v_hired int := 0;
  v_roll float8;
begin
  select * into v_game from public.games where id = p_game_id;
  select count(*) into v_owned from public.game_territories where owner_player_id = p_player_id;
  v_want := least(1 + p_difficulty, greatest(2, v_owned / 2));

  select t.id into v_terr
  from public.game_territories t
  where t.owner_player_id = p_player_id
  order by (t.id = (select capital_territory_id from public.game_players where id = p_player_id)) desc, t.tier desc, t.id
  limit 1;
  if v_terr is null then
    return;
  end if;

  loop
    select count(*) into v_living from public.commanders where owner_player_id = p_player_id and status <> 'dead';
    select gold into v_gold from public.game_players where id = p_player_id;
    exit when v_living >= v_want or v_hired >= 2 or v_gold < v_game.commander_cost;
    v_roll := random();
    perform public.hire_commander_core(
      p_game_id, p_player_id, v_terr,
      case when v_roll < 0.5 then 'battleschool' when v_roll < 0.8 then 'rangers' else 'university' end
    );
    v_hired := v_hired + 1;
  end loop;
end;
$$;

create function public.ai_spend(p_game_id int, p_player_id int, p_difficulty int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_game public.games%rowtype;
  v_gold int;
  v_living int;
  v_reserve int;
  v_budget int;
  v_pick record;
  v_guard int := 0;
begin
  select * into v_game from public.games where id = p_game_id;
  select gold into v_gold from public.game_players where id = p_player_id;
  select count(*) into v_living from public.commanders where owner_player_id = p_player_id and status <> 'dead';

  v_reserve := case when v_living < 1 + p_difficulty then v_game.commander_cost else 0 end;
  v_budget := floor((v_gold - v_reserve) * (0.3 + 0.1 * (p_difficulty - 1)))::int;

  loop
    v_guard := v_guard + 1;
    exit when v_guard > 30 or v_budget <= 0;

    select x.id, x.t, x.cost into v_pick
    from (
      select
        gt.id,
        tp.t,
        public.infra_cost(
          tp.t,
          case tp.t when 'recruitment' then gt.industry_level else gt.gold_level end,
          gt.effective_influence,
          v_game.infra_cost_mult
        ) as cost
      from public.game_territories gt
      cross join (values ('recruitment'), ('treasury')) as tp(t)
      where gt.owner_player_id = p_player_id
    ) x
    order by x.cost * case x.t when 'recruitment' then 1.0 else 1.2 end, x.id
    limit 1;

    exit when v_pick.id is null or v_pick.cost > v_budget;
    perform public.upgrade_infrastructure_core(p_game_id, p_player_id, v_pick.id, v_pick.t);
    v_budget := v_budget - v_pick.cost;
  end loop;
end;
$$;

create function public.ai_commanders(p_game_id int, p_player_id int, p_difficulty int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
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
begin
  select * into v_game from public.games where id = p_game_id;
  v_margin := case p_difficulty when 1 then 1.6 when 2 then 1.4 when 3 then 1.2 when 4 then 1.1 else 1.0 end;
  v_reserve := 8 - p_difficulty;
  v_armory := public.armory_level(p_player_id);

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
      where gt.game_id = p_game_id
        and not public.is_friendly_territory(p_player_id, gt.id)
        and exists (
          select 1 from public.territory_edges e
          where e.game_id = gt.game_id
            and (
              (e.from_territory_id = gt.id and public.is_friendly_territory(p_player_id, e.to_territory_id))
              or (e.to_territory_id = gt.id and public.is_friendly_territory(p_player_id, e.from_territory_id))
            )
        )
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
      from public.game_territories gt
      where gt.game_id = p_game_id and gt.owner_player_id = p_player_id
      order by (
        select min(sqrt((h.x - gt.x) ^ 2 + (h.y - gt.y) ^ 2))
        from public.game_territories h
        where h.game_id = gt.game_id and not public.is_friendly_territory(p_player_id, h.id)
      ) asc nulls last, gt.troops desc, gt.id
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
$$;

create function public.ai_take_turn(p_game_id int, p_player_id int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_difficulty int;
begin
  select ai_difficulty into v_difficulty from public.games where id = p_game_id;

  perform public.ai_pick_area(p_player_id);
  perform public.ai_crown(p_game_id, p_player_id);
  perform public.ai_hire(p_game_id, p_player_id, v_difficulty);
  perform public.ai_commanders(p_game_id, p_player_id, v_difficulty);
  perform public.ai_spend(p_game_id, p_player_id, v_difficulty);
end;
$$;

create function public.run_ai_players(p_game_id int, p_tick int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_p record;
  v_interval int;
begin
  select case ai_difficulty when 1 then 6 when 2 then 4 when 3 then 3 when 4 then 2 else 1 end
  into v_interval
  from public.games where id = p_game_id;

  for v_p in
    select id from public.game_players
    where game_id = p_game_id and is_ai and eliminated_at_tick is null
    order by id
  loop
    continue when (p_tick + v_p.id) % v_interval <> 0;
    begin
      perform public.ai_take_turn(p_game_id, v_p.id);
    exception when others then
      insert into public.game_events (game_id, tick, type, payload)
      values (p_game_id, p_tick, 'ai_error', jsonb_build_object('player_id', v_p.id, 'message', sqlerrm));
    end;
  end loop;
end;
$$;

create or replace function public.resolve_tick_events(p_game_id int, p_tick int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cycle boolean;
  v_moves jsonb;
  v_inter jsonb;
  v_combat jsonb;
  v_siege jsonb;
begin
  select p_tick % production_cycle_ticks = 0 into v_cycle from public.games where id = p_game_id;

  perform public.run_ai_players(p_game_id, p_tick);
  perform public.apply_siege_attrition(p_game_id, p_tick, v_cycle);
  v_moves := public.advance_movements(p_game_id, p_tick);
  v_inter := public.resolve_intercepts(p_game_id, p_tick);
  v_combat := public.resolve_contacts(p_game_id, p_tick);
  v_siege := public.resolve_siege_contacts(p_game_id, p_tick);
  perform public.end_stale_sieges(p_game_id);
  perform public.award_production_xp(p_game_id, p_tick, v_cycle);
  if v_cycle then
    perform public.award_scout_xp(p_game_id, p_tick);
  end if;
  perform public.evaluate_game_end(p_game_id, p_tick);

  return jsonb_build_object(
    'arrivals', v_moves -> 'arrivals',
    'contacts', v_moves -> 'contacts',
    'captures', v_combat -> 'captures',
    'sieges_started', v_siege -> 'sieges_started',
    'combats', (v_inter ->> 'combats')::int + (v_combat ->> 'combats')::int + (v_siege ->> 'combats')::int,
    'combat_events', (v_inter -> 'combat_events') || (v_combat -> 'combat_events') || (v_siege -> 'combat_events')
  );
end;
$$;

revoke execute on function public.hire_commander_core(int, int, int, text) from public, anon, authenticated;
revoke execute on function public.transfer_troops_core(int, int, int, int) from public, anon, authenticated;
revoke execute on function public.upgrade_infrastructure_core(int, int, int, text) from public, anon, authenticated;
revoke execute on function public.ai_pick_area(int) from public, anon, authenticated;
revoke execute on function public.ai_crown(int, int) from public, anon, authenticated;
revoke execute on function public.ai_hire(int, int, int) from public, anon, authenticated;
revoke execute on function public.ai_spend(int, int, int) from public, anon, authenticated;
revoke execute on function public.ai_commanders(int, int, int) from public, anon, authenticated;
revoke execute on function public.ai_take_turn(int, int) from public, anon, authenticated;
revoke execute on function public.run_ai_players(int, int) from public, anon, authenticated;
revoke execute on function public.resolve_tick_events(int, int) from public, anon, authenticated;

revoke execute on function public.hire_commander(int, int, text) from public, anon;
grant execute on function public.hire_commander(int, int, text) to authenticated;
revoke execute on function public.transfer_troops(int, int, int) from public, anon;
grant execute on function public.transfer_troops(int, int, int) to authenticated;
revoke execute on function public.upgrade_infrastructure(int, int, text) from public, anon;
grant execute on function public.upgrade_infrastructure(int, int, text) to authenticated;
