create function public.gen_join_code()
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_code text;
  i int;
begin
  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * 32)::int, 1);
    end loop;
    v_code := substr(v_code, 1, 3) || '-' || substr(v_code, 4, 3);
    exit when not exists (select 1 from public.games g where g.join_code = v_code);
  end loop;
  return v_code;
end;
$function$;

revoke execute on function public.gen_join_code() from anon, authenticated, public;

alter table public.games add column visibility text not null default 'open' check (visibility in ('open', 'friends', 'invite'));
alter table public.games add column join_code text;
update public.games set join_code = public.gen_join_code() where join_code is null;
alter table public.games alter column join_code set default public.gen_join_code();
alter table public.games alter column join_code set not null;
create unique index games_join_code_key on public.games (join_code);

create table public.game_invites (
  id bigint generated always as identity primary key,
  game_id integer not null references public.games (id) on delete cascade,
  from_user uuid not null references auth.users (id) on delete cascade,
  to_user uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (game_id, to_user)
);
create index game_invites_to_user_idx on public.game_invites (to_user);
alter table public.game_invites enable row level security;
revoke all on public.game_invites from anon, authenticated;

create function public.are_friends(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1 from public.friendships f
    where f.status = 'accepted' and f.user_low = least(p_a, p_b) and f.user_high = greatest(p_a, p_b)
  );
$function$;

revoke execute on function public.are_friends(uuid, uuid) from anon, authenticated, public;

create function public.game_lobby_card(p_game_id integer)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select jsonb_build_object(
    'id', g.id,
    'name', g.name,
    'host_name', coalesce((select p.display_name from public.profiles p where p.user_id = g.created_by), 'Unknown'),
    'max_players', g.max_players,
    'player_count', (select count(*)::int from public.game_players gp where gp.game_id = g.id),
    'taken_factions', coalesce((select jsonb_agg(gp.faction_slug order by gp.id) from public.game_players gp where gp.game_id = g.id), '[]'::jsonb),
    'map_style', g.map_style,
    'map_size', g.map_size,
    'tick_speed', g.tick_speed,
    'fill_with_ai', g.fill_with_ai,
    'victory_pct', g.victory_pct,
    'fog_of_war', g.fog_of_war,
    'created_at', g.created_at,
    'joined', exists (select 1 from public.game_players gp where gp.game_id = g.id and gp.user_id = (select auth.uid())),
    'has_password', g.has_password
  )
  from public.games g where g.id = p_game_id;
$function$;

revoke execute on function public.game_lobby_card(integer) from anon, authenticated, public;

create function public.game_invite_info(p_game_id integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  g public.games;
begin
  select * into g from public.games where id = p_game_id and created_by = (select auth.uid());
  if not found then
    raise exception 'Only the host can share this game';
  end if;
  return jsonb_build_object('code', g.join_code, 'visibility', g.visibility, 'invited', coalesce((select jsonb_agg(i.to_user) from public.game_invites i where i.game_id = p_game_id), '[]'::jsonb));
end;
$function$;

create function public.invite_friend(p_game_id integer, p_friendship_id bigint)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_me uuid := (select auth.uid());
  g public.games;
  f public.friendships;
  v_other uuid;
begin
  select * into g from public.games where id = p_game_id and created_by = v_me;
  if not found then
    raise exception 'Only the host can invite players';
  end if;
  if g.status <> 'lobby' then
    raise exception 'The game has already started';
  end if;
  select * into f from public.friendships where id = p_friendship_id and status = 'accepted' and v_me in (user_low, user_high);
  if not found then
    raise exception 'You are not friends with that player';
  end if;
  v_other := case when f.user_low = v_me then f.user_high else f.user_low end;
  if exists (select 1 from public.game_players gp where gp.game_id = p_game_id and gp.user_id = v_other) then
    raise exception 'That player is already in the game';
  end if;
  if (select count(*) from public.game_invites i where i.game_id = p_game_id) >= 20 then
    raise exception 'You have invited enough players';
  end if;
  insert into public.game_invites (game_id, from_user, to_user) values (p_game_id, v_me, v_other) on conflict (game_id, to_user) do nothing;
  return 'invited';
end;
$function$;

create function public.my_game_invites()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', i.id, 'game_id', g.id, 'game_name', g.name,
    'host_name', coalesce((select p.display_name from public.profiles p where p.user_id = i.from_user), 'A friend')
  ) order by i.id desc), '[]'::jsonb)
  from public.game_invites i
  join public.games g on g.id = i.game_id
  where i.to_user = (select auth.uid())
    and g.status = 'lobby'
    and not exists (select 1 from public.game_players gp where gp.game_id = g.id and gp.user_id = i.to_user);
