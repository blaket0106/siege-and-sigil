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
        E'        + (v_plan ->> ''travel_ticks'')::int * (v_t.industry_level * 5.0 / v_game.production_cycle_ticks);',
        E'        + (case when v_t.owner_player_id is null then 0 else (v_plan ->> ''travel_ticks'')::int * (v_t.industry_level * 5.0 / v_game.production_cycle_ticks) end);',
        '      v_def_est := v_def_est * v_margin;',
        '      v_def_est := v_def_est * case when v_t.owner_player_id is null then 1.0 else v_margin end;'
      ]),
      ('ai_sieges', array[
        '(select sum(troops) from public.commanders where id = any (v_def)), 0)) * v_margin;',
        '(select sum(troops) from public.commanders where id = any (v_def)), 0)) * case when v_t.owner_player_id is null then 1.0 else v_margin end;'
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
