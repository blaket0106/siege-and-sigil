create function public.player_regard(p_game_id int, p_observer int, p_other int)
returns int
language plpgsql
stable
security definer
set search_path = ''
as $f$
declare
  v_tick int;
  v_cap float8;
  v_war float8;
  v_gold float8;
  v_tech float8;
  v_st text;
  v_s float8;
begin
  select current_tick into v_tick from public.games where id = p_game_id;
  select coalesce(sum(greatest(0.25, 1 - (v_tick - m.tick) / 120.0)), 0) into v_cap
  from public.game_moments m
  where m.game_id = p_game_id and m.type = 'castle_captured'
    and (m.payload ->> 'from_player_id')::int = p_observer and (m.payload ->> 'to_player_id')::int = p_other;
  select coalesce(sum(greatest(0.25, 1 - (v_tick - m.tick) / 120.0)), 0) into v_war
  from public.game_moments m
  where m.game_id = p_game_id and m.type = 'war_declared'
    and (m.payload ->> 'by_player_id')::int = p_other and (m.payload ->> 'against_player_id')::int = p_observer;
  select coalesce(sum(least(6, l.amount / 25.0) * greatest(0.25, 1 - (v_tick - l.tick) / 120.0)), 0) into v_gold
  from public.ledger l
  where l.game_id = p_game_id and l.player_id = p_observer and l.type = 'receive_gold' and l.counterparty_player_id = p_other;
  select coalesce(sum(5 * greatest(0.25, 1 - (v_tick - e.tick) / 120.0)), 0) into v_tech
  from public.game_events e
  where e.game_id = p_game_id and e.type = 'tech_shared'
    and (e.payload ->> 'from')::int = p_other and (e.payload ->> 'to')::int = p_observer;
  select d.status into v_st from public.diplomacy d
  where d.game_id = p_game_id and d.player_a_id = least(p_observer, p_other) and d.player_b_id = greatest(p_observer, p_other);
  v_s := -4 * v_cap - 8 * v_war + v_gold + v_tech + case v_st when 'allied' then 4 when 'war' then -3 else 0 end;
  return greatest(-10, least(10, round(v_s)::int));
end;
$f$;
revoke execute on function public.player_regard(int, int, int) from public, anon, authenticated;

create function public.regards(p_game_id int)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $f$
declare
  v_me int;
begin
  select id into v_me from public.game_players where game_id = p_game_id and user_id = (select auth.uid());
  if v_me is null then
    raise exception 'you are not in this game';
  end if;
  return coalesce((
    select jsonb_object_agg(p.id::text, public.player_regard(p_game_id, p.id, v_me))
    from public.game_players p
    where p.game_id = p_game_id and p.is_ai and p.eliminated_at_tick is null
  ), '{}'::jsonb);
end;
$f$;
revoke execute on function public.regards(int) from public, anon;
grant execute on function public.regards(int) to authenticated;

create function public.intel_live(p_game_id int)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $f$
declare
  v_me int;
begin
  select id into v_me from public.game_players where game_id = p_game_id and user_id = (select auth.uid());
  if v_me is null then
    raise exception 'you are not in this game';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('tick', s.tick, 'payload', jsonb_build_object('players', (
      select coalesce(jsonb_agg(case when (q ->> 'player_id')::int = v_me then q else q - 'gold' end), '[]'::jsonb)
      from jsonb_array_elements(s.payload -> 'players') q))) order by s.tick)
    from public.intel_snapshots s where s.game_id = p_game_id
  ), '[]'::jsonb);
end;
$f$;
revoke execute on function public.intel_live(int) from public, anon;
grant execute on function public.intel_live(int) to authenticated;

create function public.research_info(p_game_id int)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $f$
declare
  v_me int;
  v_g public.games%rowtype;
  v_income float8;
  v_lib int;
begin
  select id into v_me from public.game_players where game_id = p_game_id and user_id = (select auth.uid());
  if v_me is null then
    raise exception 'you are not in this game';
  end if;
  select * into v_g from public.games where id = p_game_id;
  select coalesce(sum(t.prestige_level * (1 + 0.10 * public.territory_ability(t.id, 'scholar'))), 0) into v_income
  from public.game_territories t where t.game_id = p_game_id and t.owner_player_id = v_me and not t.is_junction;
  select coalesce(level, 0) into v_lib from public.realm_areas where player_id = v_me and area = 'library';
  return jsonb_build_object(
    'cycle_ticks', v_g.production_cycle_ticks,
    'ticks_to_cycle', v_g.production_cycle_ticks - (v_g.current_tick % v_g.production_cycle_ticks),
    'income', round(v_income::numeric, 1),
    'library_bonus', case when v_g.experimentation_enabled then round((72 * v_lib * v_g.experiment_bonus_mult)::numeric, 0) else 0 end,
    'areas', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'area', ra.area, 'level', ra.level, 'accumulated', ra.prestige_accumulated, 'active', ra.is_active,
        'need', ceil(144 * ra.level * v_g.area_cost_mult * coalesce((v_g.area_cost_mults ->> ra.area)::float8, 1))::int,
        'disabled', v_g.area_cost_mult * coalesce((v_g.area_cost_mults ->> ra.area)::float8, 1) <= 0 or (ra.area = 'guildhall' and not v_g.terraforming_enabled)
      ) order by ra.area), '[]'::jsonb)
      from public.realm_areas ra where ra.player_id = v_me));
end;
$f$;
revoke execute on function public.research_info(int) from public, anon;
grant execute on function public.research_info(int) to authenticated;

