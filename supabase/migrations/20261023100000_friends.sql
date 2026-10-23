create function public.gen_friend_code()
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
    for i in 1..8 loop
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * 32)::int, 1);
    end loop;
    v_code := substr(v_code, 1, 4) || '-' || substr(v_code, 5, 4);
    exit when not exists (select 1 from public.profiles p where p.friend_code = v_code);
  end loop;
  return v_code;
end;
$function$;

revoke execute on function public.gen_friend_code() from anon, authenticated, public;

alter table public.profiles add column friend_code text;
alter table public.profiles add column stats_visibility text not null default 'friends' check (stats_visibility in ('friends', 'public'));
update public.profiles set friend_code = public.gen_friend_code() where friend_code is null;
alter table public.profiles alter column friend_code set default public.gen_friend_code();
alter table public.profiles alter column friend_code set not null;
create unique index profiles_friend_code_key on public.profiles (friend_code);

grant select (friend_code, stats_visibility) on public.profiles to authenticated;
alter policy "profiles are readable by signed-in users" on public.profiles using (user_id = (select auth.uid()));

create table public.friendships (
  id bigint generated always as identity primary key,
  user_low uuid not null references auth.users (id) on delete cascade,
  user_high uuid not null references auth.users (id) on delete cascade,
  requested_by uuid not null references auth.users (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  check (user_low < user_high),
  check (requested_by in (user_low, user_high)),
  unique (user_low, user_high)
);
create index friendships_user_high_idx on public.friendships (user_high);
alter table public.friendships enable row level security;
revoke all on public.friendships from anon, authenticated;

create function public.create_friend_request(p_from uuid, p_to uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  f public.friendships;
  v_pending int;
begin
  if p_from = p_to then
    raise exception 'You cannot add yourself';
  end if;
  select * into f from public.friendships where user_low = least(p_from, p_to) and user_high = greatest(p_from, p_to);
  if found then
    if f.status = 'accepted' then
      raise exception 'You are already friends';
    elsif f.requested_by = p_to then
      update public.friendships set status = 'accepted', responded_at = now() where id = f.id;
      return 'accepted';
    else
      raise exception 'Request already sent';
    end if;
  end if;
  select count(*) into v_pending from public.friendships where requested_by = p_from and status = 'pending';
  if v_pending >= 30 then
    raise exception 'You have too many pending requests';
  end if;
  insert into public.friendships (user_low, user_high, requested_by) values (least(p_from, p_to), greatest(p_from, p_to), p_from);
  return 'sent';
end;
$function$;

revoke execute on function public.create_friend_request(uuid, uuid) from anon, authenticated, public;

create function public.my_social()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select jsonb_build_object('code', p.friend_code, 'visibility', p.stats_visibility)
  from public.profiles p where p.user_id = (select auth.uid());
$function$;

create function public.set_stats_visibility(p_value text)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if p_value not in ('friends', 'public') then
    raise exception 'Choose friends or public';
  end if;
  update public.profiles set stats_visibility = p_value where user_id = (select auth.uid());
end;
$function$;

create function public.friend_request_by_code(p_code text)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_other uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Sign in first';
  end if;
  select p.user_id into v_other from public.profiles p where p.friend_code = upper(trim(p_code));
  if v_other is null then
    raise exception 'No one has that friend code';
  end if;
  return public.create_friend_request((select auth.uid()), v_other);
end;
$function$;

create function public.friend_request_from_game(p_game_id integer, p_player_id integer)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_other uuid;
begin
  if not exists (select 1 from public.games g where g.id = p_game_id and g.status = 'finished') then
    raise exception 'You can add friends from a game once it has finished';
  end if;
  if not public.is_game_member(p_game_id) then
    raise exception 'You were not in that game';
  end if;
  select gp.user_id into v_other from public.game_players gp where gp.id = p_player_id and gp.game_id = p_game_id and not gp.is_ai;
  if v_other is null then
    raise exception 'That player cannot be added';
  end if;
  return public.create_friend_request((select auth.uid()), v_other);
end;
$function$;

create function public.respond_friend_request(p_id bigint, p_accept boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  f public.friendships;
  v_me uuid := (select auth.uid());
begin
  select * into f from public.friendships where id = p_id and status = 'pending' and v_me in (user_low, user_high) and requested_by <> v_me;
  if not found then
    raise exception 'That request is no longer there';
  end if;
  if p_accept then
    update public.friendships set status = 'accepted', responded_at = now() where id = p_id;
  else
    delete from public.friendships where id = p_id;
  end if;
end;
$function$;

create function public.remove_friend(p_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  delete from public.friendships where id = p_id and (select auth.uid()) in (user_low, user_high);
end;
$function$;

create function public.list_friends()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  with me as (select (select auth.uid()) as id),
  rows as (
    select f.id, f.status, f.requested_by, p.display_name, p.honor, p.infamy, p.total_games, p.total_wins
    from public.friendships f
    join me on me.id in (f.user_low, f.user_high)
    join public.profiles p on p.user_id = case when f.user_low = me.id then f.user_high else f.user_low end
  )
  select jsonb_build_object(
    'friends', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'name', r.display_name, 'honor', r.honor, 'infamy', r.infamy, 'games', r.total_games, 'wins', r.total_wins) order by lower(r.display_name)) from rows r where r.status = 'accepted'), '[]'::jsonb),
    'incoming', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'name', r.display_name) order by r.id) from rows r, me where r.status = 'pending' and r.requested_by <> me.id), '[]'::jsonb),
    'outgoing', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'name', r.display_name) order by r.id) from rows r, me where r.status = 'pending' and r.requested_by = me.id), '[]'::jsonb)
  );
