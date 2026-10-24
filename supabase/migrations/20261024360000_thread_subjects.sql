alter table public.thread_messages add column if not exists subject text;

do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.post_thread_message(integer,integer,text)'::regprocedure) into v_def;
  v_new := replace(v_def, '(p_thread_id integer, p_player_id integer, p_body text)', '(p_thread_id integer, p_player_id integer, p_body text, p_subject text DEFAULT NULL::text)');
  if v_new = v_def then raise exception 'post header'; end if;
  v_def := v_new;
  v_new := replace(v_def, 'insert into public.thread_messages (thread_id, player_id, body) values (p_thread_id, p_player_id, v_body)', 'insert into public.thread_messages (thread_id, player_id, body, subject) values (p_thread_id, p_player_id, v_body, nullif(left(trim(coalesce(p_subject, '''')), 80), ''''))');
  if v_new = v_def then raise exception 'post insert'; end if;
  drop function public.post_thread_message(integer, integer, text);
  execute v_new;

  select pg_get_functiondef('public.create_thread(integer,integer[],text)'::regprocedure) into v_def;
  v_new := replace(v_def, '(p_game_id integer, p_participant_ids integer[], p_first_message text)', '(p_game_id integer, p_participant_ids integer[], p_first_message text, p_subject text DEFAULT NULL::text)');
  if v_new = v_def then raise exception 'create header'; end if;
  v_def := v_new;
  v_new := replace(v_def, 'perform public.post_thread_message(v_thread, v_me, p_first_message);', 'perform public.post_thread_message(v_thread, v_me, p_first_message, p_subject);');
  if v_new = v_def then raise exception 'create perform'; end if;
  drop function public.create_thread(integer, integer[], text);
  execute v_new;
end;
$patch$;

revoke execute on function public.post_thread_message(integer, integer, text, text) from public, anon, authenticated;
revoke execute on function public.create_thread(integer, integer[], text, text) from public, anon;
grant execute on function public.create_thread(integer, integer[], text, text) to authenticated;
