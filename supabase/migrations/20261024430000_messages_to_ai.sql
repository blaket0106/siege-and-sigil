create function public.ai_thread_replies(p_game_id int, p_player_id int)
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
  v_n int;
  v_line text;
  v_pool text[];
begin
  select ai_style into v_style from public.game_players where id = p_player_id;
  for v_t in
    select t.id
    from public.message_threads t
    join public.thread_participants tp on tp.thread_id = t.id and tp.player_id = p_player_id
    where t.game_id = p_game_id
  loop
    select m.player_id into v_sender
    from public.thread_messages m where m.thread_id = v_t.id order by m.id desc limit 1;
    continue when v_sender is null or v_sender = p_player_id;
    continue when (select is_ai from public.game_players where id = v_sender);

    select d.status into v_status from public.diplomacy d
    where d.game_id = p_game_id and d.player_a_id = least(p_player_id, v_sender) and d.player_b_id = greatest(p_player_id, v_sender);
    v_n := public.castle_count(p_player_id);

    v_pool := case
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
    v_line := v_pool[1 + floor(random() * array_length(v_pool, 1))::int];
    if random() < 0.4 then
      v_line := v_line || format(' I hold %s castles.', v_n);
    end if;
    perform public.post_thread_message(v_t.id, p_player_id, v_line);
  end loop;
end;
$f$;
revoke execute on function public.ai_thread_replies(int, int) from public, anon, authenticated;

do $patch$
declare
  v_def text;
  v_new text;
  v_fn text;
  v_pairs text[];
  i int;
begin
  for v_fn, v_pairs in
    select * from (values
      ('create_thread', array[
        E'select count(*) from public.game_players where game_id = p_game_id and id = any (v_ids) and not is_ai',
        E'select count(*) from public.game_players where game_id = p_game_id and id = any (v_ids)',
        'you can only message human players in this game',
        'you can only message players in this game'
      ]),
      ('ai_take_turn', array[
        '  perform public.ai_chatter(p_game_id, p_player_id, v_difficulty);',
        E'  perform public.ai_thread_replies(p_game_id, p_player_id);\n  perform public.ai_chatter(p_game_id, p_player_id, v_difficulty);'
      ])
    ) as t(fn, pairs)
  loop
    select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = v_fn and p.pronamespace = 'public'::regnamespace order by p.oid limit 1;
    v_new := v_def;
    for i in 1 .. array_length(v_pairs, 1) / 2 loop
      if position(v_pairs[2 * i - 1] in v_new) = 0 then
        raise exception '% patch % did not match', v_fn, i;
      end if;
      v_new := replace(v_new, v_pairs[2 * i - 1], v_pairs[2 * i]);
    end loop;
    execute v_new;
  end loop;
end;
$patch$;

do $patch$
declare
  v_def text;
  v_new text;
  v_pairs text[] := array[
    E'  v_sender int;\n',
    E'  v_sender int;\n  v_hid int;\n',
    E'    select m.player_id into v_sender\n    from public.thread_messages m where m.thread_id = v_t.id order by m.id desc limit 1;\n    continue when v_sender is null or v_sender = p_player_id;\n    continue when (select is_ai from public.game_players where id = v_sender);\n',
    E'    select m.player_id, m.id into v_sender, v_hid\n    from public.thread_messages m join public.game_players g on g.id = m.player_id and not g.is_ai\n    where m.thread_id = v_t.id order by m.id desc limit 1;\n    continue when v_sender is null;\n    continue when exists (select 1 from public.thread_messages m2 where m2.thread_id = v_t.id and m2.player_id = p_player_id and m2.id > v_hid);\n'
  ];
  i int;
begin
  select pg_get_functiondef('public.ai_thread_replies(int, int)'::regprocedure) into v_def;
  v_new := v_def;
  for i in 1 .. array_length(v_pairs, 1) / 2 loop
    if position(v_pairs[2 * i - 1] in v_new) = 0 then
      raise exception 'patch % did not match', i;
    end if;
    v_new := replace(v_new, v_pairs[2 * i - 1], v_pairs[2 * i]);
  end loop;
  execute v_new;
end;
$patch$;
