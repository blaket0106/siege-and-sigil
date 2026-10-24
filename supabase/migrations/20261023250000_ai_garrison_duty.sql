create or replace function public.ai_garrison(p_game_id integer, p_player_id integer)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_allies int[];
  v_own int[];
  v_threat int[];
  v_total int;
  v_assigned int;
  v_free int;
  v_t record;
  v_c int;
begin
  select coalesce(array_agg(case when d.player_a_id = p_player_id then d.player_b_id else d.player_a_id end), '{}') into v_allies
  from public.diplomacy d
  where d.game_id = p_game_id and d.status = 'allied' and p_player_id in (d.player_a_id, d.player_b_id);
  select coalesce(array_agg(id), '{}') into v_own
  from public.game_territories where game_id = p_game_id and owner_player_id = p_player_id;

  with recursive adj(a, b) as (
    select e.from_territory_id, e.to_territory_id from public.territory_edges e where e.game_id = p_game_id
    union all
    select e.to_territory_id, e.from_territory_id from public.territory_edges e where e.game_id = p_game_id
  ), reach(src, node, depth) as (
    select adj.a, adj.b, 1 from adj where adj.a = any (v_own)
    union all
    select r.src, adj.b, r.depth + 1 from reach r
    join adj on adj.a = r.node
    join public.game_territories jt on jt.id = r.node and jt.is_junction
    where r.depth < 4 and adj.b <> r.src
  )
  select coalesce(array_agg(distinct r.src), '{}') into v_threat
  from reach r join public.game_territories t on t.id = r.node and not t.is_junction
  where t.owner_player_id is not null and t.owner_player_id <> p_player_id and not (t.owner_player_id = any (v_allies));

  update public.game_territories
  set garrison_commander_id = null
  where game_id = p_game_id and owner_player_id = p_player_id and garrison_commander_id is not null and not (id = any (v_threat));

  select count(*) into v_total from public.commanders where owner_player_id = p_player_id and status <> 'dead' and role <> 'king';
  select count(*) into v_assigned from public.game_territories where game_id = p_game_id and owner_player_id = p_player_id and garrison_commander_id is not null;

  for v_t in
    select gt.id
    from public.game_territories gt
    where gt.game_id = p_game_id and gt.owner_player_id = p_player_id and gt.garrison_commander_id is null and gt.id = any (v_threat)
    order by gt.tier desc, gt.id
  loop
    exit when v_assigned >= ceil(v_total * 0.3);
    select count(*) into v_free
    from public.commanders c
    where c.owner_player_id = p_player_id and c.status <> 'dead' and c.role <> 'king'
      and not exists (select 1 from public.game_territories g2 where g2.garrison_commander_id = c.id);
    exit when v_free <= 2;

    v_c := null;
    select c.id into v_c
    from public.commanders c
    where c.current_territory_id = v_t.id
      and c.owner_player_id = p_player_id
      and c.status = 'idle'
      and c.role <> 'king'
      and not exists (select 1 from public.commander_routes r where r.commander_id = c.id and r.status = 'active')
      and not exists (select 1 from public.game_territories g2 where g2.garrison_commander_id = c.id)
    order by c.troops, c.id
    limit 1;

    if v_c is not null then
      update public.game_territories set garrison_commander_id = v_c where id = v_t.id;
      v_assigned := v_assigned + 1;
    end if;
  end loop;
end;
$function$;

revoke execute on function public.ai_garrison(integer, integer) from public, anon, authenticated;
