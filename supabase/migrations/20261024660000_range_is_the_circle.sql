update public.territory_edges set move_cost_mult = 1 where move_cost_mult <> 1;

create or replace function public.flatten_edge_cost()
returns trigger
language plpgsql
as $f$
begin
  new.move_cost_mult := 1;
  return new;
end;
$f$;

drop trigger if exists territory_edges_flat_cost on public.territory_edges;
create trigger territory_edges_flat_cost
before insert or update of move_cost_mult on public.territory_edges
for each row execute function public.flatten_edge_cost();

do $patch$
declare
  v_fn text;
  v_def text;
  v_new text;
begin
  foreach v_fn in array array['plan_march', 'plan_march_from'] loop
    select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = v_fn and p.pronamespace = 'public'::regnamespace;
    v_new := replace(v_def, 'v_raw <= v_range', '(select sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) from public.game_territories a, public.game_territories b where a.id = v_path_ids[1] and b.id = v_path_ids[array_length(v_path_ids, 1)]) <= v_range');
    if v_new = v_def then
      raise exception '% patch did not match', v_fn;
    end if;
    execute v_new;
  end loop;
end;
$patch$;
