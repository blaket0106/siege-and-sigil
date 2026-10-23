create or replace function public.gen_join_code()
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_bytes bytea;
  v_code text;
  i int;
begin
  loop
    v_bytes := extensions.gen_random_bytes(8);
    v_code := '';
    for i in 0..7 loop
      v_code := v_code || substr(v_alphabet, 1 + (get_byte(v_bytes, i) % 32), 1);
    end loop;
    v_code := substr(v_code, 1, 4) || '-' || substr(v_code, 5, 4);
    exit when not exists (select 1 from public.games g where g.join_code = v_code);
  end loop;
  return v_code;
end;
$function$;

create or replace function public.gen_friend_code()
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_bytes bytea;
  v_code text;
  i int;
begin
  loop
    v_bytes := extensions.gen_random_bytes(8);
    v_code := '';
    for i in 0..7 loop
      v_code := v_code || substr(v_alphabet, 1 + (get_byte(v_bytes, i) % 32), 1);
    end loop;
    v_code := substr(v_code, 1, 4) || '-' || substr(v_code, 5, 4);
    exit when not exists (select 1 from public.profiles p where p.friend_code = v_code);
  end loop;
  return v_code;
end;
$function$;

update public.games set join_code = public.gen_join_code();

create table public.join_code_failures (
  user_id uuid not null references auth.users (id) on delete cascade,
  at timestamptz not null default now()
);
create index join_code_failures_user_idx on public.join_code_failures (user_id, at);
alter table public.join_code_failures enable row level security;
revoke all on public.join_code_failures from anon, authenticated;

create function public.check_code_attempts()
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_me uuid := (select auth.uid());
begin
  if v_me is null then
    raise exception 'Sign in first';
  end if;
  delete from public.join_code_failures where at < now() - interval '1 hour';
  if (select count(*) from public.join_code_failures f where f.user_id = v_me and f.at > now() - interval '10 minutes') >= 15 then
    raise exception 'Too many wrong codes. Wait a few minutes and try again';
  end if;
end;
$function$;

revoke execute on function public.check_code_attempts() from anon, authenticated, public;

create or replace function public.lookup_game_by_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  g public.games;
begin
  perform public.check_code_attempts();
  select * into g from public.games where join_code = upper(trim(p_code));
  if not found then
    insert into public.join_code_failures (user_id) values ((select auth.uid()));
    return jsonb_build_object('error', 'No game has that code');
  end if;
  if g.status <> 'lobby' then
    return jsonb_build_object('error', 'That game has already started');
  end if;
  return public.game_lobby_card(g.id);
end;
$function$;

create or replace function public.join_game_by_code(p_code text, p_faction_slug text default null, p_password text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  g public.games;
begin
  perform public.check_code_attempts();
  select * into g from public.games where join_code = upper(trim(p_code));
  if not found then
    insert into public.join_code_failures (user_id) values ((select auth.uid()));
    return null;
  end if;
  perform set_config('app.join_code_game', g.id::text, true);
  return public.join_game(g.id, p_faction_slug, p_password);
end;
$function$;
