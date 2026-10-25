alter table public.games add column if not exists jump_halt_on_threat boolean not null default true;

do $patch$
declare
  v_def text;
  v_old text := 'select current_tick into v_tick from public.games where id = p_game_id;';
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'jump_threat' and p.pronamespace = 'public'::regnamespace;
  if position(v_old in v_def) = 0 then
    raise exception 'jump_threat patch did not match';
  end if;
  execute replace(v_def, v_old, v_old || chr(10) || '  if not (select jump_halt_on_threat from public.games where id = p_game_id) then' || chr(10) || '    return false;' || chr(10) || '  end if;');
end;
$patch$;

do $patch$
declare
  v_def text;
  v_old text := 'e.payload ->> ''commander'' = r.cid::text and e.payload ->> ''territory'' = r.tid::text and e.payload ->> ''phase'' = v_phase';
  v_new text := 'e.tick > v_tick - 12 and e.payload ->> ''territory'' = r.tid::text and e.payload ->> ''phase'' = v_phase';
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'jump_threat' and p.pronamespace = 'public'::regnamespace;
  if position(v_old in v_def) = 0 then
    raise exception 'jump_threat dedupe patch did not match';
  end if;
  execute replace(v_def, v_old, v_new);
end;
$patch$;
