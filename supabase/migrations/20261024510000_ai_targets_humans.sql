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
        '+ case when v_t.owner_player_id = any (v_prey) and v_style <> ''defensive'' then 4 else 0 end',
        E'+ case when v_t.owner_player_id = any (v_prey) and v_style <> ''defensive'' then 4 else 0 end\n        + case when v_style <> ''defensive'' and exists (select 1 from public.game_players hp where hp.id = v_t.owner_player_id and not hp.is_ai) then 3 else 0 end'
      ]),
      ('ai_muster', array[
        'order by ((t.x - v_hx) ^ 2 + (t.y - v_hy) ^ 2) * (case when t.owner_player_id = any (v_prey) then 0.5 else 1 end)',
        'order by ((t.x - v_hx) ^ 2 + (t.y - v_hy) ^ 2) * (case when t.owner_player_id = any (v_prey) then 0.5 else 1 end) * (case when exists (select 1 from public.game_players hp where hp.id = t.owner_player_id and not hp.is_ai) then 0.7 else 1 end)'
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
