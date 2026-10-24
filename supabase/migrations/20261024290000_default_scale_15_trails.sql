alter table public.games alter column world_scale set default 15;
alter table public.games alter column travel_mode set default 'trails';

do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.create_game(jsonb)'::regprocedure) into v_def;
  v_new := v_def;
  if position('coalesce((p_settings ->> ''world_scale'')::float8, 3)' in v_new) = 0 then raise exception 'world_scale pattern'; end if;
  v_new := replace(v_new, 'coalesce((p_settings ->> ''world_scale'')::float8, 3)', 'coalesce((p_settings ->> ''world_scale'')::float8, g.world_scale)');
  if position('free_travel = case when p_settings ->> ''travel_mode'' = ''trails'' then false' in v_new) = 0 then raise exception 'free_travel pattern'; end if;
  v_new := replace(v_new, 'free_travel = case when p_settings ->> ''travel_mode'' = ''trails'' then false', 'free_travel = case when coalesce(p_settings ->> ''travel_mode'', g.travel_mode) = ''trails'' then false');
  execute v_new;
end;
$patch$;
