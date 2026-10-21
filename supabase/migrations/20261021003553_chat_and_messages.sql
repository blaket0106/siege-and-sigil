create function public.send_chat_message(p_game_id int, p_message text)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_me int;
  v_msg text := trim(coalesce(p_message, ''));
  v_id int;
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;

  select id into v_me from public.game_players where game_id = p_game_id and user_id = v_uid;
  if v_me is null then
    raise exception 'you are not in this game';
  end if;

  if v_msg = '' then
    raise exception 'message is empty';
  end if;
  if char_length(v_msg) > 500 then
    raise exception 'message must be 500 characters or fewer';
  end if;
  if (
    select count(*) from public.game_chat
    where game_id = p_game_id and player_id = v_me and created_at > now() - interval '10 seconds'
  ) >= 8 then
    raise exception 'you are sending messages too fast';
  end if;

  insert into public.game_chat (game_id, player_id, message) values (p_game_id, v_me, v_msg) returning id into v_id;
  return v_id;
end;
$$;

create function public.post_thread_message(p_thread_id int, p_player_id int, p_body text)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_body text := trim(coalesce(p_body, ''));
  v_id int;
begin
  if v_body = '' then
    raise exception 'message is empty';
  end if;
  if char_length(v_body) > 2000 then
    raise exception 'message must be 2000 characters or fewer';
  end if;
  if (
    select count(*) from public.thread_messages
    where player_id = p_player_id and created_at > now() - interval '10 seconds'
  ) >= 8 then
    raise exception 'you are sending messages too fast';
  end if;

  insert into public.thread_messages (thread_id, player_id, body) values (p_thread_id, p_player_id, v_body) returning id into v_id;
  update public.thread_participants set last_read_at = now() where thread_id = p_thread_id and player_id = p_player_id;
  return v_id;
end;
$$;

create function public.create_thread(p_game_id int, p_participant_ids int[], p_first_message text)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_me int;
  v_ids int[];
  v_thread int;
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;

  select id into v_me from public.game_players where game_id = p_game_id and user_id = v_uid;
  if v_me is null then
    raise exception 'you are not in this game';
  end if;

  select array_agg(x order by x) into v_ids
  from (select distinct x from unnest(coalesce(p_participant_ids, '{}') || v_me) as x where x is not null) q;

  if array_length(v_ids, 1) < 2 then
    raise exception 'choose at least one other player';
  end if;
  if array_length(v_ids, 1) > 8 then
    raise exception 'a thread can include at most 8 players';
  end if;
  if (
    select count(*) from public.game_players where game_id = p_game_id and id = any (v_ids) and not is_ai
  ) <> array_length(v_ids, 1) then
    raise exception 'you can only message human players in this game';
  end if;

  select t.id into v_thread
  from public.message_threads t
  where t.game_id = p_game_id
    and (select array_agg(tp.player_id order by tp.player_id) from public.thread_participants tp where tp.thread_id = t.id) = v_ids
  limit 1;

  if v_thread is null then
    insert into public.message_threads (game_id) values (p_game_id) returning id into v_thread;
    insert into public.thread_participants (thread_id, game_id, player_id, last_read_at)
    select v_thread, p_game_id, x, case when x = v_me then now() end from unnest(v_ids) as x;
  end if;

  perform public.post_thread_message(v_thread, v_me, p_first_message);
  return v_thread;
end;
$$;

create function public.send_thread_message(p_thread_id int, p_body text)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_me int;
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;

  select tp.player_id into v_me
  from public.thread_participants tp
  join public.game_players gp on gp.game_id = tp.game_id and gp.id = tp.player_id
  where tp.thread_id = p_thread_id and gp.user_id = v_uid;
  if v_me is null then
    raise exception 'you are not in this thread';
  end if;

  return public.post_thread_message(p_thread_id, v_me, p_body);
end;
$$;

revoke execute on function public.post_thread_message(int, int, text) from public, anon, authenticated;
revoke execute on function public.send_chat_message(int, text) from public, anon;
grant execute on function public.send_chat_message(int, text) to authenticated;
revoke execute on function public.create_thread(int, int[], text) from public, anon;
grant execute on function public.create_thread(int, int[], text) to authenticated;
revoke execute on function public.send_thread_message(int, text) from public, anon;
grant execute on function public.send_thread_message(int, text) to authenticated;

revoke insert, update, delete on public.game_chat, public.message_threads, public.thread_messages from anon, authenticated;
revoke insert, delete on public.thread_participants from anon, authenticated;
revoke update on public.thread_participants from anon;
