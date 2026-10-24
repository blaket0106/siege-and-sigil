alter table public.commander_history
  add column foe_player int,
  add column foe_commander int;

do $patch$
declare
  v_def text;
  v_new text;
  v_old text := '      perform public.log_commander(v_c, p_tick, v_kind, v_text);';
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'log_battle_history' and p.pronamespace = 'public'::regnamespace;
  if position(v_old in v_def) = 0 then
    raise exception 'log_battle_history patch did not match';
  end if;
  v_new := replace(v_def, v_old,
    '      insert into public.commander_history (game_id, commander_id, tick, kind, text, foe_player, foe_commander)' || chr(10)
    || '      select c.game_id, c.id, p_tick, v_kind, v_text, v_enemy, (case when v_side = 0 then p_b_ids else p_a_ids end)[1]' || chr(10)
    || '      from public.commanders c where c.id = v_c;');
  execute v_new;
end;
$patch$;

create or replace function public.commander_chronicle(p_commander_id int)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $f$
declare
  v_owner int;
  v_nem jsonb;
  v_foe jsonb;
begin
  select owner_player_id into v_owner from public.commanders where id = p_commander_id;
  if v_owner is null or not exists (select 1 from public.game_players gp where gp.id = v_owner and gp.user_id = auth.uid()) then
    return jsonb_build_object('entries', '[]'::jsonb, 'wins', 0, 'losses', 0, 'castles', 0, 'captured', 0);
  end if;

  select jsonb_build_object('name', fc.name, 'house', public.house_name(fc.owner_player_id), 'times', n.cnt)
  into v_nem
  from (
    select foe_commander, count(*) as cnt, max(id) as mx
    from public.commander_history
    where commander_id = p_commander_id and kind = 'loss' and foe_commander is not null
    group by foe_commander
    order by cnt desc, mx desc
    limit 1
  ) n
  join public.commanders fc on fc.id = n.foe_commander;

  select jsonb_build_object('house', public.house_name(q.foe_player), 'wins', q.w, 'losses', q.l)
  into v_foe
  from (
    select foe_player,
           count(*) filter (where kind in ('win', 'capture')) as w,
           count(*) filter (where kind = 'loss') as l
    from public.commander_history
    where commander_id = p_commander_id and foe_player is not null and kind in ('win', 'capture', 'loss')
    group by foe_player
    order by count(*) desc, max(id) desc
    limit 1
  ) q;

  return jsonb_build_object(
    'entries', coalesce((select jsonb_agg(jsonb_build_object('tick', h.tick, 'kind', h.kind, 'text', h.text) order by h.id desc)
                         from (select * from public.commander_history where commander_id = p_commander_id order by id desc limit 80) h), '[]'::jsonb),
    'wins', (select count(*) from public.commander_history where commander_id = p_commander_id and kind in ('win', 'capture')),
    'losses', (select count(*) from public.commander_history where commander_id = p_commander_id and kind = 'loss'),
    'castles', (select count(*) from public.commander_history where commander_id = p_commander_id and kind = 'capture'),
    'captured', (select count(*) from public.commander_history where commander_id = p_commander_id and kind = 'captured'),
    'nemesis', v_nem,
    'old_foe', v_foe);
end;
$f$;

create function public.commander_growth(p_commander_id int)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $f$
declare
  v_owner int;
  v_rank int;
  v_max int := public.xp_cfg('ability_max_level')::int;
  v_cap int := public.xp_cfg('rank_cap')::int;
begin
  select owner_player_id into v_owner from public.commanders where id = p_commander_id;
  if v_owner is null or not exists (select 1 from public.game_players gp where gp.id = v_owner and gp.user_id = auth.uid()) then
    return null;
  end if;
  select coalesce(sum(level), 0) into v_rank from public.commander_abilities where commander_id = p_commander_id;
  return jsonb_build_object(
    'rank', v_rank, 'rank_cap', v_cap, 'max_level', v_max, 'affinity', public.xp_cfg('school_affinity'),
    'abilities', coalesce((
      select jsonb_agg(jsonb_build_object(
        'ability', ca.ability, 'level', ca.level, 'xp', round(ca.xp::numeric, 1),
        'next', case when ca.level >= v_max or v_rank >= v_cap then null
                     else round((public.xp_cfg('xp_base_cost') * (ca.level + 1) * (1 + public.xp_cfg('xp_rank_step') * v_rank))::numeric, 0) end
      ) order by ca.ability)
      from public.commander_abilities ca where ca.commander_id = p_commander_id
    ), '[]'::jsonb));
end;
$f$;

