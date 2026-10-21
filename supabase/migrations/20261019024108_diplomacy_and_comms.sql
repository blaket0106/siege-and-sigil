create table public.diplomacy (
  game_id int not null,
  player_a_id int not null,
  player_b_id int not null,
  status text not null default 'neutral' check (status in ('neutral', 'proposed', 'allied', 'grace_period', 'war')),
  proposed_by_player_id int,
  broken_by_player_id int,
  grace_ends_tick int,
  updated_tick int not null default 0,
  primary key (player_a_id, player_b_id),
  check (player_a_id < player_b_id),
  check (proposed_by_player_id is null or proposed_by_player_id in (player_a_id, player_b_id)),
  check (broken_by_player_id is null or broken_by_player_id in (player_a_id, player_b_id)),
  check (status <> 'proposed' or proposed_by_player_id is not null),
  check (status <> 'grace_period' or (grace_ends_tick is not null and broken_by_player_id is not null)),
  foreign key (game_id, player_a_id) references public.game_players (game_id, id) on delete cascade,
  foreign key (game_id, player_b_id) references public.game_players (game_id, id) on delete cascade
);

create index diplomacy_game_a_idx on public.diplomacy (game_id, player_a_id);
create index diplomacy_game_b_idx on public.diplomacy (game_id, player_b_id);

create table public.player_inbox (
  id int generated always as identity primary key,
  game_id int not null,
  player_id int not null,
  type text not null check (type in ('system', 'combat', 'diplomacy', 'message')),
  title text not null,
  body jsonb not null default '{}'::jsonb,
  tick int not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now(),
  foreign key (game_id, player_id) references public.game_players (game_id, id) on delete cascade
);

create index player_inbox_player_idx on public.player_inbox (game_id, player_id, tick desc);

