alter table public.commanders add column coronation_tick int;

create function public.acting_player(p_game_id int)
returns public.game_players
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_status text;
  v_player public.game_players;
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;

  select status into v_status from public.games where id = p_game_id;
  if v_status is null then
    raise exception 'game not found';
  end if;
  if v_status <> 'active' then
    raise exception 'game is not active';
  end if;

  select * into v_player
  from public.game_players
  where game_id = p_game_id and user_id = v_uid
  for update;
  if not found then
    raise exception 'you are not in this game';
  end if;
  if v_player.eliminated_at_tick is not null then
    raise exception 'you have been eliminated';
  end if;

  return v_player;
end;
$$;

create function public.infra_cost(p_type text, p_level int, p_effective_influence int, p_mult float8)
returns int
language sql
immutable
set search_path = ''
as $$
  select greatest(1, floor(
    (case p_type when 'treasury' then 500 when 'recruitment' then 1000 when 'prestige' then 4000 end)::float8
    * (p_level + 1) / p_effective_influence * p_mult
  ))::int;
$$;

create function public.refresh_effective_influence(p_game_id int, p_player_id int)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.game_territories gt
  set effective_influence = gt.base_influence + 5 * coalesce((
    select ra.level from public.realm_areas ra where ra.player_id = p_player_id and ra.area = 'guildhall'
  ), 0)
  where gt.game_id = p_game_id and gt.owner_player_id = p_player_id;
$$;

create function public.add_area_prestige(p_game_id int, p_player_id int, p_area text, p_amount int)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_mult float8;
  v_tick int;
  v_area public.realm_areas%rowtype;
  v_cost int;
  v_gains int := 0;
begin
  select area_cost_mult, current_tick into v_mult, v_tick from public.games where id = p_game_id;

  select * into v_area
  from public.realm_areas
  where player_id = p_player_id and area = p_area
  for update;
  if not found then
    raise exception 'unknown area % for player %', p_area, p_player_id;
  end if;

  v_area.prestige_accumulated := v_area.prestige_accumulated + p_amount;
  loop
    v_cost := ceil(144 * v_area.level * v_mult)::int;
    exit when v_area.prestige_accumulated < v_cost;
    v_area.prestige_accumulated := v_area.prestige_accumulated - v_cost;
    v_area.level := v_area.level + 1;
    v_gains := v_gains + 1;
  end loop;

  update public.realm_areas
  set level = v_area.level, prestige_accumulated = v_area.prestige_accumulated
  where player_id = p_player_id and area = p_area;

  if v_gains > 0 then
    insert into public.game_events (game_id, tick, type, payload)
    values (p_game_id, v_tick, 'area_level_up', jsonb_build_object('player_id', p_player_id, 'area', p_area, 'level', v_area.level));

    if p_area = 'guildhall' then
      perform public.refresh_effective_influence(p_game_id, p_player_id);
    end if;
  end if;

  return v_area.level;
end;
$$;

revoke execute on function public.acting_player(int) from public, anon, authenticated;
revoke execute on function public.infra_cost(text, int, int, float8) from public, anon, authenticated;
revoke execute on function public.refresh_effective_influence(int, int) from public, anon, authenticated;
revoke execute on function public.add_area_prestige(int, int, text, int) from public, anon, authenticated;

