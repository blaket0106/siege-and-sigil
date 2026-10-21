create table public.battle_reports (
  id int generated always as identity primary key,
  game_id int not null references public.games (id) on delete cascade,
  tick int not null,
  kind text not null check (kind in ('assault', 'sally', 'relief', 'intercept')),
  territory_id int,
  territory_name text,
  involved_player_ids int[] not null,
  report jsonb not null,
  created_at timestamptz not null default now()
);

create index battle_reports_game_idx on public.battle_reports (game_id, id desc);

alter table public.battle_reports enable row level security;

create policy "battle reports are readable by the players involved"
  on public.battle_reports for select to authenticated
  using (
    exists (
      select 1 from public.game_players gp
      where gp.game_id = battle_reports.game_id
        and gp.user_id = (select auth.uid())
        and gp.id = any (battle_reports.involved_player_ids)
    )
  );

revoke all on public.battle_reports from anon, authenticated;
grant select on public.battle_reports to authenticated;

create function public.record_battle_report(
  p_game_id int, p_tick int, p_kind text, p_territory_id int,
  p_a_role text, p_a_ids int[], p_a_player int, p_a_garrison int, p_a_troops int, p_a_dmg int,
  p_b_role text, p_b_ids int[], p_b_player int, p_b_garrison int, p_b_troops int, p_b_dmg int,
  p_first int, p_winner int, p_survivors int, p_captured boolean, p_salvage int, p_from_siege boolean
)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
  v_players int[];
  v_sides jsonb;
  v_rounds jsonb := '[]'::jsonb;
  v_ft int;
  v_fd int;
  v_st int;
  v_sd int;
  v_n int := 0;
  v_truncated boolean := false;
  v_id int;
