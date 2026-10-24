alter table public.council_members add column profile jsonb;

create function public.council_school(p_area text)
returns text
language sql
immutable
set search_path = ''
as $f$
  select case p_area when 'armory' then 'battleschool' when 'barracks' then 'battleschool'
                     when 'watchtowers' then 'rangers' when 'stables' then 'rangers' else 'university' end
$f$;

create or replace function public.create_council_member()
returns trigger
language plpgsql
security definer
set search_path = ''
as $f$
declare
  v_ident jsonb;
begin
  v_ident := public.commander_identity(new.game_id, new.player_id);
  insert into public.council_members (game_id, player_id, area, name, status, created_tick, profile)
  values (new.game_id, new.player_id, new.area, v_ident ->> 'name', 'seated',
          coalesce((select current_tick from public.games where id = new.game_id), 0),
          public.commander_profile(new.player_id, public.council_school(new.area), 'commander', v_ident ->> 'sex'));
  return new;
end;
$f$;

update public.council_members m
set profile = public.commander_profile(
  m.player_id, public.council_school(m.area), 'commander',
  case when split_part(m.name, ' ', 1) = any (array['Isolde', 'Maren', 'Brenna', 'Cordelia', 'Daria', 'Elara', 'Freya', 'Greta', 'Helena', 'Ingrid', 'Jocelyn', 'Katarin', 'Mirelle']) then 'f' else 'm' end)
where m.profile is null;

do $patch$
declare
  v_def text;
  v_new text;
  v_pairs text[];
  v_fn text;
  i int;
begin
  for v_fn, v_pairs in
    select * from (values
      ('recruit_councillor', array[
        '  v_name text;',
        '  v_name text;' || chr(10) || '  v_ident jsonb;',
        '  v_name := public.random_commander_name(p_game_id);',
        '  v_ident := public.commander_identity(p_game_id, v_player.id);' || chr(10) || '  v_name := v_ident ->> ''name'';',
        'insert into public.council_members (game_id, player_id, area, name, status, created_tick) values (p_game_id, v_player.id, p_area, v_name, ''seated'', v_tick);',
        'insert into public.council_members (game_id, player_id, area, name, status, created_tick, profile) values (p_game_id, v_player.id, p_area, v_name, ''seated'', v_tick, public.commander_profile(v_player.id, public.council_school(p_area), ''commander'', v_ident ->> ''sex''));'
      ]),
      ('deploy_councillor', array[
        '  update public.commanders set name = v_m.name, council_area = p_area where id = v_id;',
        '  update public.commanders set name = v_m.name, council_area = p_area, profile = coalesce(v_m.profile, profile) where id = v_id;'
      ]),
      ('my_council', array[
        '''name'', m.name, ''status'', coalesce(m.status, ''dead''), ''commander_id'', m.commander_id',
        '''name'', m.name, ''status'', coalesce(m.status, ''dead''), ''commander_id'', m.commander_id, ''member_id'', m.id, ''profile'', m.profile'
      ]),
      ('ai_crown', array[
        '  where id = v_id;',
        '  where id = v_id;' || chr(10)
          || '  perform public.log_commander(v_id, v_game.current_tick, ''crowned'', format(''Was named king of House %s.'', public.house_name(p_player_id)));'
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
