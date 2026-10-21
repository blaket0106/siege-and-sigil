create or replace function public.create_commander(
  p_game_id int,
  p_player_id int,
  p_school text,
  p_role text,
  p_territory_id int,
  p_tick int
)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id int;
  v_school_abilities text[] := case p_school
    when 'battleschool' then array['valor', 'tactics', 'siegecraft']
    when 'university' then array['muster', 'steward', 'scholar']
    when 'rangers' then array['pace', 'scout', 'plunder']
  end;
  v_pick text;
begin
  if v_school_abilities is null then
    raise exception 'unknown school: %', p_school;
  end if;

  v_pick := v_school_abilities[1 + floor(random() * 3)::int];

  insert into public.commanders (game_id, owner_player_id, name, school, role, current_territory_id, created_tick)
  values (p_game_id, p_player_id, public.random_commander_name(p_game_id), p_school, p_role, p_territory_id, p_tick)
  returning id into v_id;

  insert into public.commander_abilities (game_id, commander_id, ability, level)
  select p_game_id, v_id, a, case when a = v_pick then 1 else 0 end
  from unnest(array['valor', 'tactics', 'siegecraft', 'muster', 'steward', 'scholar', 'pace', 'scout', 'plunder']) as a;

  return v_id;
end;
$$;

revoke execute on function public.create_commander(int, int, text, text, int, int) from public, anon, authenticated;
