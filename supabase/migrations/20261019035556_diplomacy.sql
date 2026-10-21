alter table public.games add column grace_period_ticks int not null default 24 check (grace_period_ticks >= 0);

create function public.mark_war(p_game_id int, p_a int, p_b int, p_tick int, p_how text)
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
  if not found or v_d.status in ('war', 'allied') then
    return;
  end if;

  update public.diplomacy
  set status = 'war', proposed_by_player_id = null, broken_by_player_id = null, grace_ends_tick = null, updated_tick = p_tick
  where game_id = p_game_id and player_a_id = v_d.player_a_id and player_b_id = v_d.player_b_id;

  insert into public.game_moments (game_id, tick, type, payload)
  values (p_game_id, p_tick, 'war_declared', jsonb_build_object('by_player_id', p_a, 'against_player_id', p_b, 'how', p_how));

  perform public.notify_diplomacy(
    p_game_id, p_tick, array[p_a, p_b], 'War declared',
    jsonb_build_object('kind', 'war_declared', 'by_player_id', p_a, 'against_player_id', p_b, 'how', p_how)
  );
end;
$$;

create function public.notify_diplomacy(p_game_id int, p_tick int, p_players int[], p_title text, p_body jsonb)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.player_inbox (game_id, player_id, type, title, body, tick)
  select p_game_id, p, 'diplomacy', p_title, p_body, p_tick
  from (select distinct unnest(p_players) as p) x
  where p is not null;
$$;

create function public.on_hostile_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_a int;
  v_b int;
  v_how text := 'attack';
begin
  if new.type = 'battle' then
    v_a := (new.payload ->> 'attacker_player_id')::int;
    v_b := (new.payload ->> 'defender_player_id')::int;
  elsif new.type = 'intercept' then
    v_a := (new.payload ->> 'winner_player_id')::int;
    v_b := (new.payload ->> 'loser_player_id')::int;
    v_how := 'intercept';
  elsif new.type = 'siege_started' then
    v_a := (new.payload ->> 'player_id')::int;
    select owner_player_id into v_b from public.game_territories where id = (new.payload ->> 'territory_id')::int;
    v_how := 'siege';
  end if;

  perform public.mark_war(new.game_id, v_a, v_b, new.tick, v_how);
  return new;
end;
$$;

create trigger game_events_hostile
  after insert on public.game_events
  for each row
  when (new.type in ('battle', 'intercept', 'siege_started'))
  execute function public.on_hostile_event();

