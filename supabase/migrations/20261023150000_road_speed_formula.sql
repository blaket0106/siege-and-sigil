do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.plan_march(integer,integer,integer)'::regprocedure) into v_def;
  v_new := replace(v_def, '  v_off int;
begin', '  v_off int;
  v_road_div float8;
begin');
  v_new := replace(v_new, '  for v_e in
    select e.from_territory_id as f', '  v_road_div := sqrt(3 + coalesce((select ra.level from public.realm_areas ra where ra.player_id = p_player_id and ra.area = ''stables''), 0));

  for v_e in
    select e.from_territory_id as f');
  v_new := replace(v_new, 'then v_e.w / 3.0 else v_e.w end', 'then v_e.w / v_road_div else v_e.w end');
  if v_new = v_def or v_new not like '%v_road_div float8%' or v_new not like '%/ v_road_div else%' or v_new not like '%v_road_div := sqrt%' then
    raise exception 'plan_march patch did not apply';
  end if;
  execute v_new;
end;
$patch$;
