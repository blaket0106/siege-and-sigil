create function public.is_my_player(p_player_id integer)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1 from public.game_players gp
    where gp.id = p_player_id and gp.user_id = (select auth.uid())
  );
$function$;

create function public.my_player_id(p_game_id integer)
returns integer
language sql
stable
security definer
set search_path = ''
as $function$
  select gp.id from public.game_players gp
  where gp.game_id = p_game_id and gp.user_id = (select auth.uid())
  limit 1;
$function$;

grant execute on function public.is_my_player(integer), public.my_player_id(integer) to authenticated;
revoke execute on function public.is_my_player(integer), public.my_player_id(integer) from anon, public;

alter policy "realm areas are readable by their owner" on public.realm_areas
  using (public.is_my_player(player_id));
alter policy "diplomacy is readable by the two players involved" on public.diplomacy
  using (public.is_my_player(player_a_id) or public.is_my_player(player_b_id));
alter policy "inbox is readable by its owner" on public.player_inbox
  using (public.is_my_player(player_id));
alter policy "inbox read flag is updatable by its owner" on public.player_inbox
  using (public.is_my_player(player_id)) with check (public.is_my_player(player_id));
alter policy "moments are readable when public or involving the viewer" on public.game_moments
  using (public.is_game_member(game_id) and (visibility = 'public' or public.my_player_id(game_id) = any (involved_player_ids)));
alter policy "participants can update their own read marker" on public.thread_participants
  using (public.is_my_player(player_id)) with check (public.is_my_player(player_id));
alter policy "ledger is readable by its owner" on public.ledger
  using (public.is_my_player(player_id));
alter policy "battle reports are readable by the players involved" on public.battle_reports
  using (public.my_player_id(game_id) = any (involved_player_ids));

create or replace function public.player_reputations(p_game_id integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_hidden boolean;
begin
  if not public.is_game_member(p_game_id) then
    raise exception 'you are not in this game';
  end if;
  select g.anonymity = 'extra' and g.status <> 'finished' into v_hidden from public.games g where g.id = p_game_id;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'player_id', gp.id,
      'trust', case when p.honor - 2 * p.infamy >= 50 then 'Trusted' when p.honor - 2 * p.infamy <= -20 then 'Notorious' else 'Unproven' end,
      'honor', case when v_hidden then null else p.honor end,
      'infamy', case when v_hidden then null else p.infamy end,
      'games', case when v_hidden then null else p.total_games end,
      'wins', case when v_hidden then null else p.total_wins end
    ) order by gp.id)
    from public.game_players gp
    join public.profiles p on p.user_id = gp.user_id
    where gp.game_id = p_game_id
  ), '[]'::jsonb);
end;
$function$;

create function public.room_players(p_game_id integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_g public.games;
begin
  if not public.is_game_member(p_game_id) then
    raise exception 'you are not in this game';
  end if;
  select * into v_g from public.games where id = p_game_id;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', gp.id, 'game_id', gp.game_id, 'faction_slug', gp.faction_slug, 'display_name', gp.display_name,
      'is_ai', gp.is_ai, 'eliminated_at_tick', gp.eliminated_at_tick, 'created_at', gp.created_at,
      'is_me', gp.user_id = (select auth.uid()),
      'is_host', gp.user_id = v_g.created_by and not (v_g.anonymity = 'extra' and v_g.status <> 'finished')
    ) order by gp.id)
    from public.game_players gp
    where gp.game_id = p_game_id
  ), '[]'::jsonb);
end;
$function$;

create function public.my_games()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', gp.id, 'faction_slug', gp.faction_slug,
    'games', jsonb_build_object('id', g.id, 'name', g.name, 'status', g.status, 'max_players', g.max_players, 'current_tick', g.current_tick, 'created_by', g.created_by)
  ) order by gp.id desc), '[]'::jsonb)
  from public.game_players gp
  join public.games g on g.id = gp.game_id
  where gp.user_id = (select auth.uid());
$function$;

grant execute on function public.room_players(integer), public.my_games() to authenticated;
revoke execute on function public.room_players(integer), public.my_games() from anon, public;

do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.get_game_view(integer)'::regprocedure) into v_def;
  v_new := replace(v_def, '''user_id'', case when v_g.anonymity = ''extra'' and v_g.status <> ''finished'' and p.id <> v_me then null else p.user_id end,', '''is_me'', p.id = v_me,');
  if v_new = v_def or v_new like '%p.user_id%' then
    raise exception 'get_game_view patch did not apply';
  end if;
  execute v_new;
end;
$patch$;
