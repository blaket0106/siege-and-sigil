do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'plan_march' and p.pronamespace = 'public'::regnamespace order by p.oid limit 1;
  v_new := replace(v_def, 'public.plan_march(p_player_id integer, p_commander_id integer, p_to_territory_id integer)', 'public.plan_march_from(p_player_id integer, p_commander_id integer, p_from_territory_id integer, p_to_territory_id integer)');
  if v_new = v_def then
    raise exception 'plan_march_from header did not match';
  end if;
  v_new := replace(v_new, 'v_c.current_territory_id', 'coalesce(p_from_territory_id, v_c.current_territory_id)');
  execute v_new;
end;
$patch$;

revoke execute on function public.plan_march_from(int, int, int, int) from public, anon, authenticated;

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
      ('send_on_route', array[
        E'  v_origin jsonb := ''{}''::jsonb;\nbegin',
        E'  v_origin jsonb := ''{}''::jsonb;\n  v_from int;\n  v_to int;\n  v_i int;\n  v_n int;\n  v_d float8;\n  v_pm jsonb;\n  v_game public.games%rowtype;\n  v_stables int;\nbegin',
        E'  select current_tick into v_tick from public.games where id = p_game_id;\n',
        E'  select * into v_game from public.games where id = p_game_id;\n  select coalesce(level, 0) into v_stables from public.realm_areas where player_id = v_player.id and area = ''stables'';\n  v_stables := coalesce(v_stables, 0);\n  v_n := jsonb_array_length(v_stops);\n  v_from := v_c.current_territory_id;\n  for v_i in 0 .. v_n - 1 + (case when v_loop then 1 else 0 end) loop\n    v_to := (v_stops -> (v_i % v_n) ->> ''territory_id'')::int;\n    if v_i > 0 then\n      if v_game.free_travel then\n        select sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) into v_d from public.game_territories a, public.game_territories b where a.id = v_from and b.id = v_to;\n        if v_d > (210 + 60 * v_stables) * v_game.world_scale then\n          raise exception ''stop % is out of range of stop %'', v_i + 1, v_i;\n        end if;\n      else\n        begin\n          v_pm := public.plan_march_from(v_player.id, v_c.id, v_from, v_to);\n        exception when others then\n          raise exception ''stop %: %'', v_i + 1, sqlerrm;\n        end;\n        if not (v_pm ->> ''in_range'')::boolean then\n          raise exception ''stop % is out of range of stop % (% needed, % available)'', v_i + 1, v_i, v_pm ->> ''raw_length'', v_pm ->> ''range'';\n        end if;\n      end if;\n    end if;\n    v_from := v_to;\n  end loop;\n\n  select current_tick into v_tick from public.games where id = p_game_id;\n'
      ]),
      ('advance_route', array[
        '''at_territory_id'', v_c.current_territory_id, ''reason'', sqlerrm',
        '''at_territory_id'', v_c.current_territory_id, ''to_territory_id'', (v_stop ->> ''territory_id'')::int, ''reason'', sqlerrm'
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
  v_old text := '''system'', ''Route cancelled'',';
  v_new text := '''system'', ''Route cancelled: '' || v_c.name || '' stopped at '' || coalesce((select gt.name from public.game_territories gt where gt.id = v_c.current_territory_id), ''a castle'') || '' (next stop: '' || sqlerrm || '')'',';
begin
  select pg_get_functiondef('public.advance_route(integer)'::regprocedure) into v_def;
  if position(v_old in v_def) = 0 then raise exception 'pattern'; end if;
  execute replace(v_def, v_old, v_new);
end;
$patch$;
