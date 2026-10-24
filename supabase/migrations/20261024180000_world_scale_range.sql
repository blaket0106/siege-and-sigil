alter table public.games drop constraint games_world_scale_check;
alter table public.games add constraint games_world_scale_check check (world_scale >= 1 and world_scale <= 18);
