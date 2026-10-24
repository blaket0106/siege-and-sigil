alter table public.commander_movements add column if not exists prev_status text;

alter table public.games add column if not exists speed_basis numeric not null default 1;
alter table public.games alter column speed_basis set default 3;
grant select (speed_basis) on public.games to authenticated;

alter table public.games alter column neutral_armory set default 0;

do $patch$
declare
  v_def text;
  v_new text;
  v_fn text;
  v_pairs text[];
  i int;
begin
  for v_fn, v_pairs in
    select * from (values
      ('launch_leg', array[
        E'departed_tick, arrival_tick, march_type\n  ) values (',
        E'departed_tick, arrival_tick, march_type, prev_status\n  ) values (',
        E'v_arrivals[array_length(v_arrivals, 1)], p_march_type\n  );',
        E'v_arrivals[array_length(v_arrivals, 1)], p_march_type, v_c.status\n  );'
      ]),
      ('march_speed', array[
        'g.commander_speed_mult',
        'g.commander_speed_mult * g.speed_basis'
      ])
    ) as t(fn, pairs)
  loop
    select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = v_fn and p.pronamespace = 'public'::regnamespace order by p.oid limit 1;
    v_new := v_def;
    for i in 1 .. array_length(v_pairs, 1) / 2 loop
      if position(v_pairs[2 * i - 1] in v_new) = 0 then
        raise exception '% patch % did not match', v_fn, i;
      end if;
      v_new := replace(v_new, v_pairs[2 * i - 1], v_pairs[2 * i]);
    end loop;
    execute v_new;
  end loop;
end;
$patch$;

create function public.cancel_march(p_game_id int, p_commander_id int)
returns void
language plpgsql
security definer
set search_path = ''
as $f$
declare
  v_player public.game_players;
  v_tick int;
  v_m public.commander_movements%rowtype;
  v_r public.commander_routes%rowtype;
begin
  v_player := public.acting_player(p_game_id);
  if not exists (select 1 from public.commanders where id = p_commander_id and game_id = p_game_id and owner_player_id = v_player.id and status = 'moving') then
    raise exception 'commander is not marching';
  end if;
  select current_tick into v_tick from public.games where id = p_game_id;
  select * into v_m from public.commander_movements where commander_id = p_commander_id order by id desc limit 1;
  if not found then
    raise exception 'commander is not marching';
  end if;
  if v_m.departed_tick <> v_tick then
    raise exception 'orders are locked once the first tick has passed; halt at the next stop instead';
  end if;
  select * into v_r from public.commander_routes where commander_id = p_commander_id and status = 'active' order by id desc limit 1;
  if found and (v_r.created_tick <> v_m.departed_tick or v_r.next_stop_index > 0) then
    raise exception 'orders are locked once the first tick has passed; halt at the next stop instead';
  end if;
  delete from public.commander_movements where id = v_m.id;
  if v_r.id is not null then
    update public.commander_routes set status = 'aborted', resume_tick = null where id = v_r.id;
  end if;
  update public.commanders set status = coalesce(v_m.prev_status, 'idle'), current_territory_id = v_m.from_territory_id where id = p_commander_id;
end;
$f$;

revoke execute on function public.cancel_march(int, int) from public, anon;
grant execute on function public.cancel_march(int, int) to authenticated;

revoke execute on function public.recall_route(int, int) from public, anon, authenticated;
