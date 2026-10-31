create or replace function public.rival_reach(p_game_id int)
returns jsonb
language plpgsql
stable
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
  select id into v_me from public.game_players where game_id = p_game_id and user_id = v_uid;
  if v_me is null then
    raise exception 'you are not in this game';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'player_id', gp.id,
      'watchtowers', coalesce((select ra.level from public.realm_areas ra where ra.player_id = gp.id and ra.area = 'watchtowers'), 0),
      'stables', coalesce((select ra.level from public.realm_areas ra where ra.player_id = gp.id and ra.area = 'stables'), 0)))
    from public.game_players gp
    where gp.game_id = p_game_id
      and gp.id <> v_me
      and exists (
        select 1 from public.game_territories t
        where t.game_id = p_game_id
          and t.owner_player_id = gp.id
          and public.fog_sees(p_game_id, v_me, t.x, t.y))
  ), '[]'::jsonb);
end;
$$;

revoke execute on function public.rival_reach(int) from public, anon;
grant execute on function public.rival_reach(int) to authenticated;
