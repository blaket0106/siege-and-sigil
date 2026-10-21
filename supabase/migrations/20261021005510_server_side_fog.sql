create function public.fog_movement_pos(p_path int[], p_arrivals int[], p_tf float8)
returns table (x float8, y float8, seg int)
language plpgsql
stable
strict
security definer
set search_path = ''
as $$
declare
  v_n int := array_length(p_path, 1);
  v_i int := 1;
  v_x1 float8; v_y1 float8; v_x2 float8; v_y2 float8;
  v_denom int;
  v_f float8;
begin
  if p_tf >= p_arrivals[v_n] then
    return query select t.x, t.y, v_n from public.game_territories t where t.id = p_path[v_n];
    return;
  end if;

  while v_i < v_n - 1 and p_arrivals[v_i + 1] <= p_tf loop
    v_i := v_i + 1;
  end loop;

  select t.x, t.y into v_x1, v_y1 from public.game_territories t where t.id = p_path[v_i];
  select t.x, t.y into v_x2, v_y2 from public.game_territories t where t.id = p_path[v_i + 1];
  v_denom := p_arrivals[v_i + 1] - p_arrivals[v_i];
  v_f := case when v_denom <= 0 then 1 else least(1, greatest(0, (p_tf - p_arrivals[v_i]) / v_denom)) end;

  return query select v_x1 + (v_x2 - v_x1) * v_f, v_y1 + (v_y2 - v_y1) * v_f, v_i;
end;
$$;

