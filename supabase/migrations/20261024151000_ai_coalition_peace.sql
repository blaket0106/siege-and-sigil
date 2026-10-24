do $patch$
declare
  v_def text;
  v_new text;
  v_old text := 'and v_my < 0.8 * public.castle_count(v_other) and v_other is distinct from public.dominant_house(p_game_id) and random() < 0.5 then';
  v_rep text := 'and ((v_my < 0.8 * public.castle_count(v_other) and v_other is distinct from public.dominant_house(p_game_id)) or (public.dominant_house(p_game_id) is not null and v_other is distinct from public.dominant_house(p_game_id) and p_player_id is distinct from public.dominant_house(p_game_id))) and random() < 0.5 then';
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'ai_diplomacy' and p.pronamespace = 'public'::regnamespace;
  if position(v_old in v_def) = 0 then
    raise exception 'ai_diplomacy coalition peace patch did not match';
  end if;
  v_new := replace(v_def, v_old, v_rep);
  execute v_new;
end;
$patch$;
