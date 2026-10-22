alter table public.game_territories rename column base_influence to natural_resources;
alter table public.game_territories rename column effective_influence to resources;

do $patch$
declare
  r record;
  v_def text;
  v_new text;
begin
  for r in
    select p.oid
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f'
      and (pg_get_functiondef(p.oid) like '%base_influence%' or pg_get_functiondef(p.oid) like '%effective_influence%')
  loop
    v_def := pg_get_functiondef(r.oid);
    v_new := replace(replace(v_def, 'refresh_effective_influence', '@@refresh@@'), 'p_effective_influence', '@@param@@');
    v_new := replace(replace(v_new, 'base_influence', 'natural_resources'), 'effective_influence', 'resources');
    v_new := replace(replace(v_new, '@@refresh@@', 'refresh_effective_influence'), '@@param@@', 'p_effective_influence');
    execute v_new;
  end loop;

  select pg_get_functiondef('public.infra_cost(text,integer,integer,double precision)'::regprocedure) into v_def;
  v_new := replace(replace(v_def, 'when ''treasury'' then 500', 'when ''treasury'' then 1250'), 'when ''recruitment'' then 1000', 'when ''recruitment'' then 2500');
  v_new := replace(v_new, 'when ''prestige'' then 4000', 'when ''prestige'' then 10000');
  if v_new = v_def then raise exception 'infra_cost patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.build_road(integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def, '10000.0 / v_t.natural_resources * v_game.infra_cost_mult', '30.0 * v_t.resources * v_game.infra_cost_mult');
  if v_new = v_def then raise exception 'build_road patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.plan_march_free(integer,integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def, 'case when v_road then 3.0 else 1.0 end',
    'case when v_road then sqrt(3 + coalesce((select level from public.realm_areas where player_id = p_player_id and area = ''stables''), 0)) else 1.0 end');
  if v_new = v_def then raise exception 'plan_march_free patch did not apply'; end if;
  execute v_new;

  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f'
      and (replace(replace(pg_get_functiondef(p.oid), 'refresh_effective_influence', ''), 'p_effective_influence', '') like '%base_influence%'
        or replace(replace(pg_get_functiondef(p.oid), 'refresh_effective_influence', ''), 'p_effective_influence', '') like '%effective_influence%')
  ) then
    raise exception 'influence columns still referenced';
  end if;
end;
$patch$;

create or replace function public.clear_road_on_capture()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.owner_player_id is distinct from old.owner_player_id then
    new.has_road := false;
  end if;
  return new;
end;
$function$;

create or replace function public.retime_marches_on_road_loss()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_m record;
  v_free boolean;
  v_tick int;
  v_other int;
  v_other_road boolean;
  v_e public.territory_edges%rowtype;
  v_total int;
  v_elapsed int;
  v_base int;
  v_new int;
begin
  select free_travel, current_tick into v_free, v_tick from public.games where id = new.game_id;
  if not v_free then
    return new;
  end if;
  for v_m in
    select * from public.commander_movements
    where game_id = new.game_id and array_length(path, 1) = 2 and (from_territory_id = new.id or to_territory_id = new.id)
  loop
    v_other := case when v_m.from_territory_id = new.id then v_m.to_territory_id else v_m.from_territory_id end;
    select has_road into v_other_road from public.game_territories where id = v_other;
    continue when not coalesce(v_other_road, false);
    select * into v_e from public.territory_edges
    where game_id = new.game_id and from_territory_id = least(v_m.from_territory_id, v_m.to_territory_id)
      and to_territory_id = greatest(v_m.from_territory_id, v_m.to_territory_id);
    continue when not found;
    v_total := v_m.arrival_tick - v_m.departed_tick;
    continue when v_total <= 0;
    v_elapsed := least(greatest(v_tick - v_m.departed_tick, 0), v_total);
    v_base := greatest(1, ceil(v_e.length * v_e.move_cost_mult / public.march_speed(v_m.commander_id))::int);
    v_new := v_tick + greatest(1, ceil(v_base * (1.0 - v_elapsed::float8 / v_total))::int);
    continue when v_new <= v_m.arrival_tick;
    update public.commander_movements
    set arrival_tick = v_new,
        path_arrival_ticks[array_length(path_arrival_ticks, 1)] = v_new
    where id = v_m.id;
  end loop;
  return new;
end;
$function$;

revoke all on function public.clear_road_on_capture() from public, anon, authenticated;
revoke all on function public.retime_marches_on_road_loss() from public, anon, authenticated;

drop trigger if exists clear_road_on_capture on public.game_territories;
create trigger clear_road_on_capture
  before update of owner_player_id on public.game_territories
  for each row execute function public.clear_road_on_capture();

drop trigger if exists retime_marches_on_road_loss on public.game_territories;
create trigger retime_marches_on_road_loss
  after update on public.game_territories
  for each row when (old.has_road and not new.has_road)
  execute function public.retime_marches_on_road_loss();