create function public.get_game_view(p_game_id int)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_me int;
  v_g public.games%rowtype;
  v_fog boolean;
  v_interval float8;
  v_tf float8;
  v_out jsonb;
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;

  select id into v_me from public.game_players where game_id = p_game_id and user_id = v_uid;
  if v_me is null then
    raise exception 'you are not in this game';
  end if;

  select * into v_g from public.games where id = p_game_id;
  v_fog := v_g.fog_of_war and v_g.status = 'active';
  v_interval := case v_g.tick_speed when 'slow' then 7200000 when 'normal' then 3600000 when 'fast' then 1800000 when 'quad' then 900000 end;
  v_tf := v_g.current_tick + case
    when v_interval is not null and v_g.status = 'active' and v_g.last_tick_processed_at is not null
      then least(1, greatest(0, extract(epoch from (now() - v_g.last_tick_processed_at)) * 1000 / v_interval))
    else 0
  end;

  with
  friends as (
    select v_me as id
    union
    select case when d.player_a_id = v_me then d.player_b_id else d.player_a_id end
    from public.diplomacy d
    where d.game_id = p_game_id and d.status = 'allied' and v_me in (d.player_a_id, d.player_b_id)
  ),
  wl as (
    select ra.player_id, ra.level from public.realm_areas ra where ra.game_id = p_game_id and ra.area = 'watchtowers'
  ),
  rk as (
    select ca.commander_id,
           sum(ca.level)::int as rank,
           coalesce(max(ca.level) filter (where ca.ability = 'scout'), 0)::int as scout
    from public.commander_abilities ca
    where ca.game_id = p_game_id
    group by ca.commander_id
  ),
  cp as (
    select c.id, c.owner_player_id, c.status, c.current_territory_id,
           coalesce(t.x, mp.x) as x, coalesce(t.y, mp.y) as y
    from public.commanders c
    left join public.game_territories t on t.id = c.current_territory_id
    left join public.commander_movements m on m.commander_id = c.id
    left join lateral public.fog_movement_pos(m.path, m.path_arrival_ticks, v_tf) mp on true
    where c.game_id = p_game_id and c.status <> 'dead'
  ),
  src as (
    select t.x, t.y, (90 + 60 * coalesce(wl.level, 0))::float8 as r
    from public.game_territories t
    join friends f on f.id = t.owner_player_id
    left join wl on wl.player_id = t.owner_player_id
    where t.game_id = p_game_id
    union all
    select cp.x, cp.y, (45 + 15 * coalesce(rk.rank, 0) + 30 * coalesce(rk.scout, 0))::float8
    from cp
    join friends f on f.id = cp.owner_player_id
    left join rk on rk.commander_id = cp.id
    where cp.x is not null
  ),
  vis as (
    select t.id,
           (not v_fog
            or t.owner_player_id in (select id from friends)
            or exists (select 1 from src s where sqrt((t.x - s.x) ^ 2 + (t.y - s.y) ^ 2) <= s.r)) as seen
    from public.game_territories t
    where t.game_id = p_game_id
  ),
  seen_c as (
    select cp.id,
           (not v_fog
            or cp.owner_player_id in (select id from friends)
            or (cp.current_territory_id is not null and exists (select 1 from vis where vis.id = cp.current_territory_id and vis.seen))
            or (cp.current_territory_id is null and cp.x is not null
                and exists (select 1 from src s where sqrt((cp.x - s.x) ^ 2 + (cp.y - s.y) ^ 2) <= s.r))) as seen
    from cp
  )
  select jsonb_build_object(
    'game', (select to_jsonb(g) - 'world_seed' - 'generator_version' from public.games g where g.id = p_game_id),
    'me', v_me,
    'fog_active', v_fog,
    'players', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', p.id, 'game_id', p.game_id, 'user_id', p.user_id, 'faction_slug', p.faction_slug,
        'display_name', p.display_name, 'is_ai', p.is_ai, 'eliminated_at_tick', p.eliminated_at_tick,
        'gold', case when p.id = v_me then p.gold end,
        'capital_territory_id', case when p.id = v_me or not v_fog or coalesce((select vis.seen from vis where vis.id = p.capital_territory_id), false) then p.capital_territory_id end
      ) order by p.id), '[]'::jsonb)
      from public.game_players p where p.game_id = p_game_id
    ),
    'territories', (
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'id', t.id, 'game_id', t.game_id, 'slug', t.slug, 'name', t.name, 'tier', t.tier, 'region', t.region,
          'base_influence', t.base_influence, 'x', t.x, 'y', t.y, 'terrain', t.terrain, 'seen', v.seen
        ) || case when v.seen then jsonb_build_object(
          'owner_player_id', t.owner_player_id, 'troops', t.troops, 'gold_level', t.gold_level,
          'industry_level', t.industry_level, 'prestige_level', t.prestige_level, 'has_road', t.has_road,
          'effective_influence', t.effective_influence, 'garrison_commander_id', t.garrison_commander_id
        ) else '{}'::jsonb end
        order by t.id), '[]'::jsonb)
      from public.game_territories t join vis v on v.id = t.id
      where t.game_id = p_game_id
    ),
    'standings', (
      select coalesce(jsonb_object_agg(q.owner_player_id::text, q.n), '{}'::jsonb)
      from (
        select t.owner_player_id, count(*)::int as n
        from public.game_territories t
        where t.game_id = p_game_id and t.owner_player_id is not null
        group by t.owner_player_id
      ) q
    ),
    'territory_total', (select count(*)::int from public.game_territories t where t.game_id = p_game_id),
    'commanders', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', c.id, 'game_id', c.game_id, 'owner_player_id', c.owner_player_id, 'name', c.name, 'school', c.school,
        'role', c.role, 'troops', c.troops, 'status', c.status, 'current_territory_id', c.current_territory_id,
        'created_tick', c.created_tick, 'coronation_tick', c.coronation_tick
      ) order by c.id), '[]'::jsonb)
      from public.commanders c join seen_c s on s.id = c.id
      where c.game_id = p_game_id and c.status <> 'dead' and s.seen
    ),
    'abilities', (
      select coalesce(jsonb_agg(jsonb_build_object('commander_id', ca.commander_id, 'ability', ca.ability, 'level', ca.level)), '[]'::jsonb)
      from public.commander_abilities ca join seen_c s on s.id = ca.commander_id
      where ca.game_id = p_game_id and s.seen
    ),
    'movements', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', m.id, 'game_id', m.game_id, 'commander_id', m.commander_id, 'from_territory_id', m.from_territory_id,
        'to_territory_id', m.to_territory_id, 'path', m.path, 'path_arrival_ticks', m.path_arrival_ticks,
        'departed_tick', m.departed_tick, 'arrival_tick', m.arrival_tick, 'march_type', m.march_type
      )), '[]'::jsonb)
      from public.commander_movements m join seen_c s on s.id = m.commander_id
      where m.game_id = p_game_id and s.seen
    ),
    'routes', (
      select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
      from public.commander_routes r
      join public.commanders c on c.id = r.commander_id
      where r.game_id = p_game_id and c.owner_player_id = v_me
    ),
    'areas', (
      select coalesce(jsonb_agg(to_jsonb(ra)), '[]'::jsonb)
      from public.realm_areas ra where ra.game_id = p_game_id and ra.player_id = v_me
    ),
    'diplomacy', (
      select coalesce(jsonb_agg(to_jsonb(d)), '[]'::jsonb)
      from public.diplomacy d where d.game_id = p_game_id and v_me in (d.player_a_id, d.player_b_id)
    ),
    'sources', (
      select coalesce(jsonb_agg(jsonb_build_object('x', s.x, 'y', s.y, 'r', s.r)), '[]'::jsonb)
      from src s where v_fog
    )
  ) into v_out;

  return v_out;
end;
$$;

create function public.my_starting_schools(p_game_id int)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select gp.starting_schools from public.game_players gp where gp.game_id = p_game_id and gp.user_id = (select auth.uid());
$$;

