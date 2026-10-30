create or replace function public.delete_game(p_game_id int)
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

  delete from public.games where id = p_game_id;
end;
$$;

revoke execute on function public.delete_game(int) from public, anon;
grant execute on function public.delete_game(int) to authenticated;
