create or replace function public.pulse_game()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gid int;
  v_key text;
begin
  for v_gid in
    select distinct coalesce(to_jsonb(c) ->> 'game_id', to_jsonb(c) ->> 'id')::int from changed c
  loop
    v_key := 'ss.pulse_' || v_gid;
    if coalesce(current_setting(v_key, true), '') = '' then
      perform set_config(v_key, '1', true);
      perform realtime.send(jsonb_build_object('game_id', v_gid), 'refresh', 'game:' || v_gid, true);
    end if;
  end loop;
  return null;
end;
$$;
