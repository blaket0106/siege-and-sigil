alter table public.games add column if not exists fog_dark boolean not null default false;
grant select (fog_dark) on public.games to authenticated;
alter table public.game_players add column if not exists explored text;

create or replace function public.update_explored(p_game_id integer)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_g public.games%rowtype;
  v_cs float8;
begin
  select * into v_g from public.games where id = p_game_id;
  v_cs := v_g.map_w / 48.0;
  update public.game_players gp
  set explored = (
    with src as (
      select t.x, t.y,
             ((90 + 60 * coalesce((select ra.level from public.realm_areas ra where ra.player_id = gp.id and ra.area = 'watchtowers'), 0)) * v_g.world_scale)::float8 as r
      from public.game_territories t
      where t.game_id = p_game_id and t.owner_player_id = gp.id
      union all
      select coalesce(t.x, mp.x), coalesce(t.y, mp.y),
             ((45 + 15 * coalesce((select sum(ca.level) from public.commander_abilities ca where ca.commander_id = c.id), 0)
                  + 30 * coalesce((select max(ca.level) from public.commander_abilities ca where ca.commander_id = c.id and ca.ability = 'scout'), 0)) * v_g.world_scale)::float8
      from public.commanders c
      left join public.game_territories t on t.id = c.current_territory_id
      left join public.commander_movements m on m.commander_id = c.id
      left join lateral public.fog_movement_pos(m.path, m.path_arrival_ticks, v_g.current_tick::float8) mp on true
      where c.game_id = p_game_id and c.owner_player_id = gp.id and c.status not in ('dead', 'captured')
    )
    select string_agg(
      case when coalesce(substr(gp.explored, i, 1), '0') = '1'
             or exists (select 1 from src s where s.x is not null and sqrt(((((i - 1) % 48) + 0.5) * v_cs - s.x) ^ 2 + (((((i - 1) / 48) + 0.5) * v_cs - s.y)) ^ 2) <= s.r + v_cs * 0.7)
           then '1' else '0' end, '' order by i)
    from generate_series(1, 2304) i
  )
  where gp.game_id = p_game_id and not gp.is_ai and gp.eliminated_at_tick is null;
end;
$function$;

revoke all on function public.update_explored(integer) from public, anon, authenticated;

create or replace function public.explore_on_tick()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform public.update_explored(new.id);
  return new;
end;
$function$;

revoke all on function public.explore_on_tick() from public, anon, authenticated;

drop trigger if exists explore_on_tick on public.games;
create trigger explore_on_tick
  after update on public.games
  for each row
  when (new.fog_dark and new.fog_of_war and new.status = 'active'
        and (old.current_tick is distinct from new.current_tick or old.status is distinct from new.status))
  execute function public.explore_on_tick();

do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.get_game_view(integer)'::regprocedure) into v_def;
  v_new := replace(v_def, '  v_tf float8;', '  v_tf float8;
  v_exp text;');
  v_new := replace(v_new, '  v_fog := v_g.fog_of_war and v_g.status = ''active'';', '  v_fog := v_g.fog_of_war and v_g.status = ''active'';
  select gp.explored into v_exp from public.game_players gp where gp.id = v_me;');
  v_new := replace(v_new, '      from public.game_territories t join vis v on v.id = t.id
      where t.game_id = p_game_id
', '      from public.game_territories t join vis v on v.id = t.id
      where t.game_id = p_game_id
        and (not (v_fog and v_g.fog_dark) or v.seen
          or coalesce(substr(v_exp, 1 + least(47, floor(t.x / v_g.map_w * 48)::int) + 48 * least(47, floor(t.y / v_g.map_h * 48)::int), 1), ''0'') = ''1'')
');
  v_new := replace(v_new, '    ''sources'', (', '    ''explored'', case when v_fog and v_g.fog_dark then coalesce(v_exp, '''') end,
    ''sources'', (');
  if v_new = v_def or v_new not like '%v_exp text%' or v_new not like '%select gp.explored%' or v_new not like '%least(47, floor(t.x%' or v_new not like '%''explored'', case%' then
    raise exception 'get_game_view patch did not apply';
  end if;
  execute v_new;

  select pg_get_functiondef('public.create_game(jsonb)'::regprocedure) into v_def;
  v_new := replace(v_def, '''world_scale'', ''free_travel'',', '''world_scale'', ''free_travel'', ''fog_dark'',');
  v_new := replace(v_new, 'world_scale = coalesce((p_settings ->> ''world_scale'')::float8, 3),', 'fog_dark = coalesce((p_settings ->> ''fog_dark'')::boolean, g.fog_dark),
      world_scale = coalesce((p_settings ->> ''world_scale'')::float8, 3),');
  if v_new = v_def or v_new not like '%''fog_dark'',%' or v_new not like '%fog_dark = coalesce%' then
    raise exception 'create_game patch did not apply';
  end if;
  execute v_new;
end;
$patch$;