create function public.abandon_castle(p_game_id int, p_territory_id int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $f$
declare
  v_player public.game_players;
  v_t public.game_territories%rowtype;
  v_tick int;
begin
  v_player := public.acting_player(p_game_id);
  select * into v_t from public.game_territories where id = p_territory_id and game_id = p_game_id and not is_junction for update;
  if not found or v_t.owner_player_id is distinct from v_player.id then
    raise exception 'that castle is not yours';
  end if;
  if (select count(*) from public.game_territories where game_id = p_game_id and owner_player_id = v_player.id and not is_junction) <= 1 then
    raise exception 'you cannot abandon your last castle';
  end if;
  if exists (select 1 from public.commanders c where c.game_id = p_game_id and c.current_territory_id = v_t.id and c.status in ('idle', 'sieging') and c.owner_player_id = v_player.id) then
    raise exception 'move your commanders out of the castle first';
  end if;
  if exists (select 1 from public.commanders c where c.game_id = p_game_id and c.current_territory_id = v_t.id and c.status = 'sieging' and c.owner_player_id <> v_player.id) then
    raise exception 'the castle is under siege';
  end if;
  select current_tick into v_tick from public.games where id = p_game_id;
  update public.game_territories set owner_player_id = null, troops = 0, troop_accum = 0, garrison_commander_id = null, has_road = false where id = v_t.id;
  insert into public.territory_owner_log (game_id, tick, territory_id, owner_player_id) values (p_game_id, v_tick, v_t.id, null) on conflict (game_id, tick, territory_id) do update set owner_player_id = null;
  insert into public.game_moments (game_id, tick, type, payload, visibility, involved_player_ids)
  values (p_game_id, v_tick, 'castle_abandoned', jsonb_build_object('territory', v_t.name, 'territory_id', v_t.id, 'player_id', v_player.id), 'public', array[v_player.id]);
  return jsonb_build_object('abandoned', v_t.name);
end;
$f$;
revoke execute on function public.abandon_castle(int, int) from public, anon;
grant execute on function public.abandon_castle(int, int) to authenticated;

create function public.game_awards(p_game_id int)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $f$
declare
  v_g public.games%rowtype;
begin
  select * into v_g from public.games where id = p_game_id;
  if not found or v_g.status <> 'finished' then
    return null;
  end if;
  if not exists (select 1 from public.game_players where game_id = p_game_id and user_id = (select auth.uid())) then
    return null;
  end if;
  return (
    with st as (
      select gp.id, gp.display_name, gp.faction_slug,
        (select count(*) from public.game_territories t where t.game_id = p_game_id and t.owner_player_id = gp.id and not t.is_junction) as castles,
        (select count(*) from public.game_moments m where m.game_id = p_game_id and m.type = 'castle_captured' and (m.payload ->> 'to_player_id')::int = gp.id) as captures,
        (select count(*) from public.game_moments m where m.game_id = p_game_id and m.type = 'castle_captured' and (m.payload ->> 'from_player_id')::int = gp.id) as lost,
        (select count(*) from public.battle_reports b where b.game_id = p_game_id and gp.id = any (b.involved_player_ids)) as battles
      from public.game_players gp where gp.game_id = p_game_id
    ), sc as (
      select st.*, st.castles * 10 + st.captures * 3 + st.battles + case when st.id = v_g.winner_player_id then 50 else 0 end as score from st
    )
    select jsonb_build_object(
      'scores', (select coalesce(jsonb_agg(jsonb_build_object('player_id', id, 'name', display_name, 'faction', faction_slug, 'castles', castles, 'captures', captures, 'lost', lost, 'battles', battles, 'score', score) order by score desc, id), '[]'::jsonb) from sc),
      'badges', (
        select coalesce(jsonb_agg(b), '[]'::jsonb) from (
          select jsonb_build_object('badge', 'Conqueror', 'note', 'Most castles taken', 'player_id', id, 'name', display_name, 'value', captures) b from (select * from sc order by captures desc, id limit 1) x where captures > 0
          union all
          select jsonb_build_object('badge', 'Iron Wall', 'note', 'Fewest castles lost', 'player_id', id, 'name', display_name, 'value', lost) from (select * from sc where castles > 0 order by lost, id limit 1) x
          union all
          select jsonb_build_object('badge', 'Warlord', 'note', 'Most battles fought', 'player_id', id, 'name', display_name, 'value', battles) from (select * from sc order by battles desc, id limit 1) x where battles > 0
          union all
          select jsonb_build_object('badge', 'Last House Standing', 'note', 'Held the most castles at the end', 'player_id', id, 'name', display_name, 'value', castles) from (select * from sc order by castles desc, id limit 1) x
        ) q))
  );
end;
$f$;
revoke execute on function public.game_awards(int) from public, anon;
grant execute on function public.game_awards(int) to authenticated;

do $patch$
declare
  v_def text;
  v_new text;
  v_pairs text[] := array[
    'random() >= v_chance * (case',
    'random() >= least(0.97, v_chance * (1 + 0.08 * public.player_regard(p_game_id, p_player_id, v_d.proposed_by_player_id))) * (case',
    'if random() < v_pc then',
    'if random() < least(0.97, greatest(0.02, v_pc + 0.04 * public.player_regard(p_game_id, p_player_id, v_d.proposed_by_player_id))) then'
  ];
  i int;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'ai_diplomacy' and p.pronamespace = 'public'::regnamespace;
  v_new := v_def;
  for i in 1 .. array_length(v_pairs, 1) / 2 loop
    if position(v_pairs[2 * i - 1] in v_new) = 0 then
      raise exception 'ai_diplomacy patch % did not match', i;
    end if;
    v_new := replace(v_new, v_pairs[2 * i - 1], v_pairs[2 * i]);
  end loop;
  execute v_new;
end;
$patch$;
