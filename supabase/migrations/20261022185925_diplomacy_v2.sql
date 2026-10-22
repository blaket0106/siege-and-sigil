alter table public.diplomacy drop constraint if exists diplomacy_status_check;
alter table public.diplomacy add constraint diplomacy_status_check
  check (status = any (array['neutral', 'proposed', 'allied', 'grace_period', 'war', 'truce', 'peace_proposed', 'nap']));
alter table public.diplomacy add column if not exists locked_until_tick integer;

create table if not exists public.diplomacy_offers (
  id serial primary key,
  game_id integer not null references public.games (id) on delete cascade,
  kind text not null check (kind in ('nap', 'marriage', 'peace_terms', 'trade', 'mediation')),
  from_player_id integer not null,
  to_player_id integer not null,
  terms jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'withdrawn', 'expired')),
  created_tick integer not null,
  expires_tick integer not null,
  created_at timestamptz not null default now(),
  foreign key (game_id, from_player_id) references public.game_players (game_id, id) on delete cascade,
  foreign key (game_id, to_player_id) references public.game_players (game_id, id) on delete cascade
);
create index if not exists diplomacy_offers_game_idx on public.diplomacy_offers (game_id, status);
alter table public.diplomacy_offers enable row level security;
revoke all on public.diplomacy_offers from anon, authenticated;

create table if not exists public.gold_deals (
  id serial primary key,
  game_id integer not null references public.games (id) on delete cascade,
  kind text not null check (kind in ('tribute', 'trade')),
  payer_id integer not null,
  payee_id integer not null,
  amount integer not null check (amount > 0),
  cycles_left integer not null check (cycles_left >= 0),
  status text not null default 'active' check (status in ('active', 'ended', 'cancelled')),
  created_tick integer not null,
  foreign key (game_id, payer_id) references public.game_players (game_id, id) on delete cascade,
  foreign key (game_id, payee_id) references public.game_players (game_id, id) on delete cascade
);
create index if not exists gold_deals_game_idx on public.gold_deals (game_id, status);
alter table public.gold_deals enable row level security;
revoke all on public.gold_deals from anon, authenticated;