create function public.rename_commander(p_commander_id int, p_name text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $f$
declare
  v_c public.commanders%rowtype;
  v_name text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  v_tick int;
begin
  select * into v_c from public.commanders where id = p_commander_id;
  if not found or v_c.status = 'dead' then
    raise exception 'commander not found';
  end if;
  if not exists (select 1 from public.game_players gp where gp.id = v_c.owner_player_id and gp.user_id = auth.uid()) then
    raise exception 'that is not your commander';
  end if;
  if v_name !~ '^[A-Za-z][A-Za-z '' -]{1,31}$' then
    raise exception 'use 2 to 32 letters, spaces, hyphens or apostrophes';
  end if;
  select current_tick into v_tick from public.games where id = v_c.game_id;
  if exists (select 1 from public.commander_history h where h.commander_id = v_c.id and h.kind = 'renamed' and h.tick > v_tick - 3) then
    raise exception 'that commander was renamed a moment ago';
  end if;
  if v_name = v_c.name then
    return jsonb_build_object('name', v_c.name);
  end if;
  update public.commanders set name = v_name where id = v_c.id;
  perform public.log_commander(v_c.id, v_tick, 'renamed', format('Came to be known as %s, once called %s.', v_name, v_c.name));
  return jsonb_build_object('name', v_name);
end;
$f$;

create function public.fallen_commanders(p_game_id int)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $f$
declare
  v_me int;
begin
  select id into v_me from public.game_players where game_id = p_game_id and user_id = auth.uid();
  if v_me is null then
    return '[]'::jsonb;
  end if;
  return coalesce((
    select jsonb_agg(r order by r.died_tick desc nulls last, r.id desc)
    from (
      select c.id, c.name, c.school, c.role, c.profile, c.created_tick, c.died_tick,
        (select count(*) from public.commander_history h where h.commander_id = c.id and h.kind in ('win', 'capture')) as wins,
        (select count(*) from public.commander_history h where h.commander_id = c.id and h.kind = 'capture') as castles,
        (select h.text from public.commander_history h where h.commander_id = c.id and h.kind in ('fell', 'executed') order by h.id desc limit 1) as epitaph,
        coalesce((select jsonb_agg(q.text order by q.id desc) from (
          select h.id, h.text from public.commander_history h where h.commander_id = c.id and h.kind in ('capture', 'win', 'named', 'crowned', 'skill') order by h.id desc limit 3) q), '[]'::jsonb) as deeds
      from public.commanders c
      where c.game_id = p_game_id and c.owner_player_id = v_me and c.status = 'dead'
      order by c.died_tick desc nulls last, c.id desc
      limit 60
    ) r
  ), '[]'::jsonb);
end;
$f$;

create table public.castle_notes (
  game_id int not null references public.games (id) on delete cascade,
  player_id int not null references public.game_players (id) on delete cascade,
  territory_id int not null references public.game_territories (id) on delete cascade,
  tag text check (tag in ('staging', 'target', 'watch', 'fortress', 'supply', 'danger')),
  note text check (char_length(note) <= 160),
  updated_at timestamptz not null default now(),
  primary key (player_id, territory_id)
);
alter table public.castle_notes enable row level security;

create function public.my_castle_notes(p_game_id int)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $f$
  select coalesce(jsonb_agg(jsonb_build_object('territory_id', n.territory_id, 'tag', n.tag, 'note', n.note)), '[]'::jsonb)
  from public.castle_notes n
  join public.game_players gp on gp.id = n.player_id
  where n.game_id = p_game_id and gp.user_id = auth.uid()
$f$;

create function public.set_castle_note(p_game_id int, p_territory_id int, p_tag text, p_note text)
returns void
language plpgsql
security definer
set search_path = ''
as $f$
declare
  v_me int;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_tag text := nullif(p_tag, '');
begin
  select id into v_me from public.game_players where game_id = p_game_id and user_id = auth.uid();
  if v_me is null then
    raise exception 'you are not in this game';
  end if;
  if not exists (select 1 from public.game_territories t where t.id = p_territory_id and t.game_id = p_game_id and not t.is_junction) then
    raise exception 'unknown castle';
  end if;
  if v_note is not null and char_length(v_note) > 160 then
    raise exception 'notes are limited to 160 characters';
  end if;
  if v_tag is null and v_note is null then
    delete from public.castle_notes where player_id = v_me and territory_id = p_territory_id;
    return;
  end if;
  insert into public.castle_notes (game_id, player_id, territory_id, tag, note)
  values (p_game_id, v_me, p_territory_id, v_tag, v_note)
  on conflict (player_id, territory_id) do update set tag = excluded.tag, note = excluded.note, updated_at = now();
end;
$f$;

create function public.castle_report(p_game_id int, p_territory_id int)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $f$
declare
  v_me int;
  v_t public.game_territories%rowtype;
  v_game public.games%rowtype;
  v_owner int;
  v_barracks int;
  v_mint int;
  v_muster int;
  v_steward int;
  v_scholar int;
  v_troops float8;
  v_gold float8;
  v_prest float8;
  v_def_ids int[];
  v_def_troops int;
  v_armory int;
  v_valor int;
  v_dmg int;
  v_gar jsonb;
  v_need jsonb := '[]'::jsonb;
  a int;
begin
  select id into v_me from public.game_players where game_id = p_game_id and user_id = auth.uid();
  if v_me is null then
    return null;
  end if;
  select * into v_t from public.game_territories where id = p_territory_id and game_id = p_game_id and not is_junction;
  if not found or v_t.owner_player_id is null then
    return null;
  end if;
  v_owner := v_t.owner_player_id;
  if v_owner <> v_me and not public.are_allied(v_owner, v_me) then
    return null;
  end if;
  select * into v_game from public.games where id = p_game_id;

  select coalesce(level, 1) into v_barracks from public.realm_areas where player_id = v_owner and area = 'barracks';
  select coalesce(level, 1) into v_mint from public.realm_areas where player_id = v_owner and area = 'mint';
  v_barracks := coalesce(v_barracks, 1);
  v_mint := coalesce(v_mint, 1);
  v_muster := public.territory_ability(v_t.id, 'muster');
  v_steward := public.territory_ability(v_t.id, 'steward');
  v_scholar := public.territory_ability(v_t.id, 'scholar');
  v_troops := v_t.industry_level * (v_barracks + 4) * (1 + 0.10 * v_muster);
  v_gold := v_t.treasury_level * (10 + 2 * v_mint) * (1 + 0.10 * v_steward);
  v_prest := v_t.prestige_level * (1 + 0.10 * v_scholar);

  select coalesce(array_agg(c.id order by c.id), '{}') into v_def_ids
  from public.commanders c
  where c.current_territory_id = v_t.id and c.status = 'idle'
    and (c.owner_player_id = v_owner or public.are_allied(v_owner, c.owner_player_id));
  select v_t.troops + coalesce(sum(troops), 0) into v_def_troops from public.commanders where id = any (v_def_ids);
  v_armory := greatest(
    public.armory_level(v_owner),
    coalesce((select max(public.armory_level(c.owner_player_id)) from public.commanders c where c.id = any (v_def_ids)), 0));
  v_valor := public.side_valor(v_def_ids, v_t.garrison_commander_id);
  v_dmg := greatest(1, v_armory + v_valor + 1 + case when v_t.terrain = 'mountain' then 1 else 0 end);
  for a in 1 .. 4 loop
    v_need := v_need || jsonb_build_array(jsonb_build_object('attacker_damage', a, 'troops_needed', v_dmg * ceil(v_def_troops::float8 / a)::int + 1));
  end loop;

  select jsonb_build_object('id', c.id, 'name', c.name) into v_gar
  from public.commanders c where c.id = v_t.garrison_commander_id and c.status <> 'dead';

  return jsonb_build_object(
    'cycle_ticks', v_game.production_cycle_ticks,
    'yield', jsonb_build_object(
      'troops', round(v_troops::numeric, 1), 'gold', round(v_gold::numeric, 1), 'prestige', round(v_prest::numeric, 2),
      'next_troops', round(((v_t.industry_level + 1) * (v_barracks + 4) * (1 + 0.10 * v_muster) - v_troops)::numeric, 1),
      'next_gold', round(((v_t.treasury_level + 1) * (10 + 2 * v_mint) * (1 + 0.10 * v_steward) - v_gold)::numeric, 1),
      'next_prestige', round(((v_t.prestige_level + 1) * (1 + 0.10 * v_scholar) - v_prest)::numeric, 2),
      'barracks', v_barracks, 'mint', v_mint, 'muster', v_muster, 'steward', v_steward, 'scholar', v_scholar),
    'defence', jsonb_build_object(
      'damage', v_dmg, 'armory', v_armory, 'valor', v_valor, 'terrain_bonus', case when v_t.terrain = 'mountain' then 1 else 0 end,
      'troops', v_t.troops, 'stationed', coalesce(array_length(v_def_ids, 1), 0), 'total_troops', v_def_troops,
      'garrison', v_gar, 'needed', v_need));
end;
$f$;

revoke execute on function public.commander_growth(int) from public, anon;
revoke execute on function public.rename_commander(int, text) from public, anon;
revoke execute on function public.fallen_commanders(int) from public, anon;
revoke execute on function public.my_castle_notes(int) from public, anon;
revoke execute on function public.set_castle_note(int, int, text, text) from public, anon;
revoke execute on function public.castle_report(int, int) from public, anon;
grant execute on function public.commander_growth(int) to authenticated;
grant execute on function public.rename_commander(int, text) to authenticated;
grant execute on function public.fallen_commanders(int) to authenticated;
grant execute on function public.my_castle_notes(int) to authenticated;
grant execute on function public.set_castle_note(int, int, text, text) to authenticated;
grant execute on function public.castle_report(int, int) to authenticated;
