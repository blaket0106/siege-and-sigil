do $patch$
declare
  v_def text;
  v_old text := 'if v_allies < v_max_allies and v_pending = 0 and random() < 0.3 then';
  v_new text := 'if v_allies < v_max_allies and v_pending = 0 and random() < (case (select gp.ai_style from public.game_players gp where gp.id = p_player_id) when ''aggressive'' then 0.04 when ''defensive'' then 0.45 else 0.3 end) then';
begin
  select pg_get_functiondef('public.ai_diplomacy(integer,integer,integer)'::regprocedure) into v_def;
  if position(v_old in v_def) = 0 then raise exception 'pattern'; end if;
  execute replace(v_def, v_old, v_new);
end;
$patch$;
