alter table public.game_players add column if not exists ai_style text not null default 'balanced';
alter table public.game_players drop constraint if exists game_players_ai_style_check;
alter table public.game_players add constraint game_players_ai_style_check check (ai_style in ('defensive', 'balanced', 'aggressive'));

drop function if exists public.add_ai_seat(int, int, text);
create function public.add_ai_seat(p_game_id int, p_difficulty int default 3, p_faction text default null, p_style text default 'balanced')
returns int
language plpgsql
security definer
set search_path = ''
as $f$
declare
  g public.games;
  v_faction text;
  v_name text;
  v_id integer;
begin
  select * into g from public.games where id = p_game_id and created_by = (select auth.uid()) for update;
  if not found then
    raise exception 'Only the host can change the seats';
  end if;
  if g.status <> 'lobby' then
    raise exception 'The game has already started';
  end if;
  if (select count(*) from public.game_players gp where gp.game_id = p_game_id) >= g.max_players then
    raise exception 'There is no open seat';
  end if;
  if p_style not in ('defensive', 'balanced', 'aggressive') then
    raise exception 'Unknown AI style';
  end if;
  if p_faction is null then
    select f.slug, f.name into v_faction, v_name from public.factions f
    where not exists (select 1 from public.game_players gp where gp.game_id = p_game_id and gp.faction_slug = f.slug)
    order by random() limit 1;
  else
    select f.slug, f.name into v_faction, v_name from public.factions f where f.slug = p_faction;
    if v_faction is null then
      raise exception 'Unknown house';
    end if;
    if exists (select 1 from public.game_players gp where gp.game_id = p_game_id and gp.faction_slug = v_faction) then
      raise exception 'That house is already taken';
    end if;
  end if;
  if v_faction is null then
    raise exception 'No free house is left';
  end if;
  insert into public.game_players (game_id, faction_slug, display_name, is_ai, ai_difficulty, ai_style)
  values (p_game_id, v_faction, 'AI ' || v_name, true, greatest(1, least(5, coalesce(p_difficulty, 3))), p_style)
  returning id into v_id;
  return v_id;
end;
$f$;
revoke execute on function public.add_ai_seat(int, int, text, text) from public, anon;
grant execute on function public.add_ai_seat(int, int, text, text) to authenticated;

drop function if exists public.set_ai_seat(int, int, int, text);
create function public.set_ai_seat(p_game_id int, p_player_id int, p_difficulty int, p_faction text default null, p_style text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $f$
declare
  g public.games;
  v_name text;
begin
  select * into g from public.games where id = p_game_id and created_by = (select auth.uid()) for update;
  if not found then
    raise exception 'Only the host can change the seats';
  end if;
  if g.status <> 'lobby' then
    raise exception 'The game has already started';
  end if;
  if not exists (select 1 from public.game_players gp where gp.id = p_player_id and gp.game_id = p_game_id and gp.is_ai) then
    raise exception 'That seat is not an AI';
  end if;
  if p_style is not null and p_style not in ('defensive', 'balanced', 'aggressive') then
    raise exception 'Unknown AI style';
  end if;
  update public.game_players set ai_difficulty = greatest(1, least(5, coalesce(p_difficulty, 3))), ai_style = coalesce(p_style, ai_style) where id = p_player_id;
  if p_faction is not null then
    select f.name into v_name from public.factions f where f.slug = p_faction;
    if v_name is null then
      raise exception 'Unknown house';
    end if;
    if exists (select 1 from public.game_players gp where gp.game_id = p_game_id and gp.faction_slug = p_faction and gp.id <> p_player_id) then
      raise exception 'That house is already taken';
    end if;
    update public.game_players set faction_slug = p_faction, display_name = 'AI ' || v_name where id = p_player_id;
  end if;
end;
$f$;
revoke execute on function public.set_ai_seat(int, int, int, text, text) from public, anon;
grant execute on function public.set_ai_seat(int, int, int, text, text) to authenticated;

do $patch$
declare
  v_def text;
  v_new text;
  v_fn text;
  v_pairs text[];
  i int;
begin
  for v_fn, v_pairs in
    select * from (values
      ('room_players', array[
        '''ai_difficulty'', gp.ai_difficulty,',
        '''ai_difficulty'', gp.ai_difficulty, ''ai_style'', gp.ai_style,'
      ]),
      ('ai_commanders', array[
        E'  v_n_cmds int := 0;\nbegin',
        E'  v_n_cmds int := 0;\n  v_style text;\nbegin',
        E'  v_reserve := 8 - p_difficulty;\n',
        E'  select gp.ai_style into v_style from public.game_players gp where gp.id = p_player_id;\n  v_margin := greatest(1.0, v_margin * case v_style when ''defensive'' then 1.5 when ''aggressive'' then 0.92 else 1.0 end);\n  v_reserve := greatest(2, 8 - p_difficulty + case v_style when ''defensive'' then 6 when ''aggressive'' then -3 else 0 end);\n',
        E'order by (select (t0.x - gt.x) ^ 2 + (t0.y - gt.y) ^ 2 from public.game_territories t0 where t0.id = v_c.current_territory_id), gt.id\n      limit 12',
        E'order by (select (t0.x - gt.x) ^ 2 + (t0.y - gt.y) ^ 2 from public.game_territories t0 where t0.id = v_c.current_territory_id) * (case when gt.owner_player_id is not null then (case v_style when ''aggressive'' then 0.25 when ''balanced'' then 0.6 else 1.6 end) else 1 end), gt.id\n      limit 12',
        'v_score := v_t.tier * 3 + case when v_t.owner_player_id is null then 2 else 0 end + v_t.treasury_level',
        'v_score := v_t.tier * 3 + case when v_t.owner_player_id is null then (case v_style when ''defensive'' then 4 when ''aggressive'' then 0 else 2 end) else (case v_style when ''aggressive'' then 3 else 0 end) end + v_t.treasury_level',
        E'v_score := v_t.tier * 3\n        + case when v_t.owner_player_id is null then 2 else 0 end\n        + v_t.treasury_level',
        E'v_score := v_t.tier * 3\n        + case when v_t.owner_player_id is null then (case v_style when ''defensive'' then 4 when ''aggressive'' then 0 else 2 end) else (case v_style when ''aggressive'' then 3 else 0 end) end\n        + v_t.treasury_level'
      ]),
      ('ai_reinforce', array[
        E'  v_per_target int;\nbegin',
        E'  v_per_target int;\n  v_style text;\nbegin',
        E'  select current_tick into v_tick from public.games where id = p_game_id;\n\n  for v_t in',
        E'  select current_tick into v_tick from public.games where id = p_game_id;\n  select gp.ai_style into v_style from public.game_players gp where gp.id = p_player_id;\n  v_margin := v_margin + case v_style when ''defensive'' then 0.3 when ''aggressive'' then -0.1 else 0 end;\n  v_reserve := v_reserve + case v_style when ''defensive'' then 4 else 0 end;\n\n  for v_t in'
      ])
    ) as t(fn, pairs)
  loop
    select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = v_fn and p.pronamespace = 'public'::regnamespace order by p.oid limit 1;
    v_new := v_def;
    for i in 1 .. array_length(v_pairs, 1) / 2 loop
      if position(v_pairs[2 * i - 1] in v_new) = 0 then
        raise exception '% patch % did not match', v_fn, i;
      end if;
      v_new := replace(v_new, v_pairs[2 * i - 1], v_pairs[2 * i]);
    end loop;
    execute v_new;
  end loop;
end;
$patch$;
