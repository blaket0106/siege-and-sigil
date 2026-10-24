do $patch$
declare
  v_def text;
  v_old text := E'    if v_msg is null and random() < 0.04 then\n      v_msg := (array[v_f.motto, ''The realm is quiet. That never lasts.'', ''I count the castles, and I count the days.''])[1 + floor(random() * 3)::int];\n    end if;';
  v_new text := E'    if v_msg is null and random() < 0.05 then\n      v_msg := (case (select gp.ai_style from public.game_players gp where gp.id = p_player_id)\n        when ''defensive'' then array[''Our walls are high and our granaries are full.'', ''Let them come. We will be here.'', ''A castle held is worth ten taken.'', ''Patience wins more wars than haste.'']\n        when ''aggressive'' then array[''Every castle is a stepping stone.'', ''The border is where the work begins.'', ''We march at first light.'', ''Fortune favours the army that moves.'']\n        else array[''The realm is quiet. That never lasts.'', ''I count the castles, and I count the days.'', ''Take the land, hold the land.'', ''Trade, and be watchful.''] end)[1 + floor(random() * 4)::int];\n      if exists (select 1 from public.game_chat gc where gc.game_id = p_game_id and gc.message = v_msg and gc.tick >= v_tick - 80) then\n        v_msg := null;\n      end if;\n    end if;';
begin
  select pg_get_functiondef('public.ai_chatter(int, int, int)'::regprocedure) into v_def;
  if position(v_old in v_def) = 0 then raise exception 'pattern'; end if;
  execute replace(v_def, v_old, v_new);
end;
$patch$;
