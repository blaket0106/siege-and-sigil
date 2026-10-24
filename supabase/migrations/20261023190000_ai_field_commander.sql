create or replace function public.ai_garrison(p_game_id integer, p_player_id integer)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_t record;
  v_c int;
  v_free int;
begin
  for v_t in
    select gt.id
    from public.game_territories gt
    where gt.game_id = p_game_id and gt.owner_player_id = p_player_id and gt.garrison_commander_id is null
    order by gt.tier desc, gt.id
  loop
    select count(*) into v_free
    from public.commanders c
    where c.owner_player_id = p_player_id and c.status <> 'dead' and c.role <> 'king'
      and not exists (select 1 from public.game_territories g2 where g2.garrison_commander_id = c.id);
    exit when v_free <= 1;

    v_c := null;
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
$function$;

create or replace function public.ai_hire(p_game_id integer, p_player_id integer, p_difficulty integer)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_game public.games%rowtype;
  v_gold int;
  v_owned int;
  v_want int;
  v_living int;
  v_free int;
  v_terr int;
  v_hired int := 0;
  v_roll float8;
begin
  select * into v_game from public.games where id = p_game_id;
  select count(*) into v_owned from public.game_territories where owner_player_id = p_player_id;
  v_want := least(2 + p_difficulty, greatest(3, v_owned / 2 + 1));

  select t.id into v_terr
  from public.game_territories t
  where t.owner_player_id = p_player_id
  order by (t.id = (select capital_territory_id from public.game_players where id = p_player_id)) desc, t.tier desc, t.id
  limit 1;
  if v_terr is null then
    return;
  end if;

  loop
    select count(*) into v_living from public.commanders where owner_player_id = p_player_id and status <> 'dead';
    select count(*) into v_free
    from public.commanders c
    where c.owner_player_id = p_player_id and c.status <> 'dead' and c.role <> 'king'
      and not exists (select 1 from public.game_territories g2 where g2.garrison_commander_id = c.id);
    select gold into v_gold from public.game_players where id = p_player_id;
    exit when v_hired >= 2 or v_gold < v_game.commander_cost or v_living >= v_want + 2 or (v_living >= v_want and v_free >= 1);
    v_roll := random();
    perform public.hire_commander_core(
      p_game_id, p_player_id, v_terr,
      case when v_roll < 0.5 then 'battleschool' when v_roll < 0.8 then 'rangers' else 'university' end
    );
    v_hired := v_hired + 1;
  end loop;
end;
$function$;
