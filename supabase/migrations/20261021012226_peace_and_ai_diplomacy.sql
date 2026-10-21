alter table public.games add column truce_ticks int not null default 48 check (truce_ticks >= 1);
grant select (truce_ticks) on public.games to authenticated;

alter table public.diplomacy add column truce_ends_tick int;
alter table public.diplomacy add column prior_status text;
alter table public.diplomacy drop constraint diplomacy_status_check;
alter table public.diplomacy drop constraint diplomacy_check3;
alter table public.diplomacy add constraint diplomacy_status_check
  check (status in ('neutral', 'proposed', 'allied', 'grace_period', 'war', 'truce', 'peace_proposed'));
alter table public.diplomacy add constraint diplomacy_proposal_check
  check (status not in ('proposed', 'peace_proposed') or proposed_by_player_id is not null);
alter table public.diplomacy add constraint diplomacy_truce_check
  check (status <> 'truce' or truce_ends_tick is not null);

create function public.are_truced(p_a int, p_b int)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.diplomacy d
    where d.status = 'truce'
      and d.player_a_id = least(p_a, p_b)
      and d.player_b_id = greatest(p_a, p_b)
  );
$$;

create function public.castle_count(p_player_id int)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::int from public.game_territories where owner_player_id = p_player_id;
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

create function public.expel_for_truce(p_game_id int, p_a int, p_b int, p_tick int)
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
    select c.id, c.owner_player_id as owner, gt.x, gt.y
    from public.commanders c
    join public.game_territories gt on gt.id = c.current_territory_id
    where c.game_id = p_game_id
      and c.status in ('idle', 'sieging')
      and ((c.owner_player_id = p_a and gt.owner_player_id = p_b) or (c.owner_player_id = p_b and gt.owner_player_id = p_a))
  loop
    select t.id into v_dest
    from public.game_territories t
    where t.game_id = p_game_id and t.owner_player_id = v_c.owner
    order by sqrt((t.x - v_c.x) ^ 2 + (t.y - v_c.y) ^ 2), t.id
    limit 1;

    if v_dest is null then
      perform public.kill_commanders(p_game_id, array[v_c.id], p_tick);
    else
      update public.commanders set status = 'idle', current_territory_id = v_dest where id = v_c.id;
    end if;
  end loop;
end;
$$;

