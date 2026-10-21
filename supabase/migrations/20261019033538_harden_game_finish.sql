create or replace function public.finish_game(p_game_id int, p_winner_id int, p_reason text, p_tick int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_winner_user uuid;
  v_faction text;
begin
  update public.games
  set status = 'finished', winner_player_id = p_winner_id, current_turn_ends_at = null
  where id = p_game_id and status = 'active';
  if not found then
    return;
  end if;

  select user_id, faction_slug into v_winner_user, v_faction from public.game_players where id = p_winner_id;

  update public.profiles
  set total_games = total_games + 1
  where user_id in (select user_id from public.game_players where game_id = p_game_id and user_id is not null);

  if v_winner_user is not null then
    update public.profiles set total_wins = total_wins + 1 where user_id = v_winner_user;
  end if;

  perform public.record_intel_snapshot(p_game_id);

  insert into public.game_moments (game_id, tick, type, payload)
  values (p_game_id, p_tick, 'game_won', jsonb_build_object('player_id', p_winner_id, 'faction', v_faction, 'reason', p_reason));
  insert into public.game_events (game_id, tick, type, payload)
  values (p_game_id, p_tick, 'game_finished', jsonb_build_object('winner_player_id', p_winner_id, 'reason', p_reason));

  insert into public.player_inbox (game_id, player_id, type, title, body, tick)
  select p_game_id, gp.id, 'system',
         case when gp.id = p_winner_id then 'Victory' else 'Defeat' end,
         jsonb_build_object('kind', 'game_over', 'result', case when gp.id = p_winner_id then 'victory' else 'defeat' end,
                            'winner_player_id', p_winner_id, 'reason', p_reason),
         p_tick
  from public.game_players gp
  where gp.game_id = p_game_id and not gp.is_ai;
end;
$$;

create or replace function public.concede_defeat(p_game_id int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text;
  v_tick int;
  v_player public.game_players;
  v_end jsonb;
begin
  select status, current_tick into v_status, v_tick from public.games where id = p_game_id for update;
  if v_status is null then
    raise exception 'game not found';
  end if;
  if v_status <> 'active' then
    raise exception 'game is not active';
  end if;

  v_player := public.acting_player(p_game_id);

  perform public.eliminate_player(p_game_id, v_player.id, v_tick, 'conceded');
  v_end := public.evaluate_game_end(p_game_id, v_tick);

  return jsonb_build_object('conceded', true, 'game_finished', v_end -> 'finished', 'winner_player_id', v_end -> 'winner_player_id');
end;
$$;

revoke execute on function public.finish_game(int, int, text, int) from public, anon, authenticated;
revoke execute on function public.concede_defeat(int) from public, anon;
grant execute on function public.concede_defeat(int) to authenticated;
