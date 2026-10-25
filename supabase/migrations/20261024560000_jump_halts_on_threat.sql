create or replace function public.jump_threat(p_game_id int)
returns boolean
language plpgsql
security definer
set search_path = ''
as $f$
declare
  v_tick int;
  v_found boolean := false;
  r record;
begin
  select current_tick into v_tick from public.games where id = p_game_id;
  for r in
    select c.id as cid, t.id as tid
    from public.commanders c
    join public.commander_movements m on m.commander_id = c.id
    join public.game_territories t on t.id = m.to_territory_id
    join public.game_players hp on hp.id = t.owner_player_id and not hp.is_ai
    where c.game_id = p_game_id and c.status = 'moving' and c.owner_player_id is distinct from t.owner_player_id
      and m.arrival_tick - v_tick <= 4
    union
    select c.id, t.id
    from public.commanders c
    join public.game_territories t on t.id = c.current_territory_id
    join public.game_players hp on hp.id = t.owner_player_id and not hp.is_ai
    where c.game_id = p_game_id and c.status = 'sieging' and c.owner_player_id is distinct from t.owner_player_id
  loop
    if not exists (select 1 from public.game_events e where e.game_id = p_game_id and e.type = 'jump_halt' and e.payload ->> 'commander' = r.cid::text and e.payload ->> 'territory' = r.tid::text) then
      insert into public.game_events (game_id, tick, type, payload)
      values (p_game_id, v_tick, 'jump_halt', jsonb_build_object('commander', r.cid, 'territory', r.tid));
      v_found := true;
    end if;
  end loop;
  return v_found;
end;
$f$;
revoke execute on function public.jump_threat(int) from public, anon, authenticated;

do $patch$
declare
  v_def text;
  v_old text := '      exit when v_status <> ''active'';';
  v_new text := '      exit when v_status <> ''active'';' || chr(10)
    || '      if public.jump_threat(v_g.id) then' || chr(10)
    || '        update public.games set jump_remaining = 0 where id = v_g.id;' || chr(10)
    || '        exit;' || chr(10)
    || '      end if;';
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'process_jumps' and p.pronamespace = 'public'::regnamespace;
  if position(v_old in v_def) = 0 then
    raise exception 'process_jumps patch did not match';
  end if;
  execute replace(v_def, v_old, v_new);
end;
$patch$;

select cron.alter_job((select jobid from cron.job where jobname = 'process-jumps'), schedule => '1 seconds');
