create function public.game_story(p_game_id int)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $f$
declare
  v_g public.games%rowtype;
  v_ticks int;
  v_b1 int;
  v_b2 int;
  v_houses jsonb;
  v_chapters jsonb;
  v_heroes jsonb;
  v_standing jsonb;
begin
  select * into v_g from public.games where id = p_game_id;
  if not found or v_g.status <> 'finished' then
    return null;
  end if;
  if not exists (select 1 from public.game_players gp where gp.game_id = p_game_id and gp.user_id = auth.uid()) then
    return null;
  end if;
  v_ticks := greatest(v_g.current_tick, 3);
  v_b1 := v_ticks / 3;
  v_b2 := (2 * v_ticks) / 3;
  v_standing := public.game_standing(p_game_id);

  select coalesce(jsonb_agg(jsonb_build_object(
      'player_id', gp.id, 'faction', gp.faction_slug, 'name', gp.display_name, 'is_ai', gp.is_ai,
      'castles', public.castle_count(gp.id), 'eliminated_at_tick', gp.eliminated_at_tick,
      'captures', (select count(*) from public.commander_history h join public.commanders c on c.id = h.commander_id
                   where c.owner_player_id = gp.id and h.kind = 'capture'),
      'commanders', (select count(*) from public.commanders c where c.owner_player_id = gp.id),
      'fallen', (select count(*) from public.commanders c where c.owner_player_id = gp.id and c.status = 'dead')
    ) order by public.castle_count(gp.id) desc, gp.id), '[]'::jsonb)
  into v_houses
  from public.game_players gp where gp.game_id = p_game_id;

  select coalesce(jsonb_agg(jsonb_build_object(
      'n', g.n, 'from', g.f, 'to', least(g.t, v_ticks),
      'captures', coalesce((
        select jsonb_agg(jsonb_build_object('faction', q.faction_slug, 'n', q.cnt) order by q.cnt desc)
        from (
          select gp.faction_slug, count(*) as cnt
          from public.game_moments m
          join public.game_players gp on gp.id = (m.payload ->> 'to_player_id')::int
          where m.game_id = p_game_id and m.type = 'castle_captured' and m.tick >= g.f and m.tick < g.t
          group by gp.faction_slug
        ) q), '[]'::jsonb),
      'events', coalesce((
        select jsonb_agg(jsonb_build_object('tick', e.tick, 'type', e.type, 'payload', e.payload) order by e.tick)
        from (
          select m.tick, m.type, m.payload
          from public.game_moments m
          where m.game_id = p_game_id and m.type in ('player_eliminated', 'king_killed', 'alliance_formed', 'alliance_broken')
            and m.tick >= g.f and m.tick < g.t
          order by m.tick
          limit 6
        ) e), '[]'::jsonb)
    ) order by g.n), '[]'::jsonb)
  into v_chapters
  from (values (1, 0, v_b1), (2, v_b1, v_b2), (3, v_b2, v_ticks + 1)) as g(n, f, t);

  select coalesce(jsonb_agg(x.h order by (x.h ->> 'wins')::int desc, (x.h ->> 'castles')::int desc), '[]'::jsonb)
  into v_heroes
  from (
    select jsonb_build_object(
      'id', c.id, 'name', c.name, 'school', c.school, 'role', c.role, 'profile', c.profile, 'faction', gp.faction_slug,
      'wins', s.wins, 'castles', s.castles, 'alive', c.status <> 'dead', 'died_tick', c.died_tick,
      'deeds', coalesce((
        select jsonb_agg(q.text order by q.id)
        from (select hh.id, hh.text from public.commander_history hh
              where hh.commander_id = c.id and hh.kind in ('capture', 'win', 'named', 'crowned', 'captured')
              order by hh.id desc limit 3) q), '[]'::jsonb)
    ) as h
    from (
      select commander_id,
             count(*) filter (where kind in ('win', 'capture')) as wins,
             count(*) filter (where kind = 'capture') as castles
      from public.commander_history
      where game_id = p_game_id
      group by commander_id
    ) s
    join public.commanders c on c.id = s.commander_id
    join public.game_players gp on gp.id = c.owner_player_id
    where s.wins > 0
    order by s.wins desc, s.castles desc, c.id
    limit 6
  ) x;

  return jsonb_build_object(
    'name', v_g.name,
    'ticks', v_g.current_tick,
    'tick_speed', v_g.tick_speed,
    'winner_player_id', v_g.winner_player_id,
    'reason', v_standing ->> 'reason',
    'total_castles', (select count(*) from public.game_territories where game_id = p_game_id and not is_junction),
    'houses', v_houses,
    'chapters', v_chapters,
    'heroes', v_heroes,
    'stats', jsonb_build_object(
      'battles', (select count(*) from public.battle_reports where game_id = p_game_id),
      'captures', (select count(*) from public.game_moments where game_id = p_game_id and type = 'castle_captured'),
      'kings_killed', (select count(*) from public.game_moments where game_id = p_game_id and type = 'king_killed'),
      'commanders', (select count(*) from public.commanders where game_id = p_game_id),
      'fallen', (select count(*) from public.commanders where game_id = p_game_id and status = 'dead')));
end;
$f$;

revoke execute on function public.game_story(int) from public, anon;
grant execute on function public.game_story(int) to authenticated;
