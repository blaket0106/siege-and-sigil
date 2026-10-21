update public.xp_config set value = 450 where key = 'xp_base_cost';

create function public.ai_garrison(p_game_id int, p_player_id int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_t record;
  v_c int;
begin
  for v_t in
    select gt.id
    from public.game_territories gt
    where gt.game_id = p_game_id and gt.owner_player_id = p_player_id and gt.garrison_commander_id is null
    order by gt.tier desc, gt.id
  loop
    select c.id into v_c
    from public.commanders c
    where c.current_territory_id = v_t.id
      and c.owner_player_id = p_player_id
      and c.status = 'idle'
      and c.role <> 'king'
      and not exists (select 1 from public.game_territories g2 where g2.garrison_commander_id = c.id)
    order by c.troops, c.id
    limit 1;

    if v_c is not null then
      update public.game_territories set garrison_commander_id = v_c where id = v_t.id;
    end if;
  end loop;
end;
$$;

revoke execute on function public.ai_garrison(int, int) from public, anon, authenticated;

create or replace function public.ai_take_turn(p_game_id int, p_player_id int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_difficulty int;
begin
  select ai_difficulty into v_difficulty from public.games where id = p_game_id;

  perform public.ai_diplomacy(p_game_id, p_player_id, v_difficulty);
  perform public.ai_pick_area(p_player_id);
  perform public.ai_crown(p_game_id, p_player_id);
  perform public.ai_hire(p_game_id, p_player_id, v_difficulty);
  perform public.ai_garrison(p_game_id, p_player_id);
  perform public.ai_commanders(p_game_id, p_player_id, v_difficulty);
  perform public.ai_spend(p_game_id, p_player_id, v_difficulty);
end;
$$;
