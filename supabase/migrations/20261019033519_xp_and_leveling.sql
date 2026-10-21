create table public.xp_config (
  key text primary key,
  value float8 not null
);

alter table public.xp_config enable row level security;

create policy "xp config is readable by signed-in users"
  on public.xp_config for select to authenticated
  using (true);

insert into public.xp_config (key, value) values
  ('xp_base_cost', 1000),
  ('xp_rank_step', 0.1),
  ('rank_cap', 20),
  ('ability_max_level', 3),
  ('school_affinity', 1.5),
  ('valor_per_troop', 20),
  ('tactics_per_troop', 20),
  ('siegecraft_per_cycle', 80),
  ('siegecraft_break_bonus', 300),
  ('muster_per_troop', 3),
  ('steward_per_gold', 0.6),
  ('scholar_per_prestige', 1),
  ('pace_per_unit', 1),
  ('scout_per_cycle', 100),
  ('plunder_per_tier', 400);

create function public.xp_cfg(p_key text)
returns float8
language sql
stable
security definer
set search_path = ''
as $$
  select value from public.xp_config where key = p_key;
$$;

create function public.award_xp(p_commander_id int, p_ability text, p_amount float8)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_c public.commanders%rowtype;
  v_row public.commander_abilities%rowtype;
  v_school_abilities text[];
  v_rank int;
  v_max int;
  v_cap int;
  v_cost float8;
  v_xp float8;
  v_level int;
  v_gains int := 0;
  v_tick int;
  v_user uuid;
begin
  if p_commander_id is null or p_amount is null or p_amount <= 0 then
    return;
  end if;

  select * into v_c from public.commanders where id = p_commander_id;
  if not found or v_c.status = 'dead' then
    return;
  end if;

  select * into v_row from public.commander_abilities
  where commander_id = p_commander_id and ability = p_ability
  for update;
  if not found then
    return;
  end if;

  v_max := public.xp_cfg('ability_max_level')::int;
  v_cap := public.xp_cfg('rank_cap')::int;
  select coalesce(sum(level), 0) into v_rank from public.commander_abilities where commander_id = p_commander_id;
  if v_row.level >= v_max or v_rank >= v_cap then
    return;
  end if;

  v_school_abilities := case v_c.school
    when 'battleschool' then array['valor', 'tactics', 'siegecraft']
    when 'university' then array['muster', 'steward', 'scholar']
    when 'rangers' then array['pace', 'scout', 'plunder']
    else '{}'::text[]
  end;

  v_xp := v_row.xp + p_amount * case when p_ability = any (v_school_abilities) then public.xp_cfg('school_affinity') else 1 end;
  v_level := v_row.level;

  loop
    exit when v_level >= v_max or v_rank >= v_cap;
    v_cost := public.xp_cfg('xp_base_cost') * (v_level + 1) * (1 + public.xp_cfg('xp_rank_step') * v_rank);
    exit when v_xp < v_cost;
    v_xp := v_xp - v_cost;
    v_level := v_level + 1;
    v_rank := v_rank + 1;
    v_gains := v_gains + 1;
  end loop;

  if v_level >= v_max or v_rank >= v_cap then
    v_xp := 0;
  end if;

  update public.commander_abilities
  set level = v_level, xp = v_xp
  where commander_id = p_commander_id and ability = p_ability;

  if v_gains > 0 then
    select current_tick into v_tick from public.games where id = v_c.game_id;
    insert into public.game_events (game_id, tick, type, payload)
    values (v_c.game_id, v_tick, 'commander_level_up', jsonb_build_object('commander_id', p_commander_id, 'ability', p_ability, 'level', v_level, 'rank', v_rank));

    select user_id into v_user from public.game_players where id = v_c.owner_player_id;
    if v_user is not null then
      insert into public.player_inbox (game_id, player_id, type, title, body, tick)
      values (
        v_c.game_id, v_c.owner_player_id, 'system',
        v_c.name || ' improved ' || p_ability,
        jsonb_build_object('kind', 'commander_level_up', 'commander_id', p_commander_id, 'ability', p_ability, 'level', v_level, 'rank', v_rank),
        v_tick
      );
    end if;
  end if;
end;
$$;

create function public.award_flat_xp(p_ids int[], p_ability text, p_amount float8)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id int;
begin
  if p_ids is null then
    return;
  end if;
  foreach v_id in array p_ids loop
    perform public.award_xp(v_id, p_ability, p_amount);
  end loop;
end;
$$;

