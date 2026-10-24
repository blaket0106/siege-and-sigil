create table public.commander_history (
  id bigserial primary key,
  game_id int not null references public.games (id) on delete cascade,
  commander_id int not null references public.commanders (id) on delete cascade,
  tick int not null,
  kind text not null,
  text text not null
);
create index commander_history_cmd_idx on public.commander_history (commander_id, id desc);
alter table public.commander_history enable row level security;

create function public.house_name(p_player int)
returns text
language sql
stable
security definer
set search_path = ''
as $f$
  select f.name from public.game_players gp join public.factions f on f.slug = gp.faction_slug where gp.id = p_player
$f$;

create function public.log_commander(p_commander_id int, p_tick int, p_kind text, p_text text)
returns void
language sql
security definer
set search_path = ''
as $f$
  insert into public.commander_history (game_id, commander_id, tick, kind, text)
  select c.game_id, c.id, p_tick, p_kind, p_text from public.commanders c where c.id = p_commander_id
$f$;

create function public.log_battle_history(p_game_id int, p_tick int, p_kind text, p_place text, p_a_role text, p_a_ids int[], p_a_player int, p_b_role text, p_b_ids int[], p_b_player int, p_winner int, p_captured boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $f$
declare
  v_side int;
  v_ids int[];
  v_role text;
  v_enemy int;
  v_foe text;
  v_won boolean;
  v_text text;
  v_kind text;
  v_c int;
  v_place text := coalesce(p_place, 'the road');
  v_r int;
begin
  for v_side in 0 .. 1 loop
    v_ids := case when v_side = 0 then p_a_ids else p_b_ids end;
    continue when v_ids is null or array_length(v_ids, 1) is null;
    v_role := case when v_side = 0 then p_a_role else p_b_role end;
    v_enemy := case when v_side = 0 then p_b_player else p_a_player end;
    if v_enemy is null then
      select c.owner_player_id into v_enemy from public.commanders c
      where c.id = (case when v_side = 0 then p_b_ids else p_a_ids end)[1];
    end if;
    v_foe := coalesce(public.house_name(v_enemy), 'the enemy');
    v_won := p_winner = v_side;
    v_r := 1 + floor(random() * 3)::int;

    if p_kind = 'assault' and v_role = 'attacker' then
      if v_won and p_captured then
        v_kind := 'capture';
        v_text := (array[
          format('Led the assault on %s and took it from House %s.', v_place, v_foe),
          format('Broke House %s at the walls of %s and raised a new banner over it.', v_foe, v_place),
          format('Stormed %s and wrested it from House %s.', v_place, v_foe)])[v_r];
      elsif v_won then
        v_kind := 'win';
        v_text := (array[
          format('Beat House %s before the walls of %s.', v_foe, v_place),
          format('Drove House %s back from %s.', v_foe, v_place),
          format('Won the field at %s against House %s.', v_place, v_foe)])[v_r];
      else
        v_kind := 'loss';
        v_text := (array[
          format('Was thrown back from the walls of %s by House %s.', v_place, v_foe),
          format('Failed to take %s from House %s and lost the field.', v_place, v_foe),
          format('Marched on %s and was beaten by House %s.', v_place, v_foe)])[v_r];
      end if;
    elsif p_kind = 'assault' then
      if v_won then
        v_kind := 'win';
        v_text := (array[
          format('Held %s against House %s.', v_place, v_foe),
          format('Turned back House %s at the gates of %s.', v_foe, v_place),
          format('Stood on the walls of %s and broke House %s.', v_place, v_foe)])[v_r];
      else
        v_kind := 'loss';
        v_text := (array[
          format('Lost %s to House %s.', v_place, v_foe),
          format('Defended %s to the last and was overwhelmed by House %s.', v_place, v_foe),
          format('Watched %s fall to House %s.', v_place, v_foe)])[v_r];
      end if;
    elsif p_kind = 'sally' and v_role = 'sally' then
      if v_won then
        v_kind := 'win';
        v_text := (array[
          format('Rode out of %s and broke the siege laid by House %s.', v_place, v_foe),
          format('Led a sally from %s that scattered House %s.', v_place, v_foe),
          format('Burst through the gates of %s and lifted the siege.', v_place)])[v_r];
      else
        v_kind := 'loss';
        v_text := format('Sallied from %s against House %s and was driven back.', v_place, v_foe);
      end if;
    elsif p_kind = 'sally' then
      if v_won then
        v_kind := 'win';
        v_text := format('Beat back a sally from %s by House %s.', v_place, v_foe);
      else
        v_kind := 'loss';
        v_text := format('Saw the siege of %s broken by House %s.', v_place, v_foe);
      end if;
    else
      if v_won then
        v_kind := 'win';
        v_text := (array[
          format('Caught House %s on %s and won the clash.', v_foe, v_place),
          format('Met House %s on %s and carried the day.', v_foe, v_place),
          format('Ambushed House %s on %s and broke them.', v_foe, v_place)])[v_r];
      else
        v_kind := 'loss';
        v_text := (array[
          format('Was beaten by House %s in a clash on %s.', v_foe, v_place),
          format('Met House %s on %s and lost the field.', v_foe, v_place),
          format('Was caught by House %s on %s and cut down.', v_foe, v_place)])[v_r];
      end if;
    end if;

    foreach v_c in array v_ids loop
      perform public.log_commander(v_c, p_tick, v_kind, v_text);
    end loop;
  end loop;
end;
$f$;

create function public.commander_chronicle(p_commander_id int)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $f$
declare
  v_owner int;
begin
  select owner_player_id into v_owner from public.commanders where id = p_commander_id;
  if v_owner is null or not exists (select 1 from public.game_players gp where gp.id = v_owner and gp.user_id = auth.uid()) then
    return jsonb_build_object('entries', '[]'::jsonb, 'wins', 0, 'losses', 0, 'castles', 0);
  end if;
  return jsonb_build_object(
    'entries', coalesce((select jsonb_agg(jsonb_build_object('tick', h.tick, 'kind', h.kind, 'text', h.text) order by h.id desc)
                         from (select * from public.commander_history where commander_id = p_commander_id order by id desc limit 80) h), '[]'::jsonb),
    'wins', (select count(*) from public.commander_history where commander_id = p_commander_id and kind in ('win', 'capture')),
    'losses', (select count(*) from public.commander_history where commander_id = p_commander_id and kind = 'loss'),
    'castles', (select count(*) from public.commander_history where commander_id = p_commander_id and kind = 'capture'));
end;
$f$;

revoke execute on function public.house_name(int) from public, anon, authenticated;
revoke execute on function public.log_commander(int, int, text, text) from public, anon, authenticated;
revoke execute on function public.log_battle_history(int, int, text, text, text, int[], int, text, int[], int, int, boolean) from public, anon, authenticated;
revoke execute on function public.commander_chronicle(int) from public, anon;
grant execute on function public.commander_chronicle(int) to authenticated;

do $patch$
declare
  v_def text;
  v_new text;
  v_pairs text[];
  i int;
  v_fn text;
  v_sets text[][];
begin
  -- fn name | patch pairs are applied in order; any miss aborts the migration
  for v_fn, v_pairs in
    select * from (values
      ('create_commander', array[
        '  returning id into v_id;' || chr(10),
        '  returning id into v_id;' || chr(10)
          || '  perform public.log_commander(v_id, p_tick, ''enlisted'', case when p_role = ''king'' then format(''Rose to lead House %s as its king, at %s.'', public.house_name(p_player_id), coalesce((select name from public.game_territories where id = p_territory_id), ''the capital''))' || chr(10)
          || '    else format(''Took up arms for House %s at %s.'', public.house_name(p_player_id), coalesce((select name from public.game_territories where id = p_territory_id), ''the capital'')) end);' || chr(10)
      ]),
      ('record_battle_report', array[
        '  perform set_config(''ss.battle_report'', v_id || '':'' || p_tick, true);',
        '  perform public.log_battle_history(p_game_id, p_tick, p_kind, v_name, p_a_role, p_a_ids, p_a_player, p_b_role, p_b_ids, p_b_player, p_winner, p_captured);' || chr(10)
          || '  perform set_config(''ss.battle_report'', v_id || '':'' || p_tick, true);'
      ]),
      ('kill_commanders', array[
        '  update public.commanders' || chr(10) || '  set status = ''dead'', died_tick = p_tick,',
        '  insert into public.commander_history (game_id, commander_id, tick, kind, text)' || chr(10)
          || '  select c.game_id, c.id, p_tick, ''fell'', (array[''Fell in battle.'', ''Died on the field, and was mourned by the house.'', ''Met a soldier''''s end.''])[1 + (c.id % 3)]' || chr(10)
          || '  from public.commanders c' || chr(10)
          || '  where c.id = any (p_ids) and c.status <> ''dead''' || chr(10)
          || '    and not exists (select 1 from public.commander_history h where h.commander_id = c.id and h.kind = ''executed'' and h.tick = p_tick);' || chr(10) || chr(10)
          || '  update public.commanders' || chr(10) || '  set status = ''dead'', died_tick = p_tick,'
      ]),
      ('kill_or_capture', array[
        '      insert into public.game_moments (game_id, tick, type, payload, visibility, involved_player_ids)' || chr(10) || '      values (p_game_id, p_tick, ''commander_captured'',',
        '      perform public.log_commander(v_c.id, p_tick, ''captured'', format(''Was taken prisoner by House %s.'', coalesce(public.house_name(p_captor), ''the enemy'')));' || chr(10)
          || '      insert into public.game_moments (game_id, tick, type, payload, visibility, involved_player_ids)' || chr(10) || '      values (p_game_id, p_tick, ''commander_captured'','
      ]),
      ('release_captive_core', array[
        '  where id = v_c.id;' || chr(10) || chr(10) || '  perform public.notify_players(',
        '  where id = v_c.id;' || chr(10) || chr(10)
          || '  perform public.log_commander(v_c.id, p_tick, ''freed'', case when p_reason = ''ransomed'' then format(''Was ransomed back from House %s.'', coalesce(public.house_name(v_c.captured_by_player_id), ''the enemy''))' || chr(10)
          || '    else format(''Was freed from House %s.'', coalesce(public.house_name(v_c.captured_by_player_id), ''the enemy'')) end);' || chr(10) || chr(10)
          || '  perform public.notify_players('
      ]),
      ('execute_captive_core', array[
        '  perform public.kill_commanders(p_game_id, array[v_c.id], p_tick);',
        '  perform public.log_commander(v_c.id, p_tick, ''executed'', format(''Was executed by House %s.'', coalesce(public.house_name(p_captor), ''the enemy'')));' || chr(10)
          || '  perform public.kill_commanders(p_game_id, array[v_c.id], p_tick);'
      ]),
      ('crown_commander', array[
        '  update public.commanders set role = ''king'', coronation_tick = v_tick where id = v_c.id;',
        '  update public.commanders set role = ''king'', coronation_tick = v_tick where id = v_c.id;' || chr(10)
          || '  perform public.log_commander(v_c.id, v_game.current_tick, ''crowned'', format(''Was named king of House %s.'', public.house_name(v_player.id)));'
      ]),
      ('promote_veterans', array[
        '    select current_tick into v_tick from public.games where id = v_c.game_id;',
        '    select current_tick into v_tick from public.games where id = v_c.game_id;' || chr(10)
          || '    perform public.log_commander(v_c.id, v_tick, ''named'', format(''Won five fights and earned a name: %s.'', v_name));'
      ]),
      ('award_xp', array[
        'values (v_c.game_id, v_tick, ''commander_level_up'', jsonb_build_object(''commander_id'', p_commander_id, ''ability'', p_ability, ''level'', v_level, ''rank'', v_rank));',
        'values (v_c.game_id, v_tick, ''commander_level_up'', jsonb_build_object(''commander_id'', p_commander_id, ''ability'', p_ability, ''level'', v_level, ''rank'', v_rank));' || chr(10)
          || '    if v_level % 3 = 0 then' || chr(10)
          || '      perform public.log_commander(p_commander_id, v_tick, ''skill'', (array[format(''Mastered the craft of %s (level %s).'', initcap(p_ability), v_level), format(''Grew formidable in %s (level %s).'', initcap(p_ability), v_level), format(''Earned a fearsome name for %s (level %s).'', initcap(p_ability), v_level)])[1 + (p_commander_id % 3)]);' || chr(10)
          || '    end if;'
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

insert into public.commander_history (game_id, commander_id, tick, kind, text)
select c.game_id, c.id, c.created_tick, 'enlisted',
  case when c.role = 'king' then format('Rose to lead House %s as its king.', public.house_name(c.owner_player_id))
       else format('Took up arms for House %s.', public.house_name(c.owner_player_id)) end
from public.commanders c
where not exists (select 1 from public.commander_history h where h.commander_id = c.id);
