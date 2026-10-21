alter table public.game_players add column infamy_delta int not null default 0;

create or replace function public.create_game(p_settings jsonb default '{}'::jsonb)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_allowed text[] := array[
    'name', 'faction_slug', 'max_players', 'tick_speed', 'production_cycle_ticks', 'commander_speed_mult',
    'infra_cost_mult', 'area_cost_mult', 'victory_pct', 'fog_of_war', 'starting_gold', 'starting_garrison',
    'starting_gold_level', 'starting_industry_level', 'starting_prestige_level', 'fill_with_ai', 'ai_difficulty',
    'turn_timeout_minutes', 'ticks_per_turn', 'map_style', 'map_size', 'starting_territories',
    'starting_commanders', 'commander_cost', 'coronation_ticks', 'world_seed', 'truce_ticks', 'grace_period_ticks'
  ];
  v_bad text;
  v_name text;
  v_id int;
  v_game public.games%rowtype;
  v_per_player int;
  v_faction text;
  v_display text;
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;

  select k into v_bad from jsonb_object_keys(coalesce(p_settings, '{}'::jsonb)) as k where k <> all (v_allowed) limit 1;
  if v_bad is not null then
    raise exception 'unknown setting: %', v_bad;
  end if;

  v_name := coalesce(nullif(trim(p_settings ->> 'name'), ''), 'New Game');
  if char_length(v_name) > 60 then
    raise exception 'name must be 60 characters or fewer';
  end if;

  insert into public.games (name, created_by) values (v_name, v_uid) returning id into v_id;

  update public.games g
  set max_players = coalesce((p_settings ->> 'max_players')::int, g.max_players),
      tick_speed = coalesce(p_settings ->> 'tick_speed', g.tick_speed),
      production_cycle_ticks = coalesce((p_settings ->> 'production_cycle_ticks')::int, g.production_cycle_ticks),
      commander_speed_mult = coalesce((p_settings ->> 'commander_speed_mult')::float8, g.commander_speed_mult),
      infra_cost_mult = coalesce((p_settings ->> 'infra_cost_mult')::float8, g.infra_cost_mult),
      area_cost_mult = coalesce((p_settings ->> 'area_cost_mult')::float8, g.area_cost_mult),
      victory_pct = coalesce((p_settings ->> 'victory_pct')::float8, g.victory_pct),
      fog_of_war = coalesce((p_settings ->> 'fog_of_war')::boolean, g.fog_of_war),
      starting_gold = coalesce((p_settings ->> 'starting_gold')::int, g.starting_gold),
      starting_garrison = coalesce((p_settings ->> 'starting_garrison')::int, g.starting_garrison),
      starting_gold_level = coalesce((p_settings ->> 'starting_gold_level')::int, g.starting_gold_level),
      starting_industry_level = coalesce((p_settings ->> 'starting_industry_level')::int, g.starting_industry_level),
      starting_prestige_level = coalesce((p_settings ->> 'starting_prestige_level')::int, g.starting_prestige_level),
      fill_with_ai = coalesce((p_settings ->> 'fill_with_ai')::boolean, g.fill_with_ai),
      ai_difficulty = coalesce((p_settings ->> 'ai_difficulty')::int, g.ai_difficulty),
      turn_timeout_minutes = coalesce((p_settings ->> 'turn_timeout_minutes')::int, g.turn_timeout_minutes),
      ticks_per_turn = coalesce((p_settings ->> 'ticks_per_turn')::int, g.ticks_per_turn),
      map_style = coalesce(p_settings ->> 'map_style', g.map_style),
      map_size = coalesce(p_settings ->> 'map_size', g.map_size),
      starting_territories = coalesce((p_settings ->> 'starting_territories')::int, g.starting_territories),
      starting_commanders = coalesce((p_settings ->> 'starting_commanders')::int, g.starting_commanders),
      commander_cost = coalesce((p_settings ->> 'commander_cost')::int, g.commander_cost),
      coronation_ticks = coalesce((p_settings ->> 'coronation_ticks')::int, g.coronation_ticks),
      truce_ticks = coalesce((p_settings ->> 'truce_ticks')::int, g.truce_ticks),
      grace_period_ticks = coalesce((p_settings ->> 'grace_period_ticks')::int, g.grace_period_ticks),
      world_seed = coalesce((p_settings ->> 'world_seed')::bigint, g.world_seed)
  where g.id = v_id
  returning * into v_game;

  v_per_player := case v_game.map_size when 'compact' then 6 when 'standard' then 9 else 14 end;
  if v_game.starting_territories > v_per_player - 2 then
    raise exception 'starting_territories must leave at least 2 neutral territories per player on a % map', v_game.map_size;
  end if;

  v_faction := p_settings ->> 'faction_slug';
  if v_faction is null then
    select slug into v_faction from public.factions order by random() limit 1;
  elsif not exists (select 1 from public.factions where slug = v_faction) then
    raise exception 'unknown faction: %', v_faction;
  end if;

  select display_name into v_display from public.profiles where user_id = v_uid;

  insert into public.game_players (game_id, user_id, faction_slug, display_name)
  values (v_id, v_uid, v_faction, coalesce(v_display, 'Player'));

  return v_id;
