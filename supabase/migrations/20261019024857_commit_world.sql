create function public.commit_world(p_game_id int, p_layout jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_game public.games%rowtype;
  v_players int;
  v_seat_players int[];
  v_territories jsonb;
  v_count int;
  v_ids int[] := '{}';
  v_t jsonb;
  v_seat int;
  v_owner int;
  v_new_id int;
  v_reached int;
  v_edge_count int;
begin
  select * into v_game from public.games where id = p_game_id for update;
  if not found then
    raise exception 'game % not found', p_game_id;
  end if;
  if v_game.status <> 'lobby' then
    raise exception 'game % is not in the lobby', p_game_id;
  end if;
  if exists (select 1 from public.game_territories where game_id = p_game_id) then
    raise exception 'world already committed for game %', p_game_id;
  end if;

  if p_layout is null
     or jsonb_typeof(p_layout) <> 'object'
     or not jsonb_exists_all(p_layout, array['territories', 'edges', 'seats', 'seat_player_ids', 'map_w', 'map_h', 'generator_version']) then
    raise exception 'layout is missing required keys';
  end if;

  select count(*) into v_players from public.game_players where game_id = p_game_id;
  if v_players < 2 then
    raise exception 'game % needs at least 2 players', p_game_id;
  end if;

  select array_agg(s.value::int order by s.ord) into v_seat_players
  from jsonb_array_elements_text(p_layout -> 'seat_player_ids') with ordinality as s(value, ord);

  if coalesce(array_length(v_seat_players, 1), 0) <> v_players
     or (select count(distinct x) from unnest(v_seat_players) x) <> v_players
     or exists (
       select 1 from public.game_players gp
       where gp.game_id = p_game_id and gp.id <> all (v_seat_players)
     ) then
    raise exception 'seat_player_ids must list every player of the game exactly once';
  end if;

  if jsonb_array_length(p_layout -> 'seats') <> v_players then
    raise exception 'seats must have one entry per player';
  end if;

  v_territories := p_layout -> 'territories';
  v_count := jsonb_array_length(v_territories);

  if exists (
    select 1 from jsonb_array_elements(v_territories) with ordinality as t(e, ord)
    where (t.e ->> 'idx')::int <> t.ord - 1
  ) then
    raise exception 'territory idx values must be contiguous from 0';
  end if;

  if exists (
    select 1 from jsonb_array_elements(v_territories) as t(e)
    where (t.e ->> 'x')::float8 < 0 or (t.e ->> 'x')::float8 > (p_layout ->> 'map_w')::float8
       or (t.e ->> 'y')::float8 < 0 or (t.e ->> 'y')::float8 > (p_layout ->> 'map_h')::float8
  ) then
    raise exception 'territory outside the map bounds';
  end if;

  if exists (
    select 1 from jsonb_array_elements(v_territories) as t(e)
    where (t.e ->> 'owner_seat')::int < 0 or (t.e ->> 'owner_seat')::int >= v_players
  ) then
    raise exception 'owner_seat out of range';
  end if;

  if exists (
    select 1 from generate_series(0, v_players - 1) as s
    where (
      select count(*) from jsonb_array_elements(v_territories) as t(e)
      where (t.e ->> 'owner_seat')::int = s
    ) <> v_game.starting_territories
    or (
      select count(*) from jsonb_array_elements(v_territories) as t(e)
      where (t.e ->> 'owner_seat')::int = s and (t.e ->> 'tier')::int = 3
    ) <> 1
  ) then
    raise exception 'every seat must start with the same number of territories and exactly one tier 3 capital';
  end if;

  if (
    select count(*) from jsonb_array_elements(v_territories) as t(e)
    where t.e ->> 'owner_seat' is null
  ) % v_players <> 0 then
    raise exception 'neutral territories must divide evenly among seats';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_layout -> 'seats') as s(e)
    where not exists (
      select 1 from jsonb_array_elements(v_territories) as t(e)
      where (t.e ->> 'idx')::int = (s.e ->> 'capital_idx')::int
        and (t.e ->> 'tier')::int = 3
        and (t.e ->> 'owner_seat')::int = (s.e ->> 'seat')::int
    )
  ) then
    raise exception 'each seat capital must be a tier 3 territory owned by that seat';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_layout -> 'edges') as e(e)
    where (e.e ->> 'a')::int < 0
       or (e.e ->> 'b')::int >= v_count
       or (e.e ->> 'a')::int >= (e.e ->> 'b')::int
       or (e.e ->> 'length')::float8 <= 0
  ) then
    raise exception 'invalid edge in layout';
  end if;

  for v_t in
    select t.e from jsonb_array_elements(v_territories) with ordinality as t(e, ord) order by t.ord
  loop
    v_seat := (v_t ->> 'owner_seat')::int;
    v_owner := case when v_seat is null then null else v_seat_players[v_seat + 1] end;

    insert into public.game_territories (
      game_id, slug, name, tier, base_influence, x, y, owner_player_id,
      troops, gold_level, industry_level, prestige_level, effective_influence
    ) values (
      p_game_id,
      v_t ->> 'slug',
      v_t ->> 'name',
      (v_t ->> 'tier')::smallint,
      (v_t ->> 'base_influence')::int,
      (v_t ->> 'x')::float8,
      (v_t ->> 'y')::float8,
      v_owner,
      case when v_owner is null then (v_t ->> 'troops')::int else v_game.starting_garrison end,
      case when v_owner is null then (v_t ->> 'gold_level')::int else v_game.starting_gold_level end,
      case when v_owner is null then (v_t ->> 'industry_level')::int else v_game.starting_industry_level end,
      case when v_owner is null then (v_t ->> 'prestige_level')::int else v_game.starting_prestige_level end,
      (v_t ->> 'effective_influence')::int
    )
    returning id into v_new_id;

    v_ids := v_ids || v_new_id;
  end loop;

  insert into public.territory_edges (
    game_id, from_territory_id, to_territory_id, kind, length, move_cost_mult, defense_mult
  )
  select
    p_game_id,
    least(v_ids[(e.e ->> 'a')::int + 1], v_ids[(e.e ->> 'b')::int + 1]),
    greatest(v_ids[(e.e ->> 'a')::int + 1], v_ids[(e.e ->> 'b')::int + 1]),
    coalesce(e.e ->> 'kind', 'land'),
    (e.e ->> 'length')::float8,
    coalesce((e.e ->> 'move_cost_mult')::float8, 1),
    coalesce((e.e ->> 'defense_mult')::float8, 1)
  from jsonb_array_elements(p_layout -> 'edges') as e(e);

  get diagnostics v_edge_count = row_count;

  with recursive reach(id) as (
    select min(gt.id) from public.game_territories gt where gt.game_id = p_game_id
    union
    select case when te.from_territory_id = r.id then te.to_territory_id else te.from_territory_id end
    from reach r
    join public.territory_edges te
      on te.game_id = p_game_id
     and (te.from_territory_id = r.id or te.to_territory_id = r.id)
  )
  select count(*) into v_reached from reach;

  if v_reached <> v_count then
    raise exception 'territory graph is not connected (% of % reachable)', v_reached, v_count;
  end if;

  update public.game_players gp
  set capital_territory_id = c.territory_id
  from (
    select
      v_seat_players[(s.e ->> 'seat')::int + 1] as player_id,
      v_ids[(s.e ->> 'capital_idx')::int + 1] as territory_id
    from jsonb_array_elements(p_layout -> 'seats') as s(e)
  ) c
  where gp.id = c.player_id;

  update public.games
  set map_w = (p_layout ->> 'map_w')::float8,
      map_h = (p_layout ->> 'map_h')::float8,
      generator_version = (p_layout ->> 'generator_version')::int
  where id = p_game_id;

  return jsonb_build_object(
    'game_id', p_game_id,
    'territories', v_count,
    'edges', v_edge_count,
    'capitals', (
      select jsonb_agg(jsonb_build_object('player_id', gp.id, 'territory_id', gp.capital_territory_id) order by gp.id)
      from public.game_players gp
      where gp.game_id = p_game_id
    )
  );
end;
$$;

revoke execute on function public.commit_world(int, jsonb) from public, anon, authenticated;
grant execute on function public.commit_world(int, jsonb) to service_role;