$function$;

create function public.decline_game_invite(p_id bigint)
returns void
language sql
security definer
set search_path = ''
as $function$
  delete from public.game_invites where id = p_id and to_user = (select auth.uid());
$function$;

create function public.lookup_game_by_code(p_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  g public.games;
begin
  if (select auth.uid()) is null then
    raise exception 'Sign in first';
  end if;
  select * into g from public.games where join_code = upper(trim(p_code));
  if not found then
    raise exception 'No game has that code';
  end if;
  if g.status <> 'lobby' then
    raise exception 'That game has already started';
  end if;
  return public.game_lobby_card(g.id);
end;
$function$;

create function public.join_game_by_code(p_code text, p_faction_slug text default null, p_password text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  g public.games;
begin
  if (select auth.uid()) is null then
    raise exception 'Sign in first';
  end if;
  select * into g from public.games where join_code = upper(trim(p_code));
  if not found then
    raise exception 'No game has that code';
  end if;
  perform set_config('app.join_code_game', g.id::text, true);
  return public.join_game(g.id, p_faction_slug, p_password);
end;
$function$;

grant execute on function public.game_invite_info(integer), public.invite_friend(integer, bigint), public.my_game_invites(), public.decline_game_invite(bigint),
  public.lookup_game_by_code(text), public.join_game_by_code(text, text, text) to authenticated;
revoke execute on function public.game_invite_info(integer), public.invite_friend(integer, bigint), public.my_game_invites(), public.decline_game_invite(bigint),
  public.lookup_game_by_code(text), public.join_game_by_code(text, text, text) from anon, public;

do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.join_game(integer,text,text)'::regprocedure) into v_def;
  v_new := replace(v_def, '  if v_game.status <> ''lobby'' then
    raise exception ''game is not in the lobby'';
  end if;', '  if v_game.status <> ''lobby'' then
    raise exception ''game is not in the lobby'';
  end if;
  if v_game.visibility <> ''open'' and v_game.created_by <> v_uid
     and coalesce(current_setting(''app.join_code_game'', true), '''') <> p_game_id::text
     and not exists (select 1 from public.game_invites i where i.game_id = p_game_id and i.to_user = v_uid)
     and not (v_game.visibility = ''friends'' and public.are_friends(v_uid, v_game.created_by)) then
    raise exception ''This game is by invitation only'';
  end if;');
  if v_new = v_def then
    raise exception 'join_game patch did not apply';
  end if;
  execute v_new;

  select pg_get_functiondef('public.list_open_games()'::regprocedure) into v_def;
  v_new := replace(v_def, '    and (select auth.uid()) is not null
  order by', '    and (select auth.uid()) is not null
    and (
      g.visibility = ''open''
      or g.created_by = (select auth.uid())
      or exists (select 1 from public.game_players gp where gp.game_id = g.id and gp.user_id = (select auth.uid()))
      or exists (select 1 from public.game_invites i where i.game_id = g.id and i.to_user = (select auth.uid()))
      or (g.visibility = ''friends'' and public.are_friends((select auth.uid()), g.created_by))
    )
  order by');
  if v_new = v_def then
    raise exception 'list_open_games patch did not apply';
  end if;
  execute v_new;

  select pg_get_functiondef('public.create_game(jsonb)'::regprocedure) into v_def;
  v_new := replace(v_def, '''home_distance'', ''anonymity'',', '''home_distance'', ''anonymity'', ''visibility'',');
  v_new := replace(v_new, 'anonymity = coalesce(p_settings ->> ''anonymity'', g.anonymity),', 'anonymity = coalesce(p_settings ->> ''anonymity'', g.anonymity),
      visibility = coalesce(p_settings ->> ''visibility'', g.visibility),');
  if v_new = v_def or v_new not like '%visibility = coalesce%' or v_new not like '%''anonymity'', ''visibility'',%' then
    raise exception 'create_game patch did not apply';
  end if;
  execute v_new;
end;
$patch$;
