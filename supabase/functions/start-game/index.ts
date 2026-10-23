import { createClient } from 'npm:@supabase/supabase-js@2';
import { generateWorld, assignSeats } from './generator.js';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function respond(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return respond({ error: 'method not allowed' }, 405);

  let gameId: number;
  try {
    const body = await req.json();
    gameId = Number(body.game_id);
  } catch {
    return respond({ error: 'invalid json body' }, 400);
  }
  if (!Number.isInteger(gameId)) return respond({ error: 'game_id must be an integer' }, 400);

  const url = Deno.env.get('SUPABASE_URL')!;
  const authHeader = req.headers.get('Authorization');
  const userClient = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: authHeader ? { Authorization: authHeader } : {} },
  });
  const { data: userData } = await userClient.auth.getUser();
  const user = userData?.user ?? null;

  const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

  const { data: game, error: gameError } = await admin.from('games').select('*').eq('id', gameId).maybeSingle();
  if (gameError) return respond({ error: gameError.message }, 500);
  if (!game) return respond({ error: 'game not found' }, 404);
  if (game.status !== 'lobby') return respond({ error: 'game is not in the lobby' }, 409);

  const { data: players, error: playersError } = await admin
    .from('game_players')
    .select('id')
    .eq('game_id', gameId)
    .order('id');
  if (playersError) return respond({ error: playersError.message }, 500);

  const humans: number[] = players.map((p: { id: number }) => p.id);
  const autoStart = game.auto_start && humans.length >= game.max_players;
  if (!user && !autoStart) return respond({ error: 'not signed in' }, 401);
  if (user && game.created_by !== user.id && !autoStart) return respond({ error: 'only the game creator can start the game' }, 403);

  const total = game.fill_with_ai ? game.max_players : humans.length;
  if (total < 2) return respond({ error: 'a game needs at least 2 players: enable AI fill or wait for more players' }, 422);

  const aiSlots = Array.from({ length: total - humans.length }, (_, i) => -(i + 1));
  const seed = Number(game.world_seed);

  let layout;
  try {
    layout = generateWorld({
      seed,
      players: total,
      mapSize: game.map_size,
      startingTerritories: game.starting_territories,
      style: game.map_style,
      startingGarrison: game.starting_garrison,
      scale: Number(game.world_scale) || 1,
      freeTravel: !!game.free_travel,
      shape: game.map_shape || 'continent',
      richness: game.resource_richness || 'standard',
      randomRoads: game.random_roads || 'none',
      starScatter: game.star_scatter || 'random',
      mirrored: !!game.mirrored,
    });
  } catch (error) {
    return respond({ error: (error as Error).message }, 422);
  }

  const payload = {
    ...layout,
    seat_player_ids: assignSeats(seed, [...humans, ...aiSlots]),
  };

  const { data: summary, error: startError } = await admin.rpc('start_game', {
    p_game_id: gameId,
    p_layout: payload,
  });
  if (startError) return respond({ error: startError.message }, 500);

  return respond(summary);
});
