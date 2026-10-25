create or replace function public.ai_thread_replies(p_game_id int, p_player_id int)
returns void
language plpgsql
security definer
set search_path = ''
as $f$
declare
  v_t record;
  v_style text;
  v_status text;
  v_sender int;
  v_hid int;
  v_body text;
  v_n int;
  v_line text;
  v_pool text[];
  v_last text;
  v_try int;
begin
  select ai_style into v_style from public.game_players where id = p_player_id;
  for v_t in
    select t.id
    from public.message_threads t
    join public.thread_participants tp on tp.thread_id = t.id and tp.player_id = p_player_id
    where t.game_id = p_game_id
  loop
    select m.player_id, m.id, m.body into v_sender, v_hid, v_body
    from public.thread_messages m join public.game_players g on g.id = m.player_id and not g.is_ai
    where m.thread_id = v_t.id order by m.id desc limit 1;
    continue when v_sender is null;
    continue when exists (select 1 from public.thread_messages m2 where m2.thread_id = v_t.id and m2.player_id = p_player_id and m2.id > v_hid);

    select d.status into v_status from public.diplomacy d
    where d.game_id = p_game_id and d.player_a_id = least(p_player_id, v_sender) and d.player_b_id = greatest(p_player_id, v_sender);
    v_n := public.castle_count(p_player_id);
    v_body := lower(coalesce(v_body, ''));

    v_pool := case
      when v_body ~ 'allian|ally|allies' then case
        when v_status = 'allied' then array['We are already allied. Name the target and I will look at it.']
        when v_style = 'defensive' then array['An alliance is a heavy promise. Propose it in Standings and I will weigh it with care.', 'I would stand with a steady neighbour. Send the proposal through Standings.']
        when v_style = 'aggressive' then array['Alliances rarely suit me. Propose it in Standings and I will see what it is worth.', 'I march alone more often than not. Make it worth my while in Standings.']
        else array['Propose it in Standings and I will weigh it on its merits.', 'An alliance needs more than words. Send the proposal in Standings.'] end
      when v_body ~ 'peace|truce|ceasefire|treaty' then case
        when v_style = 'defensive' then array['Peace suits me. Send terms in Standings and I will read them gladly.']
        when v_style = 'aggressive' then array['Peace is for those who cannot win. Make an offer in Standings if you mean it.', 'I will hear terms, but I will not hurry to take them.']
        else array['I would hear peace terms. Send them through Standings.', 'Peace is possible at a fair price. Propose it in Standings.'] end
      when v_body ~ 'gold|pay|tribute|trade|coin|ransom' then case
        when v_style = 'aggressive' then array['Gold does not stop armies, but it slows them. Name a sum, and send it through Standings.']
        when v_style = 'defensive' then array['Gold keeps granaries full. Send an offer through Standings and I will consider it.']
        else array['Gold speaks. Put your offer in Standings and we will see.', 'Trade is welcome. Make the offer in Standings.'] end
      when v_body ~ 'war|attack|invade|destroy|crush|surrender|fight' then case
        when v_style = 'defensive' then array['We would rather not. But our walls are ready.']
        when v_style = 'aggressive' then array['Come, then. I am already on the road.', 'Threats are wind. Armies are not.']
        else array['Threats are cheap. My walls are not.', 'If it is war you want, you will have to take it.'] end
      when v_status = 'allied' then array['We stand together. Name the target and I will look at it.', 'An ally''s word carries weight. What do you need?', 'Our banners fly side by side. I am listening.']
      when v_status in ('war', 'war_declared') then case v_style
        when 'defensive' then array['I want no more war than I must. Offer terms and I will weigh them.', 'My walls are high. Come if you must, or speak of peace.']
        when 'aggressive' then array['We are at war. Save your words for the end of it.', 'Take the field, then. I am already on the road.']
        else array['We are at war. A fair offer might still be heard.', 'Speak plainly, and bring an offer.'] end
      else case v_style
        when 'defensive' then array['I keep to my walls and my granaries. Let us keep the peace.', 'I have no quarrel with you, and I mean to keep it so.', 'I am glad to talk. I will not be hurried into anything.']
        when 'aggressive' then array['Speak plainly. The border is where I look first.', 'I hear you. I move when I see an opening, so make it worth my while.', 'Be quick. My armies do not wait on letters.']
        else array['I hear you. A fair offer gets a fair answer.', 'Well met. What do you propose?', 'Tell me what you want, and I will tell you what it costs.'] end
    end;

    select left(m3.body, 400) into v_last from public.thread_messages m3 where m3.thread_id = v_t.id and m3.player_id = p_player_id order by m3.id desc limit 1;
    v_line := v_pool[1 + floor(random() * array_length(v_pool, 1))::int];
    v_try := 0;
    while v_last is not null and left(v_last, length(v_line)) = v_line and v_try < 4 loop
      v_line := v_pool[1 + floor(random() * array_length(v_pool, 1))::int];
      v_try := v_try + 1;
    end loop;
    if random() < 0.4 then
      v_line := v_line || format(' I hold %s castles.', v_n);
    end if;
    perform public.post_thread_message(v_t.id, p_player_id, v_line);
  end loop;
