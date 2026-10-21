alter table public.game_players
  add column starting_schools text[]
  check (starting_schools is null or starting_schools <@ array['battleschool', 'university', 'rangers']);

create function public.random_commander_name(p_game_id int)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_given text[] := array[
    'Aldric', 'Berengar', 'Cedric', 'Dunstan', 'Edmund', 'Faramond', 'Godric', 'Hadrian', 'Isolde',
    'Jorund', 'Kendrick', 'Leofric', 'Maren', 'Nikolai', 'Osric', 'Percival', 'Quentin', 'Roderic',
    'Sigurd', 'Tancred', 'Ulric', 'Valen', 'Wystan', 'Yorick', 'Alaric', 'Brenna', 'Cordelia',
    'Daria', 'Elara', 'Freya', 'Greta', 'Helena', 'Ingrid', 'Jocelyn', 'Katarin', 'Mirelle'
  ];
  v_family text[] := array[
    'Ashgrave', 'Blackwood', 'Brightwater', 'Coldbrook', 'Dawnfield', 'Elmwright', 'Fairholm',
    'Greymantle', 'Hawthorne', 'Ironside', 'Kestrel', 'Lockhart', 'Marlowe', 'Northcott', 'Pemberton',
    'Stonebridge', 'Thornfield', 'Underhill', 'Vance', 'Whitlock', 'Yarrow', 'Ambrose', 'Branwell',
    'Calloway', 'Dunmore', 'Everhart', 'Falconer', 'Harrow', 'Langley', 'Merrick', 'Oakhurst',
    'Prescott', 'Radcliffe', 'Sutton', 'Tolliver', 'Winslow'
  ];
  v_name text;
  v_try int := 0;
begin
  loop
    v_name := v_given[1 + floor(random() * array_length(v_given, 1))::int]
      || ' '
      || v_family[1 + floor(random() * array_length(v_family, 1))::int];
    v_try := v_try + 1;
    exit when v_try > 200
      or not exists (select 1 from public.commanders c where c.game_id = p_game_id and c.name = v_name);
  end loop;
  return v_name;
end;
$$;

create function public.create_commander(
  p_game_id int,
  p_player_id int,
  p_school text,
  p_role text,
  p_territory_id int,
  p_tick int
)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id int;
  v_school_abilities text[] := case p_school
    when 'battleschool' then array['valor', 'tactics', 'siegecraft']
    when 'university' then array['muster', 'steward', 'scholar']
    when 'rangers' then array['pace', 'scout', 'plunder']
  end;
begin
  if v_school_abilities is null then
    raise exception 'unknown school: %', p_school;
  end if;

  insert into public.commanders (game_id, owner_player_id, name, school, role, current_territory_id, created_tick)
  values (p_game_id, p_player_id, public.random_commander_name(p_game_id), p_school, p_role, p_territory_id, p_tick)
  returning id into v_id;

  insert into public.commander_abilities (game_id, commander_id, ability)
  select p_game_id, v_id, a
  from unnest(array['valor', 'tactics', 'siegecraft', 'muster', 'steward', 'scholar', 'pace', 'scout', 'plunder']) as a;

  update public.commander_abilities
  set level = 1
  where commander_id = v_id
    and ability = v_school_abilities[1 + floor(random() * 3)::int];

  return v_id;
end;
$$;

revoke execute on function public.random_commander_name(int) from public, anon, authenticated;
revoke execute on function public.create_commander(int, int, text, text, int, int) from public, anon, authenticated;

