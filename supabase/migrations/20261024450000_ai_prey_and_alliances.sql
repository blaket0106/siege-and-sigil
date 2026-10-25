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
        E'  v_strike_cmd int;\n',
        E'  v_strike_cmd int;\n  v_prey int[];\n',
        E'  select c.id into v_strike_cmd\n',
        E'  select coalesce(array_agg(gp.id), ''{}'') into v_prey from public.game_players gp where gp.game_id = p_game_id and gp.id <> p_player_id and gp.eliminated_at_tick is null and public.castle_count(gp.id) < 0.8 * public.castle_count(p_player_id);\n  select c.id into v_strike_cmd\n',
        'min((ct.x - r.x) ^ 2 + (ct.y - r.y) ^ 2)',
        'min(((ct.x - r.x) ^ 2 + (ct.y - r.y) ^ 2) * (case when r.owner_player_id = any (v_prey) then 0.5 else 1 end))',
        'min(sqrt((r.x - v_t.x) ^ 2 + (r.y - v_t.y) ^ 2))',
        'min(sqrt((r.x - v_t.x) ^ 2 + (r.y - v_t.y) ^ 2) * (case when r.owner_player_id = any (v_prey) then 0.7 else 1 end))',
        E'else 0 end\n        + case when v_t.owner_player_id is not null and exists (select 1 from public.diplomacy w',
        E'else 0 end\n        + case when v_t.owner_player_id = any (v_prey) and v_style <> ''defensive'' then 4 else 0 end\n        + case when v_t.owner_player_id is not null and exists (select 1 from public.diplomacy w'
      ]),
      ('ai_diplomacy', array[
        'when ''aggressive'' then 0.04 when ''defensive'' then 0.45 else 0.3 end',
        'when ''aggressive'' then 0.005 when ''defensive'' then 0.45 else 0.3 end',
        'or random() >= v_chance then',
        'or random() >= v_chance * (case (select gp.ai_style from public.game_players gp where gp.id = p_player_id) when ''aggressive'' then 0.15 when ''defensive'' then 1.2 else 1 end) then'
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
