alter table public.games add column if not exists unit_scale float8 not null default 10;
alter table public.games add column if not exists league boolean not null default true;
update public.games set unit_scale = world_scale, league = false where league;
grant select (unit_scale, league) on public.games to authenticated;

do $patch$
declare
  v_def text;
  v_new text;
  v_fn text;
  v_pairs text[];
  i int;
begin
  for v_fn, v_pairs in
    select * from (values
      ('get_game_view', array['v_g.world_scale', 'v_g.unit_scale']),
      ('players_seeing', array['g.world_scale', 'g.unit_scale']),
      ('update_explored', array['v_g.world_scale', 'v_g.unit_scale']),
      ('can_trade', array['g.world_scale', 'g.unit_scale']),
      ('resolve_intercepts', array['(select world_scale from public.games where id = p_game_id)', '(select unit_scale from public.games where id = p_game_id)']),
      ('plan_march_free', array['v_g.world_scale', 'v_g.unit_scale']),
      ('send_on_route', array['v_game.world_scale', 'v_game.unit_scale']),
      ('ai_commanders', array['''stables''), 0)) * v_game.world_scale;', '''stables''), 0)) * v_game.unit_scale;']),
      ('plan_march', array[
        '(select g.world_scale from public.games g where g.id = v_c.game_id)',
        '(select g.unit_scale from public.games g where g.id = v_c.game_id)',
        'else 90 + 60 * coalesce(v_stables, 0) end',
        'else (90 + 60 * coalesce(v_stables, 0)) * (select case when g.league then g.unit_scale else 1 end from public.games g where g.id = v_c.game_id) end'
      ]),
      ('plan_march_from', array[
        '(select g.world_scale from public.games g where g.id = v_c.game_id)',
        '(select g.unit_scale from public.games g where g.id = v_c.game_id)',
        'else 90 + 60 * coalesce(v_stables, 0) end',
        'else (90 + 60 * coalesce(v_stables, 0)) * (select case when g.league then g.unit_scale else 1 end from public.games g where g.id = v_c.game_id) end'
      ]),
      ('march_speed', array[
        'case when g.free_travel then (1 + g.world_scale) / 2.0',
        'case when g.league then g.unit_scale when g.free_travel then (1 + g.world_scale) / 2.0'
      ])
    ) as t(fn, pairs)
  loop
    select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = v_fn and p.pronamespace = 'public'::regnamespace order by p.oid limit 1;
    v_new := v_def;
    for i in 1 .. array_length(v_pairs, 1) / 2 loop
      if position(v_pairs[2 * i - 1] in v_new) = 0 then
        raise exception '% patch % did not match', v_fn, i;
      end if;
      v_new := replace(v_new, v_pairs[2 * i - 1], v_pairs[2 * i]);
    end loop;
    execute v_new;
  end loop;
end;
$patch$;

create function public.ruler(p_game_id int, p_from int, p_to int, p_commander_id int default null)
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
  v_stables int;
  v_cmd int;
  v_speed float8;
  v_mult float8;
  v_base float8;
  v_step float8;
  v_need int;
  v_range float8;
  v_road_div float8;
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
  v_need := greatest(0, ceil((v_dist / v_mult - v_base) / v_step)::int);

  v_cmd := p_commander_id;
  if v_cmd is null or not exists (select 1 from public.commanders c where c.id = v_cmd and c.owner_player_id = v_me and c.game_id = p_game_id) then
    select c.id into v_cmd from public.commanders c where c.game_id = p_game_id and c.owner_player_id = v_me and c.status <> 'dead' order by (c.role = 'king') desc, c.id limit 1;
  end if;
  v_speed := case when v_cmd is null then null else public.march_speed(v_cmd) end;
  v_road_div := sqrt(3 + v_stables);

  return jsonb_build_object(
    'distance', round(v_dist::numeric, 1),
    'leagues', round((v_dist / 1500)::numeric, 2),
    'range', round(v_range::numeric, 0),
    'range_leagues', round((v_range / 1500)::numeric, 2),
    'in_range', v_dist <= v_range,
    'stables_needed', v_need,
    'stables', v_stables,
    'speed', round(v_speed::numeric, 1),
    'eta_foot', case when v_speed is null then null else greatest(1, ceil(v_dist / v_speed))::int end,
    'roads', coalesce(v_a.has_road, false) and coalesce(v_b.has_road, false),
    'eta_road', case when v_speed is null then null else greatest(1, ceil(v_dist / (v_speed * v_road_div)))::int end
  );
end;
$f$;
revoke execute on function public.ruler(int, int, int, int) from public, anon;
grant execute on function public.ruler(int, int, int, int) to authenticated;
