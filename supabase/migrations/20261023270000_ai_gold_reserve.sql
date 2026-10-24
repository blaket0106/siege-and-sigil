do $patch$
declare
  v_def text;
  v_new text;
  v_pairs text[];
  i int;
begin
  v_pairs := array[
    '  v_guard int := 0;' || chr(10) || 'begin',
    '  v_guard int := 0;' || chr(10) || '  v_castles int;' || chr(10) || '  v_loops int;' || chr(10) || 'begin',
    '  v_budget := floor(',
    '  if p_difficulty >= 2 then' || chr(10)
    || '    select count(*) into v_castles from public.game_territories where game_id = p_game_id and owner_player_id = p_player_id and not is_junction;' || chr(10)
    || '    select count(*) into v_loops from public.commander_routes r join public.commanders c on c.id = r.commander_id' || chr(10)
    || '    where r.game_id = p_game_id and c.owner_player_id = p_player_id and r.status = ''active'' and r.looping;' || chr(10)
    || '    if v_castles >= 4 and v_loops < least(16, ceil(v_castles / 4.0)::int) then' || chr(10)
    || '      v_reserve := greatest(v_reserve, v_game.commander_cost + 100);' || chr(10)
    || '    end if;' || chr(10)
    || '  end if;' || chr(10)
    || '  v_budget := floor('
  ];
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'ai_spend' and p.pronamespace = 'public'::regnamespace;
  v_new := v_def;
  for i in 1 .. array_length(v_pairs, 1) / 2 loop
    if position(v_pairs[2 * i - 1] in v_new) = 0 then
      raise exception 'ai_spend patch % did not match', i;
    end if;
    v_new := replace(v_new, v_pairs[2 * i - 1], v_pairs[2 * i]);
  end loop;
  execute v_new;
end;
$patch$;