create function public.expel_commanders(p_game_id int, p_from_player int, p_territory_owner int, p_tick int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_c record;
  v_dest int;
begin
  for v_c in
    select c.id, gt.x, gt.y
    from public.commanders c
    join public.game_territories gt on gt.id = c.current_territory_id
    where c.game_id = p_game_id
      and c.owner_player_id = p_from_player
      and c.status = 'idle'
      and gt.owner_player_id = p_territory_owner
  loop
    select t.id into v_dest
    from public.game_territories t
    where t.game_id = p_game_id and t.owner_player_id = p_from_player
    order by sqrt((t.x - v_c.x) ^ 2 + (t.y - v_c.y) ^ 2), t.id
    limit 1;

    if v_dest is null then
      perform public.kill_commanders(p_game_id, array[v_c.id], p_tick);
    else
      update public.commanders set current_territory_id = v_dest where id = v_c.id;
    end if;
  end loop;
end;
$$;

create function public.accept_alliance_core(p_game_id int, p_responder int, p_proposer int, p_tick int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_d public.diplomacy%rowtype;
begin
  select * into v_d
  from public.diplomacy
  where game_id = p_game_id and player_a_id = least(p_responder, p_proposer) and player_b_id = greatest(p_responder, p_proposer)
  for update;
  if not found or v_d.status <> 'proposed' or v_d.proposed_by_player_id is distinct from p_proposer then
    raise exception 'there is no pending proposal from that player';
  end if;

  update public.diplomacy
  set status = 'allied', proposed_by_player_id = null, updated_tick = p_tick
  where game_id = p_game_id and player_a_id = v_d.player_a_id and player_b_id = v_d.player_b_id;

  insert into public.game_moments (game_id, tick, type, payload, visibility, involved_player_ids)
  values (p_game_id, p_tick, 'alliance_formed', jsonb_build_object('player_a', p_responder, 'player_b', p_proposer), 'private', array[p_responder, p_proposer]);

  perform public.notify_diplomacy(
    p_game_id, p_tick, array[p_proposer, p_responder], 'Alliance formed',
    jsonb_build_object('kind', 'alliance_formed', 'players', to_jsonb(array[p_proposer, p_responder]))
  );
end;
$$;

create function public.decline_alliance_core(p_game_id int, p_responder int, p_proposer int, p_tick int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_d public.diplomacy%rowtype;
begin
  select * into v_d
  from public.diplomacy
  where game_id = p_game_id and player_a_id = least(p_responder, p_proposer) and player_b_id = greatest(p_responder, p_proposer)
  for update;
  if not found or v_d.status <> 'proposed' or v_d.proposed_by_player_id is distinct from p_proposer then
    raise exception 'there is no pending proposal from that player';
  end if;

  update public.diplomacy
  set status = 'neutral', proposed_by_player_id = null, updated_tick = p_tick
  where game_id = p_game_id and player_a_id = v_d.player_a_id and player_b_id = v_d.player_b_id;

  perform public.notify_diplomacy(
    p_game_id, p_tick, array[p_proposer], 'Alliance declined',
    jsonb_build_object('kind', 'alliance_declined', 'by_player_id', p_responder)
  );
end;
$$;

create function public.propose_alliance(p_game_id int, p_target_player_id int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.game_players;
  v_target public.game_players%rowtype;
  v_d public.diplomacy%rowtype;
  v_tick int;
begin
  v_player := public.acting_player(p_game_id);

  if p_target_player_id = v_player.id then
    raise exception 'you cannot ally with yourself';
  end if;
  select * into v_target from public.game_players where id = p_target_player_id and game_id = p_game_id;
  if not found then
    raise exception 'player not found in this game';
  end if;
  if v_target.eliminated_at_tick is not null then
    raise exception 'that player has been eliminated';
  end if;

  select current_tick into v_tick from public.games where id = p_game_id;
  select * into v_d
  from public.diplomacy
  where game_id = p_game_id and player_a_id = least(v_player.id, v_target.id) and player_b_id = greatest(v_player.id, v_target.id)
  for update;
  if not found then
    raise exception 'no diplomatic relation with that player';
  end if;

  if v_d.status = 'neutral' then
    update public.diplomacy
    set status = 'proposed', proposed_by_player_id = v_player.id, updated_tick = v_tick
    where game_id = p_game_id and player_a_id = v_d.player_a_id and player_b_id = v_d.player_b_id;

    perform public.notify_diplomacy(
      p_game_id, v_tick, array[v_target.id], 'Alliance proposal from ' || v_player.display_name,
      jsonb_build_object('kind', 'alliance_proposed', 'from_player_id', v_player.id)
    );
    return jsonb_build_object('status', 'proposed');
  elsif v_d.status = 'proposed' then
    if v_d.proposed_by_player_id = v_player.id then
      raise exception 'you have already proposed an alliance';
    end if;
    perform public.accept_alliance_core(p_game_id, v_player.id, v_target.id, v_tick);
    return jsonb_build_object('status', 'allied');
  elsif v_d.status = 'allied' then
    raise exception 'you are already allied';
  elsif v_d.status = 'grace_period' then
    raise exception 'that alliance was just broken';
  else
    raise exception 'you are at war with that player';
  end if;
end;
$$;

create function public.accept_alliance(p_game_id int, p_target_player_id int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.game_players;
  v_tick int;
begin
  v_player := public.acting_player(p_game_id);
  select current_tick into v_tick from public.games where id = p_game_id;
  perform public.accept_alliance_core(p_game_id, v_player.id, p_target_player_id, v_tick);
  return jsonb_build_object('status', 'allied');
end;
$$;

create function public.decline_alliance(p_game_id int, p_target_player_id int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.game_players;
  v_tick int;
begin
  v_player := public.acting_player(p_game_id);
  select current_tick into v_tick from public.games where id = p_game_id;
  perform public.decline_alliance_core(p_game_id, v_player.id, p_target_player_id, v_tick);
  return jsonb_build_object('status', 'neutral');
end;
$$;

create function public.break_alliance(p_game_id int, p_target_player_id int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.game_players;
  v_d public.diplomacy%rowtype;
  v_game public.games%rowtype;
begin
  v_player := public.acting_player(p_game_id);
  select * into v_game from public.games where id = p_game_id;

  select * into v_d
  from public.diplomacy
  where game_id = p_game_id and player_a_id = least(v_player.id, p_target_player_id) and player_b_id = greatest(v_player.id, p_target_player_id)
  for update;
  if not found or v_d.status <> 'allied' then
    raise exception 'you are not allied with that player';
  end if;

  update public.diplomacy
  set status = 'grace_period',
      broken_by_player_id = v_player.id,
      grace_ends_tick = v_game.current_tick + v_game.grace_period_ticks,
      updated_tick = v_game.current_tick
  where game_id = p_game_id and player_a_id = v_d.player_a_id and player_b_id = v_d.player_b_id;

  perform public.expel_commanders(p_game_id, v_player.id, p_target_player_id, v_game.current_tick);
  perform public.expel_commanders(p_game_id, p_target_player_id, v_player.id, v_game.current_tick);

  insert into public.game_moments (game_id, tick, type, payload, visibility, involved_player_ids)
  values (
    p_game_id, v_game.current_tick, 'alliance_broken',
    jsonb_build_object('by_player_id', v_player.id, 'against_player_id', p_target_player_id),
    'private', array[v_player.id, p_target_player_id]
  );

  perform public.notify_diplomacy(
    p_game_id, v_game.current_tick, array[p_target_player_id], v_player.display_name || ' broke the alliance',
    jsonb_build_object('kind', 'alliance_broken', 'by_player_id', v_player.id, 'war_at_tick', v_game.current_tick + v_game.grace_period_ticks)
  );

  return jsonb_build_object('status', 'grace_period', 'war_at_tick', v_game.current_tick + v_game.grace_period_ticks);
end;
$$;

create function public.advance_diplomacy(p_game_id int, p_tick int)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_d record;
  v_count int := 0;
begin
  for v_d in
    select * from public.diplomacy
    where game_id = p_game_id and status = 'grace_period' and grace_ends_tick <= p_tick
    order by player_a_id, player_b_id
  loop
    perform public.mark_war(
      p_game_id,
      v_d.broken_by_player_id,
      case when v_d.broken_by_player_id = v_d.player_a_id then v_d.player_b_id else v_d.player_a_id end,
      p_tick,
      'alliance_broken'
    );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

create function public.ai_diplomacy(p_game_id int, p_player_id int, p_difficulty int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_d record;
  v_tick int;
  v_win_at int;
  v_castles int;
  v_chance float8;
begin
  select current_tick into v_tick from public.games where id = p_game_id;
  v_win_at := (public.game_standing(p_game_id) ->> 'win_at')::int;
  v_chance := case p_difficulty when 1 then 0.8 when 2 then 0.65 when 3 then 0.5 when 4 then 0.35 else 0.25 end;

  for v_d in
    select * from public.diplomacy
    where game_id = p_game_id
      and status = 'proposed'
      and proposed_by_player_id <> p_player_id
      and p_player_id in (player_a_id, player_b_id)
  loop
    select count(*) into v_castles from public.game_territories where owner_player_id = v_d.proposed_by_player_id;
    if v_castles >= 0.7 * v_win_at or random() >= v_chance then
      perform public.decline_alliance_core(p_game_id, p_player_id, v_d.proposed_by_player_id, v_tick);
    else
      perform public.accept_alliance_core(p_game_id, p_player_id, v_d.proposed_by_player_id, v_tick);
    end if;
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
  perform public.ai_commanders(p_game_id, p_player_id, v_difficulty);
  perform public.ai_spend(p_game_id, p_player_id, v_difficulty);
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
  perform public.advance_diplomacy(p_game_id, p_tick);
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

revoke execute on function public.mark_war(int, int, int, int, text) from public, anon, authenticated;
revoke execute on function public.notify_diplomacy(int, int, int[], text, jsonb) from public, anon, authenticated;
revoke execute on function public.on_hostile_event() from public, anon, authenticated;
revoke execute on function public.expel_commanders(int, int, int, int) from public, anon, authenticated;
revoke execute on function public.accept_alliance_core(int, int, int, int) from public, anon, authenticated;
revoke execute on function public.decline_alliance_core(int, int, int, int) from public, anon, authenticated;
revoke execute on function public.advance_diplomacy(int, int) from public, anon, authenticated;
revoke execute on function public.ai_diplomacy(int, int, int) from public, anon, authenticated;
revoke execute on function public.ai_take_turn(int, int) from public, anon, authenticated;
revoke execute on function public.resolve_tick_events(int, int) from public, anon, authenticated;

revoke execute on function public.propose_alliance(int, int) from public, anon;
grant execute on function public.propose_alliance(int, int) to authenticated;
revoke execute on function public.accept_alliance(int, int) from public, anon;
grant execute on function public.accept_alliance(int, int) to authenticated;
revoke execute on function public.decline_alliance(int, int) from public, anon;
grant execute on function public.decline_alliance(int, int) to authenticated;
revoke execute on function public.break_alliance(int, int) from public, anon;
grant execute on function public.break_alliance(int, int) to authenticated;