create function public.accept_peace_core(p_game_id int, p_responder int, p_proposer int, p_tick int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_d public.diplomacy%rowtype;
  v_len int;
begin
  select * into v_d
  from public.diplomacy
  where game_id = p_game_id and player_a_id = least(p_responder, p_proposer) and player_b_id = greatest(p_responder, p_proposer)
  for update;
  if not found or v_d.status <> 'peace_proposed' or v_d.proposed_by_player_id is distinct from p_proposer then
    raise exception 'there is no pending peace proposal from that player';
  end if;

  select truce_ticks into v_len from public.games where id = p_game_id;

  update public.diplomacy
  set status = 'truce', truce_ends_tick = p_tick + v_len, proposed_by_player_id = null, prior_status = null,
      broken_by_player_id = null, grace_ends_tick = null, updated_tick = p_tick
  where game_id = p_game_id and player_a_id = v_d.player_a_id and player_b_id = v_d.player_b_id;

  perform public.expel_for_truce(p_game_id, p_responder, p_proposer, p_tick);

  insert into public.game_moments (game_id, tick, type, payload)
  values (p_game_id, p_tick, 'truce_formed', jsonb_build_object('player_a', p_responder, 'player_b', p_proposer, 'ends_tick', p_tick + v_len));

  perform public.notify_diplomacy(
    p_game_id, p_tick, array[p_proposer, p_responder], 'Truce agreed',
    jsonb_build_object('kind', 'truce_formed', 'players', to_jsonb(array[p_proposer, p_responder]), 'ends_tick', p_tick + v_len)
  );
end;
$$;

create function public.decline_peace_core(p_game_id int, p_responder int, p_proposer int, p_tick int)
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
  if not found or v_d.status <> 'peace_proposed' or v_d.proposed_by_player_id is distinct from p_proposer then
    raise exception 'there is no pending peace proposal from that player';
  end if;

  update public.diplomacy
  set status = coalesce(v_d.prior_status, 'neutral'), proposed_by_player_id = null, prior_status = null, updated_tick = p_tick
  where game_id = p_game_id and player_a_id = v_d.player_a_id and player_b_id = v_d.player_b_id;

  perform public.notify_diplomacy(
    p_game_id, p_tick, array[p_proposer], 'Peace declined',
    jsonb_build_object('kind', 'peace_declined', 'by_player_id', p_responder)
  );
end;
$$;

create function public.propose_peace_core(p_game_id int, p_proposer int, p_target int, p_tick int)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_d public.diplomacy%rowtype;
  v_name text;
begin
  select * into v_d
  from public.diplomacy
  where game_id = p_game_id and player_a_id = least(p_proposer, p_target) and player_b_id = greatest(p_proposer, p_target)
  for update;
  if not found then
    raise exception 'no diplomatic relation with that player';
  end if;

  if v_d.status in ('neutral', 'war') then
    update public.diplomacy
    set status = 'peace_proposed', prior_status = v_d.status, proposed_by_player_id = p_proposer, updated_tick = p_tick
    where game_id = p_game_id and player_a_id = v_d.player_a_id and player_b_id = v_d.player_b_id;

    select display_name into v_name from public.game_players where id = p_proposer;
    perform public.notify_diplomacy(
      p_game_id, p_tick, array[p_target], 'Peace proposal from ' || v_name,
      jsonb_build_object('kind', 'peace_proposed', 'from_player_id', p_proposer)
    );
    return 'peace_proposed';
  elsif v_d.status = 'peace_proposed' then
    if v_d.proposed_by_player_id = p_proposer then
      raise exception 'you have already proposed peace';
    end if;
    perform public.accept_peace_core(p_game_id, p_proposer, p_target, p_tick);
    return 'truce';
  elsif v_d.status = 'truce' then
    raise exception 'you already have a truce with that player';
  elsif v_d.status = 'allied' then
    raise exception 'you are allied with that player';
  elsif v_d.status = 'proposed' then
    raise exception 'an alliance proposal is pending with that player';
  else
    raise exception 'that alliance was just broken';
  end if;
end;
$$;

create function public.propose_peace(p_game_id int, p_target_player_id int)
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
  if p_target_player_id = v_player.id then
    raise exception 'you cannot make peace with yourself';
  end if;
  select * into v_target from public.game_players where id = p_target_player_id and game_id = p_game_id;
  if not found then
    raise exception 'player not found in this game';
  end if;
  if v_target.eliminated_at_tick is not null then
    raise exception 'that player has been eliminated';
  end if;

  select current_tick into v_tick from public.games where id = p_game_id;
  return jsonb_build_object('status', public.propose_peace_core(p_game_id, v_player.id, v_target.id, v_tick));
end;
$$;

create function public.accept_peace(p_game_id int, p_target_player_id int)
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
  perform public.accept_peace_core(p_game_id, v_player.id, p_target_player_id, v_tick);
  return jsonb_build_object('status', 'truce');
end;
$$;

create function public.decline_peace(p_game_id int, p_target_player_id int)
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
  perform public.decline_peace_core(p_game_id, v_player.id, p_target_player_id, v_tick);
  return jsonb_build_object('status', 'declined');
end;
$$;

create or replace function public.propose_alliance(p_game_id int, p_target_player_id int)
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
  elsif v_d.status = 'truce' then
    raise exception 'you have a truce with that player until tick %; ask for an alliance once it ends', v_d.truce_ends_tick;
  elsif v_d.status = 'peace_proposed' then
    raise exception 'a peace proposal is pending with that player';
  else
    raise exception 'you are at war with that player';
  end if;
end;
$$;

create function public.break_alliance_core(p_game_id int, p_breaker int, p_target int, p_tick int)
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

create or replace function public.break_alliance(p_game_id int, p_target_player_id int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player public.game_players;
  v_tick int;
  v_war_at int;
begin
  v_player := public.acting_player(p_game_id);
  select current_tick into v_tick from public.games where id = p_game_id;
  v_war_at := public.break_alliance_core(p_game_id, v_player.id, p_target_player_id, v_tick);
  return jsonb_build_object('status', 'grace_period', 'war_at_tick', v_war_at);
end;
$$;

create or replace function public.advance_diplomacy(p_game_id int, p_tick int)
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

  for v_d in
    select * from public.diplomacy
    where game_id = p_game_id and status = 'truce' and truce_ends_tick <= p_tick
    order by player_a_id, player_b_id
  loop
    update public.diplomacy
    set status = 'neutral', truce_ends_tick = null, updated_tick = p_tick
    where game_id = p_game_id and player_a_id = v_d.player_a_id and player_b_id = v_d.player_b_id;

    insert into public.game_moments (game_id, tick, type, payload)
    values (p_game_id, p_tick, 'truce_ended', jsonb_build_object('player_a', v_d.player_a_id, 'player_b', v_d.player_b_id));

    perform public.notify_diplomacy(
      p_game_id, p_tick, array[v_d.player_a_id, v_d.player_b_id], 'Truce ended',
      jsonb_build_object('kind', 'truce_ended', 'players', to_jsonb(array[v_d.player_a_id, v_d.player_b_id]))
    );
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;


create or replace function public.plan_march(p_player_id int, p_commander_id int, p_to_territory_id int)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_c public.commanders%rowtype;
  v_ids int[];
  v_owner int[];
  v_road boolean[];
  v_allies int[];
  v_friendly boolean[];
  v_ea int[] := '{}';
  v_eb int[] := '{}';
  v_ew float8[] := '{}';
  v_er float8[] := '{}';
  v_dist float8[];
  v_prev int[];
  v_done boolean[];
  v_n int;
  v_src int;
  v_dst int;
  v_u int;
  v_best float8;
  v_i int;
  v_k int;
  v_x int;
  v_e record;
  v_a int;
  v_b int;
  v_speed float8;
  v_stables int;
  v_range float8;
  v_rev int[] := '{}';
  v_path_ids int[] := '{}';
  v_offsets int[] := '{}';
  v_cum float8 := 0;
  v_raw float8 := 0;
  v_prev_offset int := 0;
  v_off int;
begin
  select * into v_c from public.commanders where id = p_commander_id;
  if not found or v_c.owner_player_id <> p_player_id or v_c.status = 'dead' then
    raise exception 'commander not found';
  end if;
  if v_c.current_territory_id is null then
    raise exception 'commander is not at a territory';
  end if;

  select array_agg(id order by id), array_agg(owner_player_id order by id), array_agg(has_road order by id)
  into v_ids, v_owner, v_road
  from public.game_territories where game_id = v_c.game_id;
  v_n := array_length(v_ids, 1);

  v_src := array_position(v_ids, v_c.current_territory_id);
  v_dst := array_position(v_ids, p_to_territory_id);
  if v_dst is null then
    raise exception 'unknown destination territory';
  end if;
  if v_src = v_dst then
    raise exception 'commander is already there';
  end if;
  if v_owner[v_dst] is not null and public.are_truced(p_player_id, v_owner[v_dst]) then
    raise exception 'you have a truce with that player until tick %', (
      select d.truce_ends_tick from public.diplomacy d
      where d.game_id = v_c.game_id and d.player_a_id = least(p_player_id, v_owner[v_dst]) and d.player_b_id = greatest(p_player_id, v_owner[v_dst])
    );
  end if;

  select coalesce(array_agg(case when d.player_a_id = p_player_id then d.player_b_id else d.player_a_id end), '{}')
  into v_allies
  from public.diplomacy d
  where d.game_id = v_c.game_id
    and d.status = 'allied'
    and p_player_id in (d.player_a_id, d.player_b_id);

  v_friendly := array_fill(false, array[v_n]);
  for v_i in 1 .. v_n loop
    v_friendly[v_i] := v_owner[v_i] is not null and (v_owner[v_i] = p_player_id or v_owner[v_i] = any (v_allies));
  end loop;

  for v_e in
    select e.from_territory_id as f, e.to_territory_id as t, e.length * e.move_cost_mult as w
    from public.territory_edges e
    where e.game_id = v_c.game_id
  loop
    v_a := array_position(v_ids, v_e.f);
    v_b := array_position(v_ids, v_e.t);
    v_ea := v_ea || v_a;
    v_eb := v_eb || v_b;
    v_ew := v_ew || v_e.w;
    v_er := v_er || case when v_road[v_a] and v_road[v_b] then v_e.w / 3.0 else v_e.w end;
  end loop;

  v_dist := array_fill('Infinity'::float8, array[v_n]);
  v_prev := array_fill(0, array[v_n]);
  v_done := array_fill(false, array[v_n]);
  v_dist[v_src] := 0;

  loop
    v_u := 0;
    v_best := 'Infinity'::float8;
    for v_i in 1 .. v_n loop
      if not v_done[v_i] and v_dist[v_i] < v_best then
        v_best := v_dist[v_i];
        v_u := v_i;
      end if;
    end loop;
    exit when v_u = 0;
    v_done[v_u] := true;
    exit when v_u = v_dst;
    continue when v_u <> v_src and not v_friendly[v_u];

    for v_k in 1 .. coalesce(array_length(v_ea, 1), 0) loop
      if v_ea[v_k] = v_u then
        v_x := v_eb[v_k];
      elsif v_eb[v_k] = v_u then
        v_x := v_ea[v_k];
      else
        continue;
      end if;
      if not v_done[v_x] and v_dist[v_u] + v_er[v_k] < v_dist[v_x] then
        v_dist[v_x] := v_dist[v_u] + v_er[v_k];
        v_prev[v_x] := v_u;
      end if;
    end loop;
  end loop;

  if v_dist[v_dst] = 'Infinity'::float8 then
    raise exception 'no route: the destination is not reachable through friendly territory';
  end if;

  v_x := v_dst;
  while v_x <> 0 loop
    v_rev := v_rev || v_x;
    v_x := v_prev[v_x];
  end loop;

  v_speed := public.march_speed(p_commander_id);

  for v_i in reverse array_length(v_rev, 1) .. 1 loop
    v_x := v_rev[v_i];
    v_path_ids := v_path_ids || v_ids[v_x];
    if v_i < array_length(v_rev, 1) then
      v_a := v_rev[v_i + 1];
      for v_k in 1 .. array_length(v_ea, 1) loop
        if (v_ea[v_k] = v_a and v_eb[v_k] = v_x) or (v_ea[v_k] = v_x and v_eb[v_k] = v_a) then
          v_cum := v_cum + v_er[v_k];
          v_raw := v_raw + v_ew[v_k];
          exit;
        end if;
      end loop;
    end if;
    v_off := greatest(v_prev_offset, ceil(v_cum / v_speed)::int);
    if v_i = 1 then
      v_off := greatest(v_off, 1);
    end if;
    v_offsets := v_offsets || v_off;
    v_prev_offset := v_off;
  end loop;

  select coalesce(level, 0) into v_stables
  from public.realm_areas where player_id = p_player_id and area = 'stables';
  v_range := 90 + 60 * coalesce(v_stables, 0);

  return jsonb_build_object(
    'from_territory_id', v_c.current_territory_id,
    'to_territory_id', p_to_territory_id,
    'path', to_jsonb(v_path_ids),
    'offsets', to_jsonb(v_offsets),
    'travel_ticks', v_offsets[array_length(v_offsets, 1)],
    'raw_length', round(v_raw::numeric, 3),
    'speed', v_speed,
    'range', v_range,
    'hops', array_length(v_path_ids, 1) - 1,
    'in_range', (array_length(v_path_ids, 1) = 2 or v_raw <= v_range)
  );
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

    if not public.is_friendly_territory(v_owner, v_node)
       and public.are_truced(v_owner, (select owner_player_id from public.game_territories where id = v_node)) then
      update public.commanders set status = 'idle', current_territory_id = v_m.path[v_stop - 1] where id = v_m.commander_id;
      delete from public.commander_movements where id = v_m.id;
      update public.commander_routes set status = 'aborted' where commander_id = v_m.commander_id and status = 'active';
      perform public.notify_players(
        p_game_id, p_tick, array[v_owner], 'March cancelled by truce',
        jsonb_build_object('kind', 'truce_march_cancelled', 'territory_id', v_node)
      );
      continue;
    end if;

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


create or replace function public.ai_diplomacy(p_game_id int, p_player_id int, p_difficulty int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tick int;
  v_win_at int;
  v_my int;
  v_theirs int;
  v_d record;
  v_c record;
  v_other int;
  v_chance float8;
  v_pc float8;
  v_betray float8;
  v_allies int;
  v_max_allies int;
  v_pending int;
  v_best int;
  v_best_score float8;
  v_score float8;
  v_dist float8;
  v_enemies int[];
  v_name text;
  v_done boolean;
begin
  select current_tick into v_tick from public.games where id = p_game_id;
  v_win_at := (public.game_standing(p_game_id) ->> 'win_at')::int;
  v_chance := case p_difficulty when 1 then 0.8 when 2 then 0.65 when 3 then 0.5 when 4 then 0.35 else 0.25 end;
  v_my := public.castle_count(p_player_id);

  for v_d in
    select * from public.diplomacy
    where game_id = p_game_id and status = 'proposed'
      and proposed_by_player_id <> p_player_id and p_player_id in (player_a_id, player_b_id)
  loop
    if public.castle_count(v_d.proposed_by_player_id) >= 0.7 * v_win_at or random() >= v_chance then
      perform public.decline_alliance_core(p_game_id, p_player_id, v_d.proposed_by_player_id, v_tick);
    else
      perform public.accept_alliance_core(p_game_id, p_player_id, v_d.proposed_by_player_id, v_tick);
    end if;
  end loop;

  for v_d in
    select * from public.diplomacy
    where game_id = p_game_id and status = 'peace_proposed'
      and proposed_by_player_id <> p_player_id and p_player_id in (player_a_id, player_b_id)
  loop
    v_theirs := public.castle_count(v_d.proposed_by_player_id);
    v_pc := case
      when v_my < v_theirs then 0.9
      when v_my >= 1.5 * v_theirs then 0.15
      else case p_difficulty when 1 then 0.8 when 2 then 0.7 when 3 then 0.55 when 4 then 0.45 else 0.35 end
    end;
    if random() < v_pc then
      perform public.accept_peace_core(p_game_id, p_player_id, v_d.proposed_by_player_id, v_tick);
    else
      perform public.decline_peace_core(p_game_id, p_player_id, v_d.proposed_by_player_id, v_tick);
    end if;
  end loop;

  update public.diplomacy
  set status = case when status = 'proposed' then 'neutral' else coalesce(prior_status, 'neutral') end,
      proposed_by_player_id = null, prior_status = null, updated_tick = v_tick
  where game_id = p_game_id and status in ('proposed', 'peace_proposed')
    and proposed_by_player_id = p_player_id and updated_tick + 24 <= v_tick;

  v_betray := case p_difficulty when 1 then 0.2 when 2 then 0.35 when 3 then 0.5 when 4 then 0.7 else 0.9 end;
  v_done := false;
  for v_d in
    select * from public.diplomacy
    where game_id = p_game_id and status = 'allied' and p_player_id in (player_a_id, player_b_id)
    order by player_a_id, player_b_id
  loop
    v_other := case when v_d.player_a_id = p_player_id then v_d.player_b_id else v_d.player_a_id end;
    if public.castle_count(v_other) >= 0.7 * v_win_at and random() < v_betray then
      perform public.break_alliance_core(p_game_id, p_player_id, v_other, v_tick);
      v_done := true;
      exit;
    end if;
  end loop;

  for v_d in
    select * from public.diplomacy
    where game_id = p_game_id and status = 'war' and p_player_id in (player_a_id, player_b_id)
      and updated_tick + 12 <= v_tick
    order by player_a_id, player_b_id
  loop
    v_other := case when v_d.player_a_id = p_player_id then v_d.player_b_id else v_d.player_a_id end;
    if (select eliminated_at_tick from public.game_players where id = v_other) is null
       and v_my < 0.8 * public.castle_count(v_other) and random() < 0.5 then
      perform public.propose_peace_core(p_game_id, p_player_id, v_other, v_tick);
    end if;
  end loop;

  if v_done then
    return;
  end if;

  select count(*) into v_allies from public.diplomacy
  where game_id = p_game_id and status = 'allied' and p_player_id in (player_a_id, player_b_id);
  select count(*) into v_pending from public.diplomacy
  where game_id = p_game_id and status in ('proposed', 'peace_proposed') and proposed_by_player_id = p_player_id;
  v_max_allies := case when p_difficulty <= 3 then 1 else 2 end;

  if v_allies < v_max_allies and v_pending = 0 and random() < 0.3 then
    select coalesce(array_agg(case when player_a_id = p_player_id then player_b_id else player_a_id end), '{}') into v_enemies
    from public.diplomacy
    where game_id = p_game_id and status = 'war' and p_player_id in (player_a_id, player_b_id);

    v_best := null;
    v_best_score := -1e9;
    for v_c in
      select gp.id
      from public.game_players gp
      join public.diplomacy d on d.game_id = gp.game_id
        and d.player_a_id = least(gp.id, p_player_id) and d.player_b_id = greatest(gp.id, p_player_id)
      where gp.game_id = p_game_id and gp.id <> p_player_id and gp.eliminated_at_tick is null
        and d.status = 'neutral' and d.updated_tick + 12 <= v_tick
        and public.castle_count(gp.id) < 0.7 * v_win_at
    loop
      select min(sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)) into v_dist
      from public.game_territories a
      join public.game_territories b on b.game_id = a.game_id
      where a.game_id = p_game_id and a.owner_player_id = p_player_id and b.owner_player_id = v_c.id;

      v_score := - coalesce(v_dist, 1000) / 150.0
        + case when exists (
            select 1 from public.diplomacy w
            where w.game_id = p_game_id and w.status = 'war' and v_c.id in (w.player_a_id, w.player_b_id)
              and (case when w.player_a_id = v_c.id then w.player_b_id else w.player_a_id end) = any (v_enemies)
          ) then 2 else 0 end
        + random();
      if v_score > v_best_score then
        v_best := v_c.id;
        v_best_score := v_score;
      end if;
    end loop;

    if v_best is not null then
      update public.diplomacy
      set status = 'proposed', proposed_by_player_id = p_player_id, updated_tick = v_tick
      where game_id = p_game_id and player_a_id = least(v_best, p_player_id) and player_b_id = greatest(v_best, p_player_id);

      select display_name into v_name from public.game_players where id = p_player_id;
      perform public.notify_diplomacy(
        p_game_id, v_tick, array[v_best], 'Alliance proposal from ' || v_name,
        jsonb_build_object('kind', 'alliance_proposed', 'from_player_id', p_player_id)
      );
    end if;
  end if;
end;
$$;

revoke execute on function public.are_truced(int, int) from public, anon, authenticated;
revoke execute on function public.castle_count(int) from public, anon, authenticated;
revoke execute on function public.expel_for_truce(int, int, int, int) from public, anon, authenticated;
revoke execute on function public.accept_peace_core(int, int, int, int) from public, anon, authenticated;
revoke execute on function public.decline_peace_core(int, int, int, int) from public, anon, authenticated;
revoke execute on function public.propose_peace_core(int, int, int, int) from public, anon, authenticated;
revoke execute on function public.break_alliance_core(int, int, int, int) from public, anon, authenticated;

revoke execute on function public.propose_peace(int, int) from public, anon;
grant execute on function public.propose_peace(int, int) to authenticated;
revoke execute on function public.accept_peace(int, int) from public, anon;
grant execute on function public.accept_peace(int, int) to authenticated;
revoke execute on function public.decline_peace(int, int) from public, anon;
grant execute on function public.decline_peace(int, int) to authenticated;