create function public.award_combat_xp(p_winner_ids int[], p_winner_troops int, p_loser_troops int, p_open_field boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_amount float8;
begin
  if p_winner_ids is null or p_loser_troops <= 0 then
    return;
  end if;
  v_amount := p_loser_troops * least(1.0, p_loser_troops::float8 / greatest(p_winner_troops, 1));
  perform public.award_flat_xp(p_winner_ids, 'valor', v_amount * public.xp_cfg('valor_per_troop'));
  if p_open_field then
    perform public.award_flat_xp(p_winner_ids, 'tactics', v_amount * public.xp_cfg('tactics_per_troop'));
  end if;
end;
$$;

create function public.side_leader(p_commander_ids int[], p_garrison_commander_id int)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select c.id
  from public.commanders c
  where c.id = any (p_commander_ids)
  order by
    (c.id = p_garrison_commander_id) desc nulls last,
    (select coalesce(sum(ca.level), 0) from public.commander_abilities ca where ca.commander_id = c.id) desc,
    (c.role = 'king') desc,
    c.id
  limit 1;
$$;

create function public.path_length(p_path int[])
returns float8
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(e.length), 0)
  from generate_series(1, coalesce(array_length(p_path, 1), 1) - 1) as i
  join public.territory_edges e
    on e.from_territory_id = least(p_path[i], p_path[i + 1])
   and e.to_territory_id = greatest(p_path[i], p_path[i + 1]);
$$;

