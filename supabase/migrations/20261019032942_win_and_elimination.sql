create function public.game_standing(p_game_id int)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_pct float8;
  v_total int;
  v_win_at int;
  v_alive int;
  v_leader int;
  v_castles int;
  v_winner int;
  v_reason text;
begin
  select victory_pct into v_pct from public.games where id = p_game_id;
  select count(*) into v_total from public.game_territories where game_id = p_game_id;
  v_win_at := greatest(1, ceil(v_total * v_pct)::int);
  select count(*) into v_alive from public.game_players where game_id = p_game_id and eliminated_at_tick is null;

  select s.id, s.castles into v_leader, v_castles
  from (
    select
      gp.id,
      (select count(*) from public.game_territories gt where gt.owner_player_id = gp.id) as castles,
      coalesce((select sum(gt.troops) from public.game_territories gt where gt.owner_player_id = gp.id), 0)
        + coalesce((select sum(c.troops) from public.commanders c where c.owner_player_id = gp.id and c.status <> 'dead'), 0) as troops
    from public.game_players gp
    where gp.game_id = p_game_id and gp.eliminated_at_tick is null
  ) s
  order by s.castles desc, s.troops desc, s.id
  limit 1;

  if v_alive = 1 then
    v_winner := v_leader;
    v_reason := 'last_standing';
  elsif v_leader is not null and v_castles >= v_win_at then
    v_winner := v_leader;
    v_reason := 'territory';
  end if;

  return jsonb_build_object(
    'total', v_total,
    'win_at', v_win_at,
    'players_alive', v_alive,
    'leader_id', v_leader,
    'castles', coalesce(v_castles, 0),
    'winner', v_winner is not null,
    'winner_id', v_winner,
    'reason', v_reason
  );
end;
$$;

create function public.eliminate_player(p_game_id int, p_player_id int, p_tick int, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ids int[];
  v_faction text;
  v_user uuid;
begin
  update public.game_players
  set eliminated_at_tick = p_tick
  where id = p_player_id and game_id = p_game_id and eliminated_at_tick is null
  returning faction_slug, user_id into v_faction, v_user;
  if not found then
    return;
  end if;

  select coalesce(array_agg(id), '{}') into v_ids
  from public.commanders where owner_player_id = p_player_id and status <> 'dead';
  perform public.kill_commanders(p_game_id, v_ids, p_tick);

  update public.game_territories
  set owner_player_id = null,
      garrison_commander_id = null,
      effective_influence = base_influence
  where owner_player_id = p_player_id;

  insert into public.game_moments (game_id, tick, type, payload)
  values (p_game_id, p_tick, 'player_eliminated', jsonb_build_object('player_id', p_player_id, 'faction', v_faction, 'reason', p_reason));

  if v_user is not null then
    insert into public.player_inbox (game_id, player_id, type, title, body, tick)
    values (p_game_id, p_player_id, 'system', 'You have been eliminated', jsonb_build_object('kind', 'eliminated', 'reason', p_reason), p_tick);
  end if;
end;
$$;

create function public.finish_game(p_game_id int, p_winner_id int, p_reason text, p_tick int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_winner_user uuid;
  v_faction text;
begin
  select user_id, faction_slug into v_winner_user, v_faction from public.game_players where id = p_winner_id;

  update public.games
  set status = 'finished', winner_player_id = p_winner_id, current_turn_ends_at = null
  where id = p_game_id;

  update public.profiles
  set total_games = total_games + 1
  where user_id in (select user_id from public.game_players where game_id = p_game_id and user_id is not null);

  if v_winner_user is not null then
    update public.profiles set total_wins = total_wins + 1 where user_id = v_winner_user;
  end if;

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

create function public.evaluate_game_end(p_game_id int, p_tick int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_p record;
  v_eliminated int[] := '{}';
  v_standing jsonb;
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

revoke execute on function public.game_standing(int) from public, anon, authenticated;
revoke execute on function public.eliminate_player(int, int, int, text) from public, anon, authenticated;
revoke execute on function public.finish_game(int, int, text, int) from public, anon, authenticated;
revoke execute on function public.evaluate_game_end(int, int) from public, anon, authenticated;
revoke execute on function public.resolve_tick_events(int, int) from public, anon, authenticated;
revoke execute on function public.process_game(int) from public, anon, authenticated;

revoke execute on function public.check_win_condition(int) from public, anon;
grant execute on function public.check_win_condition(int) to authenticated;
revoke execute on function public.concede_defeat(int) from public, anon;
grant execute on function public.concede_defeat(int) to authenticated;