end;
$$;

create or replace function public.award_xp(p_commander_id int, p_ability text, p_amount float8)
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
  v_applied float8;
  v_rep text;
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

  v_applied := p_amount * case when p_ability = any (v_school_abilities) then public.xp_cfg('school_affinity') else 1 end;
  v_xp := v_row.xp + v_applied;
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

  v_rep := nullif(split_part(coalesce(current_setting('ss.battle_report', true), ''), ':', 1), '');
  if v_rep is not null and p_ability in ('valor', 'tactics', 'plunder', 'siegecraft')
     and split_part(current_setting('ss.battle_report', true), ':', 2)::int = (select current_tick from public.games where id = v_c.game_id) then
    update public.battle_reports r
    set report = jsonb_set(
      r.report, '{xp}',
      coalesce(r.report -> 'xp', '[]'::jsonb)
        || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
          'commander_id', p_commander_id, 'ability', p_ability, 'amount', round(v_applied::numeric, 1),
          'level_up', case when v_gains > 0 then v_level end
        ))),
      true
    )
    where r.id = v_rep::int
      and exists (
        select 1 from jsonb_array_elements(r.report -> 'sides') sd, jsonb_array_elements(sd -> 'commanders') cm
        where (cm ->> 'id')::int = p_commander_id
      );
  end if;

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