create function public.moments_fog_filter()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.type in ('castle_captured', 'siege_started', 'siege_lifted')
     and exists (select 1 from public.games g where g.id = new.game_id and g.fog_of_war) then
    new.visibility := 'private';
    new.involved_player_ids := array(
      select distinct x::int
      from (values
        (new.payload ->> 'from_player_id'), (new.payload ->> 'to_player_id'), (new.payload ->> 'by_player_id'),
        (new.payload ->> 'owner_player_id'), (new.payload ->> 'player_id')
      ) v(x)
      where x is not null
    );
  end if;
  return new;
end;
$$;

create trigger game_moments_fog before insert on public.game_moments
  for each row execute function public.moments_fog_filter();

create function public.pulse_game()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gid int;
  v_key text;
begin
  for v_gid in
    select distinct coalesce(to_jsonb(c) ->> 'game_id', to_jsonb(c) ->> 'id')::int from changed c
  loop
    v_key := 'ss.pulse.' || v_gid;
    if coalesce(current_setting(v_key, true), '') = '' then
      perform set_config(v_key, '1', true);
      perform realtime.send(jsonb_build_object('game_id', v_gid), 'refresh', 'game:' || v_gid, true);
    end if;
  end loop;
  return null;
end;
$$;

create trigger pulse_ins after insert on public.games referencing new table as changed for each statement execute function public.pulse_game();
create trigger pulse_upd after update on public.games referencing new table as changed for each statement execute function public.pulse_game();
create trigger pulse_del after delete on public.games referencing old table as changed for each statement execute function public.pulse_game();
create trigger pulse_ins after insert on public.game_players referencing new table as changed for each statement execute function public.pulse_game();
create trigger pulse_upd after update on public.game_players referencing new table as changed for each statement execute function public.pulse_game();
create trigger pulse_del after delete on public.game_players referencing old table as changed for each statement execute function public.pulse_game();
create trigger pulse_ins after insert on public.game_territories referencing new table as changed for each statement execute function public.pulse_game();
create trigger pulse_upd after update on public.game_territories referencing new table as changed for each statement execute function public.pulse_game();
create trigger pulse_del after delete on public.game_territories referencing old table as changed for each statement execute function public.pulse_game();
create trigger pulse_ins after insert on public.commanders referencing new table as changed for each statement execute function public.pulse_game();
create trigger pulse_upd after update on public.commanders referencing new table as changed for each statement execute function public.pulse_game();
create trigger pulse_del after delete on public.commanders referencing old table as changed for each statement execute function public.pulse_game();
create trigger pulse_ins after insert on public.commander_movements referencing new table as changed for each statement execute function public.pulse_game();
create trigger pulse_upd after update on public.commander_movements referencing new table as changed for each statement execute function public.pulse_game();
create trigger pulse_del after delete on public.commander_movements referencing old table as changed for each statement execute function public.pulse_game();

create policy "game members receive game pulses" on realtime.messages
  for select to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and case
      when (select realtime.topic()) ~ '^game:[0-9]+$'
        then public.is_game_member(split_part((select realtime.topic()), ':', 2)::int)
      else false
    end
  );

alter publication supabase_realtime drop table
  public.games, public.game_players, public.game_territories, public.commanders, public.commander_movements;

revoke select on public.commanders, public.commander_abilities, public.commander_movements, public.commander_routes from anon, authenticated;

revoke select on public.game_territories from anon, authenticated;
grant select (id, game_id, slug, name, tier, region, base_influence, x, y, terrain) on public.game_territories to authenticated;

revoke select on public.game_players from anon, authenticated;
grant select (id, game_id, user_id, faction_slug, display_name, is_ai, eliminated_at_tick, created_at) on public.game_players to authenticated;

revoke select on public.games from anon, authenticated;
grant select (
  id, name, status, created_by, current_tick, last_tick_processed_at, tick_speed, production_cycle_ticks,
  commander_speed_mult, infra_cost_mult, area_cost_mult, victory_pct, fog_of_war, starting_gold, starting_garrison,
  starting_gold_level, starting_industry_level, starting_prestige_level, fill_with_ai, ai_difficulty, winner_player_id,
  turn_timeout_minutes, ticks_per_turn, current_turn_ends_at, max_players, map_style, map_size, map_w, map_h,
  starting_territories, starting_commanders, commander_cost, coronation_ticks, created_at, grace_period_ticks
) on public.games to authenticated;

revoke execute on function public.fog_movement_pos(int[], int[], float8) from public, anon, authenticated;
revoke execute on function public.moments_fog_filter() from public, anon, authenticated;
revoke execute on function public.pulse_game() from public, anon, authenticated;
revoke execute on function public.get_game_view(int) from public, anon;
grant execute on function public.get_game_view(int) to authenticated;
revoke execute on function public.my_starting_schools(int) from public, anon;
grant execute on function public.my_starting_schools(int) to authenticated;
