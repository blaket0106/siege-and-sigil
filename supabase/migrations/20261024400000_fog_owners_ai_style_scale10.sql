alter table public.games alter column world_scale set default 10;

do $patch$
declare
  v_def text;
  v_new text;
  v_pairs text[] := array[
    E'        ) else ''{}''::jsonb end\n        order by t.id), ''[]''::jsonb)',
    E'        ) else case when not v_g.fog_dark then jsonb_build_object(''owner_player_id'', t.owner_player_id) else ''{}''::jsonb end end\n        order by t.id), ''[]''::jsonb)',
    E'''display_name'', p.display_name, ''is_ai'', p.is_ai,',
    E'''display_name'', p.display_name, ''is_ai'', p.is_ai, ''ai_style'', case when p.is_ai then p.ai_style end,'
  ];
  i int;
begin
  select pg_get_functiondef('public.get_game_view(integer)'::regprocedure) into v_def;
  v_new := v_def;
  for i in 1 .. array_length(v_pairs, 1) / 2 loop
    if position(v_pairs[2 * i - 1] in v_new) = 0 then
      raise exception 'get_game_view patch % did not match', i;
    end if;
    v_new := replace(v_new, v_pairs[2 * i - 1], v_pairs[2 * i]);
  end loop;
  execute v_new;
end;
$patch$;
