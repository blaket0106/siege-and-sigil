do $$
declare
  u1 uuid := gen_random_uuid();
  u2 uuid := gen_random_uuid();
  g int; p1 int; p2 int; p3 int; oid int; n int; res text := ''; ok int := 0; bad int := 0; st text; tk int;
  lay jsonb := $json${"generator_version":1,"map_w":949.186,"map_h":949.186,"seats":[{"seat":0,"capital_idx":0,"territory_idxs":[0,1,2]},{"seat":1,"capital_idx":6,"territory_idxs":[6,7,8]},{"seat":2,"capital_idx":12,"territory_idxs":[12,13,14]},{"seat":3,"capital_idx":18,"territory_idxs":[18,19,20]}],"territories":[{"idx":0,"name":"Highmoor","slug":"highmoor","tier":3,"natural_resources":6,"x":345.9667,"y":653.5907,"owner_seat":0,"troops":null,"treasury_level":null,"industry_level":null,"prestige_level":null,"resources":11},{"idx":1,"name":"Ashwatch","slug":"ashwatch","tier":1,"natural_resources":2,"x":438.6696,"y":726.2898,"owner_seat":0,"troops":null,"treasury_level":null,"industry_level":null,"prestige_level":null,"resources":7},{"idx":2,"name":"Westhaven","slug":"westhaven","tier":1,"natural_resources":2,"x":353.2744,"y":516.8905,"owner_seat":0,"troops":null,"treasury_level":null,"industry_level":null,"prestige_level":null,"resources":7},{"idx":3,"name":"Westfell","slug":"westfell","tier":1,"natural_resources":2,"x":153.8541,"y":610.927,"owner_seat":null,"troops":10,"treasury_level":0,"industry_level":1,"prestige_level":0,"resources":2},{"idx":4,"name":"Graybarrow","slug":"graybarrow","tier":1,"natural_resources":2,"x":441.0372,"y":866.7519,"owner_seat":null,"troops":10,"treasury_level":0,"industry_level":1,"prestige_level":0,"resources":2},{"idx":5,"name":"Highmarch","slug":"highmarch","tier":2,"natural_resources":4,"x":282.8935,"y":760.1532,"owner_seat":null,"troops":20,"treasury_level":1,"industry_level":1,"prestige_level":0,"resources":4},{"idx":6,"name":"Elmfell","slug":"elmfell","tier":3,"natural_resources":6,"x":295.5953,"y":345.9667,"owner_seat":1,"troops":null,"treasury_level":null,"industry_level":null,"prestige_level":null,"resources":11},{"idx":7,"name":"Whitebridge","slug":"whitebridge","tier":1,"natural_resources":2,"x":222.8962,"y":438.6696,"owner_seat":1,"troops":null,"treasury_level":null,"industry_level":null,"prestige_level":null,"resources":7},{"idx":8,"name":"Fencrest","slug":"fencrest","tier":1,"natural_resources":2,"x":432.2954,"y":353.2744,"owner_seat":1,"troops":null,"treasury_level":null,"industry_level":null,"prestige_level":null,"resources":7},{"idx":9,"name":"Rookfell","slug":"rookfell","tier":1,"natural_resources":2,"x":338.259,"y":153.8541,"owner_seat":null,"troops":10,"treasury_level":0,"industry_level":1,"prestige_level":0,"resources":2},{"idx":10,"name":"Stonedale","slug":"stonedale","tier":1,"natural_resources":2,"x":82.4341,"y":441.0372,"owner_seat":null,"troops":10,"treasury_level":0,"industry_level":1,"prestige_level":0,"resources":2},{"idx":11,"name":"Westford","slug":"westford","tier":2,"natural_resources":4,"x":189.0328,"y":282.8935,"owner_seat":null,"troops":20,"treasury_level":1,"industry_level":1,"prestige_level":0,"resources":4},{"idx":12,"name":"Redkeep","slug":"redkeep","tier":3,"natural_resources":6,"x":603.2192,"y":295.5953,"owner_seat":2,"troops":null,"treasury_level":null,"industry_level":null,"prestige_level":null,"resources":11},{"idx":13,"name":"Grayhollow","slug":"grayhollow","tier":1,"natural_resources":2,"x":510.5164,"y":222.8962,"owner_seat":2,"troops":null,"treasury_level":null,"industry_level":null,"prestige_level":null,"resources":7},{"idx":14,"name":"Millmarch","slug":"millmarch","tier":1,"natural_resources":2,"x":595.9116,"y":432.2954,"owner_seat":2,"troops":null,"treasury_level":null,"industry_level":null,"prestige_level":null,"resources":7},{"idx":15,"name":"Southgate","slug":"southgate","tier":1,"natural_resources":2,"x":795.3319,"y":338.259,"owner_seat":null,"troops":10,"treasury_level":0,"industry_level":1,"prestige_level":0,"resources":2},{"idx":16,"name":"Graycliff","slug":"graycliff","tier":1,"natural_resources":2,"x":508.1488,"y":82.4341,"owner_seat":null,"troops":10,"treasury_level":0,"industry_level":1,"prestige_level":0,"resources":2},{"idx":17,"name":"Fenhollow","slug":"fenhollow","tier":2,"natural_resources":4,"x":666.2924,"y":189.0328,"owner_seat":null,"troops":20,"treasury_level":1,"industry_level":1,"prestige_level":0,"resources":4},{"idx":18,"name":"Thorncrest","slug":"thorncrest","tier":3,"natural_resources":6,"x":653.5907,"y":603.2192,"owner_seat":3,"troops":null,"treasury_level":null,"industry_level":null,"prestige_level":null,"resources":11},{"idx":19,"name":"Pikefell","slug":"pikefell","tier":1,"natural_resources":2,"x":726.2898,"y":510.5164,"owner_seat":3,"troops":null,"treasury_level":null,"industry_level":null,"prestige_level":null,"resources":7},{"idx":20,"name":"Thornwick","slug":"thornwick","tier":1,"natural_resources":2,"x":516.8905,"y":595.9116,"owner_seat":3,"troops":null,"treasury_level":null,"industry_level":null,"prestige_level":null,"resources":7},{"idx":21,"name":"Pikehold","slug":"pikehold","tier":1,"natural_resources":2,"x":610.927,"y":795.3319,"owner_seat":null,"troops":10,"treasury_level":0,"industry_level":1,"prestige_level":0,"resources":2},{"idx":22,"name":"Fairfield","slug":"fairfield","tier":1,"natural_resources":2,"x":866.7519,"y":508.1488,"owner_seat":null,"troops":10,"treasury_level":0,"industry_level":1,"prestige_level":0,"resources":2},{"idx":23,"name":"Redford","slug":"redford","tier":2,"natural_resources":4,"x":760.1532,"y":666.2924,"owner_seat":null,"troops":20,"treasury_level":1,"industry_level":1,"prestige_level":0,"resources":4}],"edges":[{"a":0,"b":1,"kind":"land","length":117.8091,"move_cost_mult":1,"defense_mult":1},{"a":0,"b":2,"kind":"land","length":136.8953,"move_cost_mult":1,"defense_mult":1},{"a":0,"b":3,"kind":"land","length":196.7929,"move_cost_mult":1,"defense_mult":1},{"a":0,"b":5,"kind":"land","length":123.8297,"move_cost_mult":1,"defense_mult":1},{"a":0,"b":20,"kind":"land","length":180.3935,"move_cost_mult":1,"defense_mult":1},{"a":1,"b":4,"kind":"land","length":140.4821,"move_cost_mult":1,"defense_mult":1},{"a":1,"b":5,"kind":"land","length":159.4143,"move_cost_mult":1,"defense_mult":1},{"a":1,"b":20,"kind":"land","length":152.0427,"move_cost_mult":1,"defense_mult":1},{"a":1,"b":21,"kind":"land","length":185.5786,"move_cost_mult":1,"defense_mult":1},{"a":2,"b":3,"kind":"land","length":220.4797,"move_cost_mult":1,"defense_mult":1},{"a":2,"b":6,"kind":"land","length":180.3935,"move_cost_mult":1,"defense_mult":1},{"a":2,"b":7,"kind":"land","length":152.0427,"move_cost_mult":1,"defense_mult":1},{"a":2,"b":8,"kind":"land","length":181.6991,"move_cost_mult":1,"defense_mult":1},{"a":2,"b":20,"kind":"land","length":181.6991,"move_cost_mult":1,"defense_mult":1},{"a":3,"b":5,"kind":"land","length":197.2806,"move_cost_mult":1,"defense_mult":1},{"a":3,"b":7,"kind":"land","length":185.5786,"move_cost_mult":1,"defense_mult":1},{"a":3,"b":10,"kind":"land","length":184.2916,"move_cost_mult":1,"defense_mult":1},{"a":4,"b":5,"kind":"land","length":190.7163,"move_cost_mult":1,"defense_mult":1},{"a":4,"b":21,"kind":"land","length":184.2916,"move_cost_mult":1,"defense_mult":1},{"a":6,"b":7,"kind":"land","length":117.8091,"move_cost_mult":1,"defense_mult":1},{"a":6,"b":8,"kind":"land","length":136.8953,"move_cost_mult":1,"defense_mult":1},{"a":6,"b":9,"kind":"land","length":196.7929,"move_cost_mult":1,"defense_mult":1},{"a":6,"b":11,"kind":"land","length":123.8297,"move_cost_mult":1,"defense_mult":1},{"a":7,"b":10,"kind":"land","length":140.4821,"move_cost_mult":1,"defense_mult":1},{"a":7,"b":11,"kind":"land","length":159.4143,"move_cost_mult":1,"defense_mult":1},{"a":8,"b":9,"kind":"land","length":220.4797,"move_cost_mult":1,"defense_mult":1},{"a":8,"b":12,"kind":"land","length":180.3935,"move_cost_mult":1,"defense_mult":1},{"a":8,"b":13,"kind":"land","length":152.0427,"move_cost_mult":1,"defense_mult":1},{"a":8,"b":14,"kind":"land","length":181.6991,"move_cost_mult":1,"defense_mult":1},{"a":9,"b":11,"kind":"land","length":197.2806,"move_cost_mult":1,"defense_mult":1},{"a":9,"b":13,"kind":"land","length":185.5786,"move_cost_mult":1,"defense_mult":1},{"a":9,"b":16,"kind":"land","length":184.2916,"move_cost_mult":1,"defense_mult":1},{"a":10,"b":11,"kind":"land","length":190.7163,"move_cost_mult":1,"defense_mult":1},{"a":12,"b":13,"kind":"land","length":117.8091,"move_cost_mult":1,"defense_mult":1},{"a":12,"b":14,"kind":"land","length":136.8953,"move_cost_mult":1,"defense_mult":1},{"a":12,"b":15,"kind":"land","length":196.7929,"move_cost_mult":1,"defense_mult":1},{"a":12,"b":17,"kind":"land","length":123.8297,"move_cost_mult":1,"defense_mult":1},{"a":13,"b":16,"kind":"land","length":140.4821,"move_cost_mult":1,"defense_mult":1},{"a":13,"b":17,"kind":"land","length":159.4143,"move_cost_mult":1,"defense_mult":1},{"a":14,"b":15,"kind":"land","length":220.4797,"move_cost_mult":1,"defense_mult":1},{"a":14,"b":18,"kind":"land","length":180.3935,"move_cost_mult":1,"defense_mult":1},{"a":14,"b":19,"kind":"land","length":152.0427,"move_cost_mult":1,"defense_mult":1},{"a":14,"b":20,"kind":"land","length":181.6991,"move_cost_mult":1,"defense_mult":1},{"a":15,"b":17,"kind":"land","length":197.2806,"move_cost_mult":1,"defense_mult":1},{"a":15,"b":19,"kind":"land","length":185.5786,"move_cost_mult":1,"defense_mult":1},{"a":15,"b":22,"kind":"land","length":184.2916,"move_cost_mult":1,"defense_mult":1},{"a":16,"b":17,"kind":"land","length":190.7163,"move_cost_mult":1,"defense_mult":1},{"a":18,"b":19,"kind":"land","length":117.8091,"move_cost_mult":1,"defense_mult":1},{"a":18,"b":20,"kind":"land","length":136.8953,"move_cost_mult":1,"defense_mult":1},{"a":18,"b":21,"kind":"land","length":196.7929,"move_cost_mult":1,"defense_mult":1},{"a":18,"b":23,"kind":"land","length":123.8297,"move_cost_mult":1,"defense_mult":1},{"a":19,"b":22,"kind":"land","length":140.4821,"move_cost_mult":1,"defense_mult":1},{"a":19,"b":23,"kind":"land","length":159.4143,"move_cost_mult":1,"defense_mult":1},{"a":20,"b":21,"kind":"land","length":220.4797,"move_cost_mult":1,"defense_mult":1},{"a":21,"b":23,"kind":"land","length":197.2806,"move_cost_mult":1,"defense_mult":1},{"a":22,"b":23,"kind":"land","length":190.7163,"move_cost_mult":1,"defense_mult":1}],"seat_player_ids":[-1,-2,-3,1]}$json$::jsonb;
