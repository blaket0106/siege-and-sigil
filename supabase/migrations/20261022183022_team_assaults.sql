do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.fight_castle(integer,integer,integer,integer[],integer)'::regprocedure) into v_def;
  v_new := v_def;

  v_new := replace(v_new,
    '  v_report int;
begin',
    '  v_report int;
  v_att_players int[];
begin');

  v_new := replace(v_new,
    '  v_att_armory := public.armory_level(p_player_id);',
    '  select coalesce(array_agg(distinct c.owner_player_id), ''{}'') || p_player_id into v_att_players
  from public.commanders c where c.id = any (p_att_ids);
  v_att_armory := greatest(
    public.armory_level(p_player_id),
    coalesce((select max(public.armory_level(c.owner_player_id)) from public.commanders c where c.id = any (p_att_ids)), 0)
  );');

  v_new := replace(v_new,
    'case when (pid = p_player_id) = v_attacker_wins then ''victory'' else ''defeat'' end',
    'case when (pid = any (v_att_players)) = v_attacker_wins then ''victory'' else ''defeat'' end');

  v_new := replace(v_new,
    '''role'', case when pid = p_player_id then ''attacker'' else ''defender'' end',
    '''role'', case when pid = any (v_att_players) then ''attacker'' else ''defender'' end');

  v_new := replace(v_new,
    'from (select p_player_id as pid union select v_owner where v_owner is not null) as involved;',
    'from (
    select unnest(v_att_players) as pid
    union select v_owner where v_owner is not null
    union select c.owner_player_id from public.commanders c where c.id = any (v_def_ids)
  ) as involved;');

  if v_new = v_def or v_new not like '%v_att_players%' then
    raise exception 'fight_castle patch did not apply';
  end if;
  execute v_new;
end
$patch$;

create or replace function public.resolve_assault(p_game_id integer, p_territory_id integer, p_player_id integer, p_tick integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_att_ids int[];
  v_cid int;
begin
  select array_agg(m.commander_id order by (c.owner_player_id = p_player_id) desc, m.id) into v_att_ids
  from public.commander_movements m
  join public.commanders c on c.id = m.commander_id
  where m.game_id = p_game_id
    and m.contact_territory_id = p_territory_id
    and m.march_type = 'assault'
    and (c.owner_player_id = p_player_id or public.are_allied(p_player_id, c.owner_player_id));

  if v_att_ids is null then
    return null;
  end if;

  if public.is_friendly_territory(p_player_id, p_territory_id) then
    foreach v_cid in array v_att_ids loop
      update public.commanders set status = 'idle', current_territory_id = p_territory_id where id = v_cid;
      delete from public.commander_movements where commander_id = v_cid;
      perform public.continue_route(v_cid, p_territory_id);
    end loop;
    return jsonb_build_object('territory_id', p_territory_id, 'arrived', true);
  end if;

  return public.fight_castle(p_game_id, p_territory_id, p_player_id, v_att_ids, p_tick);
end;
$function$;
