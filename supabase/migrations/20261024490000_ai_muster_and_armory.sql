create or replace function public.ai_pick_area(p_player_id integer)
returns void
language plpgsql
security definer
set search_path = ''
as $f$
declare
  v_area text;
  v_style text;
begin
  select ai_style into v_style from public.game_players where id = p_player_id;
  select area into v_area
  from public.realm_areas
  where player_id = p_player_id
  order by level - case
      when v_style = 'aggressive' and area = 'armory' then 2.0
      when v_style = 'aggressive' and area = 'barracks' then 1.5
      when v_style = 'aggressive' and area = 'stables' then 0.5
      when v_style = 'balanced' and area = 'armory' then 1.0
      when v_style = 'balanced' and area = 'barracks' then 0.5
      when v_style = 'defensive' and area in ('armory', 'watchtowers') then 1.0
      else 0 end,
    array_position(array['mint', 'barracks', 'armory', 'guildhall', 'stables', 'watchtowers', 'library'], area)
  limit 1;
  if v_area is null then
    return;
  end if;
  update public.realm_areas set is_active = false where player_id = p_player_id and is_active;
  update public.realm_areas set is_active = true where player_id = p_player_id and area = v_area;
end;
$f$;

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
      ('ai_muster', array[
        E'select c.id, c.troops, c.current_territory_id as at_id\n',
        E'select c.id, c.troops, c.current_territory_id as at_id, ct.troops as at_troops\n',
        'and c.id <> v_sc and c.role <> ''king'' and c.troops >= 4 and ct.id <> v_hub',
        'and c.id <> v_sc and c.role <> ''king'' and (c.troops + greatest(0, ct.troops - 2)) >= 6 and ct.id <> v_hub',
        E'order by c.troops desc, c.id\n    limit 8',
        E'order by (c.troops + ct.troops) desc, c.id\n    limit 8',
        E'      insert into public.commander_routes (game_id, commander_id, stops, created_tick, origin_territory_id, looping)\n      values (p_game_id, v_c.id, v_stops, v_tick, v_c.at_id, false);',
        E'      perform public.transfer_troops_core(p_game_id, p_player_id, v_c.id, greatest(0, v_c.at_troops - 2));\n      insert into public.commander_routes (game_id, commander_id, stops, created_tick, origin_territory_id, looping)\n      values (p_game_id, v_c.id, v_stops, v_tick, v_c.at_id, false);',
        'v_force := v_force + v_c.troops;',
        'v_force := v_force + v_c.troops + greatest(0, v_c.at_troops - 2);'
      ]),
      ('ai_take_turn', array[
        E'  perform public.ai_commanders(p_game_id, p_player_id, v_difficulty);\n  perform public.ai_muster(p_game_id, p_player_id, v_difficulty);',
        E'  perform public.ai_muster(p_game_id, p_player_id, v_difficulty);\n  perform public.ai_commanders(p_game_id, p_player_id, v_difficulty);'
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
