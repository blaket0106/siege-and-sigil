do $patch$
declare
  v_def text;
  v_old text := E'''area_level_up'', jsonb_build_object(''player_id'', p_player_id, ''area'', p_area, ''level'', v_area.level));\n';
  v_new text;
begin
  select pg_get_functiondef('public.add_area_prestige(integer,integer,text,integer)'::regprocedure) into v_def;
  if position(v_old in v_def) = 0 then raise exception 'pattern'; end if;
  v_new := v_old || E'    if exists (select 1 from public.game_players gp where gp.id = p_player_id and not gp.is_ai) then\n      insert into public.player_inbox (game_id, player_id, type, title, body, tick)\n      values (p_game_id, p_player_id, ''system'', initcap(p_area) || '' reached level '' || v_area.level, jsonb_build_object(''kind'', ''area_level_up'', ''area'', p_area, ''level'', v_area.level), v_tick);\n    end if;\n';
  execute replace(v_def, v_old, v_new);
end;
$patch$;
