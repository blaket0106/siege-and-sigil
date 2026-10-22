create or replace function public.enforce_game_create_limits()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.created_by is null then
    return new;
  end if;
  if (select count(*) from public.games g where g.created_by = new.created_by and g.created_at > now() - interval '1 hour') >= 5 then
    raise exception 'you can create at most 5 games per hour';
  end if;
  if (select count(*) from public.games g where g.created_by = new.created_by and g.status in ('lobby', 'active')) >= 5 then
    raise exception 'you already have 5 unfinished games you created; finish or delete one first';
  end if;
  return new;
end;
$function$;

drop trigger if exists games_create_limits on public.games;
create trigger games_create_limits before insert on public.games
  for each row execute function public.enforce_game_create_limits();

create or replace function public.enforce_game_join_limits()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.user_id is null then
    return new;
  end if;
  if (
    select count(*) from public.game_players gp
    join public.games g on g.id = gp.game_id
    where gp.user_id = new.user_id and g.status in ('lobby', 'active') and gp.eliminated_at_tick is null
  ) >= 10 then
    raise exception 'you are already in 10 unfinished games';
  end if;
  return new;
end;
$function$;

drop trigger if exists game_players_join_limits on public.game_players;
create trigger game_players_join_limits before insert on public.game_players
  for each row execute function public.enforce_game_join_limits();