begin
  select name into v_name from public.game_territories where id = p_territory_id;

  v_sides := jsonb_build_array(
    jsonb_build_object(
      'role', p_a_role, 'player_id', p_a_player, 'garrison', p_a_garrison, 'troops', p_a_troops, 'damage', p_a_dmg,
      'died', p_winner <> 0,
      'commanders', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', c.id, 'name', c.name, 'school', c.school, 'role', c.role, 'owner_player_id', c.owner_player_id, 'troops', c.troops,
          'rank', coalesce((select sum(ca.level) from public.commander_abilities ca where ca.commander_id = c.id), 0),
          'abilities', coalesce((select jsonb_object_agg(ca.ability, ca.level) from public.commander_abilities ca where ca.commander_id = c.id and ca.level > 0), '{}'::jsonb)
        ) order by c.id)
        from public.commanders c where c.id = any (p_a_ids)
      ), '[]'::jsonb)
    ),
    jsonb_build_object(
      'role', p_b_role, 'player_id', p_b_player, 'garrison', p_b_garrison, 'troops', p_b_troops, 'damage', p_b_dmg,
      'died', p_winner <> 1,
      'commanders', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', c.id, 'name', c.name, 'school', c.school, 'role', c.role, 'owner_player_id', c.owner_player_id, 'troops', c.troops,
          'rank', coalesce((select sum(ca.level) from public.commander_abilities ca where ca.commander_id = c.id), 0),
          'abilities', coalesce((select jsonb_object_agg(ca.ability, ca.level) from public.commander_abilities ca where ca.commander_id = c.id and ca.level > 0), '{}'::jsonb)
        ) order by c.id)
        from public.commanders c where c.id = any (p_b_ids)
      ), '[]'::jsonb)
    )
  );

  select coalesce(array_agg(distinct x), '{}') into v_players
  from (
    select p_a_player as x
    union all select p_b_player
    union all select c.owner_player_id from public.commanders c where c.id = any (p_a_ids || p_b_ids)
  ) q
  where x is not null;

  if p_first = 0 then
    v_ft := p_a_troops; v_fd := greatest(1, p_a_dmg); v_st := p_b_troops; v_sd := greatest(1, p_b_dmg);
  else
    v_ft := p_b_troops; v_fd := greatest(1, p_b_dmg); v_st := p_a_troops; v_sd := greatest(1, p_a_dmg);
  end if;

  if v_ft > 0 and v_st > 0 then
    loop
      v_st := greatest(0, v_st - v_fd);
      v_rounds := v_rounds || jsonb_build_array(case when p_first = 0 then jsonb_build_array(v_ft, v_st) else jsonb_build_array(v_st, v_ft) end);
      v_n := v_n + 1;
      exit when v_st = 0;
      v_ft := greatest(0, v_ft - v_sd);
      v_rounds := v_rounds || jsonb_build_array(case when p_first = 0 then jsonb_build_array(v_ft, v_st) else jsonb_build_array(v_st, v_ft) end);
      v_n := v_n + 1;
      exit when v_ft = 0;
      if v_n >= 400 then
        v_truncated := true;
        exit;
      end if;
    end loop;
  end if;

  insert into public.battle_reports (game_id, tick, kind, territory_id, territory_name, involved_player_ids, report)
  values (
    p_game_id, p_tick, p_kind, p_territory_id, v_name, v_players,
    jsonb_build_object(
      'sides', v_sides, 'first', p_first, 'winner', p_winner, 'survivors', p_survivors, 'rounds', v_rounds,
      'rounds_truncated', v_truncated, 'captured', p_captured, 'salvage', p_salvage, 'from_siege', p_from_siege
    )
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function public.record_battle_report(int, int, text, int, text, int[], int, int, int, int, text, int[], int, int, int, int, int, int, int, boolean, int, boolean) from public, anon, authenticated;

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
  v_report int;
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

  v_report := public.record_battle_report(
    p_game_id, p_tick, 'assault', p_territory_id,
    'attacker', p_att_ids, p_player_id, 0, v_att_troops, v_atk,
    'defender', v_def_ids, v_owner, v_gar, v_def_troops, v_def,
    1, case when v_attacker_wins then 0 else 1 end, v_surv, v_attacker_wins, 0, v_from_siege
  );

  if v_attacker_wins then
    select array_agg(c.troops order by u.ord) into v_weights
    from unnest(p_att_ids) with ordinality as u(id, ord)
    join public.commanders c on c.id = u.id;
    v_alloc := public.split_survivors(v_surv, v_weights);

    select coalesce(max(public.ability_level(x, 'plunder')), 0) into v_plunder from unnest(p_att_ids) as x;
    v_salvage := floor(10 * v_t.gold_level * (1 + 0.25 * v_plunder))::int;
    update public.battle_reports set report = jsonb_set(report, '{salvage}', to_jsonb(v_salvage)) where id = v_report;

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

  perform public.record_battle_report(
    p_game_id, p_tick, 'relief', p_territory_id,
    'relief', v_arr, p_player_id, 0, v_a_troops, v_a_dmg,
    'siege', v_sg, null, 0, v_b_troops, v_b_dmg,
    case when v_out ->> 'first' = 'a' then 0 else 1 end, case when v_a_wins then 0 else 1 end, v_surv, false, 0, true
  );

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

  perform public.record_battle_report(
    p_game_id, v_tick, 'sally', p_territory_id,
    'sally', v_def, v_player.id, v_t.troops, v_a_troops, v_a_dmg,
    'siege', v_sg, null, 0, v_b_troops, v_b_dmg,
    case when v_out ->> 'first' = 'a' then 0 else 1 end, case when v_a_wins then 0 else 1 end, v_surv, false, 0, true
  );

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
      continue when v_own[v_i] = v_own[v_j] or public.are_allied(v_own[v_i], v_own[v_j]) or public.are_truced(v_own[v_i], v_own[v_j]);

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

      perform public.record_battle_report(
        p_game_id, p_tick, 'intercept', null,
        'marching', array[v_cmd[v_i]], v_own[v_i], 0, v_ta, greatest(1, public.armory_level(v_own[v_i]) + public.side_valor(array[v_cmd[v_i]], null)),
        'marching', array[v_cmd[v_j]], v_own[v_j], 0, v_tb, greatest(1, public.armory_level(v_own[v_j]) + public.side_valor(array[v_cmd[v_j]], null)),
        case when v_out ->> 'first' = 'a' then 0 else 1 end, case when v_w = v_i then 0 else 1 end, v_surv, false, 0, false
      );

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
