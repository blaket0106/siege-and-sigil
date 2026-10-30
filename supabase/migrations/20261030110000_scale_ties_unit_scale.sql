alter table public.games alter column world_scale set default 27;
alter table public.games alter column unit_scale set default 13.5;

do $patch$
declare
  v_def text;
  v_old text := 'world_scale = coalesce((p_settings ->> ''world_scale'')::float8, g.world_scale),';
  v_new text := 'world_scale = coalesce((p_settings ->> ''world_scale'')::float8, g.world_scale),
      unit_scale = coalesce((p_settings ->> ''world_scale'')::float8 / 2, g.unit_scale),';
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'create_game' and p.pronamespace = 'public'::regnamespace;
  if position(v_old in v_def) = 0 then
    raise exception 'create_game world_scale pattern not found';
  end if;
  execute replace(v_def, v_old, v_new);
end;
$patch$;