create function public.hire_commander(p_game_id int, p_territory_id int, p_school text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.game_players;
  v_game public.games%rowtype;
  v_owner int;
  v_role text;
  v_id int;
  v_name text;
begin
  v_player := public.acting_player(p_game_id);
  select * into v_game from public.games where id = p_game_id;

  select owner_player_id into v_owner
  from public.game_territories
  where id = p_territory_id and game_id = p_game_id;
  if v_owner is distinct from v_player.id then
    raise exception 'you do not own that territory';
  end if;

  if v_player.gold < v_game.commander_cost then
    raise exception 'not enough gold: % needed, % available', v_game.commander_cost, v_player.gold;
  end if;

  v_role := case
    when exists (
      select 1 from public.commanders c where c.owner_player_id = v_player.id and c.status <> 'dead'
    ) then 'commander'
    else 'king'
  end;

  update public.game_players set gold = gold - v_game.commander_cost where id = v_player.id;

  insert into public.ledger (game_id, player_id, tick, type, amount)
  values (p_game_id, v_player.id, v_game.current_tick, 'recruit', -v_game.commander_cost);

  v_id := public.create_commander(p_game_id, v_player.id, p_school, v_role, p_territory_id, v_game.current_tick);

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

create function public.transfer_troops(p_game_id int, p_commander_id int, p_amount int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.game_players;
  v_c public.commanders%rowtype;
  v_t public.game_territories%rowtype;
begin
  v_player := public.acting_player(p_game_id);

  if p_amount is null or p_amount = 0 then
    raise exception 'amount must not be zero';
  end if;

  select * into v_c from public.commanders where id = p_commander_id and game_id = p_game_id for update;
  if not found or v_c.owner_player_id <> v_player.id or v_c.status = 'dead' then
    raise exception 'commander not found';
  end if;
  if v_c.status <> 'idle' or v_c.current_territory_id is null then
    raise exception 'commander must be idle at a territory';
  end if;

  select * into v_t from public.game_territories where id = v_c.current_territory_id for update;
  if v_t.owner_player_id is distinct from v_player.id then
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

create function public.upgrade_infrastructure(p_game_id int, p_territory_id int, p_type text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.game_players;
  v_game public.games%rowtype;
  v_t public.game_territories%rowtype;
  v_level int;
  v_cost int;
begin
  v_player := public.acting_player(p_game_id);
  if p_type not in ('treasury', 'recruitment', 'prestige') then
    raise exception 'unknown infrastructure type: %', p_type;
  end if;

  select * into v_game from public.games where id = p_game_id;
  select * into v_t from public.game_territories where id = p_territory_id and game_id = p_game_id for update;
  if not found or v_t.owner_player_id is distinct from v_player.id then
    raise exception 'you do not own that territory';
  end if;

  v_level := case p_type when 'treasury' then v_t.gold_level when 'recruitment' then v_t.industry_level else v_t.prestige_level end;
  v_cost := public.infra_cost(p_type, v_level, v_t.effective_influence, v_game.infra_cost_mult);
  if v_player.gold < v_cost then
    raise exception 'not enough gold: % needed, % available', v_cost, v_player.gold;
  end if;

  update public.game_players set gold = gold - v_cost where id = v_player.id;
  update public.game_territories
  set gold_level = gold_level + case when p_type = 'treasury' then 1 else 0 end,
      industry_level = industry_level + case when p_type = 'recruitment' then 1 else 0 end,
      prestige_level = prestige_level + case when p_type = 'prestige' then 1 else 0 end
  where id = v_t.id;

  insert into public.ledger (game_id, player_id, tick, type, amount)
  values (p_game_id, v_player.id, v_game.current_tick, 'upgrade', - v_cost);

  return jsonb_build_object('type', p_type, 'level', v_level + 1, 'cost', v_cost, 'gold', v_player.gold - v_cost);
end;
$$;

create function public.bulk_upgrade_infrastructure(p_game_id int, p_infra_type text, p_budget int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.game_players;
  v_game public.games%rowtype;
  v_remaining int;
  v_spent int := 0;
  v_upgraded int := 0;
  v_next record;
  v_guard int := 0;
begin
  v_player := public.acting_player(p_game_id);
  if p_infra_type not in ('treasury', 'recruitment', 'prestige') then
    raise exception 'unknown infrastructure type: %', p_infra_type;
  end if;
  if p_budget is null or p_budget <= 0 then
    raise exception 'budget must be positive';
  end if;

  select * into v_game from public.games where id = p_game_id;
  v_remaining := least(p_budget, v_player.gold);

  loop
    v_guard := v_guard + 1;
    exit when v_guard > 1000;

    select
      gt.id as id,
      public.infra_cost(
        p_infra_type,
        case p_infra_type when 'treasury' then gt.gold_level when 'recruitment' then gt.industry_level else gt.prestige_level end,
        gt.effective_influence,
        v_game.infra_cost_mult
      ) as cost
    into v_next
    from public.game_territories gt
    where gt.game_id = p_game_id and gt.owner_player_id = v_player.id
    order by cost, gt.id
    limit 1;

    exit when v_next.id is null or v_next.cost > v_remaining;

    update public.game_territories
    set gold_level = gold_level + case when p_infra_type = 'treasury' then 1 else 0 end,
        industry_level = industry_level + case when p_infra_type = 'recruitment' then 1 else 0 end,
        prestige_level = prestige_level + case when p_infra_type = 'prestige' then 1 else 0 end
    where id = v_next.id;

    v_remaining := v_remaining - v_next.cost;
    v_spent := v_spent + v_next.cost;
    v_upgraded := v_upgraded + 1;
  end loop;

  if v_spent > 0 then
    update public.game_players set gold = gold - v_spent where id = v_player.id;
    insert into public.ledger (game_id, player_id, tick, type, amount)
    values (p_game_id, v_player.id, v_game.current_tick, 'upgrade', - v_spent);
  end if;

  return jsonb_build_object('upgraded', v_upgraded, 'spent', v_spent);
end;
$$;

create function public.build_road(p_game_id int, p_territory_id int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.game_players;
  v_game public.games%rowtype;
  v_t public.game_territories%rowtype;
  v_cost int;
begin
  v_player := public.acting_player(p_game_id);
  select * into v_game from public.games where id = p_game_id;

  select * into v_t from public.game_territories where id = p_territory_id and game_id = p_game_id for update;
  if not found or v_t.owner_player_id is distinct from v_player.id then
    raise exception 'you do not own that territory';
  end if;
  if v_t.has_road then
    raise exception 'that territory already has a road';
  end if;

  v_cost := greatest(1, floor(10000.0 / v_t.base_influence * v_game.infra_cost_mult))::int;
  if v_player.gold < v_cost then
    raise exception 'not enough gold: % needed, % available', v_cost, v_player.gold;
  end if;

  update public.game_players set gold = gold - v_cost where id = v_player.id;
  update public.game_territories set has_road = true where id = v_t.id;
  insert into public.ledger (game_id, player_id, tick, type, amount)
  values (p_game_id, v_player.id, v_game.current_tick, 'road', - v_cost);

  return jsonb_build_object('cost', v_cost, 'gold', v_player.gold - v_cost);
end;
$$;

create function public.demolish_road(p_game_id int, p_territory_id int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.game_players;
  v_t public.game_territories%rowtype;
begin
  v_player := public.acting_player(p_game_id);

  select * into v_t from public.game_territories where id = p_territory_id and game_id = p_game_id for update;
  if not found or v_t.owner_player_id is distinct from v_player.id then
    raise exception 'you do not own that territory';
  end if;
  if not v_t.has_road then
    raise exception 'that territory has no road';
  end if;

  update public.game_territories set has_road = false where id = v_t.id;
end;
$$;

create function public.send_gold(p_game_id int, p_target_player_id int, p_amount int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.game_players;
  v_target public.game_players%rowtype;
  v_tick int;
begin
  v_player := public.acting_player(p_game_id);

  if p_amount is null or p_amount <= 0 then
    raise exception 'amount must be positive';
  end if;
  if p_target_player_id = v_player.id then
    raise exception 'you cannot send gold to yourself';
  end if;

  select * into v_target
  from public.game_players
  where id = p_target_player_id and game_id = p_game_id
  for update;
  if not found then
    raise exception 'player not found in this game';
  end if;
  if v_target.eliminated_at_tick is not null then
    raise exception 'that player has been eliminated';
  end if;
  if v_player.gold < p_amount then
    raise exception 'not enough gold: % needed, % available', p_amount, v_player.gold;
  end if;

  select current_tick into v_tick from public.games where id = p_game_id;

  update public.game_players set gold = gold - p_amount where id = v_player.id;
  update public.game_players set gold = gold + p_amount where id = v_target.id;

  insert into public.ledger (game_id, player_id, tick, type, amount, counterparty_player_id)
  values
    (p_game_id, v_player.id, v_tick, 'send_gold', - p_amount, v_target.id),
    (p_game_id, v_target.id, v_tick, 'receive_gold', p_amount, v_player.id);

  insert into public.player_inbox (game_id, player_id, type, title, body, tick)
  values (
    p_game_id, v_target.id, 'system', 'Gold received',
    jsonb_build_object('kind', 'gold_received', 'from_player_id', v_player.id, 'amount', p_amount),
    v_tick
  );

  return jsonb_build_object('sent', p_amount, 'gold', v_player.gold - p_amount);
end;
$$;

create function public.set_active_area(p_game_id int, p_area text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.game_players;
begin
  v_player := public.acting_player(p_game_id);

  if not exists (select 1 from public.realm_areas where player_id = v_player.id and area = p_area) then
    raise exception 'unknown area: %', p_area;
  end if;

  update public.realm_areas set is_active = false where player_id = v_player.id and is_active;
  update public.realm_areas set is_active = true where player_id = v_player.id and area = p_area;
end;
$$;

create function public.assign_garrison_commander(p_game_id int, p_commander_id int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.game_players;
  v_c public.commanders%rowtype;
  v_owner int;
begin
  v_player := public.acting_player(p_game_id);

  select * into v_c from public.commanders where id = p_commander_id and game_id = p_game_id for update;
  if not found or v_c.owner_player_id <> v_player.id or v_c.status = 'dead' then
    raise exception 'commander not found';
  end if;
  if v_c.status <> 'idle' or v_c.current_territory_id is null then
    raise exception 'commander must be idle at a territory';
  end if;

  select owner_player_id into v_owner from public.game_territories where id = v_c.current_territory_id;
  if v_owner is distinct from v_player.id then
    raise exception 'commander is not at one of your territories';
  end if;

  update public.game_territories
  set garrison_commander_id = null
  where garrison_commander_id = v_c.id and id <> v_c.current_territory_id;

  update public.game_territories
  set garrison_commander_id = v_c.id
  where id = v_c.current_territory_id;
end;
$$;

create function public.unassign_garrison_commander(p_game_id int, p_territory_id int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.game_players;
  v_owner int;
begin
  v_player := public.acting_player(p_game_id);

  select owner_player_id into v_owner
  from public.game_territories
  where id = p_territory_id and game_id = p_game_id;
  if v_owner is distinct from v_player.id then
    raise exception 'you do not own that territory';
  end if;

  update public.game_territories set garrison_commander_id = null where id = p_territory_id;
end;
$$;

create function public.crown_commander(p_game_id int, p_commander_id int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.game_players;
  v_game public.games%rowtype;
  v_c public.commanders%rowtype;
  v_tick int;
begin
  v_player := public.acting_player(p_game_id);
  select * into v_game from public.games where id = p_game_id;

  if exists (
    select 1 from public.commanders c
    where c.owner_player_id = v_player.id and c.role = 'king' and c.status <> 'dead'
  ) then
    raise exception 'you already have a king';
  end if;

  select * into v_c from public.commanders where id = p_commander_id and game_id = p_game_id for update;
  if not found or v_c.owner_player_id <> v_player.id or v_c.status = 'dead' then
    raise exception 'commander not found';
  end if;

  v_tick := v_game.current_tick + v_game.coronation_ticks;
  update public.commanders set role = 'king', coronation_tick = v_tick where id = v_c.id;

  return jsonb_build_object('commander_id', v_c.id, 'name', v_c.name, 'effective_tick', v_tick);
end;
$$;

revoke execute on function public.hire_commander(int, int, text) from public, anon;
grant execute on function public.hire_commander(int, int, text) to authenticated;
revoke execute on function public.transfer_troops(int, int, int) from public, anon;
grant execute on function public.transfer_troops(int, int, int) to authenticated;
revoke execute on function public.upgrade_infrastructure(int, int, text) from public, anon;
grant execute on function public.upgrade_infrastructure(int, int, text) to authenticated;
revoke execute on function public.bulk_upgrade_infrastructure(int, text, int) from public, anon;
grant execute on function public.bulk_upgrade_infrastructure(int, text, int) to authenticated;
revoke execute on function public.build_road(int, int) from public, anon;
grant execute on function public.build_road(int, int) to authenticated;
revoke execute on function public.demolish_road(int, int) from public, anon;
grant execute on function public.demolish_road(int, int) to authenticated;
revoke execute on function public.send_gold(int, int, int) from public, anon;
grant execute on function public.send_gold(int, int, int) to authenticated;
revoke execute on function public.set_active_area(int, text) from public, anon;
grant execute on function public.set_active_area(int, text) to authenticated;
revoke execute on function public.assign_garrison_commander(int, int) from public, anon;
grant execute on function public.assign_garrison_commander(int, int) to authenticated;
revoke execute on function public.unassign_garrison_commander(int, int) from public, anon;
grant execute on function public.unassign_garrison_commander(int, int) to authenticated;
revoke execute on function public.crown_commander(int, int) from public, anon;
grant execute on function public.crown_commander(int, int) to authenticated;