create function public.award_production_xp(p_game_id int, p_tick int, p_cycle boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_t record;
  v_cycle_ticks int;
  v_troops float8;
  v_prestige float8;
  v_gold float8;
begin
  select production_cycle_ticks into v_cycle_ticks from public.games where id = p_game_id;

  for v_t in
    select gt.id, gt.owner_player_id, gt.garrison_commander_id, gt.industry_level, gt.gold_level, gt.prestige_level,
           coalesce((select level from public.realm_areas where player_id = gt.owner_player_id and area = 'barracks'), 1) as barracks,
           coalesce((select level from public.realm_areas where player_id = gt.owner_player_id and area = 'mint'), 1) as mint
    from public.game_territories gt
    join public.commanders c on c.id = gt.garrison_commander_id and c.status = 'idle'
    where gt.game_id = p_game_id and gt.owner_player_id is not null
  loop
    v_troops := v_t.industry_level * (v_t.barracks + 4) * (1 + 0.10 * public.territory_ability(v_t.id, 'muster')) / v_cycle_ticks;
    v_prestige := v_t.prestige_level * (1 + 0.10 * public.territory_ability(v_t.id, 'scholar'));
    perform public.award_xp(v_t.garrison_commander_id, 'muster', v_troops * public.xp_cfg('muster_per_troop'));
    perform public.award_xp(v_t.garrison_commander_id, 'scholar', v_prestige * public.xp_cfg('scholar_per_prestige'));
    if p_cycle then
      v_gold := v_t.gold_level * (10 + 2 * v_t.mint) * (1 + 0.10 * public.territory_ability(v_t.id, 'steward'));
      perform public.award_xp(v_t.garrison_commander_id, 'steward', v_gold * public.xp_cfg('steward_per_gold'));
    end if;
  end loop;
end;
$$;

create function public.award_scout_xp(p_game_id int, p_tick int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_c record;
  v_pos jsonb;
  v_x float8;
  v_y float8;
  v_radius float8;
  v_seen boolean;
begin
  for v_c in
    select c.id, c.owner_player_id, c.status, c.current_territory_id,
           (select m.id from public.commander_movements m where m.commander_id = c.id) as movement_id
    from public.commanders c
    where c.game_id = p_game_id and c.status <> 'dead'
  loop
    if v_c.movement_id is not null then
      v_pos := public.movement_position(v_c.movement_id, p_tick);
      v_x := (v_pos ->> 'x')::float8;
      v_y := (v_pos ->> 'y')::float8;
    elsif v_c.current_territory_id is not null then
      select x, y into v_x, v_y from public.game_territories where id = v_c.current_territory_id;
    else
      continue;
    end if;

    v_radius := 45
      + 15 * (select coalesce(sum(level), 0) from public.commander_abilities where commander_id = v_c.id)
      + 30 * public.ability_level(v_c.id, 'scout');

    select exists (
      select 1 from public.game_territories gt
      where gt.game_id = p_game_id
        and gt.owner_player_id is not null
        and not public.is_friendly_territory(v_c.owner_player_id, gt.id)
        and sqrt((gt.x - v_x) ^ 2 + (gt.y - v_y) ^ 2) <= v_radius
    ) or exists (
      select 1
      from public.commander_movements m2
      join public.commanders c2 on c2.id = m2.commander_id
      where m2.game_id = p_game_id
        and m2.commander_id <> v_c.id
        and c2.owner_player_id <> v_c.owner_player_id
        and not public.are_allied(v_c.owner_player_id, c2.owner_player_id)
        and sqrt(
          ((public.movement_position(m2.id, p_tick) ->> 'x')::float8 - v_x) ^ 2
          + ((public.movement_position(m2.id, p_tick) ->> 'y')::float8 - v_y) ^ 2
        ) <= v_radius
    ) into v_seen;

    if v_seen then
      perform public.award_xp(v_c.id, 'scout', public.xp_cfg('scout_per_cycle'));
    end if;
  end loop;
end;
$$;

create or replace function public.advance_movements(p_game_id int, p_tick int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m public.commander_movements%rowtype;
  v_owner int;
  v_n int;
  v_i int;
  v_stop int;
  v_node int;
  v_arrivals int := 0;
  v_contacts int := 0;
begin
  for v_m in
    select * from public.commander_movements
    where game_id = p_game_id and contact_territory_id is null
    order by arrival_tick, id
  loop
    select owner_player_id into v_owner from public.commanders where id = v_m.commander_id;
    v_n := array_length(v_m.path, 1);
    v_stop := null;

    for v_i in 2 .. v_n loop
      exit when v_m.path_arrival_ticks[v_i] > p_tick;
      v_node := v_m.path[v_i];
      if v_i = v_n
         or not public.is_friendly_territory(v_owner, v_node)
         or public.has_hostile_siege(v_owner, v_node) then
        v_stop := v_i;
        exit;
      end if;
    end loop;

    continue when v_stop is null;
    v_node := v_m.path[v_stop];

    if public.is_friendly_territory(v_owner, v_node) and not public.has_hostile_siege(v_owner, v_node) then
      update public.commanders set status = 'idle', current_territory_id = v_node where id = v_m.commander_id;
      delete from public.commander_movements where id = v_m.id;
      perform public.continue_route(v_m.commander_id, v_node);
      v_arrivals := v_arrivals + 1;
    else
      update public.commander_movements
      set path = v_m.path[1:v_stop],
          path_arrival_ticks = v_m.path_arrival_ticks[1:v_stop],
          to_territory_id = v_node,
          arrival_tick = v_m.path_arrival_ticks[v_stop],
          contact_territory_id = v_node
      where id = v_m.id;
      perform public.award_xp(v_m.commander_id, 'pace', public.path_length(v_m.path[1:v_stop]) * public.xp_cfg('pace_per_unit'));
      v_contacts := v_contacts + 1;
    end if;
  end loop;

  return jsonb_build_object('arrivals', v_arrivals, 'contacts', v_contacts);
end;
$$;

create or replace function public.fight_castle(p_game_id int, p_territory_id int, p_player_id int, p_att_ids int[], p_tick int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_t public.game_territories%rowtype;
  v_owner int;
  v_def_ids int[] := '{}';
  v_att_troops int;
  v_def_troops int;
  v_gar int;
  v_att_armory int;
  v_def_armory int;
  v_att_valor int;
  v_def_valor int;
  v_atk int;
  v_def int;
  v_ra int;
  v_rd int;
  v_attacker_wins boolean;
  v_surv int;
  v_alloc int[];
  v_weights int[];
  v_cid int;
  v_i int;
  v_plunder int := 0;
  v_salvage int := 0;
  v_from_siege boolean;
begin
  select * into v_t from public.game_territories where id = p_territory_id for update;
  v_owner := v_t.owner_player_id;

  select coalesce(bool_or(status = 'sieging'), false) into v_from_siege from public.commanders where id = any (p_att_ids);
  select coalesce(sum(troops), 0) into v_att_troops from public.commanders where id = any (p_att_ids);

  if v_owner is not null then
    select coalesce(array_agg(c.id order by c.id), '{}') into v_def_ids
    from public.commanders c
    where c.current_territory_id = p_territory_id
      and c.status = 'idle'
      and (c.owner_player_id = v_owner or public.are_allied(v_owner, c.owner_player_id));
  end if;

  v_gar := v_t.troops;
  select v_gar + coalesce(sum(troops), 0) into v_def_troops from public.commanders where id = any (v_def_ids);

  v_att_armory := public.armory_level(p_player_id);
  v_def_armory := case
    when v_owner is null then 1
    else greatest(
      public.armory_level(v_owner),
      coalesce((select max(public.armory_level(c.owner_player_id)) from public.commanders c where c.id = any (v_def_ids)), 0)
    )
  end;
  v_att_valor := public.side_valor(p_att_ids, null);
  v_def_valor := public.side_valor(v_def_ids, v_t.garrison_commander_id);
  v_atk := greatest(1, v_att_armory + v_att_valor);
  v_def := greatest(1, v_def_armory + v_def_valor + 1);

  if v_def_troops = 0 then
    v_attacker_wins := true;
    v_surv := v_att_troops;
  elsif v_att_troops = 0 then
    v_attacker_wins := false;
    v_surv := v_def_troops;
  else
    v_ra := ceil(v_att_troops::float8 / v_def)::int;
    v_rd := ceil(v_def_troops::float8 / v_atk)::int;
    if v_ra <= v_rd then
      v_attacker_wins := false;
      v_surv := v_def_troops - (v_ra - 1) * v_atk;
    else
      v_attacker_wins := true;
      v_surv := v_att_troops - v_rd * v_def;
    end if;
  end if;

  if v_attacker_wins then
    select array_agg(c.troops order by u.ord) into v_weights
    from unnest(p_att_ids) with ordinality as u(id, ord)
    join public.commanders c on c.id = u.id;
    v_alloc := public.split_survivors(v_surv, v_weights);

    select coalesce(max(public.ability_level(x, 'plunder')), 0) into v_plunder from unnest(p_att_ids) as x;
    v_salvage := floor(10 * v_t.gold_level * (1 + 0.25 * v_plunder))::int;

    perform public.kill_commanders(p_game_id, v_def_ids, p_tick);

    update public.game_territories
    set owner_player_id = p_player_id,
        troops = 0,
        troop_accum = 0,
        starve_accum = 0,
        gold_level = 0,
        garrison_commander_id = null
    where id = p_territory_id;

    perform public.refresh_effective_influence(p_game_id, p_player_id);
    if v_owner is not null then
      perform public.refresh_effective_influence(p_game_id, v_owner);
    end if;

    if v_salvage > 0 then
      update public.game_players set gold = gold + v_salvage where id = p_player_id;
      insert into public.ledger (game_id, player_id, tick, type, amount)
      values (p_game_id, p_player_id, p_tick, 'salvage', v_salvage);
    end if;

    for v_i in 1 .. array_length(p_att_ids, 1) loop
      update public.commanders
      set troops = v_alloc[v_i], status = 'idle', current_territory_id = p_territory_id
      where id = p_att_ids[v_i];
      delete from public.commander_movements where commander_id = p_att_ids[v_i];
    end loop;

    insert into public.game_moments (game_id, tick, type, payload)
    values (
      p_game_id, p_tick, 'castle_captured',
      jsonb_build_object('territory_id', p_territory_id, 'territory', v_t.name, 'from_player_id', v_owner, 'to_player_id', p_player_id)
    );

    perform public.award_combat_xp(p_att_ids, v_att_troops, v_def_troops, false);
    perform public.award_flat_xp(p_att_ids, 'plunder', v_t.tier * public.xp_cfg('plunder_per_tier'));
    if v_from_siege then
      perform public.award_flat_xp(p_att_ids, 'siegecraft', public.xp_cfg('siegecraft_break_bonus'));
    end if;

    foreach v_cid in array p_att_ids loop
      perform public.continue_route(v_cid, p_territory_id);
    end loop;
  else
    perform public.kill_commanders(p_game_id, p_att_ids, p_tick);

    select array_agg(w order by ord) into v_weights
    from (
      select 0 as ord, v_gar as w
      union all
      select u.ord, c.troops
      from unnest(v_def_ids) with ordinality as u(id, ord)
      join public.commanders c on c.id = u.id
    ) parts;
    v_alloc := public.split_survivors(v_surv, v_weights);

    update public.game_territories set troops = v_alloc[1] where id = p_territory_id;
    for v_i in 1 .. coalesce(array_length(v_def_ids, 1), 0) loop
      update public.commanders set troops = v_alloc[v_i + 1] where id = v_def_ids[v_i];
    end loop;

    perform public.award_combat_xp(v_def_ids, v_def_troops, v_att_troops, false);
  end if;

  insert into public.game_events (game_id, tick, type, payload)
  values (
    p_game_id, p_tick, 'battle',
    jsonb_build_object(
      'territory_id', p_territory_id,
      'attacker_player_id', p_player_id,
      'defender_player_id', v_owner,
      'attacker_troops', v_att_troops,
      'defender_troops', v_def_troops,
      'attacker_damage', v_atk,
      'defender_damage', v_def,
      'winner', case when v_attacker_wins then 'attacker' else 'defender' end,
      'survivors', v_surv,
      'salvage', v_salvage
    )
  );

  insert into public.player_inbox (game_id, player_id, type, title, body, tick)
  select p_game_id, pid, 'combat',
         'Battle at ' || v_t.name || ': ' ||
           case when (pid = p_player_id) = v_attacker_wins then 'victory' else 'defeat' end,
         jsonb_build_object(
           'territory_id', p_territory_id,
           'territory', v_t.name,
           'role', case when pid = p_player_id then 'attacker' else 'defender' end,
           'attacker_troops', v_att_troops,
           'defender_troops', v_def_troops,
           'attacker_damage', v_atk,
           'defender_damage', v_def,
           'winner', case when v_attacker_wins then 'attacker' else 'defender' end,
           'survivors', v_surv,
           'captured', v_attacker_wins,
           'salvage', case when pid = p_player_id then v_salvage else 0 end
         ),
         p_tick
  from (select p_player_id as pid union select v_owner where v_owner is not null) as involved;

  return jsonb_build_object(
    'territory_id', p_territory_id,
    'attacker_player_id', p_player_id,
    'defender_player_id', v_owner,
    'winner', case when v_attacker_wins then 'attacker' else 'defender' end,
    'captured', v_attacker_wins,
    'survivors', v_surv,
    'salvage', v_salvage
  );
end;
$$;

create or replace function public.resolve_relief(p_game_id int, p_territory_id int, p_player_id int, p_tick int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_arr int[];
  v_sg int[];
  v_owner int;
  v_name text;
  v_a_troops int;
  v_b_troops int;
  v_a_dmg int;
  v_b_dmg int;
  v_out jsonb;
  v_a_wins boolean;
  v_surv int;
  v_weights int[];
  v_alloc int[];
  v_i int;
  v_cid int;
  v_sg_players int[];
begin
  select array_agg(m.commander_id order by m.id) into v_arr
  from public.commander_movements m
  join public.commanders c on c.id = m.commander_id
  where m.game_id = p_game_id and m.contact_territory_id = p_territory_id and c.owner_player_id = p_player_id;
  if v_arr is null then
    return null;
  end if;

  v_sg := public.hostile_siegers(p_player_id, p_territory_id);
  select owner_player_id, name into v_owner, v_name from public.game_territories where id = p_territory_id;

  if array_length(v_sg, 1) is null then
    foreach v_cid in array v_arr loop
      update public.commanders set status = 'idle', current_territory_id = p_territory_id where id = v_cid;
      delete from public.commander_movements where commander_id = v_cid;
      perform public.continue_route(v_cid, p_territory_id);
    end loop;
    return jsonb_build_object('territory_id', p_territory_id, 'arrived', true);
  end if;

  select coalesce(sum(troops), 0) into v_a_troops from public.commanders where id = any (v_arr);
  select coalesce(sum(troops), 0) into v_b_troops from public.commanders where id = any (v_sg);
  select array_agg(distinct owner_player_id) into v_sg_players from public.commanders where id = any (v_sg);

  v_a_dmg := greatest(1, public.armory_level(p_player_id) + public.side_valor(v_arr, null));
  v_b_dmg := greatest(1, public.side_best_realm(v_sg, 'armory') + public.side_valor(v_sg, null));

  v_out := public.open_field_outcome(
    v_a_troops, v_a_dmg,
    coalesce((select level from public.realm_areas where player_id = p_player_id and area = 'watchtowers'), 1) + public.side_ability(v_arr, null, 'tactics'),
    v_b_troops, v_b_dmg,
    public.side_best_realm(v_sg, 'watchtowers') + public.side_ability(v_sg, null, 'tactics'),
    'b'
  );
  v_a_wins := v_out ->> 'winner' = 'a';
  v_surv := (v_out ->> 'survivors')::int;

  if v_a_wins then
    select array_agg(c.troops order by u.ord) into v_weights
    from unnest(v_arr) with ordinality as u(id, ord) join public.commanders c on c.id = u.id;
    v_alloc := public.split_survivors(v_surv, v_weights);

    perform public.kill_commanders(p_game_id, v_sg, p_tick);
    for v_i in 1 .. array_length(v_arr, 1) loop
      update public.commanders
      set troops = v_alloc[v_i], status = 'idle', current_territory_id = p_territory_id
      where id = v_arr[v_i];
      delete from public.commander_movements where commander_id = v_arr[v_i];
    end loop;

    insert into public.game_moments (game_id, tick, type, payload)
    values (p_game_id, p_tick, 'siege_lifted', jsonb_build_object('territory_id', p_territory_id, 'territory', v_name, 'by', 'relief', 'player_id', p_player_id));

    perform public.award_combat_xp(v_arr, v_a_troops, v_b_troops, true);
    perform public.award_flat_xp(v_arr, 'siegecraft', public.xp_cfg('siegecraft_break_bonus'));

    foreach v_cid in array v_arr loop
      perform public.continue_route(v_cid, p_territory_id);
    end loop;
  else
    select array_agg(c.troops order by u.ord) into v_weights
    from unnest(v_sg) with ordinality as u(id, ord) join public.commanders c on c.id = u.id;
    v_alloc := public.split_survivors(v_surv, v_weights);

    perform public.kill_commanders(p_game_id, v_arr, p_tick);
    for v_i in 1 .. array_length(v_sg, 1) loop
      update public.commanders set troops = v_alloc[v_i] where id = v_sg[v_i];
    end loop;

    perform public.award_combat_xp(v_sg, v_b_troops, v_a_troops, true);
    perform public.award_flat_xp(v_sg, 'siegecraft', public.xp_cfg('siegecraft_break_bonus'));
  end if;

  insert into public.game_events (game_id, tick, type, payload)
  values (
    p_game_id, p_tick, 'relief',
    jsonb_build_object(
      'territory_id', p_territory_id, 'relief_player_id', p_player_id,
      'relief_troops', v_a_troops, 'siege_troops', v_b_troops,
      'relief_damage', v_a_dmg, 'siege_damage', v_b_dmg,
      'winner', case when v_a_wins then 'relief' else 'siege' end, 'survivors', v_surv
    )
  );

  perform public.notify_players(
    p_game_id, p_tick, array[p_player_id, v_owner] || v_sg_players,
    'Relief of ' || v_name || ': ' || case when v_a_wins then 'siege lifted' else 'relief force destroyed' end,
    jsonb_build_object('kind', 'relief', 'territory_id', p_territory_id, 'territory', v_name, 'winner', case when v_a_wins then 'relief' else 'siege' end, 'survivors', v_surv)
  );

  return jsonb_build_object(
    'territory_id', p_territory_id,
    'kind', 'relief',
    'winner', case when v_a_wins then 'relief' else 'siege' end,
    'captured', false,
    'survivors', v_surv
  );
end;
$$;

create or replace function public.sally_out(p_game_id int, p_territory_id int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.game_players;
  v_t public.game_territories%rowtype;
  v_sg int[];
  v_def int[];
  v_tick int;
  v_a_troops int;
  v_b_troops int;
  v_a_dmg int;
  v_b_dmg int;
  v_out jsonb;
  v_a_wins boolean;
  v_surv int;
  v_weights int[];
  v_alloc int[];
  v_i int;
  v_sg_players int[];
begin
  v_player := public.acting_player(p_game_id);

  select * into v_t from public.game_territories where id = p_territory_id and game_id = p_game_id for update;
  if not found or v_t.owner_player_id is distinct from v_player.id then
    raise exception 'you do not own that territory';
  end if;

  v_sg := public.hostile_siegers(v_player.id, p_territory_id);
  if array_length(v_sg, 1) is null then
    raise exception 'that territory is not under siege';
  end if;

  select current_tick into v_tick from public.games where id = p_game_id;

  select coalesce(array_agg(c.id order by c.id), '{}') into v_def
  from public.commanders c
  where c.current_territory_id = p_territory_id
    and c.status = 'idle'
    and (c.owner_player_id = v_player.id or public.are_allied(v_player.id, c.owner_player_id));

  select v_t.troops + coalesce(sum(troops), 0) into v_a_troops from public.commanders where id = any (v_def);
  if v_a_troops = 0 then
    raise exception 'there is nothing to sally with';
  end if;
  select coalesce(sum(troops), 0) into v_b_troops from public.commanders where id = any (v_sg);
  select array_agg(distinct owner_player_id) into v_sg_players from public.commanders where id = any (v_sg);

  v_a_dmg := greatest(1, greatest(public.armory_level(v_player.id), public.side_best_realm(v_def, 'armory')) + public.side_valor(v_def, v_t.garrison_commander_id));
  v_b_dmg := greatest(1, public.side_best_realm(v_sg, 'armory') + public.side_valor(v_sg, null));

  v_out := public.open_field_outcome(
    v_a_troops, v_a_dmg,
    greatest(coalesce((select level from public.realm_areas where player_id = v_player.id and area = 'watchtowers'), 1), public.side_best_realm(v_def, 'watchtowers'))
      + public.side_ability(v_def, v_t.garrison_commander_id, 'tactics'),
    v_b_troops, v_b_dmg,
    public.side_best_realm(v_sg, 'watchtowers') + public.side_ability(v_sg, null, 'tactics'),
    'b'
  );
  v_a_wins := v_out ->> 'winner' = 'a';
  v_surv := (v_out ->> 'survivors')::int;

  if v_a_wins then
    select array_agg(w order by ord) into v_weights
    from (
      select 0 as ord, v_t.troops as w
      union all
      select u.ord, c.troops
      from unnest(v_def) with ordinality as u(id, ord) join public.commanders c on c.id = u.id
    ) parts;
    v_alloc := public.split_survivors(v_surv, v_weights);

    perform public.kill_commanders(p_game_id, v_sg, v_tick);
    update public.game_territories set troops = v_alloc[1], starve_accum = 0 where id = p_territory_id;
    for v_i in 1 .. coalesce(array_length(v_def, 1), 0) loop
      update public.commanders set troops = v_alloc[v_i + 1] where id = v_def[v_i];
    end loop;

    insert into public.game_moments (game_id, tick, type, payload)
    values (p_game_id, v_tick, 'siege_lifted', jsonb_build_object('territory_id', p_territory_id, 'territory', v_t.name, 'by', 'sally', 'player_id', v_player.id));

    perform public.award_combat_xp(v_def, v_a_troops, v_b_troops, true);
    perform public.award_flat_xp(v_def, 'siegecraft', public.xp_cfg('siegecraft_break_bonus'));
  else
    select array_agg(c.troops order by u.ord) into v_weights
    from unnest(v_sg) with ordinality as u(id, ord) join public.commanders c on c.id = u.id;
    v_alloc := public.split_survivors(v_surv, v_weights);

    perform public.kill_commanders(p_game_id, v_def, v_tick);
    update public.game_territories set troops = 0 where id = p_territory_id;
    for v_i in 1 .. array_length(v_sg, 1) loop
      update public.commanders set troops = v_alloc[v_i] where id = v_sg[v_i];
    end loop;

    perform public.award_combat_xp(v_sg, v_b_troops, v_a_troops, true);
    perform public.award_flat_xp(v_sg, 'siegecraft', public.xp_cfg('siegecraft_break_bonus'));
  end if;

  insert into public.game_events (game_id, tick, type, payload)
  values (
    p_game_id, v_tick, 'sally',
    jsonb_build_object(
      'territory_id', p_territory_id, 'player_id', v_player.id,
      'sally_troops', v_a_troops, 'siege_troops', v_b_troops,
      'sally_damage', v_a_dmg, 'siege_damage', v_b_dmg,
      'winner', case when v_a_wins then 'sally' else 'siege' end, 'survivors', v_surv
    )
  );

  perform public.notify_players(
    p_game_id, v_tick, array[v_player.id] || v_sg_players,
    'Sally from ' || v_t.name || ': ' || case when v_a_wins then 'siege broken' else 'sally destroyed' end,
    jsonb_build_object('kind', 'sally', 'territory_id', p_territory_id, 'territory', v_t.name, 'winner', case when v_a_wins then 'sally' else 'siege' end, 'survivors', v_surv)
  );

  return jsonb_build_object(
    'winner', case when v_a_wins then 'sally' else 'siege' end,
    'survivors', v_surv,
    'sally_troops', v_a_troops,
    'siege_troops', v_b_troops
  );
end;
$$;

create or replace function public.resolve_intercepts(p_game_id int, p_tick int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r record;
  v_p0 jsonb;
  v_p1 jsonb;
  v_mid int[] := '{}';
  v_cmd int[] := '{}';
  v_own int[] := '{}';
  v_dep int[] := '{}';
  v_ax float8[] := '{}';
  v_ay float8[] := '{}';
  v_bx float8[] := '{}';
  v_by float8[] := '{}';
  v_dead boolean[];
  v_n int;
  v_i int;
  v_j int;
  v_d0x float8; v_d0y float8; v_dx float8; v_dy float8; v_len2 float8; v_tt float8; v_dist float8;
  v_ta int; v_tb int;
  v_out jsonb;
  v_tie text;
  v_w int;
  v_l int;
  v_events jsonb := '[]'::jsonb;
  v_combats int := 0;
  v_surv int;
begin
  for v_r in
    select m.id as mid, m.commander_id as cid, c.owner_player_id as pid, m.departed_tick as dep
    from public.commander_movements m
    join public.commanders c on c.id = m.commander_id
    where m.game_id = p_game_id and m.contact_territory_id is null and c.troops > 0 and c.status = 'moving'
    order by m.id
  loop
    v_p0 := public.movement_position(v_r.mid, p_tick - 1);
    v_p1 := public.movement_position(v_r.mid, p_tick);
    v_mid := v_mid || v_r.mid;
    v_cmd := v_cmd || v_r.cid;
    v_own := v_own || v_r.pid;
    v_dep := v_dep || v_r.dep;
    v_ax := v_ax || (v_p0 ->> 'x')::float8;
    v_ay := v_ay || (v_p0 ->> 'y')::float8;
    v_bx := v_bx || (v_p1 ->> 'x')::float8;
    v_by := v_by || (v_p1 ->> 'y')::float8;
  end loop;

  v_n := coalesce(array_length(v_mid, 1), 0);
  if v_n < 2 then
    return jsonb_build_object('combats', 0, 'combat_events', '[]'::jsonb);
  end if;
  v_dead := array_fill(false, array[v_n]);

  for v_i in 1 .. v_n - 1 loop
    for v_j in v_i + 1 .. v_n loop
      continue when v_dead[v_i] or v_dead[v_j];
      continue when v_own[v_i] = v_own[v_j] or public.are_allied(v_own[v_i], v_own[v_j]);

      v_d0x := v_ax[v_i] - v_ax[v_j];
      v_d0y := v_ay[v_i] - v_ay[v_j];
      v_dx := (v_bx[v_i] - v_bx[v_j]) - v_d0x;
      v_dy := (v_by[v_i] - v_by[v_j]) - v_d0y;
      v_len2 := v_dx * v_dx + v_dy * v_dy;
      v_tt := case when v_len2 = 0 then 0 else greatest(0, least(1, - (v_d0x * v_dx + v_d0y * v_dy) / v_len2)) end;
      v_dist := sqrt((v_d0x + v_tt * v_dx) ^ 2 + (v_d0y + v_tt * v_dy) ^ 2);
      continue when v_dist > 20.2;

      select troops into v_ta from public.commanders where id = v_cmd[v_i];
      select troops into v_tb from public.commanders where id = v_cmd[v_j];
      continue when v_ta <= 0 or v_tb <= 0;

      v_tie := case when v_dep[v_i] <= v_dep[v_j] then 'a' else 'b' end;
      v_out := public.open_field_outcome(
        v_ta, greatest(1, public.armory_level(v_own[v_i]) + public.side_valor(array[v_cmd[v_i]], null)),
        coalesce((select level from public.realm_areas where player_id = v_own[v_i] and area = 'watchtowers'), 1) + public.side_ability(array[v_cmd[v_i]], null, 'tactics'),
        v_tb, greatest(1, public.armory_level(v_own[v_j]) + public.side_valor(array[v_cmd[v_j]], null)),
        coalesce((select level from public.realm_areas where player_id = v_own[v_j] and area = 'watchtowers'), 1) + public.side_ability(array[v_cmd[v_j]], null, 'tactics'),
        v_tie
      );

      v_w := case when v_out ->> 'winner' = 'a' then v_i else v_j end;
      v_l := case when v_out ->> 'winner' = 'a' then v_j else v_i end;
      v_surv := (v_out ->> 'survivors')::int;

      perform public.kill_commanders(p_game_id, array[v_cmd[v_l]], p_tick);
      update public.commanders set troops = v_surv where id = v_cmd[v_w];
      perform public.award_combat_xp(
        array[v_cmd[v_w]],
        case when v_w = v_i then v_ta else v_tb end,
        case when v_w = v_i then v_tb else v_ta end,
        true
      );
      v_dead[v_l] := true;
      v_combats := v_combats + 1;

      insert into public.game_events (game_id, tick, type, payload)
      values (
        p_game_id, p_tick, 'intercept',
        jsonb_build_object('winner_commander_id', v_cmd[v_w], 'loser_commander_id', v_cmd[v_l], 'survivors', v_surv,
                           'winner_player_id', v_own[v_w], 'loser_player_id', v_own[v_l])
      );
      perform public.notify_players(
        p_game_id, p_tick, array[v_own[v_w]],
        'Intercepted an enemy march: victory',
        jsonb_build_object('kind', 'intercept', 'winner', true, 'survivors', v_surv)
      );
      perform public.notify_players(
        p_game_id, p_tick, array[v_own[v_l]],
        'Intercepted by an enemy march: defeat',
        jsonb_build_object('kind', 'intercept', 'winner', false)
      );
      v_events := v_events || jsonb_build_array(jsonb_build_object('kind', 'intercept', 'winner', 'a', 'captured', false, 'survivors', v_surv));
    end loop;
  end loop;

  return jsonb_build_object('combats', v_combats, 'combat_events', v_events);
end;
$$;

create or replace function public.apply_siege_attrition(p_game_id int, p_tick int, p_cycle boolean)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_t record;
  v_sg int[];
  v_def int[];
  v_rate float8;
  v_loss float8;
  v_whole int;
  v_track text;
  v_count int := 0;
begin
  for v_t in
    select gt.*
    from public.game_territories gt
    where gt.game_id = p_game_id
      and array_length(public.hostile_siegers(gt.owner_player_id, gt.id), 1) is not null
  loop
    v_count := v_count + 1;
    v_sg := public.hostile_siegers(v_t.owner_player_id, v_t.id);

    select coalesce(array_agg(c.id order by c.id), '{}') into v_def
    from public.commanders c
    where v_t.owner_player_id is not null
      and c.current_territory_id = v_t.id
      and c.status = 'idle'
      and (c.owner_player_id = v_t.owner_player_id or public.are_allied(v_t.owner_player_id, c.owner_player_id));

    v_rate := greatest(
      0,
      3 + 1.0 * public.side_ability(v_sg, null, 'siegecraft') - 0.5 * public.side_ability(v_def, v_t.garrison_commander_id, 'siegecraft')
    );
    v_loss := v_t.troops * v_rate / 100.0 + v_t.starve_accum;
    v_whole := least(v_t.troops, floor(v_loss)::int);

    update public.game_territories
    set troops = troops - v_whole,
        starve_accum = case when v_whole >= v_t.troops then 0 else v_loss - v_whole end
    where id = v_t.id;

    if p_cycle then
      perform public.award_xp(public.side_leader(v_sg, null), 'siegecraft', public.xp_cfg('siegecraft_per_cycle'));
      perform public.award_xp(public.side_leader(v_def, v_t.garrison_commander_id), 'siegecraft', public.xp_cfg('siegecraft_per_cycle'));
    end if;

    if p_cycle and v_t.owner_player_id is not null then
      select tr into v_track
      from (values ('treasury', v_t.gold_level), ('recruitment', v_t.industry_level), ('prestige', v_t.prestige_level)) as x(tr, lv)
      where lv > 0
      order by random()
      limit 1;

      if v_track is not null then
        update public.game_territories
        set gold_level = gold_level - case when v_track = 'treasury' then 1 else 0 end,
            industry_level = industry_level - case when v_track = 'recruitment' then 1 else 0 end,
            prestige_level = prestige_level - case when v_track = 'prestige' then 1 else 0 end
        where id = v_t.id;

        perform public.notify_players(
          p_game_id, p_tick, array[v_t.owner_player_id],
          v_t.name || ' suffers under siege',
          jsonb_build_object('kind', 'siege_damage', 'territory_id', v_t.id, 'territory', v_t.name, 'track', v_track)
        );
      end if;
    end if;
  end loop;

  return v_count;
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

revoke execute on function public.xp_cfg(text) from public, anon, authenticated;
revoke execute on function public.award_xp(int, text, float8) from public, anon, authenticated;
revoke execute on function public.award_flat_xp(int[], text, float8) from public, anon, authenticated;
revoke execute on function public.award_combat_xp(int[], int, int, boolean) from public, anon, authenticated;
revoke execute on function public.side_leader(int[], int) from public, anon, authenticated;
revoke execute on function public.path_length(int[]) from public, anon, authenticated;
revoke execute on function public.award_production_xp(int, int, boolean) from public, anon, authenticated;
revoke execute on function public.award_scout_xp(int, int) from public, anon, authenticated;
revoke execute on function public.advance_movements(int, int) from public, anon, authenticated;
revoke execute on function public.fight_castle(int, int, int, int[], int) from public, anon, authenticated;
revoke execute on function public.resolve_relief(int, int, int, int) from public, anon, authenticated;
revoke execute on function public.resolve_intercepts(int, int) from public, anon, authenticated;
revoke execute on function public.apply_siege_attrition(int, int, boolean) from public, anon, authenticated;
revoke execute on function public.resolve_tick_events(int, int) from public, anon, authenticated;

revoke execute on function public.sally_out(int, int) from public, anon;
grant execute on function public.sally_out(int, int) to authenticated;
