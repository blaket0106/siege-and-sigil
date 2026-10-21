alter table public.game_players
  add constraint game_players_game_id_id_key unique (game_id, id);

create table public.commanders (
  id int generated always as identity primary key,
  game_id int not null references public.games (id) on delete cascade,
  owner_player_id int not null,
  name text not null,
  school text not null check (school in ('battleschool', 'university', 'rangers')),
  role text not null default 'commander' check (role in ('commander', 'king')),
  troops int not null default 0 check (troops >= 0),
  status text not null default 'idle' check (status in ('idle', 'moving', 'sieging', 'dead')),
  current_territory_id int,
  created_tick int not null default 0,
  died_tick int,
  check (status <> 'dead' or died_tick is not null),
  unique (game_id, id),
  foreign key (game_id, owner_player_id) references public.game_players (game_id, id) on delete cascade,
  foreign key (game_id, current_territory_id) references public.game_territories (game_id, id) on delete set null (current_territory_id)
);

create index commanders_owner_idx on public.commanders (game_id, owner_player_id);
create index commanders_territory_idx on public.commanders (game_id, current_territory_id);
create unique index commanders_one_living_king_idx on public.commanders (owner_player_id) where role = 'king' and status <> 'dead';

alter table public.game_territories
  add constraint game_territories_garrison_commander_fk
  foreign key (game_id, garrison_commander_id) references public.commanders (game_id, id) on delete set null (garrison_commander_id);

create unique index game_territories_garrison_commander_idx on public.game_territories (game_id, garrison_commander_id) where garrison_commander_id is not null;

create table public.commander_abilities (
  game_id int not null,
  commander_id int not null,
  ability text not null check (ability in ('valor', 'tactics', 'siegecraft', 'muster', 'steward', 'scholar', 'pace', 'scout', 'plunder')),
  level smallint not null default 0 check (level between 0 and 5),
  xp float8 not null default 0 check (xp >= 0),
  primary key (commander_id, ability),
  foreign key (game_id, commander_id) references public.commanders (game_id, id) on delete cascade
);

create index commander_abilities_game_commander_idx on public.commander_abilities (game_id, commander_id);

create table public.commander_movements (
  id int generated always as identity primary key,
  game_id int not null,
  commander_id int not null,
  from_territory_id int not null,
  to_territory_id int not null,
  path int[] not null,
  path_arrival_ticks int[] not null,
  departed_tick int not null,
  arrival_tick int not null,
  march_type text not null check (march_type in ('assault', 'siege')),
  check (cardinality(path) >= 2 and cardinality(path) = cardinality(path_arrival_ticks)),
  check (arrival_tick > departed_tick),
  unique (game_id, commander_id),
  foreign key (game_id, commander_id) references public.commanders (game_id, id) on delete cascade,
  foreign key (game_id, from_territory_id) references public.game_territories (game_id, id) on delete cascade,
  foreign key (game_id, to_territory_id) references public.game_territories (game_id, id) on delete cascade
);

create index commander_movements_from_idx on public.commander_movements (game_id, from_territory_id);
create index commander_movements_to_idx on public.commander_movements (game_id, to_territory_id);
create index commander_movements_arrival_idx on public.commander_movements (game_id, arrival_tick);

create table public.commander_routes (
  id int generated always as identity primary key,
  game_id int not null,
  commander_id int not null,
  status text not null default 'active' check (status in ('active', 'completed', 'aborted', 'recalled')),
  stops jsonb not null check (jsonb_typeof(stops) = 'array' and jsonb_array_length(stops) >= 1),
  next_stop_index int not null default 0 check (next_stop_index >= 0),
  created_tick int not null,
  foreign key (game_id, commander_id) references public.commanders (game_id, id) on delete cascade
);

create index commander_routes_game_commander_idx on public.commander_routes (game_id, commander_id);
create unique index commander_routes_one_active_idx on public.commander_routes (commander_id) where status = 'active';

create table public.realm_areas (
  game_id int not null,
  player_id int not null,
  area text not null check (area in ('armory', 'mint', 'barracks', 'guildhall', 'watchtowers', 'library', 'stables')),
  level int not null default 1 check (level >= 1),
  prestige_accumulated int not null default 0 check (prestige_accumulated >= 0),
  is_active boolean not null default false,
  primary key (player_id, area),
  foreign key (game_id, player_id) references public.game_players (game_id, id) on delete cascade
);

create index realm_areas_game_player_idx on public.realm_areas (game_id, player_id);
create unique index realm_areas_one_active_idx on public.realm_areas (player_id) where is_active;

alter table public.commanders enable row level security;
alter table public.commander_abilities enable row level security;
alter table public.commander_movements enable row level security;
alter table public.commander_routes enable row level security;
alter table public.realm_areas enable row level security;

create policy "commanders are readable by game members"
  on public.commanders for select to authenticated
  using (public.is_game_member(game_id));

create policy "commander abilities are readable by game members"
  on public.commander_abilities for select to authenticated
  using (public.is_game_member(game_id));

create policy "movements are readable by game members"
  on public.commander_movements for select to authenticated
  using (public.is_game_member(game_id));

create policy "routes are readable by game members"
  on public.commander_routes for select to authenticated
  using (public.is_game_member(game_id));

create policy "realm areas are readable by their owner"
  on public.realm_areas for select to authenticated
  using (
    exists (
      select 1
      from public.game_players gp
      where gp.id = player_id
        and gp.user_id = (select auth.uid())
    )
  );
