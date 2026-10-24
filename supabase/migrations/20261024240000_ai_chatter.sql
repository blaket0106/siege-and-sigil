alter table public.game_chat add column if not exists tick int;

create function public.ai_chatter(p_game_id int, p_player_id int, p_difficulty int)
returns void
language plpgsql
security definer
set search_path = ''
as $f$
declare
  v_tick int;
  v_gp public.game_players%rowtype;
  v_f public.factions%rowtype;
  v_last int;
  v_msg text;
  v_t text;
  v_foe int;
  v_mine int;
  v_lead record;
  v_pick int;
begin
  select current_tick into v_tick from public.games where id = p_game_id;
  select * into v_gp from public.game_players where id = p_player_id;
  select * into v_f from public.factions where slug = v_gp.faction_slug;
  if v_f.slug is null then
    return;
  end if;
  select max(tick) into v_last from public.game_chat where game_id = p_game_id and player_id = p_player_id;
  if v_last is not null and v_tick - v_last < 14 then
    return;
  end if;

  if not exists (select 1 from public.game_chat where game_id = p_game_id and player_id = p_player_id) then
    if v_tick >= 3 then
      v_msg := format('House %s greets the table. %s', v_f.name, v_f.motto);
    end if;
  else
    select m.payload ->> 'territory', (m.payload ->> 'from_player_id')::int into v_t, v_foe
    from public.game_moments m
    where m.game_id = p_game_id and m.type = 'castle_captured' and (m.payload ->> 'to_player_id')::int = p_player_id and m.tick >= v_tick - 8
    order by m.id desc limit 1;
    if v_t is not null and random() < 0.7 then
      v_pick := 1 + floor(random() * 3)::int;
      v_msg := case v_pick
        when 1 then format('The banner of House %s now flies over %s.', v_f.name, v_t)
        when 2 then format('%s is ours. %s', v_t, v_f.motto)
        else format('Another gate opened: %s. House %s does not stop.', v_t, v_f.name) end;
    end if;

    if v_msg is null then
      select m.payload ->> 'territory', (m.payload ->> 'to_player_id')::int into v_t, v_foe
      from public.game_moments m
      where m.game_id = p_game_id and m.type = 'castle_captured' and (m.payload ->> 'from_player_id')::int = p_player_id and m.tick >= v_tick - 8
      order by m.id desc limit 1;
      if v_t is not null and v_foe is not null and random() < 0.8 then
        v_msg := format('%s will be taken back, %s. Remember that.', v_t, (select display_name from public.game_players where id = v_foe));
      end if;
    end if;

    if v_msg is null then
      select gp.display_name, public.castle_count(gp.id) as n into v_lead
      from public.game_players gp
      where gp.game_id = p_game_id and gp.id <> p_player_id and gp.eliminated_at_tick is null
      order by public.castle_count(gp.id) desc, gp.id limit 1;
      v_mine := public.castle_count(p_player_id);
      if found and v_lead.n >= v_mine + 2 and random() < 0.3 then
        v_msg := format('%s holds %s castles to my %s. Enjoy it while it lasts.', v_lead.display_name, v_lead.n, v_mine);
      end if;
    end if;

    if v_msg is null and random() < 0.04 then
      v_msg := (array[v_f.motto, 'The realm is quiet. That never lasts.', 'I count the castles, and I count the days.'])[1 + floor(random() * 3)::int];
    end if;
  end if;

  if v_msg is not null then
    insert into public.game_chat (game_id, player_id, message, tick) values (p_game_id, p_player_id, v_msg, v_tick);
  end if;
end;
$f$;

revoke execute on function public.ai_chatter(int, int, int) from public, anon, authenticated;

do $patch$
declare
  v_def text;
  v_old text := '  perform public.ai_spend(p_game_id, p_player_id, v_difficulty);';
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'ai_take_turn' and p.pronamespace = 'public'::regnamespace;
  if position(v_old in v_def) = 0 then
    raise exception 'ai_take_turn patch did not match';
  end if;
  execute replace(v_def, v_old, '  perform public.ai_chatter(p_game_id, p_player_id, v_difficulty);' || chr(10) || v_old);
end;
$patch$;
