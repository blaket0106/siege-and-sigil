create function public.my_attack_stats(p_game_id int, p_commander_ids int[] default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $f$
declare
  v_me int;
  v_ids int[];
  v_armory int;
  v_valor int;
begin
  select id into v_me from public.game_players where game_id = p_game_id and user_id = auth.uid();
  if v_me is null then
    return null;
  end if;
  select coalesce(array_agg(c.id), '{}') into v_ids
  from public.commanders c
  where c.id = any (coalesce(p_commander_ids, '{}')) and c.game_id = p_game_id and c.owner_player_id = v_me and c.status <> 'dead';
  v_armory := public.armory_level(v_me);
  v_valor := public.side_valor(v_ids, null);
  return jsonb_build_object('armory', v_armory, 'valor', v_valor, 'damage', greatest(1, v_armory + v_valor));
end;
$f$;

revoke execute on function public.my_attack_stats(int, int[]) from public, anon;
grant execute on function public.my_attack_stats(int, int[]) to authenticated;
