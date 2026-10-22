alter table public.realm_areas add column if not exists banked_level integer;
alter table public.commanders add column if not exists council_area text;

create table if not exists public.council_members (
  id serial primary key,
  game_id integer not null references public.games (id) on delete cascade,
  player_id integer not null,
  area text not null,
  name text not null,
  status text not null default 'seated' check (status in ('seated', 'afield', 'dead')),
  commander_id integer references public.commanders (id) on delete set null,
  created_tick integer not null default 0,
  died_tick integer,
  foreign key (game_id, player_id) references public.game_players (game_id, id) on delete cascade
);
create unique index if not exists council_members_live on public.council_members (player_id, area) where status <> 'dead';
create index if not exists council_members_game_idx on public.council_members (game_id);
alter table public.council_members enable row level security;
revoke all on public.council_members from anon, authenticated;

create or replace function public.create_council_member()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  insert into public.council_members (game_id, player_id, area, name, status, created_tick)
  values (new.game_id, new.player_id, new.area, public.random_commander_name(new.game_id), 'seated',
          coalesce((select current_tick from public.games where id = new.game_id), 0));
  return new;
end;
$function$;

drop trigger if exists realm_areas_council on public.realm_areas;
create trigger realm_areas_council after insert on public.realm_areas
  for each row execute function public.create_council_member();

insert into public.council_members (game_id, player_id, area, name, status, created_tick)
select ra.game_id, ra.player_id, ra.area, public.random_commander_name(ra.game_id), 'seated',
       coalesce((select current_tick from public.games where id = ra.game_id), 0)
from public.realm_areas ra
where not exists (select 1 from public.council_members m where m.player_id = ra.player_id and m.area = ra.area and m.status <> 'dead');