begin
  insert into auth.users (id, aud, role, email) values (u1, 'authenticated', 'authenticated', u1 || '@t.test'), (u2, 'authenticated', 'authenticated', u2 || '@t.test');
  insert into public.games (name, created_by, max_players, status, tick_speed, fill_with_ai, ai_difficulty, map_size, starting_territories, victory_pct)
  values ('dipsuite', u1, 4, 'lobby', 'fast', true, 3, 'compact', 3, 1.0) returning id into g;
  insert into public.game_players (game_id, user_id, faction_slug, display_name) values (g, u1, 'kaldran', 'One') returning id into p1;
  insert into public.game_players (game_id, user_id, faction_slug, display_name) values (g, u2, 'veyra', 'Two') returning id into p2;
  lay := jsonb_set(lay, '{seat_player_ids}', jsonb_build_array(p1, p2, -1, -2));
  perform public.start_game(g, lay);
  select id into p3 from public.game_players where game_id = g and is_ai order by id limit 1;
  select current_tick into tk from public.games where id = g;
  update public.game_players set gold = 1000 where id in (p1, p2, p3);

  perform set_config('request.jwt.claims', jsonb_build_object('sub', u1, 'role', 'authenticated')::text, true);
  set local role authenticated;
  oid := (public.propose_nap(g, p2) ->> 'offer_id')::int;
  reset role;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', u2, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform public.respond_offer(oid, true);
  reset role;
  select status into st from public.diplomacy where game_id = g and player_a_id = least(p1, p2) and player_b_id = greatest(p1, p2);
  if st = 'nap' and public.are_truced(p1, p2) then ok := ok + 1; else bad := bad + 1; res := res || 'nap formed and blocks attacks (got ' || st || '); '; end if;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', u1, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform public.break_nap(g, p2);
  reset role;
  select status into st from public.diplomacy where game_id = g and player_a_id = least(p1, p2) and player_b_id = greatest(p1, p2);
  select infamy_delta into n from public.game_players where id = p1;
  if st = 'grace_period' and n = 10 then ok := ok + 1; else bad := bad + 1; res := res || 'break_nap grace + infamy (got ' || st || ' ' || n || '); '; end if;

  update public.diplomacy set status = 'neutral', broken_by_player_id = null, grace_ends_tick = null where game_id = g and player_a_id = least(p1, p2) and player_b_id = greatest(p1, p2);
  set local role authenticated;
  perform public.declare_war(g, p2);
  reset role;
  select status into st from public.diplomacy where game_id = g and player_a_id = least(p1, p2) and player_b_id = greatest(p1, p2);
  if st = 'war' then ok := ok + 1; else bad := bad + 1; res := res || 'declare_war (got ' || st || '); '; end if;

  set local role authenticated;
  oid := (public.propose_peace_terms(g, p2, '{"payer":"proposer","gold_now":50,"tribute":10,"cycles":3}'::jsonb) ->> 'offer_id')::int;
  reset role;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', u2, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform public.respond_offer(oid, true);
  reset role;
  select status into st from public.diplomacy where game_id = g and player_a_id = least(p1, p2) and player_b_id = greatest(p1, p2);
  select gold into n from public.game_players where id = p2;
  if st = 'truce' and n = 1050 and exists (select 1 from public.gold_deals where game_id = g and kind = 'tribute' and payer_id = p1 and cycles_left = 3) then ok := ok + 1; else bad := bad + 1; res := res || 'peace terms applied (got ' || st || ' ' || n || '); '; end if;

  perform public.process_gold_deals(g, tk + 1);
  select gold into n from public.game_players where id = p1;
  if n = 940 and (select cycles_left from public.gold_deals where game_id = g and kind = 'tribute') = 2 then ok := ok + 1; else bad := bad + 1; res := res || 'tribute paid (p1 gold ' || n || '); '; end if;

  update public.diplomacy set status = 'allied', truce_ends_tick = null where game_id = g and player_a_id = least(p1, p2) and player_b_id = greatest(p1, p2);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', u1, 'role', 'authenticated')::text, true);
  set local role authenticated;
  oid := (public.propose_marriage(g, p2, 24) ->> 'offer_id')::int;
  reset role;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', u2, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform public.respond_offer(oid, true);
  reset role;
  set local role authenticated;
  begin perform public.break_alliance(g, p1); st := 'broke'; exception when others then st := sqlerrm; end;
  reset role;
  if st like '%marriage alliance%' then ok := ok + 1; else bad := bad + 1; res := res || 'marriage blocks break (got ' || st || '); '; end if;

  update public.diplomacy set status = 'war', locked_until_tick = null where game_id = g and player_a_id = least(p1, p2) and player_b_id = greatest(p1, p2);
  oid := public.create_offer_core(g, 'mediation', p3, p1, jsonb_build_object('a', least(p1, p2), 'b', greatest(p1, p2)), tk);
  n := public.create_offer_core(g, 'mediation', p3, p2, jsonb_build_object('a', least(p1, p2), 'b', greatest(p1, p2)), tk);
  perform public.respond_offer_core(oid, true, tk);
  select status into st from public.diplomacy where game_id = g and player_a_id = least(p1, p2) and player_b_id = greatest(p1, p2);
  if st = 'war' then ok := ok + 1; else bad := bad + 1; res := res || 'mediation waits for both (got ' || st || '); '; end if;
  perform public.respond_offer_core(n, true, tk);
  select status into st from public.diplomacy where game_id = g and player_a_id = least(p1, p2) and player_b_id = greatest(p1, p2);
  if st = 'truce' then ok := ok + 1; else bad := bad + 1; res := res || 'mediation brokers truce (got ' || st || '); '; end if;

  update public.diplomacy set status = 'neutral', truce_ends_tick = null where game_id = g and player_a_id = least(p1, p2) and player_b_id = greatest(p1, p2);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', u1, 'role', 'authenticated')::text, true);
  set local role authenticated;
  oid := (public.propose_trade(g, p2, 5, 3, 2) ->> 'offer_id')::int;
  reset role;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', u2, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform public.respond_offer(oid, true);
  reset role;
  select count(*) into n from public.gold_deals where game_id = g and kind = 'trade' and status = 'active';
  if n = 2 then ok := ok + 1; else bad := bad + 1; res := res || 'trade creates two deals (got ' || n || '); '; end if;

  update public.gold_deals set status = 'cancelled' where kind = 'tribute';
  select gold into n from public.game_players where id = p1;
  update public.game_players set gold = 0 where id = p2;
  perform public.process_gold_deals(g, tk + 2);
  if (select count(*) from public.gold_deals where game_id = g and kind = 'trade' and status = 'active') = 0 and (select gold from public.game_players where id = p1) = n then ok := ok + 1; else bad := bad + 1; res := res || 'one-sided trade default cancels both legs; '; end if;

  set local role anon;
  begin perform public.propose_nap(g, p2); st := 'allowed'; exception when insufficient_privilege then st := 'denied'; end;
  reset role;
  if st = 'denied' then ok := ok + 1; else bad := bad + 1; res := res || 'anon cannot propose; '; end if;

  raise exception 'DIPLOMACY passed=% failed=% %', ok, bad, res;
end $$;
