do $patch$
declare
  v_def text;
  v_new text;
  v_pairs text[] := array[
    E'  v_style text;\nbegin',
    E'  v_style text;\n  v_rival_need float8 := 1e18;\n  v_rival_best int;\n  v_rival_best_score float8;\n  v_rival_best_need float8;\n  v_strike boolean;\nbegin',
    E'    v_min_need := 1e18;\n    v_min_prio_need := 1e18;\n',
    E'    v_min_need := 1e18;\n    v_min_prio_need := 1e18;\n    v_rival_need := 1e18;\n    v_rival_best := null;\n    v_rival_best_score := -1e9;\n    v_rival_best_need := 0;\n    v_strike := v_n_cmds = 1 and ((v_style = ''aggressive'' and v_game.current_tick >= 30) or (v_style = ''balanced'' and v_game.current_tick >= 90 and public.castle_count(p_player_id) >= 10));\n',
    'v_strat := coalesce(v_t.choke, 0) * 1.5 + case when v_t.id = any (v_caps) then 5 else 0 end;',
    E'v_strat := coalesce(v_t.choke, 0) * 1.5 + case when v_t.id = any (v_caps) then 5 else 0 end\n        + case v_style when ''aggressive'' then 0.8 when ''balanced'' then 0.3 else 0 end * greatest(0, 10 - coalesce((select min(sqrt((r.x - v_t.x) ^ 2 + (r.y - v_t.y) ^ 2)) from public.game_territories r where r.game_id = p_game_id and r.owner_player_id is not null and r.owner_player_id <> p_player_id and not (r.owner_player_id = any (v_allies)) and not r.is_junction), 1e9) / (150 * v_game.world_scale));',
    E'      if v_def_est > 0 and v_ra <= v_rd then',
    E'      if v_t.owner_player_id is not null and v_inr and not (v_t.owner_player_id = any (v_allies)) then\n        v_rival_need := least(v_rival_need, v_need);\n      end if;\n      if v_def_est > 0 and v_ra <= v_rd then',
    E'      if v_score > v_best_score then\n        v_best := v_t.id;',
    E'      if v_t.owner_player_id is not null and v_score > v_rival_best_score then\n        v_rival_best := v_t.id;\n        v_rival_best_score := v_score;\n        v_rival_best_need := v_need;\n      end if;\n      if v_score > v_best_score then\n        v_best := v_t.id;',
    E'    if v_best is not null then\n      if v_c.terr_owner = p_player_id and v_att > 2.2 * v_best_need + 30 then',
    E'    if v_strike and v_rival_need < 1e17 then\n      if v_rival_best is not null then\n        v_best := v_rival_best;\n        v_best_need := v_rival_best_need;\n      else\n        v_best := null;\n        v_best_siege := null;\n        v_far := null;\n        v_min_need := v_rival_need;\n        v_min_prio_need := 1e18;\n      end if;\n    end if;\n    if v_best is not null then\n      if v_c.terr_owner = p_player_id and v_att > 2.2 * v_best_need + 30 then'
  ];
  i int;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'ai_commanders' and p.pronamespace = 'public'::regnamespace order by p.oid limit 1;
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

do $patch$
declare
  v_def text;
  v_new text;
  v_pairs text[] := array[
    E'  v_strike boolean;\nbegin',
    E'  v_strike boolean;\n  v_strike_cmd int;\n  v_rival_siege int;\n  v_rival_siege_score float8;\nbegin',
    E'  for v_c in\n    select c.id, c.current_territory_id, gt.owner_player_id as terr_owner',
    E'  select c.id into v_strike_cmd\n  from public.commanders c\n  join public.game_territories ct on ct.id = c.current_territory_id and ct.owner_player_id = p_player_id\n  where c.game_id = p_game_id and c.owner_player_id = p_player_id and c.status = ''idle''\n    and not exists (select 1 from public.game_territories g2 where g2.garrison_commander_id = c.id)\n    and not exists (select 1 from public.commander_routes r where r.commander_id = c.id and r.status = ''active'')\n  order by (select min((ct.x - r.x) ^ 2 + (ct.y - r.y) ^ 2) from public.game_territories r where r.game_id = p_game_id and r.owner_player_id is not null and r.owner_player_id <> p_player_id and not (r.owner_player_id = any (v_allies)) and not r.is_junction) nulls last, c.id\n  limit 1;\n\n  for v_c in\n    select c.id, c.current_territory_id, gt.owner_player_id as terr_owner',
    'v_strike := v_n_cmds = 1 and (',
    'v_strike := v_c.id = v_strike_cmd and (',
    E'    v_rival_best_need := 0;\n',
    E'    v_rival_best_need := 0;\n    v_rival_siege := null;\n    v_rival_siege_score := -1e9;\n',
    E'          if v_score > v_best_siege_score then\n            v_best_siege := v_t.id;',
    E'          if v_t.owner_player_id is not null and v_score > v_rival_siege_score then\n            v_rival_siege := v_t.id;\n            v_rival_siege_score := v_score;\n          end if;\n          if v_score > v_best_siege_score then\n            v_best_siege := v_t.id;',
    E'      else\n        v_best := null;\n        v_best_siege := null;\n        v_far := null;\n        v_min_need := v_rival_need;',
    E'      elsif v_rival_siege is not null then\n        v_best := null;\n        v_best_siege := v_rival_siege;\n      else\n        v_best := null;\n        v_best_siege := null;\n        v_far := null;\n        v_min_need := v_rival_need;'
  ];
  i int;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'ai_commanders' and p.pronamespace = 'public'::regnamespace order by p.oid limit 1;
  v_new := v_def;
  for i in 1 .. array_length(v_pairs, 1) / 2 loop
    if position(v_pairs[2 * i - 1] in v_new) = 0 then
      raise exception 'ai_commanders strike patch % did not match', i;
    end if;
    v_new := replace(v_new, v_pairs[2 * i - 1], v_pairs[2 * i]);
  end loop;
  execute v_new;
end;
$patch$;

do $patch$
declare
  v_def text;
  v_old text := 'and gt.troops - coalesce(v_res_vals[array_position(v_res_ids, gt.id)], v_reserve) >= 12';
  v_new text := 'and gt.troops - coalesce(v_res_vals[array_position(v_res_ids, gt.id)], v_reserve) >= (case when v_strike then 4 else 12 end)';
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'ai_commanders' and p.pronamespace = 'public'::regnamespace order by p.oid limit 1;
  if position(v_old in v_def) = 0 then raise exception 'pattern'; end if;
  execute replace(v_def, v_old, v_new);
end;
$patch$;
