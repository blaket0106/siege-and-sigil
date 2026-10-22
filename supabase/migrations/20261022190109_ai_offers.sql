do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.ai_diplomacy(integer,integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def,
    '    where game_id = p_game_id and status = ''allied'' and p_player_id in (player_a_id, player_b_id)
    order by player_a_id, player_b_id',
    '    where game_id = p_game_id and status = ''allied'' and p_player_id in (player_a_id, player_b_id)
      and (locked_until_tick is null or locked_until_tick <= v_tick)
    order by player_a_id, player_b_id');
  if v_new = v_def then raise exception 'ai_diplomacy patch did not apply'; end if;
  execute v_new;
end
$patch$;

create or replace function public.ai_offers(p_game_id integer, p_player_id integer, p_difficulty integer)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_o record;
  v_tick int;
  v_gold int;
  v_accept boolean;
  v_pay int;
  v_get int;
  v_t jsonb;
begin
  select current_tick into v_tick from public.games where id = p_game_id;
  select gold into v_gold from public.game_players where id = p_player_id;

  for v_o in
    select * from public.diplomacy_offers
    where game_id = p_game_id and to_player_id = p_player_id and status = 'pending'
    order by id
  loop
    v_t := v_o.terms;
    v_accept := false;

    if v_o.kind = 'nap' then
      v_accept := random() < case p_difficulty when 1 then 0.8 when 2 then 0.7 when 3 then 0.6 when 4 then 0.45 else 0.35 end;

    elsif v_o.kind = 'marriage' then
      v_accept := random() < 0.4;

    elsif v_o.kind = 'mediation' then
      v_accept := random() < 0.6;

    elsif v_o.kind = 'trade' then
      v_accept := (v_t ->> 'give')::int >= (v_t ->> 'get')::int;

    elsif v_o.kind = 'peace_terms' then
      if v_t ->> 'give_territory' is not null then
        v_accept := false;
      else
        v_pay := 0;
        v_get := 0;
        if v_t ->> 'payer' = 'target' then
          v_pay := (v_t ->> 'gold_now')::int + (v_t ->> 'tribute')::int * (v_t ->> 'cycles')::int;
        else
          v_get := (v_t ->> 'gold_now')::int + (v_t ->> 'tribute')::int * (v_t ->> 'cycles')::int;
        end if;
        v_accept := v_get > 0 or v_pay <= 0.3 * v_gold;
        if v_t ->> 'ask_territory' is not null then
          v_accept := false;
        end if;
      end if;
    end if;

    begin
      perform public.respond_offer_core(v_o.id, v_accept, v_tick);
    exception when others then
      update public.diplomacy_offers set status = 'withdrawn' where id = v_o.id and status = 'pending';
    end;
  end loop;
end;
$function$;

revoke all on function public.ai_offers(integer, integer, integer) from public, anon, authenticated;

do $patch2$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.ai_take_turn(integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def,
    '  perform public.ai_diplomacy(p_game_id, p_player_id, v_difficulty);',
    '  perform public.ai_diplomacy(p_game_id, p_player_id, v_difficulty);
  perform public.ai_offers(p_game_id, p_player_id, v_difficulty);');
  if v_new = v_def then raise exception 'ai_take_turn patch did not apply'; end if;
  execute v_new;
end
$patch2$;
