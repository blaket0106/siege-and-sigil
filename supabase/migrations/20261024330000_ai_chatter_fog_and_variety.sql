create function public.ai_chat_visible(p_game_id int, p_territory_id int)
returns boolean
language sql
stable
security definer
set search_path = ''
as $f$
  select not g.fog_of_war or p_territory_id is null or exists (
    select 1 from unnest(public.players_seeing(p_game_id, p_territory_id)) pid
    join public.game_players gp on gp.id = pid
    where not gp.is_ai
  )
  from public.games g where g.id = p_game_id
$f$;
revoke execute on function public.ai_chat_visible(int, int) from public, anon, authenticated;

do $patch$
declare
  v_def text;
  v_new text;
  v_pairs text[] := array[
    E'  v_pick int;\nbegin',
    E'  v_pick int;\n  v_tid int;\nbegin',
    'select m.payload ->> ''territory'', (m.payload ->> ''from_player_id'')::int into v_t, v_foe',
    'select m.payload ->> ''territory'', (m.payload ->> ''from_player_id'')::int, (m.payload ->> ''territory_id'')::int into v_t, v_foe, v_tid',
    'if v_t is not null and random() < 0.7 then',
    'if v_t is not null and random() < 0.7 and public.ai_chat_visible(p_game_id, v_tid) then',
    'select m.payload ->> ''territory'', (m.payload ->> ''to_player_id'')::int into v_t, v_foe',
    'select m.payload ->> ''territory'', (m.payload ->> ''to_player_id'')::int, (m.payload ->> ''territory_id'')::int into v_t, v_foe, v_tid',
    'if v_t is not null and v_foe is not null and random() < 0.8 then',
    'if v_t is not null and v_foe is not null and random() < 0.8 and public.ai_chat_visible(p_game_id, v_tid) then',
    'if found and v_lead.n >= v_mine + 2 and random() < 0.3 then',
    'if found and v_lead.n >= v_mine + 2 and random() < 0.3 and not exists (select 1 from public.game_chat gc where gc.game_id = p_game_id and gc.tick >= v_tick - 30 and gc.message like ''%'' || v_lead.display_name || ''%'') then',
    'v_msg := format(''%s holds %s castles to my %s. Enjoy it while it lasts.'', v_lead.display_name, v_lead.n, v_mine);',
    E'v_msg := case 1 + floor(random() * 4)::int\n          when 1 then format(''%s holds %s castles to my %s. Enjoy it while it lasts.'', v_lead.display_name, v_lead.n, v_mine)\n          when 2 then format(''%s is pulling ahead of the rest of us with %s castles. That will not last.'', v_lead.display_name, v_lead.n)\n          when 3 then format(''Someone should humble %s before the whole realm kneels to them.'', v_lead.display_name)\n          else format(''I count %s castles for %s and %s for me. The count will change.'', v_lead.n, v_lead.display_name, v_mine) end;'
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
