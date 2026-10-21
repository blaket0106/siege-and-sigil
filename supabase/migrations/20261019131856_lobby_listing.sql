create function public.list_open_games()
returns table (
  id int,
  name text,
  host_name text,
  max_players int,
  player_count int,
  taken_factions text[],
  map_style text,
  map_size text,
  tick_speed text,
  fill_with_ai boolean,
  victory_pct float8,
  fog_of_war boolean,
  created_at timestamptz,
  joined boolean
)
language sql
stable
security definer
set search_path = ''
as $$
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
    exists (select 1 from public.game_players gp where gp.game_id = g.id and gp.user_id = (select auth.uid()))
  from public.games g
  where g.status = 'lobby'
    and (select auth.uid()) is not null
  order by g.created_at desc
  limit 100;
$$;

revoke execute on function public.list_open_games() from public, anon;
grant execute on function public.list_open_games() to authenticated;
