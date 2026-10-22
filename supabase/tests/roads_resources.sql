do $$
declare
  u1 uuid := gen_random_uuid();
  g int;
  p1 int;
  p2 int;
  lay jsonb := $json${"generator_version":3,"map_w":706.323,"map_h":706.323,"seats":[{"seat":0,"capital_idx":0,"territory_idxs":[0,1,2,3]},{"seat":1,"capital_idx":4,"territory_idxs":[4,5,6,7]}],"territories":[{"idx":0,"name":"Oakmarch","slug":"oakmarch","tier":3,"natural_resources":50,"x":407.0583,"y":214.2689,"owner_seat":0,"troops":null,"treasury_level":null,"industry_level":null,"prestige_level":null,"resources":55},{"idx":1,"name":"Birchcliff","slug":"birchcliff","tier":2,"natural_resources":30,"x":418.2272,"y":334.3707,"owner_seat":0,"troops":null,"treasury_level":null,"industry_level":null,"prestige_level":null,"resources":35},{"idx":2,"name":"Millfell","slug":"millfell","tier":1,"natural_resources":12,"x":228.4863,"y":218.7604,"owner_seat":0,"troops":null,"treasury_level":null,"industry_level":null,"prestige_level":null,"resources":17},{"idx":3,"name":"Dunmoor","slug":"dunmoor","tier":1,"natural_resources":12,"x":275.4708,"y":117.8554,"owner_seat":0,"troops":null,"treasury_level":null,"industry_level":null,"prestige_level":null,"resources":17},{"idx":4,"name":"Whitehaven","slug":"whitehaven","tier":3,"natural_resources":50,"x":299.2647,"y":492.0542,"owner_seat":1,"troops":null,"treasury_level":null,"industry_level":null,"prestige_level":null,"resources":55},{"idx":5,"name":"Marhaven","slug":"marhaven","tier":2,"natural_resources":30,"x":288.0958,"y":371.9523,"owner_seat":1,"troops":null,"treasury_level":null,"industry_level":null,"prestige_level":null,"resources":35},{"idx":6,"name":"Fairhold","slug":"fairhold","tier":1,"natural_resources":12,"x":477.8368,"y":487.5626,"owner_seat":1,"troops":null,"treasury_level":null,"industry_level":null,"prestige_level":null,"resources":17},{"idx":7,"name":"Margate","slug":"margate","tier":1,"natural_resources":12,"x":430.8522,"y":588.4676,"owner_seat":1,"troops":null,"treasury_level":null,"industry_level":null,"prestige_level":null,"resources":17},{"idx":8,"name":"Lowwatch","slug":"lowwatch","tier":1,"natural_resources":13,"x":336.6376,"y":275.6185,"owner_seat":null,"troops":10,"treasury_level":0,"industry_level":1,"prestige_level":0,"resources":13},{"idx":9,"name":"Thornhold","slug":"thornhold","tier":3,"natural_resources":46,"x":162.6197,"y":425.5359,"owner_seat":null,"troops":30,"treasury_level":2,"industry_level":1,"prestige_level":0,"resources":46},{"idx":10,"name":"Pikegate","slug":"pikegate","tier":2,"natural_resources":32,"x":281.5832,"y":615.778,"owner_seat":null,"troops":20,"treasury_level":1,"industry_level":1,"prestige_level":0,"resources":32},{"idx":11,"name":"Highfield","slug":"highfield","tier":1,"natural_resources":18,"x":591.4048,"y":254.2126,"owner_seat":null,"troops":10,"treasury_level":0,"industry_level":1,"prestige_level":0,"resources":18}],"edges":[{"a":0,"b":1,"kind":"land","length":120.62,"move_cost_mult":1,"defense_mult":1},{"a":0,"b":2,"kind":"land","length":178.6285,"move_cost_mult":1,"defense_mult":1},{"a":0,"b":3,"kind":"land","length":163.1283,"move_cost_mult":1,"defense_mult":1},{"a":0,"b":4,"kind":"land","length":297.9667,"move_cost_mult":1,"defense_mult":1},{"a":0,"b":5,"kind":"land","length":197.525,"move_cost_mult":1,"defense_mult":1},{"a":0,"b":6,"kind":"land","length":282.3102,"move_cost_mult":1,"defense_mult":1},{"a":0,"b":7,"kind":"land","length":374.9544,"move_cost_mult":1,"defense_mult":1},{"a":0,"b":8,"kind":"land","length":93.3962,"move_cost_mult":1,"defense_mult":1},{"a":0,"b":9,"kind":"land","length":323.0851,"move_cost_mult":1,"defense_mult":1},{"a":0,"b":10,"kind":"land","length":420.6585,"move_cost_mult":1,"defense_mult":1},{"a":0,"b":11,"kind":"land","length":188.6243,"move_cost_mult":1,"defense_mult":1},{"a":1,"b":2,"kind":"land","length":222.1876,"move_cost_mult":1,"defense_mult":1},{"a":1,"b":3,"kind":"land","length":259.342,"move_cost_mult":1,"defense_mult":1},{"a":1,"b":4,"kind":"land","length":197.5251,"move_cost_mult":1,"defense_mult":1},{"a":1,"b":5,"kind":"land","length":135.4495,"move_cost_mult":1,"defense_mult":1},{"a":1,"b":6,"kind":"land","length":164.3808,"move_cost_mult":1,"defense_mult":1},{"a":1,"b":7,"kind":"land","length":254.4103,"move_cost_mult":1,"defense_mult":1},{"a":1,"b":8,"kind":"land","length":100.542,"move_cost_mult":1,"defense_mult":1},{"a":1,"b":9,"kind":"land","length":271.3785,"move_cost_mult":1,"defense_mult":1},{"a":1,"b":10,"kind":"land","length":312.8285,"move_cost_mult":1,"defense_mult":1},{"a":1,"b":11,"kind":"land","length":190.8292,"move_cost_mult":1,"defense_mult":1},{"a":2,"b":3,"kind":"land","length":111.3075,"move_cost_mult":1,"defense_mult":1},{"a":2,"b":4,"kind":"land","length":282.3103,"move_cost_mult":1,"defense_mult":1},{"a":2,"b":5,"kind":"land","length":164.3808,"move_cost_mult":1,"defense_mult":1},{"a":2,"b":6,"kind":"land","length":366.6474,"move_cost_mult":1,"defense_mult":1},{"a":2,"b":7,"kind":"land","length":421.4681,"move_cost_mult":1,"defense_mult":1},{"a":2,"b":8,"kind":"land","length":122.1865,"move_cost_mult":1,"defense_mult":1},{"a":2,"b":9,"kind":"land","length":217.0127,"move_cost_mult":1,"defense_mult":1},{"a":2,"b":10,"kind":"land","length":400.5524,"move_cost_mult":1,"defense_mult":1},{"a":2,"b":11,"kind":"land","length":364.646,"move_cost_mult":1,"defense_mult":1},{"a":3,"b":4,"kind":"land","length":374.9545,"move_cost_mult":1,"defense_mult":1},{"a":3,"b":5,"kind":"land","length":254.4103,"move_cost_mult":1,"defense_mult":1},{"a":3,"b":6,"kind":"land","length":421.4682,"move_cost_mult":1,"defense_mult":1},{"a":3,"b":7,"kind":"land","length":495.5999,"move_cost_mult":1,"defense_mult":1},{"a":3,"b":8,"kind":"land","length":169.2057,"move_cost_mult":1,"defense_mult":1},{"a":3,"b":9,"kind":"land","length":327.7235,"move_cost_mult":1,"defense_mult":1},{"a":3,"b":10,"kind":"land","length":497.9601,"move_cost_mult":1,"defense_mult":1},{"a":3,"b":11,"kind":"land","length":344.104,"move_cost_mult":1,"defense_mult":1},{"a":4,"b":5,"kind":"land","length":120.6201,"move_cost_mult":1,"defense_mult":1},{"a":4,"b":6,"kind":"land","length":178.6286,"move_cost_mult":1,"defense_mult":1},{"a":4,"b":7,"kind":"land","length":163.1282,"move_cost_mult":1,"defense_mult":1},{"a":4,"b":8,"kind":"land","length":219.6387,"move_cost_mult":1,"defense_mult":1},{"a":4,"b":9,"kind":"land","length":151.9755,"move_cost_mult":1,"defense_mult":1},{"a":4,"b":10,"kind":"land","length":124.9809,"move_cost_mult":1,"defense_mult":1},{"a":4,"b":11,"kind":"land","length":376.7154,"move_cost_mult":1,"defense_mult":1},{"a":5,"b":6,"kind":"land","length":222.1877,"move_cost_mult":1,"defense_mult":1},{"a":5,"b":7,"kind":"land","length":259.342,"move_cost_mult":1,"defense_mult":1},{"a":5,"b":8,"kind":"land","length":107.8726,"move_cost_mult":1,"defense_mult":1},{"a":5,"b":9,"kind":"land","length":136.4385,"move_cost_mult":1,"defense_mult":1},{"a":5,"b":10,"kind":"land","length":243.9127,"move_cost_mult":1,"defense_mult":1},{"a":5,"b":11,"kind":"land","length":325.3598,"move_cost_mult":1,"defense_mult":1},{"a":6,"b":7,"kind":"land","length":111.3076,"move_cost_mult":1,"defense_mult":1},{"a":6,"b":8,"kind":"land","length":254.6714,"move_cost_mult":1,"defense_mult":1},{"a":6,"b":9,"kind":"land","length":321.2618,"move_cost_mult":1,"defense_mult":1},{"a":6,"b":10,"kind":"land","length":234.4241,"move_cost_mult":1,"defense_mult":1},{"a":6,"b":11,"kind":"land","length":259.5186,"move_cost_mult":1,"defense_mult":1},{"a":7,"b":8,"kind":"land","length":326.7276,"move_cost_mult":1,"defense_mult":1},{"a":7,"b":9,"kind":"land","length":313.8398,"move_cost_mult":1,"defense_mult":1},{"a":7,"b":10,"kind":"land","length":151.7468,"move_cost_mult":1,"defense_mult":1},{"a":7,"b":11,"kind":"land","length":370.8147,"move_cost_mult":1,"defense_mult":1},{"a":8,"b":9,"kind":"land","length":229.6899,"move_cost_mult":1,"defense_mult":1},{"a":8,"b":10,"kind":"land","length":344.5859,"move_cost_mult":1,"defense_mult":1},{"a":8,"b":11,"kind":"land","length":255.6649,"move_cost_mult":1,"defense_mult":1},{"a":9,"b":10,"kind":"land","length":224.3755,"move_cost_mult":1,"defense_mult":1},{"a":9,"b":11,"kind":"land","length":461.7449,"move_cost_mult":1,"defense_mult":1},{"a":10,"b":11,"kind":"land","length":476.1501,"move_cost_mult":1,"defense_mult":1}],"world_scale":1,"seat_player_ids":[1,-1]}$json$::jsonb;
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
  select floor(30.0 * (select resources from public.game_territories where id = a) * infra_cost_mult)::int + floor(30.0 * (select resources from public.game_territories where id = b) * infra_cost_mult)::int
    into n from public.games where id = g;
  if gold_before - gold_after = n then ok := ok + 1; else bad := bad + 1; res := res || 'road cost is 30 x resources (spent ' || (gold_before - gold_after) || ' expected ' || n || '); '; end if;

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
  if n = 0 then ok := ok + 1; else bad := bad + 1; res := res || 'capture clears the road; '; end if;

  raise exception 'SUITE passed=% failed=% %', ok, bad, res;
end $$;
