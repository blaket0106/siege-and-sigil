alter table public.games add column if not exists victory_decay_start int not null default 250 check (victory_decay_start >= 0);
alter table public.games alter column victory_decay set default 1;
grant select (victory_decay_start) on public.games to authenticated;
alter table public.game_players add column if not exists ai_focus_id int;
alter table public.game_players add column if not exists ai_focus_tick int;

create function public.ai_focus(p_game_id int, p_player_id int)
returns int
language plpgsql
security definer
set search_path = ''
as $f$
declare
  v_tick int;
  v_scale float8;
  v_cur int;
  v_since int;
  v_new int;
  v_my int;
begin
  select current_tick, world_scale into v_tick, v_scale from public.games where id = p_game_id;
  select ai_focus_id, ai_focus_tick into v_cur, v_since from public.game_players where id = p_player_id;
  if v_cur is not null and v_since is not null and v_tick - v_since < 72
     and (select eliminated_at_tick from public.game_players where id = v_cur) is null
     and not public.are_allied(p_player_id, v_cur) then
    return v_cur;
  end if;
  v_my := public.castle_count(p_player_id);
  select gp.id into v_new
  from public.game_players gp
  where gp.game_id = p_game_id and gp.id <> p_player_id and gp.eliminated_at_tick is null
    and not public.are_allied(p_player_id, gp.id)
    and public.castle_count(gp.id) >= 1
    and exists (
      select 1 from public.game_territories a
      join public.game_territories b on b.game_id = a.game_id and b.owner_player_id = gp.id and not b.is_junction
      where a.game_id = p_game_id and a.owner_player_id = p_player_id and not a.is_junction
        and (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 <= (6 * 150 * v_scale) ^ 2)
  order by (public.castle_count(gp.id) > 1.3 * v_my), public.castle_count(gp.id), gp.id
  limit 1;
  update public.game_players set ai_focus_id = v_new, ai_focus_tick = v_tick where id = p_player_id;
  return v_new;
end;
$f$;
revoke execute on function public.ai_focus(int, int) from public, anon, authenticated;

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
        '  v_hunt int;',
        '  v_hunt int;' || chr(10) || '  v_push boolean;' || chr(10) || '  v_focus int;' || chr(10) || '  v_lost int[];',
        '  v_prey := array_remove(v_prey || array[coalesce(v_hunt, 0)], 0);',
        '  v_prey := array_remove(v_prey || array[coalesce(v_hunt, 0)], 0);' || chr(10)
          || '  v_push := public.castle_count(p_player_id) >= (public.game_standing(p_game_id) ->> ''win_at'')::int - 10;' || chr(10)
          || '  v_focus := public.ai_focus(p_game_id, p_player_id);' || chr(10)
          || '  select coalesce(array_agg((m.payload ->> ''territory_id'')::int), ''{}'') into v_lost from public.game_moments m where m.game_id = p_game_id and m.type = ''castle_captured'' and (m.payload ->> ''from_player_id'')::int = p_player_id and m.tick > v_game.current_tick - 36;' || chr(10)
          || '  if v_push then v_margin := 1.0; end if;',
        '+ case when v_t.owner_player_id = v_hunt then 8 else 0 end',
        '+ case when v_t.owner_player_id = v_hunt then 8 else 0 end + case when v_t.owner_player_id = v_focus then 6 + case when public.castle_count(v_focus) <= 4 then 4 else 0 end else 0 end + case when v_t.id = any (v_lost) then 4 else 0 end',
        'random() + v_prio + v_strat',
        'random() + v_prio + v_strat + case when v_push then greatest(0, 8 - v_need / 12) else 0 end',
        'and ((v_style = ''aggressive'' and v_game.current_tick >= 20)',
        'and (v_push or (v_focus is not null and v_style <> ''defensive'' and v_game.current_tick >= 40) or (v_style = ''aggressive'' and v_game.current_tick >= 20)'
      ]),
      ('ai_spend', array[
        '  v_cheap int;',
        '  v_cheap int;' || chr(10) || '  v_late boolean;',
        '  select gold into v_gold from public.game_players where id = p_player_id;',
        '  select gold into v_gold from public.game_players where id = p_player_id;' || chr(10)
          || '  select coalesce((count(*) filter (where owner_player_id is null and not is_junction))::float8 <= 0.08 * (count(*) filter (where not is_junction)), false) into v_late from public.game_territories where game_id = p_game_id;',
        'v_reserve := least(v_reserve, 150);',
        'v_reserve := least(v_reserve, case when v_late then 60 else 150 end);',
        'case x.t when ''recruitment'' then 1.0 else 1.2 end',
        'case x.t when ''recruitment'' then 1.0 else (case when v_late then 3.0 else 1.2 end) end'
      ]),
      ('ai_diplomacy', array[
        'v_aggr := case p_difficulty when 2 then 0.004 when 3 then 0.01 when 4 then 0.02 else 0.04 end;',
        'v_aggr := case p_difficulty when 2 then 0.012 when 3 then 0.03 when 4 then 0.06 else 0.12 end;'
      ]),
      ('game_standing', array[
        'g.victory_decay * (g.current_tick / g.production_cycle_ticks)',
        'g.victory_decay * (greatest(0, g.current_tick - g.victory_decay_start) / g.production_cycle_ticks)'
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