end;
$f$;

do $patch$
declare
  v_def text;
  v_new text;
  v_pairs text[] := array[
    E'  v_pick int;\n  v_tid int;\nbegin',
    E'  v_pick int;\n  v_tid int;\n  v_bt int;\n  v_ba int;\n  v_bd int;\n  v_bw int;\n  v_foename text;\nbegin',
    E'    if v_msg is null then\n      select gp.display_name, public.castle_count(gp.id) as n into v_lead',
    E'    if v_msg is null then\n      select b.tick, (b.report -> ''sides'' -> 0 ->> ''player_id'')::int, (b.report -> ''sides'' -> 1 ->> ''player_id'')::int, (b.report ->> ''winner'')::int\n      into v_bt, v_ba, v_bd, v_bw\n      from public.battle_reports b\n      where b.game_id = p_game_id and b.tick >= v_tick - 6\n        and (b.report -> ''sides'' -> 0 ->> ''player_id'') is not null and (b.report -> ''sides'' -> 1 ->> ''player_id'') is not null\n        and p_player_id in ((b.report -> ''sides'' -> 0 ->> ''player_id'')::int, (b.report -> ''sides'' -> 1 ->> ''player_id'')::int)\n      order by b.id desc limit 1;\n      if v_bt is not null and random() < 0.7 then\n        select display_name into v_foename from public.game_players where id = case when v_ba = p_player_id then v_bd else v_ba end;\n        v_msg := case\n          when v_ba = p_player_id and v_bw = 0 then format(''%s felt the weight of House %s today.'', v_foename, v_f.name)\n          when v_ba = p_player_id then format(''A setback against %s. It will not be repeated.'', v_foename)\n          when v_bw = 1 then format(''%s broke on our walls. House %s holds.'', v_foename, v_f.name)\n          else format(''%s has taken what was ours. We will answer.'', v_foename) end;\n      end if;\n    end if;\n\n    if v_msg is null then\n      select gp.display_name, public.castle_count(gp.id) as n into v_lead',
    E'v_msg := case 1 + floor(random() * 4)::int\n          when 1 then',
    E'v_msg := case when v_gp.ai_style = ''defensive'' then format(''%s grows strong with %s castles. We hold our walls and we watch.'', v_lead.display_name, v_lead.n) else case 1 + floor(random() * 4)::int\n          when 1 then',
    E'v_lead.display_name, v_mine) end;',
    E'v_lead.display_name, v_mine) end end;'
  ];
  i int;
begin
  select pg_get_functiondef('public.ai_chatter(int, int, int)'::regprocedure) into v_def;
  v_new := v_def;
  for i in 1 .. array_length(v_pairs, 1) / 2 loop
    if position(v_pairs[2 * i - 1] in v_new) = 0 then
      raise exception 'ai_chatter patch % did not match', i;
    end if;
    v_new := replace(v_new, v_pairs[2 * i - 1], v_pairs[2 * i]);
  end loop;
  execute v_new;
end;
$patch$;
