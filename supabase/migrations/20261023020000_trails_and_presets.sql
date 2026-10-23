alter table public.games
  add column if not exists map_preset text not null default 'continental' check (map_preset in ('continental', 'highlands', 'river_valley', 'forest', 'plains')),
  add column if not exists travel_mode text not null default 'free' check (travel_mode in ('free', 'trails'));
grant select (map_preset, travel_mode) on public.games to authenticated;

alter table public.territory_edges add column if not exists path jsonb;
alter table public.game_territories
  add column if not exists crossing_kind text check (crossing_kind in ('river', 'pass')),
  add column if not exists river_idx int;

do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.create_game(jsonb)'::regprocedure) into v_def;
  v_new := replace(v_def, '''world_scale'', ''free_travel'', ''fog_dark'',', '''world_scale'', ''free_travel'', ''travel_mode'', ''map_preset'', ''fog_dark'',');
  v_new := replace(v_new, 'free_travel = coalesce((p_settings ->> ''free_travel'')::boolean, true),', 'free_travel = case when p_settings ->> ''travel_mode'' = ''trails'' then false else coalesce((p_settings ->> ''free_travel'')::boolean, true) end,
      travel_mode = coalesce(p_settings ->> ''travel_mode'', g.travel_mode),
      map_preset = coalesce(p_settings ->> ''map_preset'', g.map_preset),');
  if v_new = v_def or v_new not like '%''travel_mode'', ''map_preset'',%' or v_new not like '%map_preset = coalesce%' then
    raise exception 'create_game patch did not apply';
  end if;
  execute v_new;

  select pg_get_functiondef('public.commit_world(integer,jsonb)'::regprocedure) into v_def;
  v_new := replace(v_def, 'where t.e ->> ''owner_seat'' is null' || chr(10) || '  ) % v_players', 'where t.e ->> ''owner_seat'' is null and not coalesce((t.e ->> ''crossing'')::boolean, false)' || chr(10) || '  ) % v_players');
  v_new := replace(v_new, 'resources, has_road' || chr(10) || '    ) values (', 'resources, has_road, crossing_kind, river_idx' || chr(10) || '    ) values (');
  v_new := replace(v_new, 'coalesce((v_t ->> ''has_road'')::boolean, false)' || chr(10) || '    )', 'coalesce((v_t ->> ''has_road'')::boolean, false),' || chr(10) || '      v_t ->> ''crossing_kind'',' || chr(10) || '      (v_t ->> ''river_idx'')::int' || chr(10) || '    )');
  v_new := replace(v_new, 'kind, length, move_cost_mult, defense_mult' || chr(10) || '  )' || chr(10) || '  select', 'kind, length, move_cost_mult, defense_mult, path' || chr(10) || '  )' || chr(10) || '  select');
  v_new := replace(v_new, 'coalesce((e.e ->> ''defense_mult'')::float8, 1)' || chr(10) || '  from', 'coalesce((e.e ->> ''defense_mult'')::float8, 1),' || chr(10) || '    e.e -> ''path''' || chr(10) || '  from');
  if v_new = v_def or v_new not like '%not coalesce((t.e ->> ''crossing'')%' or v_new not like '%crossing_kind, river_idx%' or v_new not like '%v_t ->> ''crossing_kind''%' or v_new not like '%defense_mult, path%' or v_new not like '%e.e -> ''path''%' then
    raise exception 'commit_world patch did not apply';
  end if;
  execute v_new;

  select pg_get_functiondef('public.get_game_view(integer)'::regprocedure) into v_def;
  v_new := replace(v_def, '''terrain'', t.terrain, ''seen'', v.seen', '''terrain'', t.terrain, ''crossing_kind'', t.crossing_kind, ''seen'', v.seen');
  if v_new = v_def then
    raise exception 'get_game_view patch did not apply';
  end if;
  execute v_new;

  select pg_get_functiondef('public.plan_march(integer,integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def, 'v_range := 90 + 60 * coalesce(v_stables, 0);', 'v_range := case when (select g.travel_mode from public.games g where g.id = v_c.game_id) = ''trails''
    then (300 + 120 * coalesce(v_stables, 0)) * (select g.world_scale from public.games g where g.id = v_c.game_id)
    else 90 + 60 * coalesce(v_stables, 0) end;');
  if v_new = v_def then
    raise exception 'plan_march patch did not apply';
  end if;
  execute v_new;

  select pg_get_functiondef('public.march_speed(integer)'::regprocedure) into v_def;
  v_new := replace(v_def, 'case when g.free_travel then (1 + g.world_scale) / 2.0 else 1.0 end', 'case when g.free_travel then (1 + g.world_scale) / 2.0 when g.travel_mode = ''trails'' then g.world_scale else 1.0 end');
  if v_new = v_def then
    raise exception 'march_speed patch did not apply';
  end if;
  execute v_new;
end;
$patch$;

drop function if exists public.get_game_edges(integer);

create function public.get_game_edges(p_game_id integer)
returns table(game_id integer, from_territory_id integer, to_territory_id integer, kind text, length double precision, move_cost_mult double precision, defense_mult double precision, path jsonb)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_g public.games%rowtype;
  v_exp text;
begin
  if (select auth.uid()) is null then
    raise exception 'not signed in';
  end if;
  if not public.is_game_member(p_game_id) then
    raise exception 'you are not in this game';
  end if;
  select * into v_g from public.games where id = p_game_id;
  if v_g.status = 'picking' and v_g.fog_dark then
    return;
  end if;
  if v_g.status = 'active' and v_g.fog_of_war and v_g.fog_dark then
    select gp.explored into v_exp from public.game_players gp where gp.game_id = p_game_id and gp.user_id = (select auth.uid());
    return query
      select e.game_id, e.from_territory_id, e.to_territory_id, e.kind, e.length, e.move_cost_mult, e.defense_mult, e.path
      from public.territory_edges e
      join public.game_territories a on a.id = e.from_territory_id
      join public.game_territories b on b.id = e.to_territory_id
      where e.game_id = p_game_id
        and coalesce(substr(v_exp, 1 + least(47, floor(a.x / v_g.map_w * 48)::int) + 48 * least(47, floor(a.y / v_g.map_h * 48)::int), 1), '0') = '1'
        and coalesce(substr(v_exp, 1 + least(47, floor(b.x / v_g.map_w * 48)::int) + 48 * least(47, floor(b.y / v_g.map_h * 48)::int), 1), '0') = '1';
  else
    return query
      select e.game_id, e.from_territory_id, e.to_territory_id, e.kind, e.length, e.move_cost_mult, e.defense_mult, e.path
      from public.territory_edges e where e.game_id = p_game_id;
  end if;
end;
$function$;

revoke all on function public.get_game_edges(integer) from public, anon;
grant execute on function public.get_game_edges(integer) to authenticated;
