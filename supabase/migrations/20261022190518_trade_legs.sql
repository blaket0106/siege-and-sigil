alter table public.gold_deals add column if not exists offer_id integer;

do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.respond_offer_core(integer,boolean,integer)'::regprocedure) into v_def;
  v_new := replace(v_def,
    'insert into public.gold_deals (game_id, kind, payer_id, payee_id, amount, cycles_left, created_tick)
      values (v_o.game_id, ''trade'', v_o.from_player_id, v_o.to_player_id, (v_t ->> ''give'')::int, (v_t ->> ''cycles'')::int, p_tick);',
    'insert into public.gold_deals (game_id, kind, payer_id, payee_id, amount, cycles_left, created_tick, offer_id)
      values (v_o.game_id, ''trade'', v_o.from_player_id, v_o.to_player_id, (v_t ->> ''give'')::int, (v_t ->> ''cycles'')::int, p_tick, v_o.id);');
  v_new := replace(v_new,
    'insert into public.gold_deals (game_id, kind, payer_id, payee_id, amount, cycles_left, created_tick)
      values (v_o.game_id, ''trade'', v_o.to_player_id, v_o.from_player_id, (v_t ->> ''get'')::int, (v_t ->> ''cycles'')::int, p_tick);',
    'insert into public.gold_deals (game_id, kind, payer_id, payee_id, amount, cycles_left, created_tick, offer_id)
      values (v_o.game_id, ''trade'', v_o.to_player_id, v_o.from_player_id, (v_t ->> ''get'')::int, (v_t ->> ''cycles'')::int, p_tick, v_o.id);');
  if v_new = v_def or v_new not like '%created_tick, offer_id%' then
    raise exception 'respond_offer_core patch did not apply';
  end if;
  execute v_new;
end
$patch$;

create or replace function public.process_gold_deals(p_game_id integer, p_tick integer)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_d record;
  v_sib record;
  v_gold int;
  v_dead boolean;
  v_status text;
  v_blocker int;
  v_cur text;
begin
  for v_d in
    select * from public.gold_deals where game_id = p_game_id and status = 'active' order by id
  loop
    select status into v_cur from public.gold_deals where id = v_d.id;
    continue when v_cur <> 'active';

    select exists (
      select 1 from public.game_players where id in (v_d.payer_id, v_d.payee_id) and eliminated_at_tick is not null
    ) into v_dead;
    select status into v_status from public.diplomacy
    where game_id = p_game_id and player_a_id = least(v_d.payer_id, v_d.payee_id) and player_b_id = greatest(v_d.payer_id, v_d.payee_id);

    if v_dead or (v_d.kind = 'trade' and v_status = 'war') then
      update public.gold_deals set status = 'cancelled'
      where id = v_d.id or (v_d.offer_id is not null and offer_id = v_d.offer_id and status = 'active');
      continue;
    end if;

    v_blocker := null;
    select gold into v_gold from public.game_players where id = v_d.payer_id;
    if v_gold < v_d.amount then
      v_blocker := v_d.payer_id;
    elsif v_d.offer_id is not null then
      select * into v_sib from public.gold_deals where offer_id = v_d.offer_id and id > v_d.id and status = 'active';
      if found and (select gold from public.game_players where id = v_sib.payer_id) < v_sib.amount then
        v_blocker := v_sib.payer_id;
      end if;
    end if;

    if v_blocker is not null then
      update public.gold_deals set status = 'cancelled'
      where id = v_d.id or (v_d.offer_id is not null and offer_id = v_d.offer_id and status = 'active');
      update public.game_players set infamy_delta = infamy_delta + 5 where id = v_blocker;
      perform public.notify_diplomacy(
        p_game_id, p_tick, array[v_d.payer_id, v_d.payee_id], 'Payment defaulted',
        jsonb_build_object('kind', 'deal_defaulted', 'deal_kind', v_d.kind, 'payer_id', v_blocker, 'payee_id', case when v_blocker = v_d.payer_id then v_d.payee_id else v_d.payer_id end, 'amount', v_d.amount)
      );
      continue;
    end if;

    update public.game_players set gold = gold - v_d.amount where id = v_d.payer_id;
    update public.game_players set gold = gold + v_d.amount where id = v_d.payee_id;
    insert into public.ledger (game_id, player_id, tick, type, amount) values
      (p_game_id, v_d.payer_id, p_tick, 'send_gold', -v_d.amount),
      (p_game_id, v_d.payee_id, p_tick, 'receive_gold', v_d.amount);

    update public.gold_deals
    set cycles_left = cycles_left - 1,
        status = case when cycles_left - 1 <= 0 then 'ended' else 'active' end
    where id = v_d.id;
  end loop;
end;
$function$;

revoke all on function public.process_gold_deals(integer, integer) from public, anon, authenticated;

do $patch2$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.ai_offers(integer,integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def,
    '      v_accept := (v_t ->> ''give'')::int >= (v_t ->> ''get'')::int;',
    '      v_accept := (v_t ->> ''give'')::int >= (v_t ->> ''get'')::int
        and (select gold from public.game_players where id = v_o.from_player_id) >= (v_t ->> ''give'')::int;');
  if v_new = v_def then raise exception 'ai_offers patch did not apply'; end if;
  execute v_new;
end
$patch2$;
