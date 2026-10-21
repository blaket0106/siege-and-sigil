create table public.games (
  id int generated always as identity primary key,
  name text not null,
  status text not null default 'lobby' check (status in ('lobby', 'active', 'finished')),
  created_by uuid not null references auth.users (id),
  current_tick int not null default 0,
  last_tick_processed_at timestamptz,
  tick_speed text not null default 'normal' check (tick_speed in ('slow', 'normal', 'fast', 'quad', 'turn_based')),
  production_cycle_ticks int not null default 12 check (production_cycle_ticks > 0),
  commander_speed_mult float8 not null default 1.0 check (commander_speed_mult > 0),
  infra_cost_mult float8 not null default 1.0 check (infra_cost_mult > 0),
  area_cost_mult float8 not null default 1.0 check (area_cost_mult > 0),
  victory_pct float8 not null default 0.5 check (victory_pct > 0 and victory_pct <= 1),
  fog_of_war boolean not null default true,
  starting_gold int not null default 300 check (starting_gold >= 0),
  starting_garrison int not null default 10 check (starting_garrison >= 0),
  starting_gold_level int not null default 1 check (starting_gold_level >= 0),
  starting_industry_level int not null default 1 check (starting_industry_level >= 0),
  starting_prestige_level int not null default 1 check (starting_prestige_level >= 0),
  fill_with_ai boolean not null default false,
  ai_difficulty int not null default 3 check (ai_difficulty between 1 and 5),
  winner_player_id int,
  turn_timeout_minutes int,
  ticks_per_turn int,
  current_turn_ends_at timestamptz,
  max_players int not null default 4 check (max_players between 2 and 8),
  world_seed bigint not null default floor(random() * 9007199254740991)::bigint,
  generator_version int,
  map_style text not null default 'scatter' check (map_style in ('scatter', 'continents')),
  map_size text not null default 'standard' check (map_size in ('compact', 'standard', 'large')),
  map_w float8,
  map_h float8,
  starting_territories int not null default 4 check (starting_territories >= 1),
  starting_commanders int not null default 2 check (starting_commanders >= 0),
  commander_cost int not null default 100 check (commander_cost >= 0),
  coronation_ticks int not null default 12 check (coronation_ticks >= 0),
  created_at timestamptz not null default now(),
  check (tick_speed <> 'turn_based' or (ticks_per_turn is not null and turn_timeout_minutes is not null))
);

create index games_created_by_idx on public.games (created_by);
create index games_status_idx on public.games (status);

create table public.game_players (
  id int generated always as identity primary key,
  game_id int not null references public.games (id) on delete cascade,
  user_id uuid references auth.users (id),
  faction_slug text not null references public.factions (slug),
  display_name text not null,
  gold int not null default 0,
  is_ai boolean not null default false,
  eliminated_at_tick int,
  turn_submitted boolean not null default false,
  capital_territory_id int,
  created_at timestamptz not null default now(),
  check (is_ai = (user_id is null)),
  unique (game_id, faction_slug)
);

create unique index game_players_game_user_idx on public.game_players (game_id, user_id) where user_id is not null;
create index game_players_user_idx on public.game_players (user_id);
create index game_players_faction_idx on public.game_players (faction_slug);

alter table public.games
  add constraint games_winner_player_fk
  foreign key (winner_player_id) references public.game_players (id) on delete set null;

create index games_winner_player_idx on public.games (winner_player_id);

create function public.is_game_member(p_game_id int)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.game_players gp
    where gp.game_id = p_game_id
      and gp.user_id = (select auth.uid())
  );
$$;

revoke execute on function public.is_game_member(int) from public, anon;
grant execute on function public.is_game_member(int) to authenticated;

alter table public.games enable row level security;
alter table public.game_players enable row level security;

create policy "lobby games and own games are readable"
  on public.games for select to authenticated
  using (
    status = 'lobby'
    or created_by = (select auth.uid())
    or public.is_game_member(id)
  );

create policy "players are readable by game members"
  on public.game_players for select to authenticated
  using (public.is_game_member(game_id));

alter table public.games replica identity full;
alter table public.game_players replica identity full;

alter publication supabase_realtime add table public.games, public.game_players;
