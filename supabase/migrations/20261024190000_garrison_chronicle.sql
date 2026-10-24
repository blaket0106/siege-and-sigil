create function public.log_garrison_post()
returns trigger
language plpgsql
security definer
set search_path = ''
as $f$
declare
  v_tick int;
begin
  if new.garrison_commander_id is null or new.garrison_commander_id is not distinct from old.garrison_commander_id then
    return new;
  end if;
  select current_tick into v_tick from public.games where id = new.game_id;
  if exists (
    select 1 from public.commander_history h
    where h.commander_id = new.garrison_commander_id and h.kind = 'posted' and h.tick > v_tick - 12
  ) then
    return new;
  end if;
  perform public.log_commander(new.garrison_commander_id, v_tick, 'posted', format('Took command of the garrison at %s.', new.name));
  return new;
end;
$f$;

revoke execute on function public.log_garrison_post() from public, anon, authenticated;

create trigger trg_log_garrison_post
after update of garrison_commander_id on public.game_territories
for each row execute function public.log_garrison_post();
