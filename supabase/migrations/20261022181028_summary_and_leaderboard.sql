create or replace function public.game_summary(p_game_id integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_game public.games%rowtype;
  v_reason text;
begin
  if not exists (select 1 from public.game_players where game_id = p_game_id and user_id = auth.uid()) then
    raise exception 'not a player in this game';
  end if;
  select * into v_game from public.games where id = p_game_id;
  if v_game.status <> 'finished' then
    raise exception 'game is not finished';
  end if;
  select e.payload ->> 'reason' into v_reason
  from public.game_events e where e.game_id = p_game_id and e.type = 'game_finished' order by e.id desc limit 1;

  return jsonb_build_object(
    'game_id', v_game.id,
    'name', v_game.name,
    'ticks', v_game.current_tick,
    'winner_player_id', v_game.winner_player_id,
    'reason', v_reason,
    'players', coalesce((
      select jsonb_agg(jsonb_build_object(
        'player_id', gp.id,
        'name', gp.display_name,
        'faction', gp.faction_slug,
        'is_ai', gp.is_ai,
        'eliminated_at_tick', gp.eliminated_at_tick,
        'castles', (select count(*) from public.game_territories gt where gt.game_id = p_game_id and gt.owner_player_id = gp.id),
        'troops', (select coalesce(sum(gt.troops), 0) from public.game_territories gt where gt.game_id = p_game_id and gt.owner_player_id = gp.id)
                + (select coalesce(sum(c.troops), 0) from public.commanders c where c.game_id = p_game_id and c.owner_player_id = gp.id and c.status <> 'dead'),
        'battles', (select count(*) from public.battle_reports b where b.game_id = p_game_id and gp.id = any (b.involved_player_ids)),
        'infamy', gp.infamy_delta
      ) order by (gp.id = v_game.winner_player_id) desc, (gp.eliminated_at_tick is null) desc, gp.id)
      from public.game_players gp where gp.game_id = p_game_id
    ), '[]'::jsonb)
  );
end;
$function$;

revoke all on function public.game_summary(integer) from public, anon;
grant execute on function public.game_summary(integer) to authenticated;

create or replace function public.get_leaderboard(p_limit integer default 25)
returns table (display_name text, honor integer, infamy integer, total_games integer, total_wins integer)
language sql
stable
security definer
set search_path = ''
as $function$
  select p.display_name, p.honor, p.infamy, p.total_games, p.total_wins
  from public.profiles p
  where p.total_games > 0
  order by p.honor desc, p.total_wins desc, p.display_name
  limit least(greatest(coalesce(p_limit, 25), 1), 100);
$function$;

revoke all on function public.get_leaderboard(integer) from public, anon;
grant execute on function public.get_leaderboard(integer) to authenticated;