create or replace function public.set_seat_present(p_game_id integer, p_player_id integer, p_area text, p_present boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if p_present then
    update public.realm_areas
    set level = greatest(level, coalesce(banked_level, level)), banked_level = null
    where player_id = p_player_id and area = p_area;
  else
    update public.realm_areas
    set banked_level = coalesce(banked_level, level), level = 1
    where player_id = p_player_id and area = p_area;
  end if;
  if p_area = 'guildhall' then
    perform public.refresh_effective_influence(p_game_id, p_player_id);
  end if;
end;
$function$;

create or replace function public.councillor_fell(p_game_id integer, p_ids integer[], p_tick integer)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_m record;
begin
  if p_ids is null then
    return;
  end if;
  for v_m in
    select m.id, m.player_id, m.area, m.name from public.council_members m
    where m.commander_id = any (p_ids) and m.status = 'afield'
    order by m.id
  loop
    update public.council_members set status = 'dead', died_tick = p_tick, commander_id = null where id = v_m.id;
    perform public.notify_players(
      p_game_id, p_tick, array[v_m.player_id], v_m.name || ', councillor of the ' || v_m.area || ', has fallen',
      jsonb_build_object('kind', 'councillor_fell', 'area', v_m.area, 'name', v_m.name)
    );
  end loop;
end;
$function$;

create or replace function public.deploy_councillor(p_game_id integer, p_area text, p_territory_id integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_player public.game_players;
  v_m public.council_members%rowtype;
  v_tick int;
  v_school text;
  v_id int;
begin
  v_player := public.acting_player(p_game_id);
  select * into v_m from public.council_members
  where player_id = v_player.id and area = p_area and status <> 'dead' for update;
  if not found then
    raise exception 'that seat is vacant';
  end if;
  if v_m.status <> 'seated' then
    raise exception '% is already in the field', v_m.name;
  end if;
  if not exists (select 1 from public.game_territories where id = p_territory_id and game_id = p_game_id and owner_player_id = v_player.id) then
    raise exception 'you do not own that castle';
  end if;
  select current_tick into v_tick from public.games where id = p_game_id;
  v_school := case p_area when 'armory' then 'battleschool' when 'barracks' then 'battleschool'
                          when 'watchtowers' then 'rangers' when 'stables' then 'rangers' else 'university' end;
  v_id := public.create_commander(p_game_id, v_player.id, v_school, 'commander', p_territory_id, v_tick);
  update public.commanders set name = v_m.name, council_area = p_area where id = v_id;
  update public.council_members set status = 'afield', commander_id = v_id where id = v_m.id;
  perform public.set_seat_present(p_game_id, v_player.id, p_area, false);
  return jsonb_build_object('commander_id', v_id, 'name', v_m.name);
end;
$function$;

create or replace function public.recall_councillor(p_game_id integer, p_commander_id integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_player public.game_players;
  v_c public.commanders%rowtype;
  v_tick int;
begin
  v_player := public.acting_player(p_game_id);
  select * into v_c from public.commanders
  where id = p_commander_id and game_id = p_game_id and owner_player_id = v_player.id and council_area is not null for update;
  if not found then
    raise exception 'that is not one of your councillors';
  end if;
  if v_c.status <> 'idle' or v_c.current_territory_id is null
     or not exists (select 1 from public.game_territories where id = v_c.current_territory_id and owner_player_id = v_player.id) then
    raise exception 'a councillor can only be recalled from one of your castles while idle';
  end if;
  select current_tick into v_tick from public.games where id = p_game_id;

  update public.game_territories set troops = troops + v_c.troops where id = v_c.current_territory_id;
  update public.game_territories set garrison_commander_id = null where garrison_commander_id = v_c.id;
  update public.commanders set status = 'dead', died_tick = v_tick, troops = 0, current_territory_id = null where id = v_c.id;
  delete from public.commander_movements where commander_id = v_c.id;
  update public.commander_routes set status = 'aborted' where commander_id = v_c.id and status in ('active', 'recalled');
  update public.council_members set status = 'seated', commander_id = null where commander_id = v_c.id and status = 'afield';
  perform public.set_seat_present(p_game_id, v_player.id, v_c.council_area, true);
  return jsonb_build_object('status', 'seated', 'area', v_c.council_area);
end;
$function$;

create or replace function public.recruit_councillor(p_game_id integer, p_area text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_player public.game_players;
  v_tick int;
  v_name text;
begin
  v_player := public.acting_player(p_game_id);
  if not exists (select 1 from public.realm_areas where player_id = v_player.id and area = p_area) then
    raise exception 'unknown seat';
  end if;
  if exists (select 1 from public.council_members where player_id = v_player.id and area = p_area and status <> 'dead') then
    raise exception 'that seat is not vacant';
  end if;
  if v_player.gold < 150 then
    raise exception 'a new councillor costs 150 gold';
  end if;
  select current_tick into v_tick from public.games where id = p_game_id;
  update public.game_players set gold = gold - 150 where id = v_player.id;
  insert into public.ledger (game_id, player_id, tick, type, amount) values (p_game_id, v_player.id, v_tick, 'recruit', -150);
  v_name := public.random_commander_name(p_game_id);
  insert into public.council_members (game_id, player_id, area, name, status, created_tick) values (p_game_id, v_player.id, p_area, v_name, 'seated', v_tick);
  perform public.set_seat_present(p_game_id, v_player.id, p_area, true);
  return jsonb_build_object('area', p_area, 'name', v_name);
end;
$function$;

create or replace function public.my_council(p_game_id integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_me int;
begin
  select id into v_me from public.game_players where game_id = p_game_id and user_id = (select auth.uid());
  if v_me is null then
    raise exception 'you are not in this game';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'area', ra.area, 'level', ra.level, 'banked_level', ra.banked_level,
      'name', m.name, 'status', coalesce(m.status, 'dead'), 'commander_id', m.commander_id
    ) order by ra.area)
    from public.realm_areas ra
    left join lateral (
      select * from public.council_members cm where cm.player_id = ra.player_id and cm.area = ra.area and cm.status <> 'dead' limit 1
    ) m on true
    where ra.player_id = v_me
  ), '[]'::jsonb);
end;
$function$;

do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.kill_commanders(integer,integer[],integer)'::regprocedure) into v_def;
  v_new := replace(v_def, 'delete from public.commander_movements where commander_id = any (p_ids);', 'perform public.councillor_fell(p_game_id, p_ids, p_tick);

  delete from public.commander_movements where commander_id = any (p_ids);');
  if v_new = v_def then raise exception 'kill_commanders patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.apply_named_death(integer,integer[],integer)'::regprocedure) into v_def;
  v_new := replace(v_def, '(c.role = ''king'' or c.promoted)', '(c.role = ''king'' or c.promoted or c.council_area is not null)');
  if v_new = v_def then raise exception 'apply_named_death patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.get_game_view(integer)'::regprocedure) into v_def;
  v_new := replace(v_def, '''promoted'', c.promoted, ''wins'', c.wins', '''promoted'', c.promoted, ''wins'', c.wins, ''council_area'', c.council_area');
  if v_new = v_def then raise exception 'get_game_view patch did not apply'; end if;
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
      and proname in ('create_council_member', 'set_seat_present', 'councillor_fell')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
  end loop;
  for r in
    select oid::regprocedure as sig from pg_proc
    where pronamespace = 'public'::regnamespace
      and proname in ('deploy_councillor', 'recall_councillor', 'recruit_councillor', 'my_council')
  loop
    execute format('revoke all on function %s from public, anon', r.sig);
    execute format('grant execute on function %s to authenticated', r.sig);
  end loop;
end
$grants$;
