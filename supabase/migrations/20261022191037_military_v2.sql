alter table public.commanders add column if not exists captured_by_player_id integer;
alter table public.commanders add column if not exists ransom integer;
alter table public.commanders add column if not exists wins integer not null default 0;
alter table public.commanders add column if not exists promoted boolean not null default false;
alter table public.game_players add column if not exists morale_until_tick integer;

alter table public.commanders drop constraint if exists commanders_status_check;
alter table public.commanders add constraint commanders_status_check
  check (status = any (array['idle', 'moving', 'sieging', 'dead', 'captured']));

alter table public.commander_abilities drop constraint if exists commander_abilities_ability_check;
alter table public.commander_abilities add constraint commander_abilities_ability_check
  check (ability = any (array['valor', 'tactics', 'siegecraft', 'bulwark', 'muster', 'steward', 'scholar', 'pace', 'scout', 'plunder']));

insert into public.commander_abilities (game_id, commander_id, ability, level)
select c.game_id, c.id, 'bulwark', 0 from public.commanders c
where not exists (select 1 from public.commander_abilities ca where ca.commander_id = c.id and ca.ability = 'bulwark');

insert into public.xp_config (key, value) values ('bulwark_per_cycle', 80), ('bulwark_break_bonus', 300)
on conflict (key) do nothing;

create or replace function public.morale_factor(p_player_id integer, p_tick integer)
returns float8
language sql
stable
security definer
set search_path = ''
as $function$
  select case when exists (
    select 1 from public.game_players where id = p_player_id and morale_until_tick > p_tick
  ) then 0.75 else 1.0 end;
$function$;

create or replace function public.apply_named_death(p_game_id integer, p_ids integer[], p_tick integer)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_c record;
begin
  if p_ids is null then
    return;
  end if;
  for v_c in
    select c.id, c.name, c.owner_player_id
    from public.commanders c
    join public.game_players gp on gp.id = c.owner_player_id
    where c.id = any (p_ids) and c.status <> 'dead' and (c.role = 'king' or c.promoted)
      and gp.eliminated_at_tick is null
    order by c.id
  loop
    update public.realm_areas set prestige_accumulated = greatest(0, prestige_accumulated - 60)
    where player_id = v_c.owner_player_id and is_active;
    update public.game_players set morale_until_tick = p_tick + 24 where id = v_c.owner_player_id;
    perform public.notify_players(
      p_game_id, p_tick, array[v_c.owner_player_id], v_c.name || ' has fallen',
      jsonb_build_object('kind', 'named_death', 'commander_id', v_c.id, 'name', v_c.name, 'morale_until_tick', p_tick + 24)
    );
  end loop;
end;
$function$;

create or replace function public.promote_veterans(p_ids integer[])
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_c record;
  v_epithets text[] := array['the Bold', 'the Steadfast', 'the Grim', 'the Wary', 'the Swift', 'the Stern', 'the Unyielding', 'the Cunning', 'the Patient', 'the Fierce', 'the Resolute', 'the Bright'];
  v_ability text;
  v_name text;
  v_tick int;
begin
  if p_ids is null then
    return;
  end if;
  for v_c in
    select c.id, c.game_id, c.owner_player_id, c.name, c.school
    from public.commanders c
    where c.id = any (p_ids) and c.status <> 'dead' and c.role = 'commander' and not c.promoted and c.wins >= 5
    order by c.id
  loop
    v_name := v_c.name || ' ' || v_epithets[1 + (v_c.id % 12)];
    v_ability := case v_c.school when 'battleschool' then 'valor' when 'university' then 'steward' else 'scout' end;
    update public.commanders set promoted = true, name = v_name where id = v_c.id;
    update public.commander_abilities
    set level = least(level + 1, public.xp_cfg('ability_max_level')::int)
    where commander_id = v_c.id and ability = v_ability;
    select current_tick into v_tick from public.games where id = v_c.game_id;
    perform public.notify_players(
      v_c.game_id, v_tick, array[v_c.owner_player_id], v_name || ' earned a name',
      jsonb_build_object('kind', 'commander_promoted', 'commander_id', v_c.id, 'name', v_name, 'ability', v_ability)
    );
  end loop;
end;
$function$;

