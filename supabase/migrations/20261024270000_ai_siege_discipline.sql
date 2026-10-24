create function public.siege_can_win(p_att int, p_def_dmg int, p_atk_dmg int, p_def_troops int, p_max_ticks int)
returns boolean
language plpgsql
immutable
set search_path = ''
as $f$
declare
  n int;
begin
  for n in 1 .. p_max_ticks loop
    if ceil(p_att::float8 / greatest(1, p_def_dmg))::int > ceil((p_def_troops * power(0.97, n)) / greatest(1, p_atk_dmg))::int then
      return true;
    end if;
  end loop;
  return false;
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
      ('ai_commanders', array[
        '        if p_difficulty >= 3 and v_inr then',
        '        if p_difficulty >= 3 and v_inr and public.siege_can_win(v_att, v_def_dmg, v_atk_dmg, v_t.troops, 28) then'
      ]),
      ('ai_sieges', array[
        '  v_def_n float8;' || chr(10) || 'begin',
        '  v_def_n float8;' || chr(10) || '  v_cid int;' || chr(10) || '  v_home int;' || chr(10) || 'begin',
        '        update public.commanders set status = ''idle'' where id = any (v_ids) and status = ''sieging'';',
        '        foreach v_cid in array v_ids loop' || chr(10)
          || '          begin' || chr(10)
          || '            select o.id into v_home from public.game_territories o where o.game_id = p_game_id and o.owner_player_id = p_player_id and not o.is_junction order by (o.x - v_t.x) ^ 2 + (o.y - v_t.y) ^ 2 limit 1;' || chr(10)
          || '            update public.commanders set status = ''idle'' where id = v_cid and status = ''sieging'';' || chr(10)
          || '            perform public.launch_leg(p_player_id, v_cid, v_home, ''assault'');' || chr(10)
          || '          exception when others then' || chr(10)
          || '            null;' || chr(10)
          || '          end;' || chr(10)
          || '        end loop;'
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
