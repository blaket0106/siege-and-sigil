drop policy "intel snapshots are readable by game members" on public.intel_snapshots;

create policy "intel snapshots are readable after the game or without fog"
  on public.intel_snapshots for select to authenticated
  using (
    public.is_game_member(game_id)
    and exists (
      select 1 from public.games g
      where g.id = intel_snapshots.game_id and (g.status = 'finished' or not g.fog_of_war)
    )
  );
