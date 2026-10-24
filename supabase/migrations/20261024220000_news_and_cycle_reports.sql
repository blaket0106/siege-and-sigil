create function public.players_seeing(p_game_id int, p_territory_id int)
returns int[]
language sql
stable
security definer
set search_path = ''
as $f$
  select coalesce(array_agg(distinct gp.id), '{}')
  from public.game_players gp
  cross join public.games g
  cross join public.game_territories t
  where g.id = p_game_id and t.id = p_territory_id and t.game_id = p_game_id
    and gp.game_id = p_game_id and gp.eliminated_at_tick is null
    and (
      exists (
        select 1
        from public.game_territories s
        left join public.realm_areas wl on wl.player_id = s.owner_player_id and wl.area = 'watchtowers'
        where s.game_id = p_game_id and s.owner_player_id is not null
          and (s.owner_player_id = gp.id or public.are_allied(s.owner_player_id, gp.id))
          and sqrt((s.x - t.x) ^ 2 + (s.y - t.y) ^ 2) <= (90 + 60 * coalesce(wl.level, 0)) * g.world_scale
      )
      or exists (
        select 1
        from public.commanders c
        join public.game_territories ct on ct.id = c.current_territory_id
        left join lateral (
          select coalesce(sum(ca.level), 0) as rank, coalesce(max(ca.level) filter (where ca.ability = 'scout'), 0) as scout
          from public.commander_abilities ca where ca.commander_id = c.id
        ) r on true
        where c.game_id = p_game_id and c.status <> 'dead'
          and (c.owner_player_id = gp.id or public.are_allied(c.owner_player_id, gp.id))
          and sqrt((ct.x - t.x) ^ 2 + (ct.y - t.y) ^ 2) <= (45 + 15 * r.rank + 30 * r.scout) * g.world_scale
      )
    )
$f$;

revoke execute on function public.players_seeing(int, int) from public, anon, authenticated;

create or replace function public.moments_fog_filter()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.type in ('castle_captured', 'siege_started', 'siege_lifted')
     and exists (select 1 from public.games g where g.id = new.game_id and g.fog_of_war) then
    new.visibility := 'private';
    new.involved_player_ids := array(
      select distinct x::int
      from (
        select unnest(array[
          new.payload ->> 'from_player_id', new.payload ->> 'to_player_id', new.payload ->> 'by_player_id',
          new.payload ->> 'owner_player_id', new.payload ->> 'player_id'
        ]) as x
        union all
        select unnest(public.players_seeing(new.game_id, (new.payload ->> 'territory_id')::int))::text
        where new.payload ->> 'territory_id' is not null
      ) v
      where x is not null
    );
  end if;
  return new;
end;
$$;

create function public.post_cycle_reports(p_game_id int, p_tick int)
returns void
language plpgsql
security definer
set search_path = ''
as $f$
declare
  v_g public.games%rowtype;
  v_p record;
  v_gold_got int;
  v_castles int;
  v_troops numeric;
  v_cheapest int;
begin
  select * into v_g from public.games where id = p_game_id;
  for v_p in
    select gp.id, gp.gold from public.game_players gp
    where gp.game_id = p_game_id and not gp.is_ai and gp.eliminated_at_tick is null
  loop
    select coalesce(sum(l.amount), 0) into v_gold_got
    from public.ledger l where l.game_id = p_game_id and l.player_id = v_p.id and l.tick = p_tick and l.type = 'production';
    select count(*), coalesce(sum(gt.industry_level * (coalesce(ra.level, 1) + 4)), 0)
    into v_castles, v_troops
    from public.game_territories gt
    left join public.realm_areas ra on ra.player_id = gt.owner_player_id and ra.area = 'barracks'
    where gt.game_id = p_game_id and gt.owner_player_id = v_p.id and not gt.is_junction;
    select min(public.infra_cost(tp.t, case tp.t when 'recruitment' then gt.industry_level else gt.treasury_level end, gt.resources, v_g.infra_cost_mult * public.infra_type_mult(p_game_id, tp.t)))
    into v_cheapest
    from public.game_territories gt cross join (values ('recruitment'), ('treasury')) as tp(t)
    where gt.game_id = p_game_id and gt.owner_player_id = v_p.id;
    insert into public.player_inbox (game_id, player_id, type, title, body, tick)
    values (
      p_game_id, v_p.id, 'system',
      format('Cycle report: +%s gold, about +%s troops a cycle from %s %s. You hold %s gold%s.',
        v_gold_got, round(v_troops), v_castles, case when v_castles = 1 then 'castle' else 'castles' end, v_p.gold,
        case when v_cheapest is null then '' when v_p.gold >= v_cheapest then format(' and can afford an upgrade (cheapest %s)', v_cheapest) else format('; the cheapest upgrade costs %s', v_cheapest) end),
      jsonb_build_object('kind', 'cycle_report', 'gold', v_gold_got, 'castles', v_castles),
      p_tick
    );
  end loop;
end;
$f$;

revoke execute on function public.post_cycle_reports(int, int) from public, anon, authenticated;

do $patch$
declare
  v_def text;
  v_old text := '    perform public.record_intel_snapshot(p_game_id);';
  v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'run_tick' and p.pronamespace = 'public'::regnamespace;
  if position(v_old in v_def) = 0 then
    raise exception 'run_tick patch did not match';
  end if;
  v_new := replace(v_def, v_old, '    perform public.post_cycle_reports(p_game_id, v_tick);' || chr(10) || v_old);
  execute v_new;
end;
$patch$;
