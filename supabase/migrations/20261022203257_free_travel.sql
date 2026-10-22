alter table public.games add column if not exists world_scale double precision not null default 1 check (world_scale between 1 and 5);
alter table public.games add column if not exists free_travel boolean not null default false;
grant select (world_scale, free_travel) on public.games to authenticated;

create or replace function public.plan_march_free(p_player_id integer, p_commander_id integer, p_to_territory_id integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_c public.commanders%rowtype;
  v_g public.games%rowtype;
  v_src public.game_territories%rowtype;
  v_dst public.game_territories%rowtype;
  v_e public.territory_edges%rowtype;
  v_road boolean;
  v_cost float8;
  v_speed float8;
  v_stables int;
  v_range float8;
  v_ticks int;
begin
  select * into v_c from public.commanders where id = p_commander_id;
  select * into v_g from public.games where id = v_c.game_id;
  select * into v_src from public.game_territories where id = v_c.current_territory_id;
  select * into v_dst from public.game_territories where id = p_to_territory_id and game_id = v_c.game_id;
  if not found then
    raise exception 'unknown destination territory';
  end if;
  if v_src.id = v_dst.id then
    raise exception 'commander is already there';
  end if;
  if v_dst.owner_player_id is not null and public.are_truced(p_player_id, v_dst.owner_player_id) then
    raise exception 'you have a truce or pact with that player';
  end if;

  select * into v_e from public.territory_edges
  where game_id = v_c.game_id and from_territory_id = least(v_src.id, v_dst.id) and to_territory_id = greatest(v_src.id, v_dst.id);
  if not found then
    raise exception 'no direct route: the sea, a river or a mountain range is in the way; cross at a ford or pass';
  end if;

  v_road := v_src.has_road and v_dst.has_road;
  v_cost := v_e.length * v_e.move_cost_mult / case when v_road then 3.0 else 1.0 end;
  v_speed := public.march_speed(p_commander_id);
  v_ticks := greatest(1, ceil(v_cost / v_speed)::int);

  select coalesce(level, 0) into v_stables from public.realm_areas where player_id = p_player_id and area = 'stables';
  v_range := (210 + 60 * coalesce(v_stables, 0)) * v_g.world_scale;

  return jsonb_build_object(
    'from_territory_id', v_src.id,
    'to_territory_id', v_dst.id,
    'path', to_jsonb(array[v_src.id, v_dst.id]),
    'offsets', to_jsonb(array[0, v_ticks]),
    'travel_ticks', v_ticks,
    'raw_length', round(v_e.length::numeric, 3),
    'speed', v_speed,
    'range', v_range,
    'hops', 1,
    'kind', v_e.kind,
    'in_range', v_e.length <= v_range
  );
end;
$function$;

revoke all on function public.plan_march_free(integer, integer, integer) from public, anon, authenticated;

do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.plan_march(integer,integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def,
    '  select array_agg(id order by id), array_agg(owner_player_id order by id), array_agg(has_road order by id)',
    '  if (select free_travel from public.games where id = v_c.game_id) then
    return public.plan_march_free(p_player_id, p_commander_id, p_to_territory_id);
  end if;

  select array_agg(id order by id), array_agg(owner_player_id order by id), array_agg(has_road order by id)');
  if v_new = v_def then raise exception 'plan_march patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.march_speed(integer)'::regprocedure) into v_def;
  v_new := replace(v_def, '* public.season_move_factor(g.id, g.current_tick)', '* public.season_move_factor(g.id, g.current_tick) * case when g.free_travel then (1 + g.world_scale) / 2.0 else 1.0 end');
  if v_new = v_def then raise exception 'march_speed patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.get_game_view(integer)'::regprocedure) into v_def;
  v_new := replace(v_def, '(90 + 60 * coalesce(wl.level, 0))::float8', '((90 + 60 * coalesce(wl.level, 0)) * v_g.world_scale)::float8');
  v_new := replace(v_new, '(45 + 15 * coalesce(rk.rank, 0) + 30 * coalesce(rk.scout, 0))::float8', '((45 + 15 * coalesce(rk.rank, 0) + 30 * coalesce(rk.scout, 0)) * v_g.world_scale)::float8');
  if v_new = v_def or v_new not like '%v_g.world_scale)::float8%' then raise exception 'get_game_view patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.resolve_intercepts(integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def, 'continue when v_dist > 20.2;', 'continue when v_dist > 20.2 * (select world_scale from public.games where id = p_game_id);');
  if v_new = v_def then raise exception 'resolve_intercepts patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.create_game(jsonb)'::regprocedure) into v_def;
  v_new := replace(v_def, '''seasons_enabled'', ''season_length_ticks'',', '''world_scale'', ''free_travel'', ''seasons_enabled'', ''season_length_ticks'',');
  v_new := replace(v_new, 'seasons_enabled = coalesce((p_settings ->> ''seasons_enabled'')::boolean, g.seasons_enabled),', 'world_scale = coalesce((p_settings ->> ''world_scale'')::float8, 3),
      free_travel = coalesce((p_settings ->> ''free_travel'')::boolean, true),
      seasons_enabled = coalesce((p_settings ->> ''seasons_enabled'')::boolean, g.seasons_enabled),');
  if v_new = v_def or v_new not like '%world_scale = coalesce%' or v_new not like '%''world_scale'', ''free_travel''%' then raise exception 'create_game patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.ai_commanders(integer,integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def, '  v_own_dist float8[];
begin', '  v_own_dist float8[];
  v_range float8;
begin');
  v_new := replace(v_new, '  v_armory := public.armory_level(p_player_id);
', '  v_armory := public.armory_level(p_player_id);
  v_range := (210 + 60 * coalesce((select level from public.realm_areas where player_id = p_player_id and area = ''stables''), 0)) * v_game.world_scale;
');
  v_new := replace(v_new, '      select gt.*
      from public.game_territories gt
      where gt.id = any (v_frontier)
      order by gt.id', '      select gt.*
      from public.game_territories gt
      where gt.game_id = p_game_id
        and not (gt.id = any (v_friendly))
        and (
          (not v_game.free_travel and gt.id = any (v_frontier))
          or (v_game.free_travel and exists (
            select 1 from public.territory_edges e
            where e.game_id = p_game_id and e.length <= v_range
              and ((e.from_territory_id = v_c.current_territory_id and e.to_territory_id = gt.id)
                or (e.to_territory_id = v_c.current_territory_id and e.from_territory_id = gt.id))
          ))
        )
      order by gt.id');
  v_new := replace(v_new, '      join public.game_territories gt on gt.id = d.id
      order by d.dist asc nulls last, gt.troops desc, gt.id', '      join public.game_territories gt on gt.id = d.id
      where not v_game.free_travel or exists (
        select 1 from public.territory_edges e
        where e.game_id = p_game_id and e.length <= v_range
          and ((e.from_territory_id = v_c.current_territory_id and e.to_territory_id = gt.id)
            or (e.to_territory_id = v_c.current_territory_id and e.from_territory_id = gt.id))
      )
      order by d.dist asc nulls last, gt.troops desc, gt.id');
  if v_new = v_def or v_new not like '%v_range float8%' or v_new not like '%v_game.free_travel and exists%' or v_new not like '%not v_game.free_travel or exists%' then raise exception 'ai_commanders patch did not apply'; end if;
  execute v_new;
end
$patch$;