create or replace function public.record_battle_report(
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
  v_x float8;
  v_y float8;
  v_near text;
  v_loc jsonb;
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

  if p_territory_id is null and p_kind = 'intercept' then
    select avg((pos ->> 'x')::float8), avg((pos ->> 'y')::float8) into v_x, v_y
    from (
      select public.movement_position(m.id, p_tick) as pos
      from public.commander_movements m
      where m.commander_id = any (p_a_ids || p_b_ids)
    ) q;
    if v_x is not null then
      select t.name into v_near
      from public.game_territories t
      where t.game_id = p_game_id
      order by sqrt((t.x - v_x) ^ 2 + (t.y - v_y) ^ 2), t.id
      limit 1;
      v_loc := jsonb_build_object('location', jsonb_build_object('x', round(v_x::numeric, 1), 'y', round(v_y::numeric, 1), 'near', v_near));
    end if;
  end if;

  insert into public.battle_reports (game_id, tick, kind, territory_id, territory_name, involved_player_ids, report)
  values (
    p_game_id, p_tick, p_kind, p_territory_id, v_name, v_players,
    jsonb_build_object(
      'sides', v_sides, 'first', p_first, 'winner', p_winner, 'survivors', p_survivors, 'rounds', v_rounds,
      'rounds_truncated', v_truncated, 'captured', p_captured, 'salvage', p_salvage, 'from_siege', p_from_siege
    ) || coalesce(v_loc, '{}'::jsonb)
  )
  returning id into v_id;

  perform set_config('ss.battle_report', v_id || ':' || p_tick, true);

  return v_id;
end;
$$;

create or replace function public.finish_game(p_game_id int, p_winner_id int, p_reason text, p_tick int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_winner_user uuid;
  v_faction text;
begin
  update public.games
  set status = 'finished', winner_player_id = p_winner_id, current_turn_ends_at = null
  where id = p_game_id and status = 'active';
  if not found then
    return;
  end if;

  select user_id, faction_slug into v_winner_user, v_faction from public.game_players where id = p_winner_id;

  update public.profiles
  set total_games = total_games + 1
  where user_id in (select user_id from public.game_players where game_id = p_game_id and user_id is not null);

  if v_winner_user is not null then
    update public.profiles set total_wins = total_wins + 1 where user_id = v_winner_user;
  end if;

  with res as (
    select gp.user_id, gp.id as pid, gp.infamy_delta as infamy,
           (case when gp.id = p_winner_id then 25 else 0 end
            + case when gp.eliminated_at_tick is null then 5 else 0 end
            + 10 * (select count(*) from public.diplomacy d where d.game_id = p_game_id and d.status = 'allied' and gp.id in (d.player_a_id, d.player_b_id))) as honor
    from public.game_players gp
    where gp.game_id = p_game_id and gp.user_id is not null
  ),
  applied as (
    update public.profiles p
    set honor = p.honor + r.honor, infamy = p.infamy + r.infamy
    from res r
    where p.user_id = r.user_id
    returning r.pid, r.honor, r.infamy
  )
  insert into public.player_inbox (game_id, player_id, type, title, body, tick)
  select p_game_id, a.pid, 'system', 'Reputation', jsonb_build_object('kind', 'reputation', 'honor', a.honor, 'infamy', a.infamy), p_tick
  from applied a
  where a.honor <> 0 or a.infamy <> 0;

  perform public.record_intel_snapshot(p_game_id);

  insert into public.game_moments (game_id, tick, type, payload)
  values (p_game_id, p_tick, 'game_won', jsonb_build_object('player_id', p_winner_id, 'faction', v_faction, 'reason', p_reason));
  insert into public.game_events (game_id, tick, type, payload)
  values (p_game_id, p_tick, 'game_finished', jsonb_build_object('winner_player_id', p_winner_id, 'reason', p_reason));

  insert into public.player_inbox (game_id, player_id, type, title, body, tick)
  select p_game_id, gp.id, 'system',
         case when gp.id = p_winner_id then 'Victory' else 'Defeat' end,
         jsonb_build_object('kind', 'game_over', 'result', case when gp.id = p_winner_id then 'victory' else 'defeat' end,
                            'winner_player_id', p_winner_id, 'reason', p_reason),
         p_tick
  from public.game_players gp
  where gp.game_id = p_game_id and not gp.is_ai;
end;
$$;

create or replace function public.concede_defeat(p_game_id int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text;
  v_tick int;
  v_player public.game_players;
  v_end jsonb;
begin
  select status, current_tick into v_status, v_tick from public.games where id = p_game_id for update;
  if v_status is null then
    raise exception 'game not found';
  end if;
  if v_status <> 'active' then
    raise exception 'game is not active';
  end if;

  v_player := public.acting_player(p_game_id);

  perform public.eliminate_player(p_game_id, v_player.id, v_tick, 'conceded');
  v_end := public.evaluate_game_end(p_game_id, v_tick);

  return jsonb_build_object('conceded', true, 'game_finished', v_end -> 'finished', 'winner_player_id', v_end -> 'winner_player_id');
end;
$$;

create or replace function public.mark_war(p_game_id int, p_a int, p_b int, p_tick int, p_how text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_d public.diplomacy%rowtype;
begin
  if p_a is null or p_b is null or p_a = p_b then
    return;
  end if;

  select * into v_d
  from public.diplomacy
  where game_id = p_game_id and player_a_id = least(p_a, p_b) and player_b_id = greatest(p_a, p_b)
  for update;
  if not found or v_d.status in ('war', 'allied', 'truce') then
    return;
  end if;

  if v_d.status = 'grace_period' and v_d.broken_by_player_id = p_a and p_how <> 'alliance_broken' then
    update public.game_players set infamy_delta = infamy_delta + 10 where id = p_a;
  end if;

  update public.diplomacy
  set status = 'war', proposed_by_player_id = null, broken_by_player_id = null, grace_ends_tick = null,
      truce_ends_tick = null, prior_status = null, updated_tick = p_tick
  where game_id = p_game_id and player_a_id = v_d.player_a_id and player_b_id = v_d.player_b_id;

  insert into public.game_moments (game_id, tick, type, payload)
  values (p_game_id, p_tick, 'war_declared', jsonb_build_object('by_player_id', p_a, 'against_player_id', p_b, 'how', p_how));

  perform public.notify_diplomacy(
    p_game_id, p_tick, array[p_a, p_b], 'War declared',
    jsonb_build_object('kind', 'war_declared', 'by_player_id', p_a, 'against_player_id', p_b, 'how', p_how)
  );
end;
$$;

create or replace function public.break_alliance_core(p_game_id int, p_breaker int, p_target int, p_tick int)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_d public.diplomacy%rowtype;
  v_game public.games%rowtype;
  v_name text;
begin
  select * into v_game from public.games where id = p_game_id;

  select * into v_d
  from public.diplomacy
  where game_id = p_game_id and player_a_id = least(p_breaker, p_target) and player_b_id = greatest(p_breaker, p_target)
  for update;
  if not found or v_d.status <> 'allied' then
    raise exception 'you are not allied with that player';
  end if;

  update public.diplomacy
  set status = 'grace_period',
      broken_by_player_id = p_breaker,
      grace_ends_tick = p_tick + v_game.grace_period_ticks,
      updated_tick = p_tick
  where game_id = p_game_id and player_a_id = v_d.player_a_id and player_b_id = v_d.player_b_id;

  update public.game_players set infamy_delta = infamy_delta + 20 where id = p_breaker;

  perform public.expel_commanders(p_game_id, p_breaker, p_target, p_tick);
  perform public.expel_commanders(p_game_id, p_target, p_breaker, p_tick);

  insert into public.game_moments (game_id, tick, type, payload, visibility, involved_player_ids)
  values (
    p_game_id, p_tick, 'alliance_broken',
    jsonb_build_object('by_player_id', p_breaker, 'against_player_id', p_target),
    'private', array[p_breaker, p_target]
  );

  select display_name into v_name from public.game_players where id = p_breaker;
  perform public.notify_diplomacy(
    p_game_id, p_tick, array[p_target], v_name || ' broke the alliance',
    jsonb_build_object('kind', 'alliance_broken', 'by_player_id', p_breaker, 'war_at_tick', p_tick + v_game.grace_period_ticks)
  );

  return p_tick + v_game.grace_period_ticks;
end;
$$;
