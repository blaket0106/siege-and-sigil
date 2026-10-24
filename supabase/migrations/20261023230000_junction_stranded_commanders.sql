do $patch$
declare
  v_def text;
  v_new text;
  v_pairs text[];
  i int;
begin
  v_pairs := array[
    'current_territory_id = v_m.path[v_stop - 1] where id = v_m.commander_id;',
    'current_territory_id = (select u.id from unnest(v_m.path[1:v_stop - 1]) with ordinality as u(id, ord) join public.game_territories p2 on p2.id = u.id where not p2.is_junction order by u.ord desc limit 1) where id = v_m.commander_id;'
  ];
  select pg_get_functiondef('public.advance_movements(integer,integer)'::regprocedure) into v_def;
  v_new := v_def;
  for i in 1 .. array_length(v_pairs, 1) / 2 loop
    if position(v_pairs[2 * i - 1] in v_new) = 0 then
      raise exception 'advance_movements patch % did not match', i;
    end if;
    v_new := replace(v_new, v_pairs[2 * i - 1], v_pairs[2 * i]);
  end loop;
  execute v_new;

  v_pairs := array[
    'and (gt.owner_player_id = p_player_id or gt.owner_player_id = any (v_allies))',
    'and (gt.owner_player_id = p_player_id or gt.owner_player_id = any (v_allies) or gt.is_junction)'
  ];
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'ai_commanders' and p.pronamespace = 'public'::regnamespace;
  v_new := v_def;
  for i in 1 .. array_length(v_pairs, 1) / 2 loop
    if position(v_pairs[2 * i - 1] in v_new) = 0 then
      raise exception 'ai_commanders patch % did not match', i;
    end if;
    v_new := replace(v_new, v_pairs[2 * i - 1], v_pairs[2 * i]);
  end loop;
  execute v_new;
end;
$patch$;

update public.commanders c
set current_territory_id = (
  select t.id from public.game_territories t
  join public.game_territories j on j.id = c.current_territory_id
  where t.game_id = c.game_id and not t.is_junction and t.owner_player_id = c.owner_player_id
  order by (t.x - j.x) ^ 2 + (t.y - j.y) ^ 2 limit 1
)
where c.status = 'idle' and c.current_territory_id is not null
  and exists (select 1 from public.game_territories j where j.id = c.current_territory_id and j.is_junction)
  and exists (select 1 from public.game_territories t where t.game_id = c.game_id and not t.is_junction and t.owner_player_id = c.owner_player_id);
