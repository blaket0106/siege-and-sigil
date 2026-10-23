do $$
declare
  u1 uuid := gen_random_uuid();
  g int;
  p1 int;
  p2 int;
  lay jsonb := public.test_fixture_layout();
  res text := '';
  ok int := 0;
  bad int := 0;
  n int;
  a int;
  b int;
  c int;
  gold_before int;
  gold_after int;
  mult float8;
  stables int;
  len float8;
  speed float8;
  base_ticks int;
  road_ticks int;
  expect_ticks int;
  arr int;
  dep int;
  tick int;
  plan jsonb;
begin
  insert into auth.users (id, aud, role, email) values (u1, 'authenticated', 'authenticated', u1 || '@t.test');
  insert into public.games (name, created_by, max_players, status, tick_speed, fill_with_ai, ai_difficulty, map_size, starting_territories, free_travel, world_scale)
  values ('suite', u1, 2, 'lobby', 'fast', true, 5, 'compact', 4, true, 1) returning id into g;
  insert into public.game_players (game_id, user_id, faction_slug, display_name) values (g, u1, 'kaldran', 'Human') returning id into p1;
  lay := jsonb_set(lay, '{seat_player_ids}', (select jsonb_agg(case when (e #>> '{}')::int = 1 then to_jsonb(p1) else e end) from jsonb_array_elements(lay -> 'seat_player_ids') e));
  perform public.start_game(g, lay);
  select id into p2 from public.game_players where game_id = g and id <> p1;

  select count(*) into n from public.game_territories where game_id = g and owner_player_id = p1 and (natural_resources, resources) in ((50, 55), (30, 35), (12, 17));
  if n = 4 then ok := ok + 1; else bad := bad + 1; res := res || 'start castles carry 50/30/12/12 resources plus 5 terraform (got ' || n || '); '; end if;

  select count(*) into n from public.game_territories where game_id = g and owner_player_id is null and tier = case when natural_resources <= 20 then 1 when natural_resources <= 40 then 2 else 3 end;
  if n = 4 then ok := ok + 1; else bad := bad + 1; res := res || 'neutral tiers follow resources (got ' || n || '); '; end if;

  select e.from_territory_id, e.to_territory_id into a, b
  from public.territory_edges e
  join public.game_territories t1 on t1.id = e.from_territory_id and t1.owner_player_id = p1
  join public.game_territories t2 on t2.id = e.to_territory_id and t2.owner_player_id = p1
  where e.game_id = g and e.length <= 250
  order by e.length desc limit 1;
  if a is null then
    bad := bad + 1; res := res || 'no owned pair within range; ';
    raise exception 'SUITE passed=% failed=% %', ok, bad, res;
  end if;
  select length, move_cost_mult into len, mult from public.territory_edges where game_id = g and from_territory_id = a and to_territory_id = b;
  select id into c from public.commanders where game_id = g and owner_player_id = p1 and status = 'idle' limit 1;
  update public.commanders set current_territory_id = a where id = c;
  select coalesce(level, 0) into stables from public.realm_areas where player_id = p1 and area = 'stables';
  speed := public.march_speed(c);

  plan := public.plan_march(p1, c, b);
  base_ticks := (plan ->> 'travel_ticks')::int;
  if base_ticks = greatest(1, ceil(len * mult / speed)::int) then ok := ok + 1; else bad := bad + 1; res := res || 'base ticks without roads (got ' || base_ticks || '); '; end if;

  update public.game_players set gold = 1000000 where id = p1;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', u1, 'role', 'authenticated')::text, true);
  select gold into gold_before from public.game_players where id = p1;
  set local role authenticated;
  perform public.build_road(g, a);
  perform public.build_road(g, b);
  reset role;
  select gold into gold_after from public.game_players where id = p1;
  select floor(6.0 * (select resources from public.game_territories where id = a) * infra_cost_mult)::int + floor(6.0 * (select resources from public.game_territories where id = b) * infra_cost_mult)::int
    into n from public.games where id = g;
  if gold_before - gold_after = n then ok := ok + 1; else bad := bad + 1; res := res || 'road cost is 6 x resources (spent ' || (gold_before - gold_after) || ' expected ' || n || '); '; end if;

  plan := public.plan_march(p1, c, b);
  road_ticks := (plan ->> 'travel_ticks')::int;
  expect_ticks := greatest(1, ceil(len * mult / sqrt(3 + stables) / speed)::int);
  if road_ticks = expect_ticks then ok := ok + 1; else bad := bad + 1; res := res || 'road ticks use sqrt(stables+3) (got ' || road_ticks || ' expected ' || expect_ticks || '); '; end if;
  if road_ticks <= base_ticks then ok := ok + 1; else bad := bad + 1; res := res || 'roads are not slower; '; end if;

  set local role authenticated;
  perform public.march_commander(g, c, b, 'assault');
  reset role;
  select arrival_tick, departed_tick into arr, dep from public.commander_movements where commander_id = c;
  if arr - dep = road_ticks then ok := ok + 1; else bad := bad + 1; res := res || 'march launched with road time (got ' || (arr - dep) || '); '; end if;

  set local role authenticated;
  perform public.demolish_road(g, b);
  reset role;
  select arrival_tick into arr from public.commander_movements where commander_id = c;
  if arr - dep = base_ticks then ok := ok + 1; else bad := bad + 1; res := res || 'losing a road mid-march reverts to base time (got ' || (arr - dep) || ' expected ' || base_ticks || '); '; end if;

  update public.game_territories set owner_player_id = p2 where id = a;
  select has_road into n from (select (case when has_road then 1 else 0 end) as has_road from public.game_territories where id = a) s;
  if n = 1 then ok := ok + 1; else bad := bad + 1; res := res || 'capture keeps the road; '; end if;

  raise exception 'SUITE passed=% failed=% %', ok, bad, res;
end $$;
