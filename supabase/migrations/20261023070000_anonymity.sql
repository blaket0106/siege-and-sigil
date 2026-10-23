alter table public.games add column if not exists anonymity text not null default 'normal' check (anonymity in ('normal', 'extra'));
grant select (anonymity) on public.games to authenticated;
alter table public.game_players add column if not exists real_name text;

create function public.apply_anonymity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.anonymity = 'extra' and old.status = 'lobby' and new.status in ('picking', 'active') then
    update public.game_players gp
    set real_name = gp.display_name,
        display_name = coalesce((select f.name from public.factions f where f.slug = gp.faction_slug), gp.display_name)
    where gp.game_id = new.id and not gp.is_ai and gp.real_name is null;
  elsif new.status = 'finished' and old.status <> 'finished' then
    update public.game_players gp
    set display_name = gp.real_name, real_name = null
    where gp.game_id = new.id and gp.real_name is not null;
  end if;
  return new;
end;
$function$;

create trigger games_apply_anonymity after update of status on public.games
  for each row when (old.status is distinct from new.status) execute function public.apply_anonymity();

do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.create_game(jsonb)'::regprocedure) into v_def;
  v_new := replace(v_def, '''home_distance'', ''wormholes'',', '''home_distance'', ''wormholes'', ''anonymity'',');
  v_new := replace(v_new, 'wormholes = coalesce(p_settings ->> ''wormholes'', g.wormholes),', 'wormholes = coalesce(p_settings ->> ''wormholes'', g.wormholes),
      anonymity = coalesce(p_settings ->> ''anonymity'', g.anonymity),');
  if v_new = v_def or v_new not like '%''wormholes'', ''anonymity'',%' or v_new not like '%anonymity = coalesce%' then
    raise exception 'create_game patch did not apply';
  end if;
  execute v_new;

  select pg_get_functiondef('public.get_game_view(integer)'::regprocedure) into v_def;
  v_new := replace(v_def, '''user_id'', p.user_id,', '''user_id'', case when v_g.anonymity = ''extra'' and v_g.status <> ''finished'' and p.id <> v_me then null else p.user_id end,');
  if v_new = v_def then
    raise exception 'get_game_view patch did not apply';
  end if;
  execute v_new;
end;
$patch$;
