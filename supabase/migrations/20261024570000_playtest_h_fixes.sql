create or replace function public.fog_sees(p_game_id int, p_player_id int, p_x float8, p_y float8)
returns boolean
language sql
stable
security definer
set search_path = ''
as $f$
  with g as (select fog_of_war and status = 'active' as fog, unit_scale, current_tick from public.games where id = p_game_id),
  friends as (
    select p_player_id as id
    union
    select case when d.player_a_id = p_player_id then d.player_b_id else d.player_a_id end
    from public.diplomacy d
    where d.game_id = p_game_id and d.status = 'allied' and p_player_id in (d.player_a_id, d.player_b_id)
  )
  select (select not fog from g)
    or exists (
      select 1 from public.game_territories t
      join friends f on f.id = t.owner_player_id
      left join public.realm_areas ra on ra.player_id = t.owner_player_id and ra.area = 'watchtowers'
      where t.game_id = p_game_id and sqrt((t.x - p_x) ^ 2 + (t.y - p_y) ^ 2) <= (90 + 60 * coalesce(ra.level, 0)) * (select unit_scale from g)
    )
    or exists (
      select 1
      from public.commanders c
      join friends f on f.id = c.owner_player_id
      left join public.game_territories ct on ct.id = c.current_territory_id
      left join public.commander_movements m on m.commander_id = c.id
      left join lateral public.fog_movement_pos(m.path, m.path_arrival_ticks, (select current_tick from g)::float8) mp on true
      left join lateral (
        select coalesce(sum(ca.level), 0) as rank, coalesce(max(ca.level) filter (where ca.ability = 'scout'), 0) as scout
        from public.commander_abilities ca where ca.commander_id = c.id
      ) rk on true
      where c.game_id = p_game_id and c.status <> 'dead'
        and sqrt((coalesce(ct.x, mp.x) - p_x) ^ 2 + (coalesce(ct.y, mp.y) - p_y) ^ 2) <= (45 + 15 * rk.rank + 30 * rk.scout) * (select unit_scale from g)
    );
$f$;
revoke execute on function public.fog_sees(int, int, float8, float8) from public, anon, authenticated;

create or replace function public.jump_threat(p_game_id int)
returns boolean
language plpgsql
security definer
set search_path = ''
as $f$
declare
  v_tick int;
  v_found boolean := false;
  r record;
  v_phase text;
begin
  select current_tick into v_tick from public.games where id = p_game_id;
  for r in
    select c.id as cid, t.id as tid, t.owner_player_id as pid, m.arrival_tick - v_tick as eta, mp.x as ax, mp.y as ay, false as siege
    from public.commanders c
    join public.commander_movements m on m.commander_id = c.id
    join public.game_territories t on t.id = m.to_territory_id
    join public.game_players hp on hp.id = t.owner_player_id and not hp.is_ai
    left join lateral public.fog_movement_pos(m.path, m.path_arrival_ticks, v_tick::float8) mp on true
    where c.game_id = p_game_id and c.status = 'moving' and c.owner_player_id is distinct from t.owner_player_id
      and m.arrival_tick - v_tick <= 4
    union all
    select c.id, t.id, t.owner_player_id, 0, t.x, t.y, true
    from public.commanders c
    join public.game_territories t on t.id = c.current_territory_id
    join public.game_players hp on hp.id = t.owner_player_id and not hp.is_ai
    where c.game_id = p_game_id and c.status = 'sieging' and c.owner_player_id is distinct from t.owner_player_id
  loop
    if r.siege or (r.ax is not null and public.fog_sees(p_game_id, r.pid, r.ax, r.ay)) then
      v_phase := case when r.siege then 'siege' when r.eta <= 1 then 'final' else 'near' end;
      if not exists (select 1 from public.game_events e where e.game_id = p_game_id and e.type = 'jump_halt' and e.payload ->> 'commander' = r.cid::text and e.payload ->> 'territory' = r.tid::text and e.payload ->> 'phase' = v_phase) then
        insert into public.game_events (game_id, tick, type, payload)
        values (p_game_id, v_tick, 'jump_halt', jsonb_build_object('commander', r.cid, 'territory', r.tid, 'phase', v_phase));
        v_found := true;
      end if;
    end if;
  end loop;
  return v_found;
end;
$f$;
revoke execute on function public.jump_threat(int) from public, anon, authenticated;

alter function public.preview_march(int, int, int) set statement_timeout = '30s';
alter function public.my_attack_stats(int, int[]) set statement_timeout = '30s';
alter function public.ruler(int, int, int, int) set statement_timeout = '30s';
alter function public.castle_report(int, int) set statement_timeout = '30s';

do $patch$
declare
  v_def text;
  v_old text := 'order by (gp.id = v_game.winner_player_id) desc, (gp.eliminated_at_tick is null) desc, gp.id)';
  v_new text := 'order by (gp.id = v_game.winner_player_id) desc, (gp.eliminated_at_tick is null) desc, (select count(*) from public.game_territories gt2 where gt2.game_id = p_game_id and gt2.owner_player_id = gp.id) desc, gp.id)';
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'game_summary' and p.pronamespace = 'public'::regnamespace;
  if position(v_old in v_def) = 0 then
    raise exception 'game_summary patch did not match';
  end if;
  execute replace(v_def, v_old, v_new);
end;
$patch$;