create function public.create_game(p_settings jsonb default '{}'::jsonb)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_allowed text[] := array[
    'name', 'faction_slug', 'max_players', 'tick_speed', 'production_cycle_ticks', 'commander_speed_mult',
    'infra_cost_mult', 'area_cost_mult', 'victory_pct', 'fog_of_war', 'starting_gold', 'starting_garrison',
    'starting_gold_level', 'starting_industry_level', 'starting_prestige_level', 'fill_with_ai', 'ai_difficulty',
    'turn_timeout_minutes', 'ticks_per_turn', 'map_style', 'map_size', 'starting_territories',
    'starting_commanders', 'commander_cost', 'coronation_ticks', 'world_seed'
  ];
  v_bad text;
  v_name text;
  v_id int;
  v_game public.games%rowtype;
  v_per_player int;
  v_faction text;
  v_display text;
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;

  select k into v_bad from jsonb_object_keys(coalesce(p_settings, '{}'::jsonb)) as k where k <> all (v_allowed) limit 1;
  if v_bad is not null then
    raise exception 'unknown setting: %', v_bad;
  end if;

  v_name := coalesce(nullif(trim(p_settings ->> 'name'), ''), 'New Game');
  if char_length(v_name) > 60 then
    raise exception 'name must be 60 characters or fewer';
  end if;

  insert into public.games (name, created_by) values (v_name, v_uid) returning id into v_id;

  update public.games g
  set max_players = coalesce((p_settings ->> 'max_players')::int, g.max_players),
      tick_speed = coalesce(p_settings ->> 'tick_speed', g.tick_speed),
      production_cycle_ticks = coalesce((p_settings ->> 'production_cycle_ticks')::int, g.production_cycle_ticks),
      commander_speed_mult = coalesce((p_settings ->> 'commander_speed_mult')::float8, g.commander_speed_mult),
      infra_cost_mult = coalesce((p_settings ->> 'infra_cost_mult')::float8, g.infra_cost_mult),
      area_cost_mult = coalesce((p_settings ->> 'area_cost_mult')::float8, g.area_cost_mult),
      victory_pct = coalesce((p_settings ->> 'victory_pct')::float8, g.victory_pct),
      fog_of_war = coalesce((p_settings ->> 'fog_of_war')::boolean, g.fog_of_war),
      starting_gold = coalesce((p_settings ->> 'starting_gold')::int, g.starting_gold),
      starting_garrison = coalesce((p_settings ->> 'starting_garrison')::int, g.starting_garrison),
      starting_gold_level = coalesce((p_settings ->> 'starting_gold_level')::int, g.starting_gold_level),
      starting_industry_level = coalesce((p_settings ->> 'starting_industry_level')::int, g.starting_industry_level),
      starting_prestige_level = coalesce((p_settings ->> 'starting_prestige_level')::int, g.starting_prestige_level),
      fill_with_ai = coalesce((p_settings ->> 'fill_with_ai')::boolean, g.fill_with_ai),
      ai_difficulty = coalesce((p_settings ->> 'ai_difficulty')::int, g.ai_difficulty),
      turn_timeout_minutes = coalesce((p_settings ->> 'turn_timeout_minutes')::int, g.turn_timeout_minutes),
      ticks_per_turn = coalesce((p_settings ->> 'ticks_per_turn')::int, g.ticks_per_turn),
      map_style = coalesce(p_settings ->> 'map_style', g.map_style),
      map_size = coalesce(p_settings ->> 'map_size', g.map_size),
      starting_territories = coalesce((p_settings ->> 'starting_territories')::int, g.starting_territories),
      starting_commanders = coalesce((p_settings ->> 'starting_commanders')::int, g.starting_commanders),
      commander_cost = coalesce((p_settings ->> 'commander_cost')::int, g.commander_cost),
      coronation_ticks = coalesce((p_settings ->> 'coronation_ticks')::int, g.coronation_ticks),
      world_seed = coalesce((p_settings ->> 'world_seed')::bigint, g.world_seed)
  where g.id = v_id
  returning * into v_game;

  v_per_player := case v_game.map_size when 'compact' then 6 when 'standard' then 9 else 14 end;
  if v_game.starting_territories > v_per_player - 2 then
    raise exception 'starting_territories must leave at least 2 neutral territories per player on a % map', v_game.map_size;
  end if;

  v_faction := p_settings ->> 'faction_slug';
  if v_faction is null then
    select slug into v_faction from public.factions order by random() limit 1;
  elsif not exists (select 1 from public.factions where slug = v_faction) then
    raise exception 'unknown faction: %', v_faction;
  end if;

  select display_name into v_display from public.profiles where user_id = v_uid;

  insert into public.game_players (game_id, user_id, faction_slug, display_name)
  values (v_id, v_uid, v_faction, coalesce(v_display, 'Player'));

  return v_id;
