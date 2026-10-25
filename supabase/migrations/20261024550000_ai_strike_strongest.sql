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
      ('ai_commanders', array[
        E'    and not exists (select 1 from public.commander_routes r where r.commander_id = c.id and r.status = ''active'')\n  order by (select min(((ct.x - r.x) ^ 2 + (ct.y - r.y) ^ 2) * (case when r.owner_player_id = any (v_prey) then 0.5 else 1 end))',
        E'    and not exists (select 1 from public.commander_routes r where r.commander_id = c.id and r.status = ''active'')\n    and exists (select 1 from public.game_territories rr where rr.game_id = p_game_id and rr.owner_player_id is not null and rr.owner_player_id <> p_player_id and not (rr.owner_player_id = any (v_allies)) and not rr.is_junction and ((ct.x - rr.x) ^ 2 + (ct.y - rr.y) ^ 2) <= (8 * 150 * v_game.world_scale) ^ 2)\n  order by c.troops desc, (select min(((ct.x - r.x) ^ 2 + (ct.y - r.y) ^ 2) * (case when r.owner_player_id = any (v_prey) then 0.5 else 1 end))'
      ]),
      ('ai_muster', array[
        E'    and not exists (select 1 from public.commander_routes r where r.commander_id = c.id and r.status = ''active'')\n  order by (select min(((ct.x - r.x) ^ 2 + (ct.y - r.y) ^ 2) * (case when r.owner_player_id = any (v_prey) then 0.5 else 1 end))',
        E'    and not exists (select 1 from public.commander_routes r where r.commander_id = c.id and r.status = ''active'')\n    and exists (select 1 from public.game_territories rr where rr.game_id = p_game_id and rr.owner_player_id is not null and rr.owner_player_id <> p_player_id and not (rr.owner_player_id = any (v_allies)) and not rr.is_junction and ((ct.x - rr.x) ^ 2 + (ct.y - rr.y) ^ 2) <= (8 * 150 * v_game.world_scale) ^ 2)\n  order by c.troops desc, (select min(((ct.x - r.x) ^ 2 + (ct.y - r.y) ^ 2) * (case when r.owner_player_id = any (v_prey) then 0.5 else 1 end))'
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
