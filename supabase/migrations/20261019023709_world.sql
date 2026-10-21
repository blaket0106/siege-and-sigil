create table public.game_territories (
  id int generated always as identity primary key,
  game_id int not null references public.games (id) on delete cascade,
  slug text not null,
  name text not null,
  tier smallint not null check (tier between 1 and 3),
  region text,
  base_influence int not null default 1 check (base_influence >= 1),
  x float8 not null,
  y float8 not null,
  terrain text not null default 'plains' check (terrain in ('plains')),
  owner_player_id int references public.game_players (id) on delete set null,
  troops int not null default 0 check (troops >= 0),
  gold_level int not null default 0 check (gold_level >= 0),
  industry_level int not null default 0 check (industry_level >= 0),
  prestige_level int not null default 0 check (prestige_level >= 0),
  has_road boolean not null default false,
  effective_influence int not null default 1 check (effective_influence >= 1),
  troop_accum float8 not null default 0 check (troop_accum >= 0),
  garrison_commander_id int,
  unique (game_id, slug),
  unique (game_id, id)
);

create index game_territories_owner_idx on public.game_territories (owner_player_id);

alter table public.game_players
  add constraint game_players_capital_fk
  foreign key (capital_territory_id) references public.game_territories (id) on delete set null;

create index game_players_capital_idx on public.game_players (capital_territory_id);

create table public.territory_edges (
  game_id int not null,
  from_territory_id int not null,
  to_territory_id int not null,
  kind text not null default 'land' check (kind in ('land', 'river', 'pass', 'sea')),
  length float8 not null check (length > 0),
  move_cost_mult float8 not null default 1.0 check (move_cost_mult > 0),
  defense_mult float8 not null default 1.0 check (defense_mult > 0),
  primary key (from_territory_id, to_territory_id),
  check (from_territory_id < to_territory_id),
  foreign key (game_id, from_territory_id) references public.game_territories (game_id, id) on delete cascade,
  foreign key (game_id, to_territory_id) references public.game_territories (game_id, id) on delete cascade
);

create index territory_edges_game_from_idx on public.territory_edges (game_id, from_territory_id);
create index territory_edges_game_to_idx on public.territory_edges (game_id, to_territory_id);

alter table public.game_territories enable row level security;
alter table public.territory_edges enable row level security;

create policy "territories are readable by game members"
  on public.game_territories for select to authenticated
  using (public.is_game_member(game_id));

create policy "edges are readable by game members"
  on public.territory_edges for select to authenticated
  using (public.is_game_member(game_id));

alter table public.game_territories replica identity full;

alter publication supabase_realtime add table public.game_territories;
