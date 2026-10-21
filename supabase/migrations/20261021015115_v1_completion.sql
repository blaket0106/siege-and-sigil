alter table public.games add column time_limit_ticks int check (time_limit_ticks is null or time_limit_ticks > 0);
grant select (time_limit_ticks) on public.games to authenticated;

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
    'starting_commanders', 'commander_cost', 'coronation_ticks', 'world_seed', 'truce_ticks', 'grace_period_ticks', 'time_limit_ticks'
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
      time_limit_ticks = coalesce((p_settings ->> 'time_limit_ticks')::int, g.time_limit_ticks),
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

create or replace function public.evaluate_game_end(p_game_id int, p_tick int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_p record;
  v_eliminated int[] := '{}';
  v_standing jsonb;
  v_limit int;
  v_leader int;
begin
  for v_p in
    select gp.id
    from public.game_players gp
    where gp.game_id = p_game_id
      and gp.eliminated_at_tick is null
      and not exists (select 1 from public.game_territories gt where gt.owner_player_id = gp.id)
    order by gp.id
  loop
    perform public.eliminate_player(p_game_id, v_p.id, p_tick, 'lost_all_territories');
    v_eliminated := v_eliminated || v_p.id;
  end loop;

  v_standing := public.game_standing(p_game_id);
  if (v_standing ->> 'winner')::boolean then
    perform public.finish_game(p_game_id, (v_standing ->> 'winner_id')::int, v_standing ->> 'reason', p_tick);
  else
    select g.time_limit_ticks into v_limit from public.games g where g.id = p_game_id and g.status = 'active';
    if v_limit is not null and p_tick >= v_limit then
      select s.id into v_leader
      from (
        select gp.id,
               (select count(*) from public.game_territories gt where gt.owner_player_id = gp.id) as castles,
               coalesce((select sum(gt.troops) from public.game_territories gt where gt.owner_player_id = gp.id), 0)
                 + coalesce((select sum(c.troops) from public.commanders c where c.owner_player_id = gp.id and c.status <> 'dead'), 0) as troops
        from public.game_players gp
        where gp.game_id = p_game_id and gp.eliminated_at_tick is null
      ) s
      order by s.castles desc, s.troops desc, s.id
      limit 1;
      if v_leader is not null then
        perform public.finish_game(p_game_id, v_leader, 'time_limit', p_tick);
        v_standing := jsonb_build_object('winner', true, 'winner_id', v_leader);
      end if;
    end if;
  end if;

  return jsonb_build_object(
    'finished', (v_standing ->> 'winner')::boolean,
    'winner_player_id', v_standing -> 'winner_id',
    'eliminated', to_jsonb(v_eliminated)
  );
end;
$$;

create function public.check_win_condition(p_game_id int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'not signed in';
  end if;
  if not public.is_game_member(p_game_id) then
    raise exception 'you are not in this game';
  end if;
  return public.game_standing(p_game_id) || jsonb_build_object(
    'status', (select status from public.games where id = p_game_id),
    'winner_player_id', (select winner_player_id from public.games where id = p_game_id)
  );
end;
$$;

create function public.concede_defeat(p_game_id int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.game_players;
  v_tick int;
  v_end jsonb;
begin
  v_player := public.acting_player(p_game_id);
  select current_tick into v_tick from public.games where id = p_game_id;

  perform public.eliminate_player(p_game_id, v_player.id, v_tick, 'conceded');
  v_end := public.evaluate_game_end(p_game_id, v_tick);

  return jsonb_build_object('conceded', true, 'game_finished', v_end -> 'finished', 'winner_player_id', v_end -> 'winner_player_id');
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

create or replace function public.process_game(p_game_id int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_game public.games%rowtype;
  v_interval int;
  v_pending int := 0;
  v_n int := 0;
  v_done int := 0;
  v_i int;
  v_res jsonb;
  v_gold int := 0;
  v_troops int := 0;
  v_cycles int := 0;
  v_arrivals int := 0;
  v_contacts int := 0;
  v_combats int := 0;
  v_combat_events jsonb := '[]'::jsonb;
  v_ready boolean;
  v_status text;
  v_winner int;
begin
  select * into v_game from public.games where id = p_game_id for update;
  if not found or v_game.status <> 'active' then
    return jsonb_build_object(
      'pending_ticks', 0, 'ticks_processed', 0, 'gold_added', 0, 'troops_added', 0, 'cycles_fired', 0,
      'arrivals', 0, 'contacts', 0, 'combats', 0, 'combat_events', '[]'::jsonb,
      'game_status', coalesce(v_game.status, 'missing'), 'winner_player_id', v_game.winner_player_id
    );
  end if;

  if v_game.tick_speed = 'turn_based' then
    v_ready := not exists (
      select 1 from public.game_players gp
      where gp.game_id = p_game_id and not gp.is_ai and gp.eliminated_at_tick is null and not gp.turn_submitted
    ) or (v_game.current_turn_ends_at is not null and now() >= v_game.current_turn_ends_at);
    v_pending := case when v_ready then v_game.ticks_per_turn else 0 end;
    v_n := v_pending;
  else
    v_interval := case v_game.tick_speed when 'slow' then 7200 when 'normal' then 3600 when 'fast' then 1800 else 900 end;
    v_pending := greatest(floor(extract(epoch from (now() - v_game.last_tick_processed_at)) / v_interval)::int, 0);
    v_n := least(v_pending, 200);
  end if;

  for v_i in 1 .. v_n loop
    v_res := public.run_tick(p_game_id);
    v_done := v_done + 1;
    v_gold := v_gold + (v_res ->> 'gold_added')::int;
    v_troops := v_troops + (v_res ->> 'troops_added')::int;
    v_arrivals := v_arrivals + (v_res ->> 'arrivals')::int;
    v_contacts := v_contacts + (v_res ->> 'contacts')::int;
    v_combats := v_combats + (v_res ->> 'combats')::int;
    v_combat_events := v_combat_events || (v_res -> 'combat_events');
    if (v_res ->> 'cycle')::boolean then
      v_cycles := v_cycles + 1;
    end if;

    select status, winner_player_id into v_status, v_winner from public.games where id = p_game_id;
    exit when v_status <> 'active';
  end loop;

  if v_done > 0 and v_status = 'active' then
    if v_game.tick_speed = 'turn_based' then
      update public.game_players set turn_submitted = false where game_id = p_game_id;
      update public.games
      set last_tick_processed_at = now(),
          current_turn_ends_at = now() + make_interval(mins => turn_timeout_minutes)
      where id = p_game_id;
    else
      update public.games
      set last_tick_processed_at = last_tick_processed_at + make_interval(secs => v_done * v_interval)
      where id = p_game_id;
    end if;
  end if;

  return jsonb_build_object(
    'pending_ticks', v_pending,
    'ticks_processed', v_done,
    'gold_added', v_gold,
    'troops_added', v_troops,
    'cycles_fired', v_cycles,
    'arrivals', v_arrivals,
    'contacts', v_contacts,
    'combats', v_combats,
    'combat_events', v_combat_events,
    'game_status', coalesce(v_status, 'active'),
    'winner_player_id', v_winner
  );
end;
$$;

create function public.kick_player(p_game_id int, p_player_id int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_game public.games%rowtype;
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;

  select * into v_game from public.games where id = p_game_id for update;
  if not found then
    raise exception 'game not found';
  end if;
  if v_game.created_by <> v_uid then
    raise exception 'only the game creator can remove players';
  end if;
  if v_game.status <> 'lobby' then
    raise exception 'players can only be removed from a game that has not started';
  end if;
  if exists (select 1 from public.game_players where id = p_player_id and game_id = p_game_id and user_id = v_uid) then
    raise exception 'you cannot remove yourself; use leave game';
  end if;

  delete from public.game_players where id = p_player_id and game_id = p_game_id;
  if not found then
    raise exception 'player not found in this game';
  end if;
end;
$$;

create function public.turn_status(p_game_id int)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_game_member(p_game_id) then
    raise exception 'you are not in this game';
  end if;

  return (
    select jsonb_build_object(
      'turn_based', g.tick_speed = 'turn_based',
      'ends_at', g.current_turn_ends_at,
      'submitted', coalesce((select jsonb_agg(gp.id order by gp.id) from public.game_players gp where gp.game_id = g.id and gp.turn_submitted), '[]'::jsonb),
      'waiting', coalesce((select jsonb_agg(gp.id order by gp.id) from public.game_players gp where gp.game_id = g.id and not gp.is_ai and gp.eliminated_at_tick is null and not gp.turn_submitted), '[]'::jsonb)
    )
    from public.games g where g.id = p_game_id
  );
end;
$$;

create function public.cleanup_abandoned_lobbies()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count int;
begin
  with gone as (
    delete from public.games where status = 'lobby' and created_at < now() - interval '7 days' returning id
  )
  select count(*) into v_count from gone;
  return v_count;
end;
$$;

revoke execute on function public.kick_player(int, int) from public, anon;
grant execute on function public.kick_player(int, int) to authenticated;
revoke execute on function public.turn_status(int) from public, anon;
grant execute on function public.turn_status(int) to authenticated;
revoke execute on function public.cleanup_abandoned_lobbies() from public, anon, authenticated;

select cron.schedule('cleanup-abandoned-lobbies', '17 3 * * *', $job$select public.cleanup_abandoned_lobbies()$job$);
