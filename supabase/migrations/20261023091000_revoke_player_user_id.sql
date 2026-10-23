revoke select on public.game_players from anon, authenticated;
grant select (id, game_id, faction_slug, display_name, is_ai, eliminated_at_tick, created_at) on public.game_players to authenticated;
