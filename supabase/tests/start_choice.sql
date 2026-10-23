do $$
declare
  u1 uuid := gen_random_uuid();
  u2 uuid := gen_random_uuid();
  g int; g2 int; p1 int; p2 int; n int; res text := ''; ok int := 0; bad int := 0; st text; v jsonb; s1 int; s2 int; cap1 int;
  lay jsonb := public.test_fixture_layout();
begin
  insert into auth.users (id, aud, role, email) values (u1, 'authenticated', 'authenticated', u1 || '@t.test'), (u2, 'authenticated', 'authenticated', u2 || '@t.test');
  perform set_config('request.jwt.claims', jsonb_build_object('sub', u1, 'role', 'authenticated')::text, true);
  set local role authenticated;
  g := public.create_game('{"name":"pick","max_players":2,"start_selection":"choose","pick_minutes":5}'::jsonb);
  reset role;
  select id into p1 from public.game_players where game_id = g;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', u2, 'role', 'authenticated')::text, true);
  set local role authenticated;
  p2 := public.join_game(g);
  reset role;

  lay := jsonb_set(lay, '{seat_player_ids}', jsonb_build_array(p1, p2));
  perform public.start_game(g, lay);
  if (select status from public.games where id = g) = 'picking' and (select count(*) from public.game_territories where game_id = g and owner_player_id is not null) = 0 and (select count(*) from public.start_seats where game_id = g) = 2 then ok := ok + 1; else bad := bad + 1; res := res || 'choose mode waits in picking with nobody owning anything; '; end if;
  if (select count(*) from public.commanders where game_id = g) = 0 and (select count(*) from public.realm_areas where game_id = g) = 0 then ok := ok + 1; else bad := bad + 1; res := res || 'no per-player setup before picks; '; end if;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', u1, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v := public.get_start_options(g);
  reset role;
  if jsonb_array_length(v -> 'seats') = 2 and jsonb_array_length(v -> 'castles') = 12 then ok := ok + 1; else bad := bad + 1; res := res || 'options list seats and castles (got ' || jsonb_array_length(v -> 'seats') || '/' || jsonb_array_length(v -> 'castles') || '); '; end if;

  set local role authenticated;
  begin perform 1 from public.game_territories limit 1; st := 'allowed'; exception when insufficient_privilege then st := 'denied'; end;
  reset role;
  if st = 'denied' then ok := ok + 1; else bad := bad + 1; res := res || 'castle table is not directly readable; '; end if;

  set local role authenticated;
  select count(*) into n from public.get_game_edges(g);
  reset role;
  if n = 66 then ok := ok + 1; else bad := bad + 1; res := res || 'edges come from the rpc (got ' || n || '); '; end if;

  update public.games set fog_dark = true where id = g;
  set local role authenticated;
  v := public.get_start_options(g);
  select count(*) into n from public.get_game_edges(g);
  reset role;
  if jsonb_array_length(v -> 'castles') = 0 and jsonb_array_length(v -> 'seats') = 2 and n = 0 then ok := ok + 1; else bad := bad + 1; res := res || 'dark picking shows only start markers; '; end if;
  set local role authenticated;
  v := public.get_game_view(g);
  reset role;
  if jsonb_array_length(v -> 'territories') = 0 then ok := ok + 1; else bad := bad + 1; res := res || 'dark picking hides castles in the view; '; end if;

  select seat into s1 from public.start_seats where game_id = g order by seat limit 1;
  select seat into s2 from public.start_seats where game_id = g order by seat desc limit 1;
  select capital_territory_id into cap1 from public.start_seats where game_id = g and seat = s1;
  set local role authenticated;
  perform public.pick_start(g, s1);
  reset role;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', u2, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin perform public.pick_start(g, s1); st := 'allowed'; exception when others then st := sqlerrm; end;
  reset role;
  if st like '%already taken%' then ok := ok + 1; else bad := bad + 1; res := res || 'a taken start cannot be picked (got ' || st || '); '; end if;
  set local role authenticated;
  v := public.pick_start(g, s2);
  reset role;
  if (v ->> 'started')::boolean and (select status from public.games where id = g) = 'active' then ok := ok + 1; else bad := bad + 1; res := res || 'last pick starts the game; '; end if;
  if (select capital_territory_id from public.game_players where id = p1) = cap1 and (select count(*) from public.game_territories where game_id = g and owner_player_id = p1) = 4 and (select count(*) from public.commanders where owner_player_id = p1) >= 2 and (select count(*) from public.realm_areas where player_id = p1) = 7 then ok := ok + 1; else bad := bad + 1; res := res || 'picked seat owns its castles, capital, commanders and areas; '; end if;
  if not exists (select 1 from public.start_seats where game_id = g) then ok := ok + 1; else bad := bad + 1; res := res || 'seat table is cleaned up; '; end if;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', u1, 'role', 'authenticated')::text, true);
  set local role authenticated;
  g2 := public.create_game('{"name":"pick2","max_players":2,"fill_with_ai":true,"start_selection":"choose"}'::jsonb);
  reset role;
  select id into p1 from public.game_players where game_id = g2;
  lay := jsonb_set(public.test_fixture_layout(), '{seat_player_ids}', jsonb_build_array(p1, -1));
  perform public.start_game(g2, lay);
  update public.games set pick_deadline = now() - interval '1 minute' where id = g2;
  perform public.finalize_due_picks();
  if (select status from public.games where id = g2) = 'active' and (select count(distinct owner_player_id) from public.game_territories where game_id = g2 and owner_player_id is not null) = 2 then ok := ok + 1; else bad := bad + 1; res := res || 'deadline assigns random seats to everyone; '; end if;

  set local role anon;
  begin perform public.pick_start(g2, 0); st := 'allowed'; exception when insufficient_privilege then st := 'denied'; end;
  reset role;
  if st = 'denied' then ok := ok + 1; else bad := bad + 1; res := res || 'anon cannot pick; '; end if;

  raise exception 'STARTCHOICE passed=% failed=% %', ok, bad, res;
end $$;
