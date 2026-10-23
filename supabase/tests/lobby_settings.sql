do $$
declare
  u1 uuid := gen_random_uuid();
  u2 uuid := gen_random_uuid();
  g int; p1 int; p2 int; n int; c int; a int; res text := ''; ok int := 0; bad int := 0; st text; w int; g1 int; g2 int; cost int; lvl int; res0 int;
  lay jsonb := public.test_fixture_layout();
begin
  insert into auth.users (id, aud, role, email) values (u1, 'authenticated', 'authenticated', u1 || '@t.test'), (u2, 'authenticated', 'authenticated', u2 || '@t.test');

  perform set_config('request.jwt.claims', jsonb_build_object('sub', u1, 'role', 'authenticated')::text, true);
  set local role authenticated;
  g := public.create_game('{"name":"cfg2","password":"pw","max_players":2,"fill_with_ai":false,"victory_decay":2,"allow_alliances":false,"roads_mode":"expensive","random_roads":"rare","treasury_cost_mult":0.5,"trade_cost":40,"terraforming_enabled":false,"experimentation_enabled":false,"experiment_bonus_mult":2,"area_start_levels":{"stables":3},"area_cost_mults":{"library":0},"turn_fixed":true,"resource_richness":"sparse","map_size":"tiny"}'::jsonb);
  begin perform public.create_game('{"area_start_levels":{"foo":1}}'::jsonb); st := 'allowed'; exception when others then st := sqlerrm; end;
  reset role;
  if st like '%area_start_levels%' then ok := ok + 1; else bad := bad + 1; res := res || 'bad area key rejected (got ' || st || '); '; end if;
  if (select has_password and password_hash <> 'pw' and victory_decay = 2 and not allow_alliances and roads_mode = 'expensive' and random_roads = 'rare' and treasury_cost_mult = 0.5 and trade_cost = 40 and not terraforming_enabled and not experimentation_enabled and experiment_bonus_mult = 2 and turn_fixed and resource_richness = 'sparse' and map_size = 'tiny' from public.games where id = g) then ok := ok + 1; else bad := bad + 1; res := res || 'create_game stores every new setting; '; end if;
  select id into p1 from public.game_players where game_id = g;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', u2, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin perform public.join_game(g, null, 'nope'); st := 'allowed'; exception when others then st := sqlerrm; end;
  reset role;
  if st = 'wrong password' then ok := ok + 1; else bad := bad + 1; res := res || 'wrong password rejected (got ' || st || '); '; end if;
  set local role authenticated;
  p2 := public.join_game(g, null, 'pw');
  reset role;
  if p2 is not null then ok := ok + 1; else bad := bad + 1; res := res || 'right password joins; '; end if;

  lay := jsonb_set(lay, '{seat_player_ids}', jsonb_build_array(p1, p2));
  perform public.start_game(g, lay);

  if (select level from public.realm_areas where player_id = p1 and area = 'stables') = 3 and (select level from public.realm_areas where player_id = p1 and area = 'armory') = 1 then ok := ok + 1; else bad := bad + 1; res := res || 'area start level applied; '; end if;
  select count(*) into n from public.game_territories where game_id = g and owner_player_id is not null and resources <> natural_resources;
  if n = 0 then ok := ok + 1; else bad := bad + 1; res := res || 'terraforming off keeps resources natural (' || n || ' differ); '; end if;
  if (select count(*) from public.game_territories where game_id = g and has_road) = 1 then ok := ok + 1; else bad := bad + 1; res := res || 'layout pre-built road is committed; '; end if;

  update public.game_players set gold = 100000 where id in (p1, p2);
  select id, resources into c, res0 from public.game_territories where game_id = g and owner_player_id = p1 and not has_road order by id limit 1;
  select gold into g1 from public.game_players where id = p1;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', u1, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform public.build_road(g, c);
  reset role;
  select gold into g2 from public.game_players where id = p1;
  if g1 - g2 = floor(6.0 * res0 * 3)::int then ok := ok + 1; else bad := bad + 1; res := res || 'expensive road costs 3x (spent ' || (g1 - g2) || ' vs ' || floor(6.0 * res0 * 3) || '); '; end if;

  select treasury_level into lvl from public.game_territories where id = c;
  select gold into g1 from public.game_players where id = p1;
  set local role authenticated;
  perform public.upgrade_infrastructure(g, c, 'treasury');
  reset role;
  select gold into g2 from public.game_players where id = p1;
  if g1 - g2 = public.infra_cost('treasury', lvl, res0, 0.5) then ok := ok + 1; else bad := bad + 1; res := res || 'treasury cost multiplier applies (spent ' || (g1 - g2) || '); '; end if;

  update public.games set roads_mode = 'disabled' where id = g;
  select id into a from public.game_territories where game_id = g and owner_player_id = p1 and not has_road order by id limit 1;
  set local role authenticated;
  begin perform public.build_road(g, a); st := 'allowed'; exception when others then st := sqlerrm; end;
  reset role;
  if st like '%disabled%' then ok := ok + 1; else bad := bad + 1; res := res || 'roads can be disabled (got ' || st || '); '; end if;

  if public.add_area_prestige(g, p1, 'library', 5000) = 1 then ok := ok + 1; else bad := bad + 1; res := res || 'disabled tech never levels; '; end if;
  if public.add_area_prestige(g, p1, 'guildhall', 5000) = 1 then ok := ok + 1; else bad := bad + 1; res := res || 'terraforming off locks guildhall; '; end if;

  update public.games set current_tick = 3 * production_cycle_ticks where id = g;
  if (public.game_standing(g) ->> 'win_at')::int = 2 then ok := ok + 1; else bad := bad + 1; res := res || 'victory decay lowers the target (got ' || (public.game_standing(g) ->> 'win_at') || '); '; end if;

  set local role authenticated;
  begin perform public.propose_alliance(g, p2); st := 'allowed'; exception when others then st := sqlerrm; end;
  reset role;
  if st like '%alliances are disabled%' then ok := ok + 1; else bad := bad + 1; res := res || 'alliances can be disabled (got ' || st || '); '; end if;

  update public.realm_areas set level = 1 where player_id = p2 and area = 'stables';
  select gold into g1 from public.game_players where id = p1;
  set local role authenticated;
  perform public.gift_tech(g, p2, 'stables');
  reset role;
  select gold into g2 from public.game_players where id = p1;
  if (select level from public.realm_areas where player_id = p2 and area = 'stables') = 2 and g1 - g2 = 80 then ok := ok + 1; else bad := bad + 1; res := res || 'gift_tech raises the ally one level for 40 x level (fee ' || (g1 - g2) || '); '; end if;
  set local role authenticated;
  begin perform public.gift_tech(g, p2, 'library'); st := 'allowed'; exception when others then st := sqlerrm; end;
  reset role;
  if st like '%disabled%' or st like '%already%' then ok := ok + 1; else bad := bad + 1; res := res || 'disabled tech cannot be gifted (got ' || st || '); '; end if;

  update public.game_territories set owner_player_id = p2 where id = c;
  if (select has_road from public.game_territories where id = c) then ok := ok + 1; else bad := bad + 1; res := res || 'roads survive capture; '; end if;

  set local role anon;
  begin perform public.gift_tech(g, p2, 'stables'); st := 'allowed'; exception when insufficient_privilege then st := 'denied'; end;
  reset role;
  if st = 'denied' then ok := ok + 1; else bad := bad + 1; res := res || 'anon cannot gift; '; end if;

  raise exception 'LOBBYSETTINGS passed=% failed=% %', ok, bad, res;
end $$;