do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.are_truced(integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def, 'd.status = ''truce''', 'd.status in (''truce'', ''nap'')');
  if v_new = v_def then raise exception 'are_truced patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.mark_war(integer,integer,integer,integer,text)'::regprocedure) into v_def;
  v_new := replace(v_def, 'v_d.status in (''war'', ''allied'', ''truce'')', 'v_d.status in (''war'', ''allied'', ''truce'', ''nap'')');
  if v_new = v_def then raise exception 'mark_war patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.break_alliance_core(integer,integer,integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def,
    '    raise exception ''you are not allied with that player'';
  end if;',
    '    raise exception ''you are not allied with that player'';
  end if;
  if v_d.locked_until_tick is not null and v_d.locked_until_tick > p_tick then
    raise exception ''this alliance is a marriage alliance and cannot be broken before tick %'', v_d.locked_until_tick;
  end if;');
  if v_new = v_def then raise exception 'break_alliance_core patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.propose_alliance(integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def, 'if v_d.status = ''neutral'' then', 'if v_d.status in (''neutral'', ''nap'') then');
  if v_new = v_def then raise exception 'propose_alliance patch did not apply'; end if;
  execute v_new;

  select pg_get_functiondef('public.resolve_tick_events(integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def,
    '  perform public.advance_diplomacy(p_game_id, p_tick);',
    '  perform public.advance_diplomacy(p_game_id, p_tick);
  perform public.advance_offers(p_game_id, p_tick);
  if v_cycle then
    perform public.process_gold_deals(p_game_id, p_tick);
  end if;');
  if v_new = v_def then raise exception 'resolve_tick_events patch did not apply'; end if;
  execute v_new;
end
$patch$;

create or replace function public.advance_offers(p_game_id integer, p_tick integer)
returns void
language sql
security definer
set search_path = ''
as $function$
  update public.diplomacy_offers set status = 'expired'
  where game_id = p_game_id and status = 'pending' and expires_tick <= p_tick;
$function$;

create or replace function public.process_gold_deals(p_game_id integer, p_tick integer)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_d record;
  v_gold int;
  v_dead boolean;
  v_status text;
begin
  for v_d in
    select * from public.gold_deals where game_id = p_game_id and status = 'active' order by id
  loop
    select exists (
      select 1 from public.game_players where id in (v_d.payer_id, v_d.payee_id) and eliminated_at_tick is not null
    ) into v_dead;
    select status into v_status from public.diplomacy
    where game_id = p_game_id and player_a_id = least(v_d.payer_id, v_d.payee_id) and player_b_id = greatest(v_d.payer_id, v_d.payee_id);

    if v_dead or (v_d.kind = 'trade' and v_status = 'war') then
      update public.gold_deals set status = 'cancelled' where id = v_d.id;
      continue;
    end if;

    select gold into v_gold from public.game_players where id = v_d.payer_id;
    if v_gold < v_d.amount then
      update public.gold_deals set status = 'cancelled' where id = v_d.id;
      update public.game_players set infamy_delta = infamy_delta + 5 where id = v_d.payer_id;
      perform public.notify_diplomacy(
        p_game_id, p_tick, array[v_d.payer_id, v_d.payee_id], 'Payment defaulted',
        jsonb_build_object('kind', 'deal_defaulted', 'deal_kind', v_d.kind, 'payer_id', v_d.payer_id, 'payee_id', v_d.payee_id, 'amount', v_d.amount)
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

create or replace function public.diplo_check_target(p_game_id integer, p_me integer, p_target integer)
returns public.diplomacy
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_t public.game_players%rowtype;
  v_d public.diplomacy%rowtype;
begin
  if p_target = p_me then
    raise exception 'you cannot do that with yourself';
  end if;
  select * into v_t from public.game_players where id = p_target and game_id = p_game_id;
  if not found then
    raise exception 'player not found in this game';
  end if;
  if v_t.eliminated_at_tick is not null then
    raise exception 'that player has been eliminated';
  end if;
  select * into v_d from public.diplomacy
  where game_id = p_game_id and player_a_id = least(p_me, p_target) and player_b_id = greatest(p_me, p_target)
  for update;
  if not found then
    raise exception 'no diplomatic relation with that player';
  end if;
  return v_d;
end;
$function$;

create or replace function public.create_offer_core(p_game_id integer, p_kind text, p_from integer, p_to integer, p_terms jsonb, p_tick integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_id int;
  v_name text;
begin
  if exists (
    select 1 from public.diplomacy_offers o
    where o.game_id = p_game_id and o.kind = p_kind and o.status = 'pending'
      and ((o.from_player_id = p_from and o.to_player_id = p_to) or (o.from_player_id = p_to and o.to_player_id = p_from))
  ) then
    raise exception 'there is already a pending % offer between you', p_kind;
  end if;

  insert into public.diplomacy_offers (game_id, kind, from_player_id, to_player_id, terms, created_tick, expires_tick)
  values (p_game_id, p_kind, p_from, p_to, coalesce(p_terms, '{}'::jsonb), p_tick, p_tick + 24)
  returning id into v_id;

  select display_name into v_name from public.game_players where id = p_from;
  perform public.notify_diplomacy(
    p_game_id, p_tick, array[p_to], 'Offer from ' || v_name,
    jsonb_build_object('kind', 'offer_received', 'offer_id', v_id, 'offer_kind', p_kind, 'from_player_id', p_from)
  );
  return v_id;
end;
$function$;

create or replace function public.validate_peace_terms(p_game_id integer, p_proposer integer, p_target integer, p_terms jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_payer text := coalesce(p_terms ->> 'payer', 'proposer');
  v_gold int := coalesce((p_terms ->> 'gold_now')::int, 0);
  v_tribute int := coalesce((p_terms ->> 'tribute')::int, 0);
  v_cycles int := coalesce((p_terms ->> 'cycles')::int, 0);
  v_give int := nullif(p_terms ->> 'give_territory', '')::int;
  v_ask int := nullif(p_terms ->> 'ask_territory', '')::int;
begin
  if v_payer not in ('proposer', 'target') then
    raise exception 'payer must be proposer or target';
  end if;
  if v_gold < 0 or v_gold > 100000 or v_tribute < 0 or v_tribute > 10000 or v_cycles < 0 or v_cycles > 20 then
    raise exception 'terms out of range';
  end if;
  if v_tribute > 0 and v_cycles < 1 then
    raise exception 'tribute needs at least one cycle';
  end if;
  if v_tribute = 0 then
    v_cycles := 0;
  end if;
  if v_gold = 0 and v_tribute = 0 and v_give is null and v_ask is null then
    raise exception 'peace terms must include gold, tribute or a castle; use plain peace instead';
  end if;
  if v_give is not null then
    perform public.check_cedable(p_game_id, v_give, p_proposer);
  end if;
  if v_ask is not null then
    perform public.check_cedable(p_game_id, v_ask, p_target);
  end if;
  return jsonb_build_object('payer', v_payer, 'gold_now', v_gold, 'tribute', v_tribute, 'cycles', v_cycles, 'give_territory', v_give, 'ask_territory', v_ask);
end;
$function$;

create or replace function public.check_cedable(p_game_id integer, p_territory_id integer, p_owner integer)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_t public.game_territories%rowtype;
begin
  select * into v_t from public.game_territories where id = p_territory_id and game_id = p_game_id;
  if not found or v_t.owner_player_id is distinct from p_owner then
    raise exception 'that castle is not held by the player who would give it up';
  end if;
  if exists (select 1 from public.game_players where id = p_owner and capital_territory_id = p_territory_id) then
    raise exception 'a capital cannot be ceded';
  end if;
  if exists (select 1 from public.commanders where current_territory_id = p_territory_id and status <> 'dead') then
    raise exception 'a castle with commanders in it cannot be ceded';
  end if;
  if public.has_hostile_siege(p_owner, p_territory_id) then
    raise exception 'a besieged castle cannot be ceded';
  end if;
end;
$function$;

create or replace function public.set_truce_core(p_game_id integer, p_a integer, p_b integer, p_tick integer, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_len int;
begin
  select truce_ticks into v_len from public.games where id = p_game_id;
  update public.diplomacy
  set status = 'truce', truce_ends_tick = p_tick + v_len, proposed_by_player_id = null, prior_status = null,
      broken_by_player_id = null, grace_ends_tick = null, updated_tick = p_tick
  where game_id = p_game_id and player_a_id = least(p_a, p_b) and player_b_id = greatest(p_a, p_b);

  perform public.expel_for_truce(p_game_id, p_a, p_b, p_tick);

  insert into public.game_moments (game_id, tick, type, payload)
  values (p_game_id, p_tick, 'truce_formed', jsonb_build_object('player_a', p_a, 'player_b', p_b, 'ends_tick', p_tick + v_len, 'via', p_reason));

  perform public.notify_diplomacy(
    p_game_id, p_tick, array[p_a, p_b], 'Truce agreed',
    jsonb_build_object('kind', 'truce_formed', 'players', to_jsonb(array[p_a, p_b]), 'ends_tick', p_tick + v_len)
  );
end;
$function$;

create or replace function public.respond_offer_core(p_offer_id integer, p_accept boolean, p_tick integer)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_o public.diplomacy_offers%rowtype;
  v_d public.diplomacy%rowtype;
  v_a int;
  v_b int;
  v_payer int;
  v_payee int;
  v_gold int;
  v_t jsonb;
  v_sib public.diplomacy_offers%rowtype;
  v_name text;
begin
  select * into v_o from public.diplomacy_offers where id = p_offer_id for update;
  if not found or v_o.status <> 'pending' then
    raise exception 'that offer is no longer open';
  end if;
  if v_o.expires_tick <= p_tick then
    update public.diplomacy_offers set status = 'expired' where id = v_o.id;
    raise exception 'that offer has expired';
  end if;

  select display_name into v_name from public.game_players where id = v_o.to_player_id;

  if not p_accept then
    update public.diplomacy_offers set status = 'declined' where id = v_o.id;
    perform public.notify_diplomacy(
      v_o.game_id, p_tick, array[v_o.from_player_id], v_name || ' declined your offer',
      jsonb_build_object('kind', 'offer_declined', 'offer_id', v_o.id, 'offer_kind', v_o.kind, 'by_player_id', v_o.to_player_id)
    );
    if v_o.kind = 'mediation' then
      update public.diplomacy_offers set status = 'withdrawn'
      where game_id = v_o.game_id and kind = 'mediation' and status = 'pending' and from_player_id = v_o.from_player_id and terms = v_o.terms and id <> v_o.id;
    end if;
    return 'declined';
  end if;

  v_t := v_o.terms;

  if v_o.kind = 'nap' then
    select * into v_d from public.diplomacy
    where game_id = v_o.game_id and player_a_id = least(v_o.from_player_id, v_o.to_player_id) and player_b_id = greatest(v_o.from_player_id, v_o.to_player_id) for update;
    if v_d.status <> 'neutral' then
      raise exception 'you are no longer neutral with that player';
    end if;
    update public.diplomacy set status = 'nap', updated_tick = p_tick, proposed_by_player_id = null
    where game_id = v_o.game_id and player_a_id = v_d.player_a_id and player_b_id = v_d.player_b_id;
    insert into public.game_moments (game_id, tick, type, payload, visibility, involved_player_ids)
    values (v_o.game_id, p_tick, 'nap_formed', jsonb_build_object('player_a', v_o.from_player_id, 'player_b', v_o.to_player_id), 'private', array[v_o.from_player_id, v_o.to_player_id]);

  elsif v_o.kind = 'marriage' then
    select * into v_d from public.diplomacy
    where game_id = v_o.game_id and player_a_id = least(v_o.from_player_id, v_o.to_player_id) and player_b_id = greatest(v_o.from_player_id, v_o.to_player_id) for update;
    if v_d.status <> 'allied' then
      raise exception 'you are no longer allied with that player';
    end if;
    update public.diplomacy set locked_until_tick = p_tick + (v_t ->> 'lock_ticks')::int, updated_tick = p_tick
    where game_id = v_o.game_id and player_a_id = v_d.player_a_id and player_b_id = v_d.player_b_id;
    insert into public.game_moments (game_id, tick, type, payload, visibility, involved_player_ids)
    values (v_o.game_id, p_tick, 'marriage_formed', jsonb_build_object('player_a', v_o.from_player_id, 'player_b', v_o.to_player_id, 'until_tick', p_tick + (v_t ->> 'lock_ticks')::int), 'public', array[v_o.from_player_id, v_o.to_player_id]);

  elsif v_o.kind = 'peace_terms' then
    select * into v_d from public.diplomacy
    where game_id = v_o.game_id and player_a_id = least(v_o.from_player_id, v_o.to_player_id) and player_b_id = greatest(v_o.from_player_id, v_o.to_player_id) for update;
    if v_d.status <> 'war' then
      raise exception 'you are no longer at war with that player';
    end if;
    v_t := public.validate_peace_terms(v_o.game_id, v_o.from_player_id, v_o.to_player_id, v_t);
    v_payer := case when v_t ->> 'payer' = 'proposer' then v_o.from_player_id else v_o.to_player_id end;
    v_payee := case when v_payer = v_o.from_player_id then v_o.to_player_id else v_o.from_player_id end;
    v_gold := (v_t ->> 'gold_now')::int;

    if v_gold > 0 then
      if (select gold from public.game_players where id = v_payer) < v_gold then
        raise exception 'the paying player cannot afford the lump sum';
      end if;
      update public.game_players set gold = gold - v_gold where id = v_payer;
      update public.game_players set gold = gold + v_gold where id = v_payee;
      insert into public.ledger (game_id, player_id, tick, type, amount) values
        (v_o.game_id, v_payer, p_tick, 'send_gold', -v_gold),
        (v_o.game_id, v_payee, p_tick, 'receive_gold', v_gold);
    end if;
    if (v_t ->> 'tribute')::int > 0 then
      insert into public.gold_deals (game_id, kind, payer_id, payee_id, amount, cycles_left, created_tick)
      values (v_o.game_id, 'tribute', v_payer, v_payee, (v_t ->> 'tribute')::int, (v_t ->> 'cycles')::int, p_tick);
    end if;
    if v_t ->> 'give_territory' is not null then
      update public.game_territories set owner_player_id = v_o.to_player_id, garrison_commander_id = null
      where id = (v_t ->> 'give_territory')::int;
    end if;
    if v_t ->> 'ask_territory' is not null then
      update public.game_territories set owner_player_id = v_o.from_player_id, garrison_commander_id = null
      where id = (v_t ->> 'ask_territory')::int;
    end if;
    if v_t ->> 'give_territory' is not null or v_t ->> 'ask_territory' is not null then
      perform public.refresh_effective_influence(v_o.game_id, v_o.from_player_id);
      perform public.refresh_effective_influence(v_o.game_id, v_o.to_player_id);
    end if;
    perform public.set_truce_core(v_o.game_id, v_o.from_player_id, v_o.to_player_id, p_tick, 'peace_terms');

  elsif v_o.kind = 'trade' then
    if (v_t ->> 'give')::int > 0 then
      insert into public.gold_deals (game_id, kind, payer_id, payee_id, amount, cycles_left, created_tick)
      values (v_o.game_id, 'trade', v_o.from_player_id, v_o.to_player_id, (v_t ->> 'give')::int, (v_t ->> 'cycles')::int, p_tick);
    end if;
    if (v_t ->> 'get')::int > 0 then
      insert into public.gold_deals (game_id, kind, payer_id, payee_id, amount, cycles_left, created_tick)
      values (v_o.game_id, 'trade', v_o.to_player_id, v_o.from_player_id, (v_t ->> 'get')::int, (v_t ->> 'cycles')::int, p_tick);
    end if;
    insert into public.game_moments (game_id, tick, type, payload, visibility, involved_player_ids)
    values (v_o.game_id, p_tick, 'trade_agreed', jsonb_build_object('player_a', v_o.from_player_id, 'player_b', v_o.to_player_id), 'private', array[v_o.from_player_id, v_o.to_player_id]);

  elsif v_o.kind = 'mediation' then
    update public.diplomacy_offers set status = 'accepted' where id = v_o.id;
    select * into v_sib from public.diplomacy_offers
    where game_id = v_o.game_id and kind = 'mediation' and from_player_id = v_o.from_player_id and terms = v_o.terms and id <> v_o.id
    order by id desc limit 1;
    if found and v_sib.status = 'accepted' then
      v_a := (v_t ->> 'a')::int;
      v_b := (v_t ->> 'b')::int;
      select * into v_d from public.diplomacy
      where game_id = v_o.game_id and player_a_id = least(v_a, v_b) and player_b_id = greatest(v_a, v_b) for update;
      if v_d.status = 'war' then
        perform public.set_truce_core(v_o.game_id, v_a, v_b, p_tick, 'mediation');
        insert into public.game_moments (game_id, tick, type, payload)
        values (v_o.game_id, p_tick, 'mediation_succeeded', jsonb_build_object('mediator', v_o.from_player_id, 'player_a', v_a, 'player_b', v_b));
        perform public.notify_diplomacy(
          v_o.game_id, p_tick, array[v_o.from_player_id], 'Your mediation succeeded',
          jsonb_build_object('kind', 'mediation_succeeded', 'player_a', v_a, 'player_b', v_b)
        );
      end if;
    end if;
    return 'accepted';
  end if;

  update public.diplomacy_offers set status = 'accepted' where id = v_o.id;
  perform public.notify_diplomacy(
    v_o.game_id, p_tick, array[v_o.from_player_id], v_name || ' accepted your offer',
    jsonb_build_object('kind', 'offer_accepted', 'offer_id', v_o.id, 'offer_kind', v_o.kind, 'by_player_id', v_o.to_player_id)
  );
  return 'accepted';
end;
$function$;

create or replace function public.propose_nap(p_game_id integer, p_target_player_id integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_player public.game_players;
  v_d public.diplomacy;
  v_tick int;
begin
  v_player := public.acting_player(p_game_id);
  v_d := public.diplo_check_target(p_game_id, v_player.id, p_target_player_id);
  if v_d.status <> 'neutral' then
    raise exception 'a non-aggression pact needs you to be neutral with that player';
  end if;
  select current_tick into v_tick from public.games where id = p_game_id;
  return jsonb_build_object('offer_id', public.create_offer_core(p_game_id, 'nap', v_player.id, p_target_player_id, '{}'::jsonb, v_tick));
end;
$function$;

create or replace function public.propose_marriage(p_game_id integer, p_target_player_id integer, p_lock_ticks integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_player public.game_players;
  v_d public.diplomacy;
  v_tick int;
begin
  v_player := public.acting_player(p_game_id);
  v_d := public.diplo_check_target(p_game_id, v_player.id, p_target_player_id);
  if v_d.status <> 'allied' then
    raise exception 'a marriage alliance needs an existing alliance';
  end if;
  if v_d.locked_until_tick is not null and v_d.locked_until_tick > (select current_tick from public.games where id = p_game_id) then
    raise exception 'that alliance is already locked';
  end if;
  if p_lock_ticks is null or p_lock_ticks < 12 or p_lock_ticks > 240 then
    raise exception 'lock length must be between 12 and 240 ticks';
  end if;
  select current_tick into v_tick from public.games where id = p_game_id;
  return jsonb_build_object('offer_id', public.create_offer_core(p_game_id, 'marriage', v_player.id, p_target_player_id, jsonb_build_object('lock_ticks', p_lock_ticks), v_tick));
end;
$function$;

create or replace function public.propose_peace_terms(p_game_id integer, p_target_player_id integer, p_terms jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_player public.game_players;
  v_d public.diplomacy;
  v_tick int;
  v_terms jsonb;
begin
  v_player := public.acting_player(p_game_id);
  v_d := public.diplo_check_target(p_game_id, v_player.id, p_target_player_id);
  if v_d.status <> 'war' then
    raise exception 'peace terms need you to be at war with that player';
  end if;
  v_terms := public.validate_peace_terms(p_game_id, v_player.id, p_target_player_id, p_terms);
  select current_tick into v_tick from public.games where id = p_game_id;
  return jsonb_build_object('offer_id', public.create_offer_core(p_game_id, 'peace_terms', v_player.id, p_target_player_id, v_terms, v_tick));
end;
$function$;

create or replace function public.propose_trade(p_game_id integer, p_target_player_id integer, p_give integer, p_get integer, p_cycles integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_player public.game_players;
  v_d public.diplomacy;
  v_tick int;
begin
  v_player := public.acting_player(p_game_id);
  v_d := public.diplo_check_target(p_game_id, v_player.id, p_target_player_id);
  if v_d.status = 'war' then
    raise exception 'you cannot trade with a player you are at war with';
  end if;
  if coalesce(p_give, 0) < 0 or coalesce(p_get, 0) < 0 or coalesce(p_give, 0) > 1000 or coalesce(p_get, 0) > 1000 or coalesce(p_give, 0) + coalesce(p_get, 0) = 0 then
    raise exception 'amounts must be between 0 and 1000, and not both zero';
  end if;
  if p_cycles is null or p_cycles < 1 or p_cycles > 20 then
    raise exception 'cycles must be between 1 and 20';
  end if;
  select current_tick into v_tick from public.games where id = p_game_id;
  return jsonb_build_object('offer_id', public.create_offer_core(p_game_id, 'trade', v_player.id, p_target_player_id,
    jsonb_build_object('give', coalesce(p_give, 0), 'get', coalesce(p_get, 0), 'cycles', p_cycles), v_tick));
end;
$function$;

create or replace function public.offer_mediation(p_game_id integer, p_player_a integer, p_player_b integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_player public.game_players;
  v_d public.diplomacy;
  v_tick int;
  v_terms jsonb;
  v_x int := least(p_player_a, p_player_b);
  v_y int := greatest(p_player_a, p_player_b);
begin
  v_player := public.acting_player(p_game_id);
  if v_player.id in (p_player_a, p_player_b) or p_player_a = p_player_b then
    raise exception 'a mediator must be a third party';
  end if;
  select * into v_d from public.diplomacy where game_id = p_game_id and player_a_id = v_x and player_b_id = v_y;
  if not found or v_d.status <> 'war' then
    raise exception 'those players are not at war';
  end if;
  if exists (select 1 from public.game_players where id in (v_x, v_y) and (eliminated_at_tick is not null or game_id <> p_game_id)) then
    raise exception 'both players must be in the game and alive';
  end if;
  select current_tick into v_tick from public.games where id = p_game_id;
  v_terms := jsonb_build_object('a', v_x, 'b', v_y);
  perform public.create_offer_core(p_game_id, 'mediation', v_player.id, v_x, v_terms, v_tick);
  perform public.create_offer_core(p_game_id, 'mediation', v_player.id, v_y, v_terms, v_tick);
  return jsonb_build_object('status', 'offered');
end;
$function$;

create or replace function public.respond_offer(p_offer_id integer, p_accept boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_game int;
  v_player public.game_players;
  v_to int;
  v_tick int;
begin
  select game_id, to_player_id into v_game, v_to from public.diplomacy_offers where id = p_offer_id;
  if v_game is null then
    raise exception 'offer not found';
  end if;
  v_player := public.acting_player(v_game);
  if v_player.id <> v_to then
    raise exception 'that offer is not addressed to you';
  end if;
  select current_tick into v_tick from public.games where id = v_game;
  return jsonb_build_object('status', public.respond_offer_core(p_offer_id, p_accept, v_tick));
end;
$function$;

create or replace function public.withdraw_offer(p_offer_id integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_o public.diplomacy_offers%rowtype;
  v_player public.game_players;
begin
  select * into v_o from public.diplomacy_offers where id = p_offer_id;
  if not found then
    raise exception 'offer not found';
  end if;
  v_player := public.acting_player(v_o.game_id);
  if v_player.id <> v_o.from_player_id then
    raise exception 'only the sender can withdraw an offer';
  end if;
  update public.diplomacy_offers set status = 'withdrawn'
  where id = p_offer_id and status = 'pending';
  if v_o.kind = 'mediation' then
    update public.diplomacy_offers set status = 'withdrawn'
    where game_id = v_o.game_id and kind = 'mediation' and status = 'pending' and from_player_id = v_o.from_player_id and terms = v_o.terms;
  end if;
  return jsonb_build_object('status', 'withdrawn');
end;
$function$;

create or replace function public.declare_war(p_game_id integer, p_target_player_id integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_player public.game_players;
  v_d public.diplomacy;
  v_tick int;
begin
  v_player := public.acting_player(p_game_id);
  v_d := public.diplo_check_target(p_game_id, v_player.id, p_target_player_id);
  if v_d.status <> 'neutral' then
    raise exception 'you can only declare war on a neutral player (current: %)', v_d.status;
  end if;
  select current_tick into v_tick from public.games where id = p_game_id;
  perform public.mark_war(p_game_id, v_player.id, p_target_player_id, v_tick, 'declared');
  return jsonb_build_object('status', 'war');
end;
$function$;

create or replace function public.break_nap(p_game_id integer, p_target_player_id integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_player public.game_players;
  v_d public.diplomacy;
  v_game public.games%rowtype;
  v_name text;
begin
  v_player := public.acting_player(p_game_id);
  v_d := public.diplo_check_target(p_game_id, v_player.id, p_target_player_id);
  if v_d.status <> 'nap' then
    raise exception 'you have no non-aggression pact with that player';
  end if;
  select * into v_game from public.games where id = p_game_id;

  update public.diplomacy
  set status = 'grace_period', broken_by_player_id = v_player.id,
      grace_ends_tick = v_game.current_tick + v_game.grace_period_ticks, updated_tick = v_game.current_tick
  where game_id = p_game_id and player_a_id = v_d.player_a_id and player_b_id = v_d.player_b_id;

  update public.game_players set infamy_delta = infamy_delta + 10 where id = v_player.id;

  insert into public.game_moments (game_id, tick, type, payload, visibility, involved_player_ids)
  values (p_game_id, v_game.current_tick, 'nap_broken', jsonb_build_object('by_player_id', v_player.id, 'against_player_id', p_target_player_id), 'public', array[v_player.id, p_target_player_id]);

  select display_name into v_name from public.game_players where id = v_player.id;
  perform public.notify_diplomacy(
    p_game_id, v_game.current_tick, array[p_target_player_id], v_name || ' broke the non-aggression pact',
    jsonb_build_object('kind', 'nap_broken', 'by_player_id', v_player.id, 'war_at_tick', v_game.current_tick + v_game.grace_period_ticks)
  );
  return jsonb_build_object('status', 'grace_period', 'war_at_tick', v_game.current_tick + v_game.grace_period_ticks);
end;
$function$;

create or replace function public.my_diplomacy_offers(p_game_id integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_me int;
begin
  select id into v_me from public.game_players where game_id = p_game_id and user_id = (select auth.uid());
  if v_me is null then
    raise exception 'you are not in this game';
  end if;
  return jsonb_build_object(
    'offers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', o.id, 'kind', o.kind, 'from_player_id', o.from_player_id, 'to_player_id', o.to_player_id,
        'terms', o.terms, 'expires_tick', o.expires_tick, 'created_tick', o.created_tick
      ) order by o.id)
      from public.diplomacy_offers o
      where o.game_id = p_game_id and o.status = 'pending' and v_me in (o.from_player_id, o.to_player_id)
    ), '[]'::jsonb),
    'deals', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id, 'kind', d.kind, 'payer_id', d.payer_id, 'payee_id', d.payee_id, 'amount', d.amount, 'cycles_left', d.cycles_left
      ) order by d.id)
      from public.gold_deals d
      where d.game_id = p_game_id and d.status = 'active' and v_me in (d.payer_id, d.payee_id)
    ), '[]'::jsonb),
    'locks', coalesce((
      select jsonb_agg(jsonb_build_object('player_a', dd.player_a_id, 'player_b', dd.player_b_id, 'until_tick', dd.locked_until_tick))
      from public.diplomacy dd
      where dd.game_id = p_game_id and dd.status = 'allied' and dd.locked_until_tick is not null and v_me in (dd.player_a_id, dd.player_b_id)
    ), '[]'::jsonb)
  );
end;
$function$;

create or replace function public.player_reputations(p_game_id integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if not exists (select 1 from public.game_players where game_id = p_game_id and user_id = (select auth.uid())) then
    raise exception 'you are not in this game';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'player_id', gp.id, 'honor', p.honor, 'infamy', p.infamy, 'games', p.total_games, 'wins', p.total_wins
    ) order by gp.id)
    from public.game_players gp
    join public.profiles p on p.user_id = gp.user_id
    where gp.game_id = p_game_id
  ), '[]'::jsonb);
end;
$function$;

do $grants$
declare
  r record;
begin
  for r in
    select oid::regprocedure as sig, proname from pg_proc
    where pronamespace = 'public'::regnamespace
      and proname in ('advance_offers', 'process_gold_deals', 'diplo_check_target', 'create_offer_core', 'validate_peace_terms', 'check_cedable', 'set_truce_core', 'respond_offer_core')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
  end loop;
  for r in
    select oid::regprocedure as sig from pg_proc
    where pronamespace = 'public'::regnamespace
      and proname in ('propose_nap', 'propose_marriage', 'propose_peace_terms', 'propose_trade', 'offer_mediation', 'respond_offer', 'withdraw_offer', 'declare_war', 'break_nap', 'my_diplomacy_offers', 'player_reputations')
  loop
    execute format('revoke all on function %s from public, anon', r.sig);
    execute format('grant execute on function %s to authenticated', r.sig);
  end loop;
end
$grants$;