end;
$$;

create function public.join_game(p_game_id int, p_faction_slug text default null)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_game public.games%rowtype;
  v_count int;
  v_faction text;
  v_display text;
  v_id int;
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;

  select * into v_game from public.games where id = p_game_id for update;
  if not found then
    raise exception 'game not found';
  end if;
  if v_game.status <> 'lobby' then
    raise exception 'game is not in the lobby';
  end if;
  if exists (select 1 from public.game_players where game_id = p_game_id and user_id = v_uid) then
    raise exception 'already in this game';
  end if;

  select count(*) into v_count from public.game_players where game_id = p_game_id;
  if v_count >= v_game.max_players then
    raise exception 'game is full';
  end if;

  if p_faction_slug is null then
    select f.slug into v_faction
    from public.factions f
    where not exists (
      select 1 from public.game_players gp where gp.game_id = p_game_id and gp.faction_slug = f.slug
    )
    order by random()
    limit 1;
  else
    v_faction := p_faction_slug;
    if not exists (select 1 from public.factions where slug = v_faction) then
      raise exception 'unknown faction: %', v_faction;
    end if;
    if exists (select 1 from public.game_players where game_id = p_game_id and faction_slug = v_faction) then
      raise exception 'faction already taken';
    end if;
  end if;

  select display_name into v_display from public.profiles where user_id = v_uid;

  insert into public.game_players (game_id, user_id, faction_slug, display_name)
  values (p_game_id, v_uid, v_faction, coalesce(v_display, 'Player'))
  returning id into v_id;

  return v_id;
end;
$$;

