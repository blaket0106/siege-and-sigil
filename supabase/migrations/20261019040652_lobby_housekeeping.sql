create function public.leave_game(p_game_id int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_game public.games%rowtype;
  v_next uuid;
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;

  select * into v_game from public.games where id = p_game_id for update;
  if not found then
    raise exception 'game not found';
  end if;
  if v_game.status <> 'lobby' then
    raise exception 'you can only leave a game that has not started; use concede_defeat instead';
  end if;
  if not exists (select 1 from public.game_players where game_id = p_game_id and user_id = v_uid) then
    raise exception 'you are not in this game';
  end if;

  if v_game.created_by = v_uid then
    select user_id into v_next
    from public.game_players
    where game_id = p_game_id and user_id is not null and user_id <> v_uid
    order by id
    limit 1;

    if v_next is null then
      delete from public.games where id = p_game_id;
      return jsonb_build_object('left', true, 'game_deleted', true);
    end if;

    update public.games set created_by = v_next where id = p_game_id;
  end if;

  delete from public.game_players where game_id = p_game_id and user_id = v_uid;

  return jsonb_build_object('left', true, 'game_deleted', false, 'new_host', v_next);
end;
$$;

create function public.cancel_game(p_game_id int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_game public.games%rowtype;
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;

  select * into v_game from public.games where id = p_game_id for update;
  if not found then
    raise exception 'game not found';
  end if;
  if v_game.created_by <> v_uid then
    raise exception 'only the game creator can cancel the game';
  end if;
  if v_game.status <> 'lobby' then
    raise exception 'only a game in the lobby can be cancelled';
  end if;

  delete from public.games where id = p_game_id;
end;
$$;

create function public.delete_game(p_game_id int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_game public.games%rowtype;
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;

  select * into v_game from public.games where id = p_game_id for update;
  if not found then
    raise exception 'game not found';
  end if;
  if v_game.created_by <> v_uid then
    raise exception 'only the game creator can delete the game';
  end if;
  if v_game.status <> 'finished' then
    raise exception 'only a finished game can be deleted';
  end if;

  delete from public.games where id = p_game_id;
end;
$$;

revoke execute on function public.leave_game(int) from public, anon;
grant execute on function public.leave_game(int) to authenticated;
revoke execute on function public.cancel_game(int) from public, anon;
grant execute on function public.cancel_game(int) to authenticated;
revoke execute on function public.delete_game(int) from public, anon;
grant execute on function public.delete_game(int) to authenticated;
