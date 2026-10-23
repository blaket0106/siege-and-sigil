alter table public.games
  add column if not exists victory_decay int not null default 0 check (victory_decay between 0 and 16),
  add column if not exists allow_alliances boolean not null default true,
  add column if not exists roads_mode text not null default 'cheap' check (roads_mode in ('cheap', 'expensive', 'disabled')),
  add column if not exists random_roads text not null default 'none' check (random_roads in ('none', 'rare', 'common')),
  add column if not exists treasury_cost_mult float8 not null default 1 check (treasury_cost_mult > 0),
  add column if not exists recruitment_cost_mult float8 not null default 1 check (recruitment_cost_mult > 0),
  add column if not exists prestige_cost_mult float8 not null default 1 check (prestige_cost_mult > 0),
  add column if not exists trade_cost int not null default 25 check (trade_cost between 0 and 500),
  add column if not exists trade_requires_scan boolean not null default false,
  add column if not exists terraforming_enabled boolean not null default true,
  add column if not exists experimentation_enabled boolean not null default true,
  add column if not exists experiment_bonus_mult float8 not null default 1 check (experiment_bonus_mult > 0),
  add column if not exists area_start_levels jsonb not null default '{}'::jsonb,
  add column if not exists area_cost_mults jsonb not null default '{}'::jsonb,
  add column if not exists turn_fixed boolean not null default false,
  add column if not exists auto_start boolean not null default false,
  add column if not exists password_hash text,
  add column if not exists has_password boolean generated always as (password_hash is not null) stored,
  add column if not exists resource_richness text not null default 'standard' check (resource_richness in ('sparse', 'standard', 'plentiful'));

alter table public.games drop constraint if exists games_map_size_check;
alter table public.games add constraint games_map_size_check check (map_size in ('tiny', 'small', 'compact', 'standard', 'large'));

grant select (victory_decay, allow_alliances, roads_mode, random_roads, treasury_cost_mult, recruitment_cost_mult, prestige_cost_mult,
  trade_cost, trade_requires_scan, terraforming_enabled, experimentation_enabled, experiment_bonus_mult, area_start_levels, area_cost_mults,
  turn_fixed, auto_start, has_password, resource_richness) on public.games to authenticated;

create or replace function public.infra_type_mult(p_game_id integer, p_type text)
returns float8
language sql
stable
security definer
set search_path = ''
as $function$
  select case p_type when 'treasury' then g.treasury_cost_mult when 'recruitment' then g.recruitment_cost_mult else g.prestige_cost_mult end
  from public.games g where g.id = p_game_id;
$function$;

create or replace function public.can_trade(p_game_id integer, p_a integer, p_b integer)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select case when not g.trade_requires_scan then true else exists (
    select 1
    from public.game_territories ta
    join public.game_territories tb on tb.game_id = ta.game_id and tb.owner_player_id = p_b
    where ta.game_id = p_game_id and ta.owner_player_id = p_a
      and sqrt((ta.x - tb.x) ^ 2 + (ta.y - tb.y) ^ 2)
        <= (90 + 60 * coalesce((select ra.level from public.realm_areas ra where ra.player_id = p_a and ra.area = 'watchtowers'), 0)) * g.world_scale
  ) end
  from public.games g where g.id = p_game_id;
$function$;

revoke all on function public.infra_type_mult(integer, text), public.can_trade(integer, integer, integer) from public, anon, authenticated;

