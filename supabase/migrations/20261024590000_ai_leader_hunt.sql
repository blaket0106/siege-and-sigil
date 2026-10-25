create function public.ai_leader(p_game_id int, p_player_id int)
returns int
language sql
stable
security definer
set search_path = ''
as $f$
  select gp.id
  from public.game_players gp
  where gp.game_id = p_game_id and gp.id <> p_player_id and gp.eliminated_at_tick is null
    and public.castle_count(gp.id) >= 0.6 * (public.game_standing(p_game_id) ->> 'win_at')::int
  order by public.castle_count(gp.id) desc, gp.id
  limit 1;
$f$;
revoke execute on function public.ai_leader(int, int) from public, anon, authenticated;

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
      ('ai_commanders', array[
        '  v_prey int[];',
        '  v_prey int[];' || chr(10) || '  v_hunt int;',
        '< 0.8 * public.castle_count(p_player_id);',
        '< 0.8 * public.castle_count(p_player_id);' || chr(10) || '  v_hunt := public.ai_leader(p_game_id, p_player_id);' || chr(10) || '  v_prey := array_remove(v_prey || array[coalesce(v_hunt, 0)], 0);',
        '+ case when v_t.owner_player_id = any (v_prey) and v_style <> ''defensive'' then 4 else 0 end',
        '+ case when v_t.owner_player_id = any (v_prey) and v_style <> ''defensive'' then 4 else 0 end + case when v_t.owner_player_id = v_hunt then 8 else 0 end'
      ]),
      ('ai_muster', array[
        '  v_prey int[];',
        '  v_prey int[];' || chr(10) || '  v_hunt int;',
        'and public.castle_count(gp.id) < 0.8 * public.castle_count(p_player_id);',
        'and public.castle_count(gp.id) < 0.8 * public.castle_count(p_player_id);' || chr(10) || '  v_hunt := public.ai_leader(p_game_id, p_player_id);' || chr(10) || '  v_prey := array_remove(v_prey || array[coalesce(v_hunt, 0)], 0);',
        '(case when r.owner_player_id = any (v_prey) then 0.5 else 1 end)',
        '(case when r.owner_player_id = v_hunt then 0.25 when r.owner_player_id = any (v_prey) then 0.5 else 1 end)',
        '(case when t.owner_player_id = any (v_prey) then 0.5 else 1 end)',
        '(case when t.owner_player_id = v_hunt then 0.25 when t.owner_player_id = any (v_prey) then 0.5 else 1 end)'
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