create table public.game_events (
  id int generated always as identity primary key,
  game_id int not null references public.games (id) on delete cascade,
  tick int not null,
  type text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index game_events_game_tick_idx on public.game_events (game_id, tick desc);

create table public.game_moments (
  id int generated always as identity primary key,
  game_id int not null references public.games (id) on delete cascade,
  tick int not null,
  type text not null,
  payload jsonb not null default '{}'::jsonb,
  visibility text not null default 'public' check (visibility in ('public', 'private')),
  involved_player_ids int[] not null default '{}',
  created_at timestamptz not null default now()
);

create index game_moments_game_tick_idx on public.game_moments (game_id, tick desc);

create table public.game_chat (
  id int generated always as identity primary key,
  game_id int not null,
  player_id int not null,
  message text not null check (char_length(message) between 1 and 500),
  created_at timestamptz not null default now(),
  foreign key (game_id, player_id) references public.game_players (game_id, id) on delete cascade
);

create index game_chat_game_created_idx on public.game_chat (game_id, created_at desc);
create index game_chat_player_idx on public.game_chat (game_id, player_id);

create table public.message_threads (
  id int generated always as identity primary key,
  game_id int not null references public.games (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (game_id, id)
);

create table public.thread_participants (
  thread_id int not null,
  game_id int not null,
  player_id int not null,
  last_read_at timestamptz,
  primary key (thread_id, player_id),
  foreign key (game_id, thread_id) references public.message_threads (game_id, id) on delete cascade,
  foreign key (game_id, player_id) references public.game_players (game_id, id) on delete cascade
);

create index thread_participants_game_thread_idx on public.thread_participants (game_id, thread_id);
create index thread_participants_game_player_idx on public.thread_participants (game_id, player_id);

create table public.thread_messages (
  id int generated always as identity primary key,
  thread_id int not null,
  player_id int not null,
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now(),
  foreign key (thread_id, player_id) references public.thread_participants (thread_id, player_id) on delete cascade
);

create index thread_messages_thread_created_idx on public.thread_messages (thread_id, created_at);
create index thread_messages_sender_idx on public.thread_messages (thread_id, player_id);

create table public.ledger (
  id int generated always as identity primary key,
  game_id int not null,
  player_id int not null,
  tick int not null,
  type text not null check (type in ('starting_gold', 'production', 'send_gold', 'receive_gold', 'recruit', 'upgrade', 'road', 'capture', 'salvage')),
  amount int not null check (amount <> 0),
  counterparty_player_id int,
  created_at timestamptz not null default now(),
  foreign key (game_id, player_id) references public.game_players (game_id, id) on delete cascade,
  foreign key (game_id, counterparty_player_id) references public.game_players (game_id, id) on delete set null (counterparty_player_id)
);

create index ledger_player_tick_idx on public.ledger (game_id, player_id, tick desc);
create index ledger_counterparty_idx on public.ledger (game_id, counterparty_player_id);

create table public.intel_snapshots (
  id int generated always as identity primary key,
  game_id int not null references public.games (id) on delete cascade,
  tick int not null,
  payload jsonb not null,
  created_at timestamptz not null default now(),
  unique (game_id, tick)
);

create function public.is_thread_participant(p_thread_id int)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.thread_participants tp
    join public.game_players gp on gp.id = tp.player_id
    where tp.thread_id = p_thread_id
      and gp.user_id = (select auth.uid())
  );
$$;

revoke execute on function public.is_thread_participant(int) from public, anon;
grant execute on function public.is_thread_participant(int) to authenticated;

alter table public.diplomacy enable row level security;
alter table public.player_inbox enable row level security;
alter table public.game_events enable row level security;
alter table public.game_moments enable row level security;
alter table public.game_chat enable row level security;
alter table public.message_threads enable row level security;
alter table public.thread_participants enable row level security;
alter table public.thread_messages enable row level security;
alter table public.ledger enable row level security;
alter table public.intel_snapshots enable row level security;

create policy "diplomacy is readable by the two players involved"
  on public.diplomacy for select to authenticated
  using (
    exists (
      select 1
      from public.game_players gp
      where gp.id in (player_a_id, player_b_id)
        and gp.user_id = (select auth.uid())
    )
  );

create policy "inbox is readable by its owner"
  on public.player_inbox for select to authenticated
  using (
    exists (
      select 1
      from public.game_players gp
      where gp.id = player_id
        and gp.user_id = (select auth.uid())
    )
  );

create policy "inbox read flag is updatable by its owner"
  on public.player_inbox for update to authenticated
  using (
    exists (
      select 1
      from public.game_players gp
      where gp.id = player_id
        and gp.user_id = (select auth.uid())
    )
  )
  with check (
    exists (
      select 1
      from public.game_players gp
      where gp.id = player_id
        and gp.user_id = (select auth.uid())
    )
  );

revoke update on public.player_inbox from authenticated;
grant update (is_read) on public.player_inbox to authenticated;

create policy "moments are readable when public or involving the viewer"
  on public.game_moments for select to authenticated
  using (
    public.is_game_member(game_id)
    and (
      visibility = 'public'
      or exists (
        select 1
        from public.game_players gp
        where gp.game_id = game_moments.game_id
          and gp.user_id = (select auth.uid())
          and gp.id = any (involved_player_ids)
      )
    )
  );

create policy "chat is readable by game members"
  on public.game_chat for select to authenticated
  using (public.is_game_member(game_id));

create policy "threads are readable by participants"
  on public.message_threads for select to authenticated
  using (public.is_thread_participant(id));

create policy "participants are readable by thread participants"
  on public.thread_participants for select to authenticated
  using (public.is_thread_participant(thread_id));

create policy "participants can update their own read marker"
  on public.thread_participants for update to authenticated
  using (
    exists (
      select 1
      from public.game_players gp
      where gp.id = player_id
        and gp.user_id = (select auth.uid())
    )
  )
  with check (
    exists (
      select 1
      from public.game_players gp
      where gp.id = player_id
        and gp.user_id = (select auth.uid())
    )
  );

revoke update on public.thread_participants from authenticated;
grant update (last_read_at) on public.thread_participants to authenticated;

create policy "thread messages are readable by participants"
  on public.thread_messages for select to authenticated
  using (public.is_thread_participant(thread_id));

create policy "ledger is readable by its owner"
  on public.ledger for select to authenticated
  using (
    exists (
      select 1
      from public.game_players gp
      where gp.id = player_id
        and gp.user_id = (select auth.uid())
    )
  );

create policy "intel snapshots are readable by game members"
  on public.intel_snapshots for select to authenticated
  using (public.is_game_member(game_id));

alter table public.diplomacy replica identity full;

alter publication supabase_realtime add table
  public.diplomacy,
  public.player_inbox,
  public.game_chat,
  public.thread_messages;
