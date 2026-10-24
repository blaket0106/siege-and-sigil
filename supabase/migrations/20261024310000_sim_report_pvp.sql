create or replace function public.sim_report(p_game integer)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $f$
select jsonb_build_object(
  'tick', (select current_tick from public.games where id = p_game),
  'castles', (select jsonb_agg(c order by c desc) from (select (select count(*) from public.game_territories t where t.owner_player_id = gp.id and not t.is_junction) c from public.game_players gp where gp.game_id = p_game) q),
  'first_capture', (select min(tick) from public.game_moments where game_id = p_game and type = 'castle_captured'),
  'captures', (select count(*) from public.game_moments where game_id = p_game and type = 'castle_captured'),
  'pvp_captures', (select count(*) from public.game_moments where game_id = p_game and type = 'castle_captured' and (payload ->> 'from_player_id') is not null),
  'sieges', (select count(*) from public.game_moments where game_id = p_game and type = 'siege_started'),
  'first_pvp_battle', (select min(tick) from public.battle_reports b where b.game_id = p_game and (b.report -> 'sides' -> 0 ->> 'player_id') is not null and (b.report -> 'sides' -> 1 ->> 'player_id') is not null),
  'pvp_battles', (select count(*) from public.battle_reports b where b.game_id = p_game and (b.report -> 'sides' -> 0 ->> 'player_id') is not null and (b.report -> 'sides' -> 1 ->> 'player_id') is not null),
  'battles', (select count(*) from public.battle_reports where game_id = p_game),
  'gold_avg', (select round(avg(gold)) from public.game_players where game_id = p_game)
) $f$;