$function$;

create function public.friend_profile(p_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_me uuid := (select auth.uid());
  f public.friendships;
  v_other uuid;
  v_profile public.profiles;
begin
  select * into f from public.friendships where id = p_id and status = 'accepted' and v_me in (user_low, user_high);
  if not found then
    raise exception 'You are not friends with that player';
  end if;
  v_other := case when f.user_low = v_me then f.user_high else f.user_low end;
  select * into v_profile from public.profiles where user_id = v_other;
  return jsonb_build_object(
    'name', v_profile.display_name,
    'honor', v_profile.honor,
    'infamy', v_profile.infamy,
    'games', v_profile.total_games,
    'wins', v_profile.total_wins,
    'joined', v_profile.created_at,
    'friends_since', f.responded_at,
    'favorite_house', (
      select gp.faction_slug from public.game_players gp join public.games g on g.id = gp.game_id
      where gp.user_id = v_other and g.status = 'finished'
      group by gp.faction_slug order by count(*) desc, gp.faction_slug limit 1
    ),
    'recent', coalesce((
      select jsonb_agg(jsonb_build_object('name', x.name, 'faction', x.faction_slug, 'won', x.won, 'ticks', x.current_tick) order by x.gid desc)
      from (
        select g.id as gid, g.name, gp.faction_slug, g.current_tick, (g.winner_player_id = gp.id) as won
        from public.game_players gp join public.games g on g.id = gp.game_id
        where gp.user_id = v_other and g.status = 'finished'
        order by g.id desc limit 8
      ) x
    ), '[]'::jsonb)
  );
end;
$function$;

grant execute on function public.my_social(), public.set_stats_visibility(text), public.friend_request_by_code(text), public.friend_request_from_game(integer, integer),
  public.respond_friend_request(bigint, boolean), public.remove_friend(bigint), public.list_friends(), public.friend_profile(bigint) to authenticated;
revoke execute on function public.my_social(), public.set_stats_visibility(text), public.friend_request_by_code(text), public.friend_request_from_game(integer, integer),
  public.respond_friend_request(bigint, boolean), public.remove_friend(bigint), public.list_friends(), public.friend_profile(bigint) from anon, public;

create or replace function public.get_leaderboard(p_limit integer default 25)
returns table (display_name text, honor integer, infamy integer, total_games integer, total_wins integer)
language sql
stable
security definer
set search_path = ''
as $function$
  select p.display_name, p.honor, p.infamy, p.total_games, p.total_wins
  from public.profiles p
  where p.total_games > 0 and p.stats_visibility = 'public'
  order by p.honor desc, p.total_wins desc, p.display_name
  limit least(greatest(coalesce(p_limit, 25), 1), 100);
$function$;