create function public.set_starting_schools(p_game_id int, p_schools text[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_game public.games%rowtype;
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;

  select * into v_game from public.games where id = p_game_id;
  if not found then
    raise exception 'game not found';
  end if;
  if v_game.status <> 'lobby' then
    raise exception 'game is not in the lobby';
  end if;
  if p_schools is not null and coalesce(array_length(p_schools, 1), 0) <> 1 + v_game.starting_commanders then
    raise exception 'choose % schools: one for the king and one for each starting commander', 1 + v_game.starting_commanders;
  end if;

  update public.game_players
  set starting_schools = p_schools
  where game_id = p_game_id and user_id = v_uid;

  if not found then
    raise exception 'you are not in this game';
  end if;
end;
$$;

create function public.start_game(p_game_id int, p_layout jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_game public.games%rowtype;
  v_humans int;
  v_target int;
  v_ai_needed int;
  v_inserted int;
  v_ai_ids int[];
  v_seats jsonb;
  v_world jsonb;
  v_p public.game_players%rowtype;
  v_i int;
  v_school text;
begin
  select * into v_game from public.games where id = p_game_id for update;
  if not found then
    raise exception 'game % not found', p_game_id;
  end if;
  if v_game.status <> 'lobby' then
    raise exception 'game % is not in the lobby', p_game_id;
  end if;

  select count(*) into v_humans from public.game_players where game_id = p_game_id;
  if v_humans < 1 then
    raise exception 'game % has no players', p_game_id;
  end if;

  v_target := case when v_game.fill_with_ai then v_game.max_players else v_humans end;
  if v_target < 2 then
    raise exception 'a game needs at least 2 players: enable AI fill or wait for more players';
  end if;
  v_ai_needed := v_target - v_humans;

  if v_ai_needed > 0 then
    insert into public.game_players (game_id, faction_slug, display_name, is_ai)
    select p_game_id, free.slug, 'AI ' || free.name, true
    from (
      select f.slug, f.name,
             row_number() over (order by hashtext(f.slug || p_game_id::text)) as rn
      from public.factions f
      where not exists (
        select 1 from public.game_players gp where gp.game_id = p_game_id and gp.faction_slug = f.slug
      )
    ) free
    where free.rn <= v_ai_needed
    order by free.rn;

    get diagnostics v_inserted = row_count;
    if v_inserted <> v_ai_needed then
      raise exception 'not enough free factions for % AI players', v_ai_needed;
    end if;
  end if;

  select array_agg(id order by id) into v_ai_ids
  from public.game_players where game_id = p_game_id and is_ai;

  select jsonb_agg(
    case when s.value::int < 0 then to_jsonb(v_ai_ids[- s.value::int]) else to_jsonb(s.value::int) end
    order by s.ord
  ) into v_seats
  from jsonb_array_elements_text(p_layout -> 'seat_player_ids') with ordinality as s(value, ord);

  v_world := public.commit_world(p_game_id, jsonb_set(p_layout, '{seat_player_ids}', v_seats));

  for v_p in select * from public.game_players where game_id = p_game_id order by id loop
    update public.game_players set gold = v_game.starting_gold where id = v_p.id;

    if v_game.starting_gold > 0 then
      insert into public.ledger (game_id, player_id, tick, type, amount)
      values (p_game_id, v_p.id, 0, 'starting_gold', v_game.starting_gold);
    end if;

    insert into public.realm_areas (game_id, player_id, area, level, is_active)
    select p_game_id, v_p.id, a, 1, a = 'armory'
    from unnest(array['armory', 'mint', 'barracks', 'guildhall', 'watchtowers', 'library', 'stables']) as a;

    for v_i in 1 .. 1 + v_game.starting_commanders loop
      v_school := case
        when v_p.starting_schools is not null
         and array_length(v_p.starting_schools, 1) = 1 + v_game.starting_commanders
        then v_p.starting_schools[v_i]
        else (array['battleschool', 'university', 'rangers'])[1 + floor(random() * 3)::int]
      end;
      perform public.create_commander(
        p_game_id, v_p.id, v_school,
        case when v_i = 1 then 'king' else 'commander' end,
        v_p.capital_territory_id, 0
      );
    end loop;
  end loop;

  insert into public.diplomacy (game_id, player_a_id, player_b_id)
  select p_game_id, a.id, b.id
  from public.game_players a
  join public.game_players b on b.game_id = a.game_id and b.id > a.id
  where a.game_id = p_game_id;

  insert into public.game_moments (game_id, tick, type, payload)
  values (
    p_game_id, 0, 'game_started',
    jsonb_build_object('players', (
      select jsonb_agg(jsonb_build_object('player_id', id, 'faction', faction_slug, 'is_ai', is_ai) order by id)
      from public.game_players where game_id = p_game_id
    ))
  );

  insert into public.game_events (game_id, tick, type, payload)
  values (p_game_id, 0, 'game_started', jsonb_build_object('players', v_target, 'ai_players', v_ai_needed));

  insert into public.player_inbox (game_id, player_id, type, title, body, tick)
  select p_game_id, id, 'system', 'The realm awaits', jsonb_build_object('kind', 'game_started'), 0
  from public.game_players
  where game_id = p_game_id and not is_ai;

  update public.games
  set status = 'active',
      current_tick = 0,
      last_tick_processed_at = now(),
      current_turn_ends_at = case
        when tick_speed = 'turn_based' then now() + make_interval(mins => turn_timeout_minutes)
        else null
      end
  where id = p_game_id;

  return jsonb_build_object(
    'game_id', p_game_id,
    'players', v_target,
    'ai_players', v_ai_needed,
    'world', v_world
  );
end;
$$;

revoke execute on function public.create_game(jsonb) from public, anon;
grant execute on function public.create_game(jsonb) to authenticated;
revoke execute on function public.join_game(int, text) from public, anon;
grant execute on function public.join_game(int, text) to authenticated;
revoke execute on function public.set_starting_schools(int, text[]) from public, anon;
grant execute on function public.set_starting_schools(int, text[]) to authenticated;
revoke execute on function public.start_game(int, jsonb) from public, anon, authenticated;
grant execute on function public.start_game(int, jsonb) to service_role;
