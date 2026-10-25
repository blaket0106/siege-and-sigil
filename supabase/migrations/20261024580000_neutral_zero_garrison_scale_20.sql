alter table public.games alter column world_scale set default 20;

do $patch$
declare
  v_def text;
  v_old text := 'case when v_owner is null then (v_t ->> ''troops'')::int else v_game.starting_garrison end,';
  v_new text := 'case when v_owner is null then 0 else v_game.starting_garrison end,';
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'commit_world' and p.pronamespace = 'public'::regnamespace;
  if position(v_old in v_def) = 0 then
    raise exception 'commit_world patch did not match';
  end if;
  execute replace(v_def, v_old, v_new);
end;
$patch$;

alter table public.games drop constraint games_world_scale_check;
alter table public.games add constraint games_world_scale_check check (world_scale >= 1 and world_scale <= 40);
