create table public.factions (
  slug text primary key,
  name text not null,
  color text not null,
  color2 text not null,
  modifier jsonb
);

create table public.achievements (
  slug text primary key,
  name text not null,
  description text not null,
  sort_order int not null default 0
);

create table public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null,
  honor int not null default 0,
  infamy int not null default 0,
  selected_title text,
  total_games int not null default 0,
  total_wins int not null default 0,
  created_at timestamptz not null default now()
);

alter table public.factions enable row level security;
alter table public.achievements enable row level security;
alter table public.profiles enable row level security;

create policy "factions are readable by everyone"
  on public.factions for select to anon, authenticated
  using (true);

create policy "achievements are readable by everyone"
  on public.achievements for select to anon, authenticated
  using (true);

create policy "profiles are readable by signed-in users"
  on public.profiles for select to authenticated
  using (true);

create policy "users can update their own profile"
  on public.profiles for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

revoke update on public.profiles from authenticated;
grant update (display_name, selected_title) on public.profiles to authenticated;

create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (user_id, display_name)
  values (
    new.id,
    coalesce(
      nullif(new.raw_user_meta_data ->> 'display_name', ''),
      nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
      'Player'
    )
  );
  return new;
end;
$$;

revoke execute on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

insert into public.factions (slug, name, color, color2) values
  ('kaldran', 'Kaldran', '#B3202A', '#E0A526'),
  ('thornwick', 'Thornwick', '#2F6B3A', '#D9D2B0'),
  ('veyra', 'Veyra', '#1F3A93', '#C0C8D4'),
  ('dravos', 'Dravos', '#26262B', '#E8662A'),
  ('ostrand', 'Ostrand', '#1E8A8F', '#E3C98A'),
  ('mereth', 'Mereth', '#6A3FA0', '#E58AA8'),
  ('halcyr', 'Halcyr', '#E8EEF2', '#4A8FC4'),
  ('brannoch', 'Brannoch', '#B8742A', '#6B3A1A');
