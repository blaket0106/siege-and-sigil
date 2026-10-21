create or replace function public.get_game_view(p_game_id int)
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
           coalesce(not v_fog
            or t.owner_player_id in (select id from friends)
            or exists (select 1 from src s where sqrt((t.x - s.x) ^ 2 + (t.y - s.y) ^ 2) <= s.r), false) as seen
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
