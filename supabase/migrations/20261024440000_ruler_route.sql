create or replace function public.ruler(p_game_id int, p_from int, p_to int, p_commander_id int default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $f$
declare
  v_me int;
  v_g public.games%rowtype;
  v_a public.game_territories%rowtype;
  v_b public.game_territories%rowtype;
  v_dist float8;
  v_route float8;
  v_stables int;
  v_cmd int;
  v_speed float8;
  v_mult float8;
  v_base float8;
  v_step float8;
  v_need int;
  v_range float8;
  v_road_div float8;
  v_plan jsonb;
  v_err text;
  v_in boolean;
  v_eta int;
begin
  select gp.id into v_me from public.game_players gp where gp.game_id = p_game_id and gp.user_id = (select auth.uid());
  if v_me is null then
    raise exception 'you are not in this game';
  end if;
  select * into v_g from public.games where id = p_game_id;
  select * into v_a from public.game_territories where id = p_from and game_id = p_game_id;
  select * into v_b from public.game_territories where id = p_to and game_id = p_game_id;
  if v_a.id is null or v_b.id is null then
    raise exception 'unknown castle';
  end if;
  v_dist := sqrt((v_a.x - v_b.x) ^ 2 + (v_a.y - v_b.y) ^ 2);
  select coalesce(ra.level, 0) into v_stables from public.realm_areas ra where ra.player_id = v_me and ra.area = 'stables';
  v_stables := coalesce(v_stables, 0);
  if v_g.free_travel then
    v_base := 210; v_step := 60;
  elsif v_g.travel_mode = 'trails' then
    v_base := 300; v_step := 120;
  else
    v_base := 90; v_step := 60;
  end if;
  v_mult := case when v_g.league then v_g.unit_scale when v_g.free_travel or v_g.travel_mode = 'trails' then v_g.world_scale else 1 end;
  v_range := (v_base + v_step * v_stables) * v_mult;

  v_cmd := p_commander_id;
  if v_cmd is null or not exists (select 1 from public.commanders c where c.id = v_cmd and c.owner_player_id = v_me and c.game_id = p_game_id) then
    select c.id into v_cmd from public.commanders c where c.game_id = p_game_id and c.owner_player_id = v_me and c.status <> 'dead' order by (c.role = 'king') desc, c.id limit 1;
  end if;
  v_speed := case when v_cmd is null then null else public.march_speed(v_cmd) end;
  v_road_div := sqrt(3 + v_stables);

  v_route := v_dist;
  v_in := v_dist <= v_range;
  v_eta := case when v_speed is null then null else greatest(1, ceil(v_dist / v_speed))::int end;
  if v_cmd is not null and not v_g.free_travel and p_from <> p_to then
    begin
      v_plan := public.plan_march_from(v_me, v_cmd, p_from, p_to);
      v_route := (v_plan ->> 'raw_length')::float8;
      v_in := (v_plan ->> 'in_range')::boolean;
      v_eta := (v_plan ->> 'travel_ticks')::int;
    exception when others then
      v_err := sqlerrm;
      v_in := false;
    end;
  end if;
  v_need := greatest(0, ceil((v_route / v_mult - v_base) / v_step)::int);

  return jsonb_build_object(
    'distance', round(v_route::numeric, 1),
    'leagues', round((v_route / 1500)::numeric, 2),
    'straight_leagues', round((v_dist / 1500)::numeric, 2),
    'follows_trails', v_plan is not null,
    'hops', case when v_plan is null then null else v_plan -> 'hops' end,
    'route_error', v_err,
    'range', round(v_range::numeric, 0),
    'range_leagues', round((v_range / 1500)::numeric, 2),
    'in_range', v_in,
    'stables_needed', v_need,
    'stables', v_stables,
    'speed', round(v_speed::numeric, 1),
    'eta_foot', v_eta,
    'roads', coalesce(v_a.has_road, false) and coalesce(v_b.has_road, false),
    'eta_road', case when v_speed is null then null else greatest(1, ceil(v_route / (v_speed * v_road_div)))::int end
  );
end;
$f$;