create or replace function public.propose_trade(p_game_id integer, p_target_player_id integer, p_give integer, p_get integer, p_cycles integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_player public.game_players;
  v_d public.diplomacy;
  v_tick int;
begin
  v_player := public.acting_player(p_game_id);
  v_d := public.diplo_check_target(p_game_id, v_player.id, p_target_player_id);
  if v_d.status = 'war' then
    raise exception 'you cannot trade with a player you are at war with';
  end if;
  if not public.can_trade(p_game_id, v_player.id, p_target_player_id) then
    raise exception 'you can only trade with players within your scanning range';
  end if;
  if coalesce(p_give, 0) < 0 or coalesce(p_get, 0) < 0 or coalesce(p_give, 0) > 1000 or coalesce(p_get, 0) > 1000 or coalesce(p_give, 0) + coalesce(p_get, 0) = 0 then
    raise exception 'amounts must be between 0 and 1000, and not both zero';
  end if;
  if p_cycles is null or p_cycles < 1 or p_cycles > 20 then
    raise exception 'cycles must be between 1 and 20';
  end if;
  select current_tick into v_tick from public.games where id = p_game_id;
  return jsonb_build_object('offer_id', public.create_offer_core(p_game_id, 'trade', v_player.id, p_target_player_id,
    jsonb_build_object('give', coalesce(p_give, 0), 'get', coalesce(p_get, 0), 'cycles', p_cycles), v_tick));
end;
$function$;

create or replace function public.gift_tech(p_game_id integer, p_target_player_id integer, p_area text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_player public.game_players;
  v_d public.diplomacy;
  v_game public.games%rowtype;
  v_mine int;
  v_theirs int;
  v_new int;
  v_fee int;
begin
  v_player := public.acting_player(p_game_id);
  v_d := public.diplo_check_target(p_game_id, v_player.id, p_target_player_id);
  if v_d.status = 'war' then
    raise exception 'you cannot trade with a player you are at war with';
  end if;
  if not public.can_trade(p_game_id, v_player.id, p_target_player_id) then
    raise exception 'you can only trade with players within your scanning range';
  end if;

  select * into v_game from public.games where id = p_game_id;
  if coalesce((v_game.area_cost_mults ->> p_area)::float8, 1) <= 0 or (p_area = 'guildhall' and not v_game.terraforming_enabled) then
    raise exception 'that technology is disabled in this game';
  end if;

  select level into v_mine from public.realm_areas where player_id = v_player.id and area = p_area;
  select level into v_theirs from public.realm_areas where player_id = p_target_player_id and area = p_area;
  if v_mine is null or v_theirs is null then
    raise exception 'unknown area: %', p_area;
  end if;
  if v_mine <= v_theirs then
    raise exception 'that player already has that technology level';
  end if;

  v_new := v_theirs + 1;
  v_fee := v_game.trade_cost * v_new;
  select gold into v_mine from public.game_players where id = v_player.id for update;
  if v_mine < v_fee then
    raise exception 'not enough gold: % needed, % available', v_fee, v_mine;
  end if;

  update public.game_players set gold = gold - v_fee where id = v_player.id;
  insert into public.ledger (game_id, player_id, tick, type, amount)
  values (p_game_id, v_player.id, v_game.current_tick, 'tech_fee', -v_fee);

  update public.realm_areas set level = v_new, prestige_accumulated = 0 where player_id = p_target_player_id and area = p_area;
  if p_area = 'guildhall' then
    perform public.refresh_effective_influence(p_game_id, p_target_player_id);
  end if;

  perform public.notify_diplomacy(
    p_game_id, v_game.current_tick, array[p_target_player_id], v_player.display_name || ' shared ' || p_area || ' technology',
    jsonb_build_object('kind', 'tech_shared', 'from_player_id', v_player.id, 'area', p_area, 'level', v_new)
  );
  insert into public.game_events (game_id, tick, type, payload)
  values (p_game_id, v_game.current_tick, 'tech_shared', jsonb_build_object('from', v_player.id, 'to', p_target_player_id, 'area', p_area, 'level', v_new));

  return jsonb_build_object('area', p_area, 'level', v_new, 'fee', v_fee);
end;
$function$;

revoke all on function public.gift_tech(integer, integer, text) from public, anon;
grant execute on function public.gift_tech(integer, integer, text) to authenticated;

create or replace function public.add_area_prestige(p_game_id integer, p_player_id integer, p_area text, p_amount integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_mult float8;
  v_tick int;
  v_terra boolean;
  v_area public.realm_areas%rowtype;
  v_cost int;
  v_gains int := 0;
begin
  select area_cost_mult * coalesce((area_cost_mults ->> p_area)::float8, 1), current_tick, terraforming_enabled
  into v_mult, v_tick, v_terra
  from public.games where id = p_game_id;

  select * into v_area
  from public.realm_areas
  where player_id = p_player_id and area = p_area
  for update;
  if not found then
    raise exception 'unknown area % for player %', p_area, p_player_id;
  end if;

  if v_mult <= 0 or (p_area = 'guildhall' and not v_terra) then
    return v_area.level;
  end if;

  v_area.prestige_accumulated := v_area.prestige_accumulated + p_amount;
  loop
    v_cost := ceil(144 * v_area.level * v_mult)::int;
    exit when v_area.prestige_accumulated < v_cost;
    v_area.prestige_accumulated := v_area.prestige_accumulated - v_cost;
    v_area.level := v_area.level + 1;
    v_gains := v_gains + 1;
  end loop;

  update public.realm_areas
  set level = v_area.level, prestige_accumulated = v_area.prestige_accumulated
  where player_id = p_player_id and area = p_area;

  if v_gains > 0 then
    insert into public.game_events (game_id, tick, type, payload)
    values (p_game_id, v_tick, 'area_level_up', jsonb_build_object('player_id', p_player_id, 'area', p_area, 'level', v_area.level));

    if p_area = 'guildhall' then
      perform public.refresh_effective_influence(p_game_id, p_player_id);
    end if;
  end if;

  return v_area.level;
end;
$function$;

drop trigger if exists clear_road_on_capture on public.game_territories;
drop function if exists public.clear_road_on_capture();

do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.upgrade_infrastructure_core(integer,integer,integer,text)'::regprocedure) into v_def;
  v_new := replace(v_def, 'v_game.infra_cost_mult', 'v_game.infra_cost_mult * public.infra_type_mult(p_game_id, p_type)');
  if v_new = v_def then raise exception 'upgrade_infrastructure_core patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.bulk_upgrade_infrastructure(integer,text,integer)'::regprocedure) into v_def;
  v_new := replace(v_def, 'v_game.infra_cost_mult', 'v_game.infra_cost_mult * public.infra_type_mult(p_game_id, p_infra_type)');
  if v_new = v_def then raise exception 'bulk_upgrade_infrastructure patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.ai_spend(integer,integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def, 'v_game.infra_cost_mult', 'v_game.infra_cost_mult * public.infra_type_mult(p_game_id, tp.t)');
  if v_new = v_def then raise exception 'ai_spend patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.build_road(integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def, 'v_cost := greatest(1, floor(30.0 * v_t.resources * v_game.infra_cost_mult))::int;',
    'if v_game.roads_mode = ''disabled'' then
    raise exception ''roads are disabled in this game'';
  end if;
  v_cost := greatest(1, floor(6.0 * v_t.resources * v_game.infra_cost_mult * case v_game.roads_mode when ''expensive'' then 3 else 1 end))::int;');
  if v_new = v_def then raise exception 'build_road patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.refresh_effective_influence(integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def, '5 * coalesce((', 'case when (select terraforming_enabled from public.games where id = p_game_id) then 5 else 0 end * coalesce((');
  if v_new = v_def then raise exception 'refresh_effective_influence patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.run_tick(integer)'::regprocedure) into v_def;
  v_new := replace(v_def, 'perform public.add_area_prestige(p_game_id, v_p.player_id, v_area, 72 * v_p.level);',
    'if (select experimentation_enabled from public.games where id = p_game_id) then
          perform public.add_area_prestige(p_game_id, v_p.player_id, v_area, round(72 * (select experiment_bonus_mult from public.games where id = p_game_id) * v_p.level)::int);
        end if;');
  if v_new = v_def then raise exception 'run_tick patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.game_standing(integer)'::regprocedure) into v_def;
  v_new := replace(v_def, 'v_win_at := greatest(1, ceil(v_total * v_pct)::int);',
    'v_win_at := greatest(1, ceil(v_total * v_pct)::int);
  v_win_at := least(v_win_at, greatest(greatest(2, ceil(v_total * 0.15)::int), v_win_at - (
    select g.victory_decay * (g.current_tick / g.production_cycle_ticks) from public.games g where g.id = p_game_id
  )));');
  if v_new = v_def then raise exception 'game_standing patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.get_game_view(integer)'::regprocedure) into v_def;
  v_new := replace(v_def, '''territory_total'', (select count(*)::int from public.game_territories t where t.game_id = p_game_id),',
    '''territory_total'', (select count(*)::int from public.game_territories t where t.game_id = p_game_id),
    ''win_at'', (public.game_standing(p_game_id) ->> ''win_at'')::int,');
  if v_new = v_def then raise exception 'get_game_view patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.process_game(integer)'::regprocedure) into v_def;
  v_new := replace(v_def, 'v_pending := case when v_ready then v_game.ticks_per_turn else 0 end;',
    'if v_game.turn_fixed then
      v_ready := v_game.current_turn_ends_at is not null and now() >= v_game.current_turn_ends_at;
    end if;
    v_pending := case when v_ready then v_game.ticks_per_turn else 0 end;');
  v_new := replace(v_new, 'current_turn_ends_at = now() + make_interval(mins => turn_timeout_minutes)',
    'current_turn_ends_at = case when turn_fixed then current_turn_ends_at + make_interval(mins => turn_timeout_minutes) else now() + make_interval(mins => turn_timeout_minutes) end');
  if v_new = v_def or v_new not like '%turn_fixed then current_turn_ends_at%' or v_new not like '%if v_game.turn_fixed then%' then raise exception 'process_game patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.submit_turn(integer)'::regprocedure) into v_def;
  v_new := replace(v_def, 'if v_all then', 'if v_all and not (select turn_fixed from public.games where id = p_game_id) then');
  if v_new = v_def then raise exception 'submit_turn patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.start_game(integer,jsonb)'::regprocedure) into v_def;
  v_new := replace(v_def, 'select p_game_id, v_p.id, a, 1, a = ''armory''', 'select p_game_id, v_p.id, a, greatest(1, coalesce((v_game.area_start_levels ->> a)::int, 1)), a = ''armory''');
  v_new := replace(v_new, 'for v_i in 1 .. 1 + v_game.starting_commanders loop', 'perform public.refresh_effective_influence(p_game_id, v_p.id);
    for v_i in 1 .. 1 + v_game.starting_commanders loop');
  if v_new = v_def or v_new not like '%area_start_levels%' or v_new not like '%refresh_effective_influence%' then raise exception 'start_game patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.commit_world(integer,jsonb)'::regprocedure) into v_def;
  v_new := replace(v_def, 'prestige_level, resources', 'prestige_level, resources, has_road');
  v_new := replace(v_new, '(v_t ->> ''resources'')::int', '(v_t ->> ''resources'')::int,
      coalesce((v_t ->> ''has_road'')::boolean, false)');
  if v_new = v_def or v_new not like '%resources, has_road%' then raise exception 'commit_world patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.propose_alliance(integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def, 'select current_tick into v_tick from public.games where id = p_game_id;',
    'if not (select allow_alliances from public.games where id = p_game_id) then
    raise exception ''alliances are disabled in this game'';
  end if;
  select current_tick into v_tick from public.games where id = p_game_id;');
  if v_new = v_def then raise exception 'propose_alliance patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.create_game(jsonb)'::regprocedure) into v_def;
  v_new := replace(v_def, '''events_enabled'', ''mercenaries_enabled''',
    '''events_enabled'', ''mercenaries_enabled'', ''victory_decay'', ''allow_alliances'', ''roads_mode'', ''random_roads'', ''treasury_cost_mult'', ''recruitment_cost_mult'', ''prestige_cost_mult'', ''trade_cost'', ''trade_requires_scan'', ''terraforming_enabled'', ''experimentation_enabled'', ''experiment_bonus_mult'', ''area_start_levels'', ''area_cost_mults'', ''turn_fixed'', ''auto_start'', ''password'', ''resource_richness''');
  v_new := replace(v_new, 'world_seed = coalesce((p_settings ->> ''world_seed'')::bigint, g.world_seed)',
    'victory_decay = coalesce((p_settings ->> ''victory_decay'')::int, g.victory_decay),
      allow_alliances = coalesce((p_settings ->> ''allow_alliances'')::boolean, g.allow_alliances),
      roads_mode = coalesce(p_settings ->> ''roads_mode'', g.roads_mode),
      random_roads = coalesce(p_settings ->> ''random_roads'', g.random_roads),
      treasury_cost_mult = coalesce((p_settings ->> ''treasury_cost_mult'')::float8, g.treasury_cost_mult),
      recruitment_cost_mult = coalesce((p_settings ->> ''recruitment_cost_mult'')::float8, g.recruitment_cost_mult),
      prestige_cost_mult = coalesce((p_settings ->> ''prestige_cost_mult'')::float8, g.prestige_cost_mult),
      trade_cost = coalesce((p_settings ->> ''trade_cost'')::int, g.trade_cost),
      trade_requires_scan = coalesce((p_settings ->> ''trade_requires_scan'')::boolean, g.trade_requires_scan),
      terraforming_enabled = coalesce((p_settings ->> ''terraforming_enabled'')::boolean, g.terraforming_enabled),
      experimentation_enabled = coalesce((p_settings ->> ''experimentation_enabled'')::boolean, g.experimentation_enabled),
      experiment_bonus_mult = coalesce((p_settings ->> ''experiment_bonus_mult'')::float8, g.experiment_bonus_mult),
      area_start_levels = coalesce(p_settings -> ''area_start_levels'', g.area_start_levels),
      area_cost_mults = coalesce(p_settings -> ''area_cost_mults'', g.area_cost_mults),
      turn_fixed = coalesce((p_settings ->> ''turn_fixed'')::boolean, g.turn_fixed),
      auto_start = coalesce((p_settings ->> ''auto_start'')::boolean, g.auto_start),
      resource_richness = coalesce(p_settings ->> ''resource_richness'', g.resource_richness),
      password_hash = case when nullif(p_settings ->> ''password'', '''') is null then null else extensions.crypt(p_settings ->> ''password'', extensions.gen_salt(''bf'')) end,
      world_seed = coalesce((p_settings ->> ''world_seed'')::bigint, g.world_seed)');
  v_new := replace(v_new, 'case v_game.map_size when ''compact'' then 6 when ''standard'' then 9 else 14 end',
    'case v_game.map_size when ''tiny'' then 8 when ''small'' then 16 when ''compact'' then 12 when ''standard'' then 24 else 36 end');
  v_new := replace(v_new, '  v_faction := p_settings ->> ''faction_slug'';',
    '  if exists (select 1 from jsonb_object_keys(v_game.area_start_levels) k where k <> all (array[''armory'', ''mint'', ''barracks'', ''guildhall'', ''watchtowers'', ''library'', ''stables''])) or
     exists (select 1 from jsonb_each_text(v_game.area_start_levels) e where e.value !~ ''^[0-9]+$'' or e.value::int > 16) then
    raise exception ''area_start_levels must map areas to levels 1 to 16'';
  end if;
  if exists (select 1 from jsonb_object_keys(v_game.area_cost_mults) k where k <> all (array[''armory'', ''mint'', ''barracks'', ''guildhall'', ''watchtowers'', ''library'', ''stables''])) or
     exists (select 1 from jsonb_each_text(v_game.area_cost_mults) e where e.value !~ ''^[0-9.]+$'' or e.value::float8 > 10) then
    raise exception ''area_cost_mults must map areas to multipliers from 0 to 10'';
  end if;
  v_faction := p_settings ->> ''faction_slug'';');
  if v_new = v_def or v_new not like '%victory_decay = coalesce%' or v_new not like '%password_hash = case%' or v_new not like '%when ''tiny'' then 8%' or v_new not like '%area_cost_mults must map%' then raise exception 'create_game patch did not apply'; end if;
  execute v_new;
end;
$patch$;

create or replace function public.join_game(p_game_id integer, p_faction_slug text default null, p_password text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
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
  if v_game.password_hash is not null and (p_password is null or extensions.crypt(p_password, v_game.password_hash) <> v_game.password_hash) then
    raise exception 'wrong password';
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
$function$;

drop function if exists public.join_game(integer, text);
revoke all on function public.join_game(integer, text, text) from public, anon;
grant execute on function public.join_game(integer, text, text) to authenticated;

drop function if exists public.list_open_games();
create function public.list_open_games()
returns table(id integer, name text, host_name text, max_players integer, player_count integer, taken_factions text[], map_style text, map_size text, tick_speed text, fill_with_ai boolean, victory_pct double precision, fog_of_war boolean, created_at timestamp with time zone, joined boolean, has_password boolean)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    g.id,
    g.name,
    coalesce((select p.display_name from public.profiles p where p.user_id = g.created_by), 'Unknown'),
    g.max_players,
    (select count(*)::int from public.game_players gp where gp.game_id = g.id),
    coalesce((select array_agg(gp.faction_slug order by gp.id) from public.game_players gp where gp.game_id = g.id), '{}'),
    g.map_style,
    g.map_size,
    g.tick_speed,
    g.fill_with_ai,
    g.victory_pct,
    g.fog_of_war,
    g.created_at,
    exists (select 1 from public.game_players gp where gp.game_id = g.id and gp.user_id = (select auth.uid())),
    g.has_password
  from public.games g
  where g.status = 'lobby'
    and (select auth.uid()) is not null
  order by g.created_at desc
  limit 100;
$function$;

revoke all on function public.list_open_games() from public, anon;
grant execute on function public.list_open_games() to authenticated;
