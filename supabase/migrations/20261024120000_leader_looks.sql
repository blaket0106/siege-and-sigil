alter table public.faction_leaders
  add column age int,
  add column school text check (school in ('battleschool', 'university', 'rangers')),
  add column look jsonb;

update public.faction_leaders fl set
  age = case when fl.ord = 1 then 50 + abs(hashtext(fl.name || 'a')) % 13 else 24 + abs(hashtext(fl.name || 'a')) % 30 end,
  school = (array['battleschool', 'university', 'rangers'])[1 + abs(hashtext(fl.name || 'sc')) % 3],
  look = jsonb_build_object(
    'skin', abs(hashtext(fl.name || 's')) % 6,
    'face', abs(hashtext(fl.name || 'f')) % 4,
    'hair', case when fl.sex = 'f'
      then (array[1, 2, 3, 4, 4, 5, 5, 6, 8])[1 + abs(hashtext(fl.name || 'h')) % 9]
      else (array[0, 1, 1, 2, 2, 3, 4, 5, 6, 7, 8])[1 + abs(hashtext(fl.name || 'h')) % 11] end,
    'hairc', abs(hashtext(fl.name || 'c')) % 7,
    'beard', case when fl.sex = 'f' then 0 else abs(hashtext(fl.name || 'b')) % 6 end,
    'eyes', abs(hashtext(fl.name || 'e')) % 5,
    'brow', abs(hashtext(fl.name || 'w')) % 4,
    'nose', abs(hashtext(fl.name || 'n')) % 3,
    'mouth', abs(hashtext(fl.name || 'm')) % 3,
    'scar', case when abs(hashtext(fl.name || 'x')) % 100 < 30 then 1 + abs(hashtext(fl.name || 'y')) % 3 else 0 end,
    'seed', 1000 + abs(hashtext(fl.name)) % 90000);

alter table public.faction_leaders alter column age set not null, alter column school set not null, alter column look set not null;

do $patch$
declare
  v_def text;
  v_new text;
  v_old text := '''epithet'', v_lead.title, ''bio'', v_lead.bio)';
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'finalize_start' and p.pronamespace = 'public'::regnamespace;
  if position(v_old in v_def) = 0 then
    raise exception 'finalize_start patch did not match';
  end if;
  v_new := replace(v_def, v_old, '''epithet'', v_lead.title, ''bio'', v_lead.bio, ''age'', v_lead.age, ''look'', v_lead.look)');
  execute v_new;
end;
$patch$;