create or replace function public.release_captive_core(p_commander_id integer, p_tick integer, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_c public.commanders%rowtype;
  v_t int;
begin
  select * into v_c from public.commanders where id = p_commander_id and status = 'captured' for update;
  if not found then
    return;
  end if;
  select t.id into v_t
  from public.game_territories t
  where t.owner_player_id = v_c.owner_player_id and t.game_id = v_c.game_id
  order by (t.id = (select capital_territory_id from public.game_players where id = v_c.owner_player_id)) desc, t.id
  limit 1;

  if v_t is null then
    perform public.kill_commanders(v_c.game_id, array[v_c.id], p_tick);
    return;
  end if;

  update public.commanders
  set status = 'idle', current_territory_id = v_t, captured_by_player_id = null, ransom = null, troops = 0
  where id = v_c.id;

  perform public.notify_players(
    v_c.game_id, p_tick, array[v_c.owner_player_id, v_c.captured_by_player_id], v_c.name || ' is free',
    jsonb_build_object('kind', 'captive_released', 'commander_id', v_c.id, 'name', v_c.name, 'reason', p_reason)
  );
end;
$function$;

create or replace function public.kill_or_capture(p_game_id integer, p_ids integer[], p_captor integer, p_tick integer)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_c record;
  v_kill int[] := '{}';
  v_cap int[] := '{}';
  v_chance float8;
  v_captor_alive boolean;
begin
  if p_ids is null or array_length(p_ids, 1) is null then
    return;
  end if;
  select p_captor is not null and exists (select 1 from public.game_players where id = p_captor and eliminated_at_tick is null)
  into v_captor_alive;

  for v_c in
    select c.id, c.role, c.owner_player_id, c.name
    from public.commanders c
    where c.id = any (p_ids) and c.status <> 'dead'
    order by c.id
  loop
    if not v_captor_alive or p_captor = v_c.owner_player_id then
      v_kill := v_kill || v_c.id;
      continue;
    end if;
    v_chance := case when v_c.role = 'king' then 0.5 else 0.3 end;
    if random() < v_chance then
      v_cap := v_cap || v_c.id;
    else
      v_kill := v_kill || v_c.id;
    end if;
  end loop;

  if array_length(v_cap, 1) is not null then
    update public.commanders
    set status = 'captured', captured_by_player_id = p_captor, ransom = null, troops = 0, current_territory_id = null
    where id = any (v_cap);
    delete from public.commander_movements where commander_id = any (v_cap);
    update public.commander_routes set status = 'aborted' where commander_id = any (v_cap) and status in ('active', 'recalled');
    update public.game_territories set garrison_commander_id = null where garrison_commander_id = any (v_cap);

    for v_c in select c.id, c.name, c.owner_player_id from public.commanders c where c.id = any (v_cap) order by c.id loop
      insert into public.game_moments (game_id, tick, type, payload, visibility, involved_player_ids)
      values (p_game_id, p_tick, 'commander_captured',
        jsonb_build_object('commander_id', v_c.id, 'name', v_c.name, 'owner_player_id', v_c.owner_player_id, 'captor_player_id', p_captor),
        'private', array[v_c.owner_player_id, p_captor]);
      perform public.notify_players(
        p_game_id, p_tick, array[v_c.owner_player_id, p_captor], v_c.name || ' was captured',
        jsonb_build_object('kind', 'commander_captured', 'commander_id', v_c.id, 'name', v_c.name, 'owner_player_id', v_c.owner_player_id, 'captor_player_id', p_captor)
      );
    end loop;
  end if;

  perform public.kill_commanders(p_game_id, v_kill, p_tick);
end;
$function$;

create or replace function public.set_ransom_core(p_game_id integer, p_captor integer, p_commander_id integer, p_amount integer)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if p_amount is not null and (p_amount < 0 or p_amount > 5000) then
    raise exception 'ransom must be between 0 and 5000';
  end if;
  update public.commanders set ransom = nullif(p_amount, 0)
  where id = p_commander_id and game_id = p_game_id and status = 'captured' and captured_by_player_id = p_captor;
  if not found then
    raise exception 'you are not holding that commander';
  end if;
end;
$function$;

create or replace function public.pay_ransom_core(p_game_id integer, p_owner integer, p_commander_id integer, p_tick integer)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_c public.commanders%rowtype;
begin
  select * into v_c from public.commanders
  where id = p_commander_id and game_id = p_game_id and status = 'captured' and owner_player_id = p_owner for update;
  if not found then
    raise exception 'that commander is not a captive of yours';
  end if;
  if v_c.ransom is null then
    raise exception 'the captor has not named a ransom';
  end if;
  if (select gold from public.game_players where id = p_owner) < v_c.ransom then
    raise exception 'you cannot afford the ransom of %', v_c.ransom;
  end if;
  update public.game_players set gold = gold - v_c.ransom where id = p_owner;
  update public.game_players set gold = gold + v_c.ransom where id = v_c.captured_by_player_id;
  insert into public.ledger (game_id, player_id, tick, type, amount) values
    (p_game_id, p_owner, p_tick, 'send_gold', -v_c.ransom),
    (p_game_id, v_c.captured_by_player_id, p_tick, 'receive_gold', v_c.ransom);
  perform public.release_captive_core(v_c.id, p_tick, 'ransomed');
end;
$function$;

create or replace function public.execute_captive_core(p_game_id integer, p_captor integer, p_commander_id integer, p_tick integer)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_c public.commanders%rowtype;
begin
  select * into v_c from public.commanders
  where id = p_commander_id and game_id = p_game_id and status = 'captured' and captured_by_player_id = p_captor for update;
  if not found then
    raise exception 'you are not holding that commander';
  end if;
  perform public.kill_commanders(p_game_id, array[v_c.id], p_tick);
  update public.game_players set infamy_delta = infamy_delta + 5 where id = p_captor;
  insert into public.game_moments (game_id, tick, type, payload)
  values (p_game_id, p_tick, 'captive_executed', jsonb_build_object('commander_id', v_c.id, 'name', v_c.name, 'owner_player_id', v_c.owner_player_id, 'by_player_id', p_captor));
  perform public.notify_players(
    p_game_id, p_tick, array[v_c.owner_player_id], v_c.name || ' was executed',
    jsonb_build_object('kind', 'captive_executed', 'commander_id', v_c.id, 'name', v_c.name, 'by_player_id', p_captor)
  );
end;
$function$;

create or replace function public.process_captives(p_game_id integer, p_tick integer)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_c record;
begin
  for v_c in
    select c.id, c.owner_player_id, c.captured_by_player_id,
           (select eliminated_at_tick is not null from public.game_players where id = c.owner_player_id) as owner_out,
           (select eliminated_at_tick is not null from public.game_players where id = c.captured_by_player_id) as captor_out
    from public.commanders c
    where c.game_id = p_game_id and c.status = 'captured'
    order by c.id
  loop
    if v_c.owner_out then
      perform public.kill_commanders(p_game_id, array[v_c.id], p_tick);
    elsif v_c.captor_out then
      perform public.release_captive_core(v_c.id, p_tick, 'captor_fell');
    elsif random() < 0.12 then
      perform public.release_captive_core(v_c.id, p_tick, 'escaped');
    end if;
  end loop;
end;
$function$;

create or replace function public.set_ransom(p_game_id integer, p_commander_id integer, p_amount integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_player public.game_players;
begin
  v_player := public.acting_player(p_game_id);
  perform public.set_ransom_core(p_game_id, v_player.id, p_commander_id, p_amount);
  return jsonb_build_object('status', 'ok');
end;
$function$;

create or replace function public.pay_ransom(p_game_id integer, p_commander_id integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_player public.game_players;
begin
  v_player := public.acting_player(p_game_id);
  perform public.pay_ransom_core(p_game_id, v_player.id, p_commander_id, (select current_tick from public.games where id = p_game_id));
  return jsonb_build_object('status', 'released');
end;
$function$;

create or replace function public.execute_captive(p_game_id integer, p_commander_id integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_player public.game_players;
begin
  v_player := public.acting_player(p_game_id);
  perform public.execute_captive_core(p_game_id, v_player.id, p_commander_id, (select current_tick from public.games where id = p_game_id));
  return jsonb_build_object('status', 'executed');
end;
$function$;

create or replace function public.release_captive(p_game_id integer, p_commander_id integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_player public.game_players;
begin
  v_player := public.acting_player(p_game_id);
  if not exists (select 1 from public.commanders where id = p_commander_id and game_id = p_game_id and status = 'captured' and captured_by_player_id = v_player.id) then
    raise exception 'you are not holding that commander';
  end if;
  perform public.release_captive_core(p_commander_id, (select current_tick from public.games where id = p_game_id), 'freed');
  return jsonb_build_object('status', 'released');
end;
$function$;

create or replace function public.ai_captives(p_game_id integer, p_player_id integer, p_difficulty integer)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_c record;
  v_tick int;
begin
  select current_tick into v_tick from public.games where id = p_game_id;

  for v_c in
    select c.id, (select coalesce(sum(level), 0) from public.commander_abilities ca where ca.commander_id = c.id) as rank
    from public.commanders c
    where c.game_id = p_game_id and c.status = 'captured' and c.captured_by_player_id = p_player_id and c.ransom is null
  loop
    update public.commanders set ransom = 60 + 30 * v_c.rank where id = v_c.id;
  end loop;

  for v_c in
    select c.id from public.commanders c
    where c.game_id = p_game_id and c.status = 'captured' and c.owner_player_id = p_player_id and c.ransom is not null
      and (select gold from public.game_players where id = p_player_id) >= c.ransom + 50
    order by c.id
  loop
    begin
      perform public.pay_ransom_core(p_game_id, p_player_id, v_c.id, v_tick);
    exception when others then
      null;
    end;
  end loop;
end;
$function$;

do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.kill_commanders(integer,integer[],integer)'::regprocedure) into v_def;
  v_new := replace(v_def,
    'update public.commanders
  set status = ''dead'', died_tick = p_tick',
    'perform public.apply_named_death(p_game_id, p_ids, p_tick);

  update public.commanders
  set status = ''dead'', died_tick = p_tick');
  if v_new = v_def then raise exception 'kill_commanders patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.fight_castle(integer,integer,integer,integer[],integer)'::regprocedure) into v_def;
  v_new := replace(v_def, 'perform public.kill_commanders(p_game_id, p_att_ids, p_tick);', 'perform public.kill_or_capture(p_game_id, p_att_ids, v_owner, p_tick);');
  v_new := replace(v_new, 'perform public.kill_commanders(p_game_id, v_def_ids, p_tick);', 'perform public.kill_or_capture(p_game_id, v_def_ids, p_player_id, p_tick);');
  if v_new = v_def or v_new not like '%kill_or_capture(p_game_id, v_def_ids%' or v_new not like '%kill_or_capture(p_game_id, p_att_ids%' then raise exception 'fight_castle patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.resolve_intercepts(integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def, 'perform public.kill_commanders(p_game_id, array[v_cmd[v_l]], p_tick);', 'perform public.kill_or_capture(p_game_id, array[v_cmd[v_l]], v_own[v_w], p_tick);');
  if v_new = v_def then raise exception 'resolve_intercepts patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.resolve_relief(integer,integer,integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def, 'perform public.kill_commanders(p_game_id, v_sg, p_tick);', 'perform public.kill_or_capture(p_game_id, v_sg, p_player_id, p_tick);');
  v_new := replace(v_new, 'perform public.kill_commanders(p_game_id, v_arr, p_tick);', 'perform public.kill_or_capture(p_game_id, v_arr, (select owner_player_id from public.commanders where id = v_sg[1]), p_tick);');
  if v_new = v_def or v_new not like '%kill_or_capture(p_game_id, v_arr%' or v_new not like '%kill_or_capture(p_game_id, v_sg%' then raise exception 'resolve_relief patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.sally_core(integer,integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def, 'perform public.kill_commanders(p_game_id, v_sg, v_tick);', 'perform public.kill_or_capture(p_game_id, v_sg, v_player.id, v_tick);');
  v_new := replace(v_new, 'perform public.kill_commanders(p_game_id, v_def, v_tick);', 'perform public.kill_or_capture(p_game_id, v_def, (select owner_player_id from public.commanders where id = v_sg[1]), v_tick);');
  v_new := replace(v_new, 'perform public.award_flat_xp(v_def, ''siegecraft'', public.xp_cfg(''siegecraft_break_bonus''));', 'perform public.award_flat_xp(v_def, ''bulwark'', public.xp_cfg(''bulwark_break_bonus''));');
  if v_new = v_def or v_new not like '%kill_or_capture(p_game_id, v_def%' or v_new not like '%kill_or_capture(p_game_id, v_sg%' or v_new not like '%''bulwark''%' then raise exception 'sally_core patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.award_combat_xp(integer[],integer,integer,boolean)'::regprocedure) into v_def;
  v_new := replace(v_def, 'v_amount := p_loser_troops * least(1.0,', 'update public.commanders set wins = wins + 1 where id = any (p_winner_ids) and status <> ''dead'';
  perform public.promote_veterans(p_winner_ids);
  v_amount := p_loser_troops * least(1.0,');
  if v_new = v_def then raise exception 'award_combat_xp patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.apply_siege_attrition(integer,integer,boolean)'::regprocedure) into v_def;
  v_new := replace(v_def, '0.5 * public.side_ability(v_def, v_t.garrison_commander_id, ''siegecraft'')', '0.5 * public.side_ability(v_def, v_t.garrison_commander_id, ''bulwark'')');
  v_new := replace(v_new, 'public.side_leader(v_def, v_t.garrison_commander_id), ''siegecraft'', public.xp_cfg(''siegecraft_per_cycle'')', 'public.side_leader(v_def, v_t.garrison_commander_id), ''bulwark'', public.xp_cfg(''bulwark_per_cycle'')');
  if v_new = v_def or v_new not like '%''bulwark'', public.xp_cfg(''bulwark_per_cycle'')%' or v_new not like '%v_t.garrison_commander_id, ''bulwark'')%' then raise exception 'apply_siege_attrition patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.award_xp(integer,text,double precision)'::regprocedure) into v_def;
  v_new := replace(v_def, 'when ''battleschool'' then array[''valor'', ''tactics'', ''siegecraft'']', 'when ''battleschool'' then array[''valor'', ''tactics'', ''siegecraft'', ''bulwark'']');
  v_new := replace(v_new, 'p_ability in (''valor'', ''tactics'', ''plunder'', ''siegecraft'')', 'p_ability in (''valor'', ''tactics'', ''plunder'', ''siegecraft'', ''bulwark'')');
  if v_new = v_def then raise exception 'award_xp patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.create_commander(integer,integer,text,text,integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def, '''pace'', ''scout'', ''plunder'']) as a', '''pace'', ''scout'', ''plunder'', ''bulwark'']) as a');
  if v_new = v_def then raise exception 'create_commander patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.run_tick(integer)'::regprocedure) into v_def;
  v_new := replace(v_def, '/ v_game.production_cycle_ticks as total', '/ v_game.production_cycle_ticks * public.morale_factor(gt.owner_player_id, v_tick) as total');
  v_new := replace(v_new, '* (1 + 0.10 * public.territory_ability(gt.id, ''steward''))
        ), 0))::int as gold', '* (1 + 0.10 * public.territory_ability(gt.id, ''steward''))
          * public.morale_factor(gp.id, v_tick)
        ), 0))::int as gold');
  if v_new = v_def or v_new not like '%morale_factor(gp.id, v_tick)%' or v_new not like '%morale_factor(gt.owner_player_id, v_tick)%' then raise exception 'run_tick patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.resolve_tick_events(integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def, '    perform public.process_gold_deals(p_game_id, p_tick);', '    perform public.process_gold_deals(p_game_id, p_tick);
    perform public.process_captives(p_game_id, p_tick);');
  if v_new = v_def then raise exception 'resolve_tick_events patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.ai_take_turn(integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def, '  perform public.ai_offers(p_game_id, p_player_id, v_difficulty);', '  perform public.ai_offers(p_game_id, p_player_id, v_difficulty);
  perform public.ai_captives(p_game_id, p_player_id, v_difficulty);');
  if v_new = v_def then raise exception 'ai_take_turn patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.get_game_view(integer)'::regprocedure) into v_def;
  v_new := replace(v_def, 'where c.game_id = p_game_id and c.status <> ''dead'' and s.seen', 'where c.game_id = p_game_id and c.status not in (''dead'', ''captured'') and s.seen');
  v_new := replace(v_new, '''created_tick'', c.created_tick, ''coronation_tick'', c.coronation_tick', '''created_tick'', c.created_tick, ''coronation_tick'', c.coronation_tick, ''promoted'', c.promoted, ''wins'', c.wins');
  v_new := replace(v_new, '''abilities'', (', '''captives'', (
      select coalesce(jsonb_agg(jsonb_build_object(
        ''id'', c.id, ''name'', c.name, ''school'', c.school, ''role'', c.role, ''owner_player_id'', c.owner_player_id,
        ''captured_by_player_id'', c.captured_by_player_id, ''ransom'', c.ransom,
        ''rank'', (select coalesce(sum(ca.level), 0) from public.commander_abilities ca where ca.commander_id = c.id)
      ) order by c.id), ''[]''::jsonb)
      from public.commanders c
      where c.game_id = p_game_id and c.status = ''captured'' and v_me in (c.owner_player_id, c.captured_by_player_id)
    ),
    ''abilities'', (');
  if v_new = v_def or v_new not like '%''captives''%' or v_new not like '%not in (''dead'', ''captured'')%' or v_new not like '%''promoted'', c.promoted%' then raise exception 'get_game_view patch did not apply'; end if;
  execute v_new;
end
$patch$;

do $grants$
declare
  r record;
begin
  for r in
    select oid::regprocedure as sig from pg_proc
    where pronamespace = 'public'::regnamespace
      and proname in ('morale_factor', 'apply_named_death', 'promote_veterans', 'release_captive_core', 'kill_or_capture', 'set_ransom_core', 'pay_ransom_core', 'execute_captive_core', 'process_captives', 'ai_captives')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
  end loop;
  for r in
    select oid::regprocedure as sig from pg_proc
    where pronamespace = 'public'::regnamespace
      and proname in ('set_ransom', 'pay_ransom', 'execute_captive', 'release_captive')
  loop
    execute format('revoke all on function %s from public, anon', r.sig);
    execute format('grant execute on function %s to authenticated', r.sig);
  end loop;
end
$grants$;
