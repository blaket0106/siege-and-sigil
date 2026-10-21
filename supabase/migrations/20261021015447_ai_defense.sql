create function public.sally_core(p_game_id int, p_player_id int, p_territory_id int)
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
  select * into v_player from public.game_players where id = p_player_id and game_id = p_game_id;
  if not found or v_player.eliminated_at_tick is not null then
    raise exception 'player not found';
  end if;

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

create or replace function public.sally_out(p_game_id int, p_territory_id int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.game_players;
begin
  v_player := public.acting_player(p_game_id);
  return public.sally_core(p_game_id, v_player.id, p_territory_id);
end;
$$;

create function public.ai_defend(p_game_id int, p_player_id int, p_difficulty int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_t record;
  v_sg int[];
  v_def int[];
  v_a_troops int;
  v_b_troops int;
  v_a_dmg int;
  v_b_dmg int;
  v_res jsonb;
begin
  for v_t in
    select gt.id, gt.troops, gt.garrison_commander_id
    from public.game_territories gt
    where gt.game_id = p_game_id and gt.owner_player_id = p_player_id
    order by gt.tier desc, gt.id
  loop
    v_sg := public.hostile_siegers(p_player_id, v_t.id);
    continue when array_length(v_sg, 1) is null;

    select coalesce(array_agg(c.id order by c.id), '{}') into v_def
    from public.commanders c
    where c.current_territory_id = v_t.id and c.status = 'idle'
      and (c.owner_player_id = p_player_id or public.are_allied(p_player_id, c.owner_player_id));

    select v_t.troops + coalesce(sum(troops), 0) into v_a_troops from public.commanders where id = any (v_def);
    select coalesce(sum(troops), 0) into v_b_troops from public.commanders where id = any (v_sg);
    continue when v_a_troops <= 0;

    v_a_dmg := greatest(1, greatest(public.armory_level(p_player_id), public.side_best_realm(v_def, 'armory')) + public.side_valor(v_def, v_t.garrison_commander_id));
    v_b_dmg := greatest(1, public.side_best_realm(v_sg, 'armory') + public.side_valor(v_sg, null));

    v_res := public.duel(v_b_troops, v_b_dmg, v_a_troops, v_a_dmg);
    continue when (v_res ->> 'first_wins')::boolean;
    continue when p_difficulty <= 2 and random() < 0.5;

    begin
      perform public.sally_core(p_game_id, p_player_id, v_t.id);
    exception when others then
      null;
    end;
  end loop;
end;
$$;

create or replace function public.ai_take_turn(p_game_id int, p_player_id int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_difficulty int;
begin
  select ai_difficulty into v_difficulty from public.games where id = p_game_id;

  perform public.ai_diplomacy(p_game_id, p_player_id, v_difficulty);
  perform public.ai_pick_area(p_player_id);
  perform public.ai_crown(p_game_id, p_player_id);
  perform public.ai_hire(p_game_id, p_player_id, v_difficulty);
  perform public.ai_garrison(p_game_id, p_player_id);
  perform public.ai_defend(p_game_id, p_player_id, v_difficulty);
  perform public.ai_commanders(p_game_id, p_player_id, v_difficulty);
  perform public.ai_spend(p_game_id, p_player_id, v_difficulty);
end;
$$;

revoke execute on function public.sally_core(int, int, int) from public, anon, authenticated;
revoke execute on function public.ai_defend(int, int, int) from public, anon, authenticated;
