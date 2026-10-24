alter table public.game_territories add column is_junction boolean not null default false;

create or replace function public.patch_fn(p_proc regprocedure, p_pairs text[])
returns void
language plpgsql
as $function$
declare
  v_def text;
  v_new text;
  i int;
begin
  select pg_get_functiondef(p_proc) into v_def;
  v_new := v_def;
  for i in 1 .. array_length(p_pairs, 1) / 2 loop
    if position(p_pairs[2 * i - 1] in v_new) = 0 then
      raise exception 'patch % for % did not match', i, p_proc;
    end if;
    v_new := replace(v_new, p_pairs[2 * i - 1], p_pairs[2 * i]);
  end loop;
  execute v_new;
end;
$function$;

select public.patch_fn('public.commit_world(integer,jsonb)'::regprocedure, array[
  'and not coalesce((t.e ->> ''crossing'')::boolean, false)',
  'and not coalesce((t.e ->> ''crossing'')::boolean, false) and not coalesce((t.e ->> ''junction'')::boolean, false)',
  'has_road, crossing_kind, river_idx',
  'has_road, crossing_kind, river_idx, is_junction',
  '(v_t ->> ''river_idx'')::int',
  '(v_t ->> ''river_idx'')::int, coalesce((v_t ->> ''junction'')::boolean, false)'
]);

select public.patch_fn('public.game_standing(integer)'::regprocedure, array[
  'select count(*) into v_total from public.game_territories where game_id = p_game_id;',
  'select count(*) into v_total from public.game_territories where game_id = p_game_id and not is_junction;'
]);

select public.patch_fn('public.get_game_view(integer)'::regprocedure, array[
  '''crossing_kind'', t.crossing_kind, ''seen'', v.seen',
  '''crossing_kind'', t.crossing_kind, ''is_junction'', t.is_junction, ''seen'', v.seen',
  '''territory_total'', (select count(*)::int from public.game_territories t where t.game_id = p_game_id)',
  '''territory_total'', (select count(*)::int from public.game_territories t where t.game_id = p_game_id and not t.is_junction)'
]);

select public.patch_fn('public.get_start_options(integer)'::regprocedure, array[
  'from public.game_territories t where t.game_id = p_game_id' || chr(10) || '    ) end',
  'from public.game_territories t where t.game_id = p_game_id and not t.is_junction' || chr(10) || '    ) end'
]);

select public.patch_fn('public.plan_march(integer,integer,integer)'::regprocedure, array[
  '  v_friendly boolean[];' || chr(10),
  '  v_friendly boolean[];' || chr(10) || '  v_junction boolean[];' || chr(10),
  'array_agg(has_road order by id)' || chr(10) || '  into v_ids, v_owner, v_road',
  'array_agg(has_road or is_junction order by id), array_agg(is_junction order by id)' || chr(10) || '  into v_ids, v_owner, v_road, v_junction',
  '  if v_src = v_dst then',
  '  if v_junction[v_dst] then' || chr(10) || '    raise exception ''a crossroads is not a destination'';' || chr(10) || '  end if;' || chr(10) || '  if v_src = v_dst then',
  'v_friendly[v_i] := v_owner[v_i] is not null and (v_owner[v_i] = p_player_id or v_owner[v_i] = any (v_allies));',
  'v_friendly[v_i] := v_junction[v_i] or (v_owner[v_i] is not null and (v_owner[v_i] = p_player_id or v_owner[v_i] = any (v_allies)));',
  '''hops'', array_length(v_path_ids, 1) - 1,',
  '''hops'', (select count(*)::int from unnest(v_path_ids) pid join public.game_territories jt on jt.id = pid where not jt.is_junction) - 1,',
  '''in_range'', (array_length(v_path_ids, 1) = 2 or v_raw <= v_range)',
  '''in_range'', ((select count(*) from unnest(v_path_ids) pid join public.game_territories jt on jt.id = pid where not jt.is_junction) = 2 or v_raw <= v_range)'
]);

select public.patch_fn('public.advance_movements(integer,integer)'::regprocedure, array[
  '      if v_i = v_n' || chr(10) || '         or not public.is_friendly_territory(v_owner, v_node)' || chr(10) || '         or public.has_hostile_siege(v_owner, v_node) then',
  '      if v_i = v_n' || chr(10) || '         or (not exists (select 1 from public.game_territories jt where jt.id = v_node and jt.is_junction)' || chr(10) || '             and (not public.is_friendly_territory(v_owner, v_node) or public.has_hostile_siege(v_owner, v_node))) then'
]);

select public.patch_fn((select p.oid::regprocedure from pg_proc p where p.proname = 'ai_commanders' and p.pronamespace = 'public'::regnamespace), array[
  '  select coalesce(array_agg(distinct gt.id), ''{}'') into v_frontier' || chr(10) || '  from public.game_territories gt' || chr(10) || '  join public.territory_edges e on e.game_id = gt.game_id and (e.from_territory_id = gt.id or e.to_territory_id = gt.id)' || chr(10) || '  where gt.game_id = p_game_id' || chr(10) || '    and not (gt.id = any (v_friendly))' || chr(10) || '    and case when e.from_territory_id = gt.id then e.to_territory_id else e.from_territory_id end = any (v_friendly);',
  '  with recursive adj(a, b) as (' || chr(10) || '    select e.from_territory_id, e.to_territory_id from public.territory_edges e where e.game_id = p_game_id' || chr(10) || '    union all' || chr(10) || '    select e.to_territory_id, e.from_territory_id from public.territory_edges e where e.game_id = p_game_id' || chr(10) || '  ), walk(id) as (' || chr(10) || '    select unnest(v_friendly)' || chr(10) || '    union' || chr(10) || '    select adj.b from walk w join adj on adj.a = w.id' || chr(10) || '    where w.id = any (v_friendly) or exists (select 1 from public.game_territories jt where jt.id = w.id and jt.is_junction)' || chr(10) || '  )' || chr(10) || '  select coalesce(array_agg(distinct w.id), ''{}'') into v_frontier' || chr(10) || '  from walk w join public.game_territories gt on gt.id = w.id' || chr(10) || '  where not (w.id = any (v_friendly)) and not gt.is_junction;',
  'where h.game_id = o.game_id and not (h.id = any (v_friendly))',
  'where h.game_id = o.game_id and not h.is_junction and not (h.id = any (v_friendly))'
]);

drop function public.patch_fn(regprocedure, text[]);
