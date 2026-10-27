# Siege & Sigil — Mechanics Reference

Distilled from the Westeros codebase (commit 483eb15). Theme-agnostic. This is the authoritative spec for the new schema and all game logic. Do not re-read the Westeros source unless something is genuinely ambiguous here.

---

## 1. Database Schema

### 1a. Static / Reference Tables (global, not per-game)

**`factions`** ← replaces `houses`
| Column | Type | Notes |
|---|---|---|
| `slug` | text PK | |
| `name` | text | Display name |
| `color` | text | Primary color (hex) — castle icon fill, inner glow |
| `color2` | text | Secondary color — outer aura glow. Makes factions visually unique even when two primaries are similar. |
| `seat_territory_slug` | text | The faction's home seat territory (used for "primary castle" logic) |

**`territories`** ← replaces `castles`
| Column | Type | Notes |
|---|---|---|
| `slug` | text PK | |
| `name` | text | |
| `tier` | int | 1, 2, or 3 |
| `region` | text | Geographic region label |
| `natural_resources` | int | Base strategic weight. Higher → cheaper upgrades there. |
| `map_x` | float | Normalized [0,1] x position on generated map |
| `map_y` | float | Normalized [0,1] y position on generated map |

**`profiles`**
| Column | Type | Notes |
|---|---|---|
| `user_id` | uuid FK | Supabase auth user |
| `display_name` | text | |
| `honor` | int | Cross-game reputation score (accumulated from wins, betrayals) |
| `infamy` | int | Cross-game infamy score |
| `selected_title` | text | Player-selected display title |
| `total_games` | int | |
| `total_wins` | int | |

**`achievements`**
| Column | Type | Notes |
|---|---|---|
| `slug` | text PK | |
| `name` | text | |
| `description` | text | |
| `sort_order` | int | Display order |

---

### 1b. Per-Game Tables

**`games`**
| Column | Type | Notes |
|---|---|---|
| `id` | int PK | |
| `name` | text | |
| `status` | text | `'lobby'` / `'active'` / `'finished'` |
| `created_by` | uuid | |
| `current_tick` | int | |
| `last_tick_processed_at` | timestamptz | |
| `tick_speed` | text | `'slow'` / `'normal'` / `'fast'` / `'quad'` / `'turn_based'` |
| `production_cycle_ticks` | int | Default 12 |
| `commander_speed_mult` | float | Default 1.0 |
| `infra_cost_mult` | float | Default 1.0 |
| `council_cost_mult` | float | Default 1.0 |
| `victory_pct` | float | Win threshold (default 0.5 = 50% of territories) |
| `fog_of_war` | bool | |
| `starting_gold` | int | |
| `starting_garrison` | int | |
| `starting_treasury_level` | int | |
| `starting_industry_level` | int | |
| `starting_prestige_level` | int | |
| `fill_with_ai` | bool | |
| `ai_difficulty` | int | 1–5 |
| `winner_player_id` | int | |
| `turn_timeout_minutes` | int | Turn-based only |
| `ticks_per_turn` | int | Turn-based only |
| `current_turn_ends_at` | timestamptz | Turn-based only |
| `max_players` | int | |

**`game_players`**
| Column | Type | Notes |
|---|---|---|
| `id` | int PK | |
| `game_id` | int FK | |
| `user_id` | uuid | null for AI |
| `faction_slug` | text | |
| `display_name` | text | |
| `gold` | int | Current gold |
| `is_ai` | bool | |
| `eliminated_at_tick` | int | null = still in game |
| `turn_submitted` | bool | Turn-based only |

**`game_territories`** ← replaces `game_castles`
| Column | Type | Notes |
|---|---|---|
| `id` | int PK | |
| `game_id` | int FK | |
| `territory_slug` | text FK | |
| `owner_player_id` | int FK | null = unowned |
| `troops` | int | Garrison troops |
| `treasury_level` | int | Treasury level |
| `industry_level` | int | Recruitment level |
| `prestige_level` | int | Prestige level |
| `has_road` | bool | Kings Road equivalent |
| `resources` | int | Computed: `(laws_level × 5) + natural_resources` |
| `troop_accum` | float | Fractional troop accumulator (carries between ticks) |

**`commanders`**
| Column | Type | Notes |
|---|---|---|
| `id` | int PK | |
| `game_id` | int FK | |
| `owner_player_id` | int FK | |
| `name` | text | |
| `level` | int | 0–10. Each level = +10% attack damage. |
| `troops` | int | Troops accompanying this commander |
| `status` | text | `'idle'` / `'moving'` / `'sieging'` / `'dead'` |
| `current_territory_slug` | text | Where the commander is stationed |
| `is_named` | bool | Named (faction-specific) vs. unnamed sworn sword |

**`commander_movements`**
| Column | Type | Notes |
|---|---|---|
| `id` | int PK | |
| `game_id` | int FK | |
| `commander_id` | int FK | |
| `from_territory_slug` | text | |
| `to_territory_slug` | text | |
| `departed_tick` | int | |
| `arrival_tick` | int | |
| `march_type` | text | `'assault'` / `'siege'` |

**`commander_routes`**
| Column | Type | Notes |
|---|---|---|
| `id` | int PK | |
| `game_id` | int FK | |
| `commander_id` | int FK | |
| `status` | text | `'active'` / `'completed'` |
| stops | jsonb | Ordered array of waypoints with territory_slug and march_type |

**`diplomacy`**
One row per ordered pair. `player_a_id < player_b_id` (always sorted to avoid duplicates).
| Column | Type | Notes |
|---|---|---|
| `game_id` | int FK | |
| `player_a_id` | int FK | |
| `player_b_id` | int FK | |
| `status` | text | `'neutral'` / `'proposed'` / `'allied'` / `'grace_period'` / `'war'` |
| `proposed_by_player_id` | int | Who sent the proposal |

**`player_inbox`**
| Column | Type | Notes |
|---|---|---|
| `id` | int PK | |
| `game_id` | int FK | |
| `player_id` | int FK | |
| `type` | text | e.g. `'system'`, `'combat'`, `'diplomacy'`, `'raven'` |
| `title` | text | |
| `body` | jsonb | Structured payload |
| `tick` | int | |
| `is_read` | bool | |

**`game_events`**
| Column | Type | Notes |
|---|---|---|
| `game_id` | int FK | |
| `tick` | int | |
| `type` | text | Event type |
| `payload` | jsonb | |

**`game_chat`**
| Column | Type | Notes |
|---|---|---|
| `game_id` | int FK | |
| `player_id` | int FK | |
| `message` | text | |
| `created_at` | timestamptz | |

**`message_threads`** + **`thread_participants`** + **`thread_messages`**
Private player-to-player threads. Each thread can include 2+ players.

| Table | Key Columns |
|---|---|
| `message_threads` | `id`, `game_id` |
| `thread_participants` | `thread_id`, `player_id` |
| `thread_messages` | `thread_id`, `player_id`, `body`, `created_at` |

**`whispers`**
AI-generated intelligence reports, delivered to a player's inbox.
| Column | Type | Notes |
|---|---|---|
| `id` | int PK | |
| `game_id` | int FK | |
| `player_id` | int FK | Recipient |
| `text` | text | AI-generated content, filled async after row insert |
| `is_read` | bool | |
| `tick` | int | |

**`council_seats`**
| Column | Type | Notes |
|---|---|---|
| `game_id` | int FK | |
| `player_id` | int FK | |
| `seat` | text | One of the 7 council seat slugs (see section 6) |
| `level` | int | All seats start at level 1. No cap. |
| `prestige_accumulated` | int | Toward next level |
| `is_focus` | bool | Current focus seat (only one per player) |

**`ledger`**
Gold transaction log.
| Column | Type | Notes |
|---|---|---|
| `game_id` | int FK | |
| `player_id` | int FK | |
| `tick` | int | |
| `type` | text | e.g. `'production'`, `'send_gold'`, `'recruit'`, `'upgrade'`, `'capture'` |
| `amount` | int | Positive = gained, negative = spent |

**`intel_snapshots`**
Periodic snapshots of visible game state (fog of war intelligence).
| Column | Type | Notes |
|---|---|---|
| `game_id` | int FK | |
| `tick` | int | |
| `payload` | jsonb | Full visible state at this tick |

**`game_moments`**
Notable events surfaced in news feed.
| Column | Type | Notes |
|---|---|---|
| `game_id` | int FK | |
| `tick` | int | |
| `type` | text | `'castle_captured'`, `'alliance_broken'`, `'war_declared'`, `'player_eliminated'`, etc. |
| `payload` | jsonb | |

---

## 2. Tick Speed

| Setting | Real time per tick |
|---|---|
| `slow` | 2 hours |
| `normal` | 1 hour |
| `fast` | 30 minutes |
| `quad` | 15 minutes |
| `turn_based` | Advances when all players submit (or deadline expires) |

**Turn-based flow:**
1. Each player takes actions (marches, upgrades, diplomacy)
2. Player calls `submit_turn(p_game_id)` to signal ready
3. When all human players submit (or `turn_timeout_minutes` elapses), `process_ticks` fires for `ticks_per_turn` ticks
4. Realtime subscription on `game_players.turn_submitted` re-renders turn status bar for all

---

## 3. Production System

Runs every `production_cycle_ticks` ticks (configurable, default 12).

### 3a. Gold
```
gold_added_per_cycle = sum(territory.treasury_level) × (10 + coinCouncilLevel × 2)
```

Gold is paid as a lump sum at the end of each cycle.

### 3b. Troops
```
troops_per_cycle_per_territory = territory.industry_level × (lordCommanderLevel + 4)

per_tick_accrual = troops_per_cycle / production_cycle_ticks
```

Troops accrue fractionally each tick. The integer part is applied immediately; the fractional part carries over in `troop_accum`. Over a full cycle, each territory produces exactly `industry_level × (lord_commander_level + 4)` troops. Production fires at the **start** of each tick, before combat.

### 3c. Prestige
```
prestige_per_tick = sum(territory.prestige_level)  (total across all owned territories)
```

Prestige flows entirely to the player's current focus council seat each tick. Grand Maester also invests a separate bonus (see section 6).

---

## 4. Infrastructure

### 4a. Three Tracks per Territory
| Track | Stat | Effect |
|---|---|---|
| Treasury | `treasury_level` | Gold income each cycle |
| Recruitment | `industry_level` | Troop production each cycle |
| Prestige | `prestige_level` | Prestige per tick toward council |

### 4b. Upgrade Cost Formula
```
cost = floor(base × (currentLevel + 1) / resources × infra_cost_mult)
```

| Track | Base Cost |
|---|---|
| Treasury | 500 |
| Recruitment | 1000 |
| Prestige | 4000 |
| Road | `floor(6 x resources x infra_cost_mult)` (x3 if costly) |

`resources = (laws_council_level × 5) + territory.natural_resources`

Higher influence = cheaper upgrades at that territory.

### 4c. Bulk Upgrade
RPC: `bulk_upgrade_infrastructure(p_game_id, p_infra_type, p_budget)` → `{upgraded, spent}`

Automatically upgrades the cheapest available territories of the chosen type until budget is exhausted. Uses `resources` to find cheapest options first.

---

## 5. Movement & March

### 5a. Base March Speed
```
base_speed = 17.5 × commander_speed_mult   (leagues/tick, using normalized map coordinate space)
```

### 5b. Road Bonus
When **both** origin and destination have a road built:
```
road_speed = base_speed × sqrt(Stables level + 3)   (about 1.73x at Stables 0, 2x at 1, 3x at 6)
```

### 5c. Travel Time
```
pixel_dist = sqrt((dx × MAP_NATIVE_W)² + (dy × MAP_NATIVE_H)²)
  where dx = toCastle.map_x - fromCastle.map_x  (both in [0,1])
  MAP_NATIVE_W = 672, MAP_NATIVE_H = 1560  (Westeros; replace with new map dimensions)

travel_ticks = max(1, ceil(pixel_dist / speed))
```

In Siege & Sigil, once the map system is designed, replace with the appropriate distance metric (e.g., euclidean on a unit square scaled to a fixed max-distance).

### 5d. March Range (Master of Horses)
```
max_march_range = 90 + (horses_level × 60)  leagues
```
At level 1: 150 leagues. Matches fog of war scan radius at the same level — intentional design.

A gold ring on the map shows valid march destinations from the selected commander.

### 5e. March Types
- **Assault** — commander fights on arrival
- **Siege** — commander begins besieging on arrival (no immediate combat)

### 5f. Troop Transfer
Before marching, a commander can take troops from or deposit troops into the territory garrison.

RPC: `transfer_troops(p_game_id, p_commander_id, p_amount)`
- Positive `p_amount` = troops move from garrison → commander
- Negative `p_amount` = troops move from commander → garrison

Transfer must be applied before the march button unlocks (UI dirty check enforced).

### 5g. Multi-Stop Routes
Commander can be dispatched on a multi-stop route (`commander_routes`). Each waypoint specifies a territory and march type. Routes proceed automatically tick-by-tick; player can recall or abort mid-route.

RPCs: `send_on_route`, `recall_route`, `abort_route`

### 5h. Intercept
Open-field intercept: when a moving commander passes within `INTERCEPT_RADIUS = 20.2` leagues of an enemy moving commander, combat can occur mid-march. (This is the "intercept" ring visible on the map.)

---

## 6. Combat

> Superseded in part by 20i (battle resolution, Valor, commander leveling). Percent-based commander damage is replaced by flat integer Armory bonuses.

### 6a. Core Formula
Fully deterministic — no dice. Troops are health pools; damage is fixed per round.

```
atkDmg = max(1, round(atkHandLevel × (1 + atkCmdLevel × 0.10)))
defDmg = max(1, round(defHandEff   × (1 + defCmdLevel × 0.10)))

Castle assault:  defHandEff = defHandLevel + 1   (+20% castle bonus, permanent)
Open field:      defHandEff = defHandLevel

roundsToKillAtk = ceil(atkTroops / defDmg)
roundsToKillDef = ceil(defTroops / atkDmg)
```

### 6b. Castle Assault (defender fires first)
```
if roundsToKillAtk <= roundsToKillDef:
  DEFENDER WINS
  survivors = max(1, defTroops − (roundsToKillAtk − 1) × atkDmg)
else:
  ATTACKER WINS
  survivors = max(1, atkTroops − roundsToKillDef × defDmg)
```

### 6c. Open Field (initiative = higher Whisperers level, ties favor defender)
```
if roundsToKillDef < roundsToKillAtk:
  ATTACKER WINS
  surviveLo = max(1, atkTroops − roundsToKillDef × defDmg)        (defender fires first)
  surviveHi = max(1, atkTroops − (roundsToKillDef − 1) × defDmg)  (attacker fires first)
  — actual survivors depend on who has initiative

elif roundsToKillAtk < roundsToKillDef:
  DEFENDER WINS
  surviveLo = max(1, defTroops − roundsToKillAtk × atkDmg)
  surviveHi = max(1, defTroops − (roundsToKillAtk − 1) × atkDmg)

else:  (tie)
  1 survivor either way, initiative determines which side
```

### 6d. Outcomes
- Attacker wins → captures territory with surviving troops
- Defender wins → attacking commander and ALL their troops destroyed (no survivors on attacking side)

### 6e. Commander Leveling
- Commanders gain levels through combat wins
- Each level: **+10% attack damage multiplier** (stacks with Hand council)
- No cap documented in code (max value 10 used in UI inputs, but SQL may differ)
- Named commanders (faction-specific roster) vs. unnamed "sworn swords" (generic backup)

---

## 7. Siege

A commander marching as `siege` type:

1. Arrives at enemy territory and enters `status = 'sieging'` — no immediate combat
2. **Besieged garrison** loses **3% of troops per tick** (starvation/attrition)
3. Each **production cycle**, one random infrastructure track (Treasury, Recruitment, or Prestige) loses **−1 level** (permanent until manually rebuilt)
4. **Sally Out**: defender sends garrison into open field — no castle bonus for either side; a successful sally destroys siege commander and lifts siege
5. **Relief march**: friendly commander marches to besieged territory → open field vs. siege commander; successful relief lifts siege and garrisons

RPCs: `break_siege_and_assault(p_game_id, p_territory_slug)`, `sally_out(p_game_id, p_territory_slug)`

---

## 8. Diplomacy

### 8a. State Machine
One row per ordered player pair (`player_a_id < player_b_id`):

```
neutral ──propose──► proposed ──accept──► allied
                        └──decline──► neutral

allied ──break──► grace_period (24 ticks) ──(time)──► war
neutral ──(attack ally)──► war  (automatic, announced to all)
```

**Grace period:** When an alliance is broken, a 24-tick grace period begins. Both sides can see each other's movement during this window and know a betrayal is coming. After 24 ticks: status → `'war'`. War declarations are visible to all players in the news feed.

**Default relationship:** Any two players without an alliance are `neutral`. Attacks can happen freely at neutral; war state is a formal declaration visible to all (not mechanically different from neutral in combat terms — the distinction is visibility and reputation).

### 8b. Alliance Benefits
- Shared fog-of-war vision: each ally's territory scan range extends your own
- Ally movements shown as friendly (gold lines) on your map
- Vision drops immediately when alliance is broken

### 8c. RPCs
```
propose_alliance(p_game_id, p_target_player_id)
accept_alliance(p_game_id, p_target_player_id)
decline_alliance(p_game_id, p_target_player_id)
break_alliance(p_game_id, p_target_player_id)
concede_defeat(p_game_id)
```

### 8d. Trade / Gold Transfer
```
send_gold(p_game_id, p_target_player_id, p_amount)
send_gold_to_player(p_game_id, p_target_player_id, p_amount)
```

Trade is voluntary, honor-based, no enforcement mechanism. Recorded in `ledger` for both sender and receiver.

---

## 9. Fog of War

Enabled per game (`fog_of_war = true`). When disabled, all territories are always visible.

### 9a. Territory Scan Radius
```
castle_scan_px = FOG_SCAN_BASE + (whisperers_level × FOG_SCAN_PER_LV)
FOG_SCAN_BASE   = 90
FOG_SCAN_PER_LV = 60
```
At level 0: 90px. At level 1: 150px. At level 2: 210px. Etc. (All in native map coordinate space.)

### 9b. Commander Scan Radius (idle only)
```
cmd_scan_px = FOG_CMD_BASE + (commander.level × FOG_CMD_PER_LV)
FOG_CMD_BASE   = 45   (half of castle base)
FOG_CMD_PER_LV = 15
```

### 9c. Distance Calculation
```
dx = (target.map_x - src.map_x) × MAP_NATIVE_W   (MAP_NATIVE_W = 672)
dy = (target.map_y - src.map_y) × MAP_NATIVE_H   (MAP_NATIVE_H = 1560)
dist = hypot(dx, dy)
visible if dist <= scan_px
```

For Siege & Sigil, replace with appropriate scale factors once the map dimensions are defined.

### 9d. Vision Rules
- Own territories: always visible
- Allied territories: visible (alliance extends vision immediately; drops immediately on break)
- Enemy territories inside scan range: visible with current state
- Enemy territories outside scan range: show **last-known position** (stored in fog memory client-side; only owner/troop count hidden, position shown as ghost)
- Moving commanders: friendly = gold dotted line on map; enemy = visible only if inside scan range

### 9e. Troop Count Hiding
In fog-of-war games, enemy troop counts at territories outside scan range are hidden from the UI even if the territory is "visible" (last-known position).

---

## 10. Council System

> Superseded by 20j (realm areas). Formulas carry over under the new names.

### 10a. The Seven Seats

| Seat (generic) | Westeros name | Function |
|---|---|---|
| Commander General | Hand of the King | Combat attack damage (`atkDmg` formula) |
| Treasurer | Master of Coin | Gold income multiplier (+2 gold per treasury level per council level) |
| Marshal | Lord Commander | Troop production (`troops = industry × (level + 4)`) |
| Steward | Master of Laws | Upgrade cost reduction via `resources = laws×5 + natural_resources` |
| Spymaster | Master of Whisperers | Fog of war scan radius; open-field combat initiative |
| Scholar | Grand Maester | Bonus prestige investment each cycle (random seat) |
| Cavalry Master | Master of Horses | March range (`90 + horses×60` leagues) |

### 10b. Leveling
- All seats start at **level 1**
- No level cap (coded max 10 in some UI elements, SQL may enforce differently)
- Prestige flows from territories to the player's **current focus seat** each tick
- **Council advance cost:**
  ```
  cost = 144 × currentLevel × council_cost_mult
  ```
  Level 1→2: 144 prestige. Level 2→3: 288. Level 3→4: 432. Etc.
- Progress resets to 0 on each level-up

### 10c. Focus Management
One seat is the current focus. All territory prestige goes there.
- Player can change focus at any time
- On game start, focus defaults to Commander General (Hand)
- RPC: `set_council_focus(p_game_id, p_seat, p_next_seat)`

### 10d. Grand Maester Bonus
```
prestige_invested_per_cycle = 72 × grand_maester_level
```
Invested into a **random non-focus** seat each production cycle. Accelerates council unpredictably.

### 10e. Individual Seat Formulas
**Treasurer (Coin):**
```
gold_per_cycle = sum(territory.treasury_level) × (10 + coin_level × 2)
```

**Marshal (Lord Commander):**
```
troops_per_cycle_per_territory = industry_level × (marshal_level + 4)
```

**Steward (Laws):**
```
resources = (laws_level × 5) + territory.natural_resources
```
This reduces all upgrade costs at every territory.

**Spymaster (Whisperers):**
- Scan radius: `90 + whisperers_level × 60` px
- Open-field combat initiative: higher level fires first; ties favor defender

**Cavalry Master (Horses):**
- March range: `90 + horses_level × 60` leagues

---

## 11. Commander Recruitment

> Superseded by 20i (schools, abilities, flat-price hiring).

### 11a. Process
1. Player opens recruit modal at a territory they own
2. RPC `get_available_commanders(p_game_id)` returns a pool of faction-specific named commanders not yet recruited in this game
3. If pool is empty, player can generate a random unnamed sworn sword
4. RPC `recruit_commander(p_game_id, p_territory_slug, p_name)` → `{name, is_named, cost}`

### 11b. Cost
Base cost: **100 gold**. (Exact formula for modifiers TBD from SQL — but 100g shown in UI default.)

New commanders start at **level 1**, idle, with **0 troops** (must transfer from garrison before marching).

### 11c. Named vs. Unnamed
- **Named commanders** are drawn from a faction-specific pool (in Westeros: house-specific character rosters). In Siege & Sigil, these are procedurally generated per game.
- **Unnamed sworn swords** are fallback generic commanders, available when the named pool is exhausted.

---

## 12. Win Condition

### 12a. Territorial Victory (default)
```
winner = first player to own ≥ victory_pct of all territories (default 50%)
win_at = ceil(total_territories × victory_pct)
```
Checked on each tick by `check_win_condition(p_game_id)`. Returns `{winner, winner_id, castles, total, win_at}`.

### 12b. Elimination
A player with zero territories is eliminated (`eliminated_at_tick` set). Eliminated players cannot take actions. Their territories become unowned and claimable by anyone.

### 12c. Concede
Player can voluntarily concede: `concede_defeat(p_game_id)`. Equivalent to elimination.

---

## 13. Turn-Based Mode

Turn-based mode fires `ticks_per_turn` ticks each round, triggered when all human players submit or deadline expires.

**`game_players.turn_submitted`** tracks who is ready. Realtime subscription on this column re-renders a turn status bar showing all players' submission state and time remaining.

---

## 14. Key RPC Signatures

```sql
-- Core tick engine
process_ticks(p_game_id int)
  RETURNS json: {pending_ticks, gold_added, troops_added, combats, combat_events[], cycles_fired}

-- Game lifecycle
start_game(p_game_id int)
  -- Fills AI player slots, assigns territories, sets status='active', starts tick clock
apply_game_settings(p_game_id int)
  -- Applies infra/council cost mults, starting levels to game_territories
check_win_condition(p_game_id int)
  RETURNS json: {winner, winner_id, castles, total, win_at}
concede_defeat(p_game_id int)
cancel_game(p_game_id int)
delete_game(p_game_id int)

-- Diplomacy
propose_alliance(p_game_id int, p_target_player_id int)
accept_alliance(p_game_id int, p_target_player_id int)
decline_alliance(p_game_id int, p_target_player_id int)
break_alliance(p_game_id int, p_target_player_id int)

-- Economy
send_gold(p_game_id int, p_target_player_id int, p_amount int)
upgrade_infrastructure(p_game_id int, p_territory_slug text, p_type text)
build_road(p_game_id int, p_territory_slug text)
demolish_road(p_game_id int, p_territory_slug text)
bulk_upgrade_infrastructure(p_game_id int, p_infra_type text, p_budget int)
  RETURNS json: {upgraded, spent}

-- Military
recruit_commander(p_game_id int, p_territory_slug text, p_name text)
  RETURNS json: {name, is_named, cost}
get_available_commanders(p_game_id int)
  RETURNS json: {pool[]}
transfer_troops(p_game_id int, p_commander_id int, p_amount int)
  -- positive = castle→commander, negative = commander→castle
send_on_route(p_game_id int, p_commander_id int, p_stops jsonb, p_march_type text)
  RETURNS json: {travel_ticks, route_id}
recall_route(p_game_id int, p_commander_id int)
abort_route(p_game_id int, p_commander_id int)
break_siege_and_assault(p_game_id int, p_territory_slug text)
sally_out(p_game_id int, p_territory_slug text)

-- Council
set_council_focus(p_game_id int, p_seat text, p_next_seat text)

-- Communication
send_chat_message(p_game_id int, p_message text)
send_thread_message(p_thread_id int, p_body text)
create_thread(p_game_id int, p_participant_ids int[], p_first_message text)
mark_whisper_read(p_whisper_id int, p_is_read bool)
delete_whisper(p_whisper_id int)

-- Intel
record_intel_snapshot(p_game_id int)
  -- Called client-side after each production cycle fires (cycles_fired > 0)

-- Profiles
submit_turn(p_game_id int)
  RETURNS json: {all_submitted}
```

---

## 15. Realtime Subscriptions

Single Supabase channel per active game: `game_{id}`.

| Table | Event | Handler |
|---|---|---|
| `player_inbox` | INSERT | Push to inbox array, update badge; if `type='system'` and title is win/lose, show game over screen |
| `game_territories` | `*` (all) | Debounced full state refresh (800ms) — NOTE: requires `REPLICA IDENTITY FULL` for UPDATE payloads |
| `games` | UPDATE | Sync active game row; refresh state on tick change; win check if status=finished |
| `diplomacy` | `*` | Reload diplomacy rows for current player |
| `game_chat` | INSERT | Append to chat array; re-render if chat pane open |
| `thread_messages` | INSERT (no filter) | Append to matching thread; badge update for unread |
| `whispers` | INSERT | Add to whispers, badge update; trigger AI whisper generation if `text=null` |
| `whispers` | UPDATE | Patch existing whisper row (AI text filled async) |
| `game_players` | UPDATE | Sync player row; re-render turn bar and turn status modal |

---

## 16. Frontend State Object

```js
state = {
  // Auth
  user,                // Supabase auth user

  // Static reference data (loaded once)
  factions,            // All faction definitions
  territories,         // All territory definitions
  achievements,

  // Active game
  activeGame,          // games row
  currentPlayer,       // game_players row for self
  gamePlayers,         // All game_players rows
  gameTerritories,     // All game_territories rows
  commanders,          // All commanders rows
  movements,           // commander_movements (in-transit)
  routes,              // commander_routes (active)

  // Player-specific
  inbox,               // player_inbox rows
  diplomacy,           // diplomacy rows involving current player
  councilSeats,        // council_seats rows for current player
  whispers,            // whispers rows for current player

  // Social
  chat,                // game_chat rows
  threads,             // message_threads with participants + messages
  unreadThreadIds,     // Set of thread ids with unread messages

  // Intel
  intelSnapshots,      // intel_snapshots rows

  // UI state
  mode,                // 'home' | 'game'
  zoom,                // map zoom level
  panX, panY,          // map pan offset

  // New for Siege & Sigil
  worldSeed,           // procedural generation seed for this game's world
  worldLayout,         // generated territory positions + adjacency graph
}
```

---

## 17. Honor & Infamy System

Cross-game reputation tracked in `profiles`. Displayed in player detail panels. Updated at game end.
- **Honor** — accrued from wins, fair play, kept alliances
- **Infamy** — accrued from betrayals, backstabs, infamy-triggering actions

Exact gain/loss amounts are defined in the SQL functions on the server. No client-side formula for these — the server awards them at game resolution.

---

## 18. AI Players

- `is_ai = true` on `game_players` row; `user_id = null`
- AI slots filled by `start_game` RPC based on `fill_with_ai = true` and `max_players`
- `ai_difficulty` (1–5) controls AI aggressiveness (defined entirely in SQL)
- AI players participate in all mechanics (production, combat, diplomacy) handled server-side by `process_ticks`
- Client-side: AI players filtered out of human player lists but shown on leaderboard and map

---

## 19. What Does NOT Carry Over to Siege & Sigil V1

These existed in Westeros but are explicitly excluded from V1:
- **Co-op / White Walker system** — `ww_state`, `ww_levy_columns`, `house_coop_roles`, `wall_pressure`, `march_start_tick`
- **GoT-specific character names and bios** — replaced by procedural generation
- **Hardcoded Westeros map** — replaced by procedural map generation
- **Scenarios table** — reintroduce in V2 if needed
- **Whispers AI feature** — requires LLM integration; reintroduce when infrastructure is ready
- **Small Council meeting mechanic** — GoT-specific feature
- **WotFK subfactions** (Baratheon factions) — GoT-specific

---

## 20. Design Decisions (resolved)

### 20a. Map system
- **Delaunay/Voronoi dual.** Points are scattered with Poisson-disk sampling, adjacency comes from the Delaunay triangulation (long edges pruned), and cells render as the Voronoi dual so visible borders and march edges are the same thing.
- **Generated per game** from game settings. No static map. Settings: `map_style`, `map_size`, player count, `starting_territories`.
- **V1 styles:** `scatter` (uniform, Neptune's Pride feel) and `continents` (clustered landmasses with gaps). More styles in V2.
- **Terrain barriers are the V2 direction** (rivers, mountains, oceans as strategic barriers). V1 schema carries the fields; V1 generation emits only `land` edges and plains terrain.

### 20b. Territory count and layout
- **Map size = territories per player**, multiplied by player count. Presets: compact 6, standard 9, large 14.
- **Spacing is held constant (~150 units).** Map dimensions (`games.map_w`, `games.map_h`) grow with territory count so scan radius (150) and march range (150) stay balanced at every size.
- **Coordinates are absolute map units** stored on `game_territories`, not normalized [0,1]. This replaces `MAP_NATIVE_W/H`; fog and march formulas use game units directly.
- **Territories are per-game.** The static `territories` table is removed; name, `x`, `y`, `tier`, `natural_resources`, `terrain` live on `game_territories`. Names are procedurally generated.

### 20c. Starting positions
- **`starting_territories` setting, default 4:** 1 tier-3 capital + 3 tier-1.
- **Fairness by N-fold rotational symmetry:** one player's starting cluster is generated and rotated around the map center. Neutral territory is scattered afterward with at least 2-3 neutral territories per player available to expand into.
- Capital is per-player: `game_players.capital_territory_id` (or `is_capital` on `game_territories`). `factions.seat_territory_slug` is dropped.

### 20d. Factions
- **8 unique factions in a static table**, name + `color` + `color2` only. `max_players` capped at 8 for V1; AI players take factions too.
- **Symmetric.** No mechanical differences. `factions.modifier jsonb` (nullable, unread) is the V2 hook.

### 20e. Movement is path-based
- Marches travel edge-by-edge along the shortest weighted path through `territory_edges`. Replaces the any-to-any euclidean model in sections 5c-5d and the Westeros pixel-distance formulas.
- `travel_ticks = max(1, ceil(path_length_weighted / speed))`, where each edge contributes `length × move_cost_mult`.
- `max_march_range = 90 + horses_level × 60` is measured along the path, not straight-line.
- `commander_movements` and `commander_routes` store the path (ordered edge/territory list).
- Road bonus applies per edge when both endpoints have a road.
- Intercept runs along edges.
- **Fog of war stays euclidean in V1.** Terrain-based line-of-sight blocking is a V2 add.

### 20f. New per-game tables / columns
- `territory_edges(game_id, from_territory_id, to_territory_id, kind, length, move_cost_mult, defense_mult)`; `kind` in `land` / `river` / `pass` / `sea`. Ordered pair, `from < to`.
- `game_territories.terrain` (V1: `plains`; V2: `hills` / `mountains` / `forest` etc.).
- `games`: `world_seed`, `generator_version`, `map_style`, `map_size`, `map_w`, `map_h`, `starting_territories`.

### 20g. Generator architecture
- **Edge function (TS)** computes the layout from a seeded PRNG, deterministic given `world_seed` + `generator_version`.
- It calls a **service-role-only RPC** `commit_world(p_game_id, p_layout jsonb)` that validates invariants and inserts territories, edges, and capitals in a single transaction. A partial world cannot exist.
- `start_game` triggers generation.
- **Invariant tests:** determinism, connected graph, equal capital stats, equal neutral count per player, capital-to-capital distance symmetry.

**Implemented (generator_version 1)** in `supabase/functions/generate-world/` (`generator.js` pure and tested with `node --test generator.test.js`, `index.ts` handler) and migration `commit_world`. Values marked (placeholder) are tuning knobs.
- **Fairness by construction:** one wedge is generated and rotated N-fold around the map center, so every seat has an identical start cluster, neutral neighborhood and edge pattern. Seat-to-player assignment is a seeded shuffle.
- **Geometry:** map is a disc of radius `150 × sqrt(territories / pi)` inside a square (`map_w = map_h = 2 × (radius + 60)`), giving about 150 units between neighbors. Points come from dart-throwing with a minimum distance (0.7 × 150 scatter, 0.55 continents), relaxed 4% per retry.
- **Adjacency:** Delaunay triangulation, symmetrized across rotations by orbit majority (breaks float ties). Edges longer than the prune limit (2.0 × 150 scatter, 1.4 continents) are removed, then the shortest removed edges are added back, as full rotation orbits, until the graph is connected. Those added edges are the chokepoints.
- **Per-player territories:** compact 6, standard 9, large 14; start `starting_territories` (default 4: 1 tier-3 capital + 3 tier-1); at least 2 neutral per player. Neutral tier 2 = 40% of neutrals, taken nearest the center.
- **Placeholder values:** `natural_resources` tier 1/2/3 = 2/4/6; owned `resources` = base + 5 (Guildhall level 1), neutral = base. Neutral garrison = `starting_garrison × tier`; neutral levels: gold = tier - 1, industry 1, prestige 0 (so captured neutrals pay salvage and produce troops). Owned territories take garrison and levels from the game settings.
- **Names:** prefix + suffix (e.g. Ashford), unique per game. `region` is unused in V1.
- **Entry point:** edge function `start-game` (see 20k). It calls `start_game`, which calls `commit_world`; `commit_world` validates the layout and writes territories, edges, ownership and capitals, and is executable by `service_role` only.
- **Known weak spot:** `continents` is a first pass (tighter clusters, a few bridge edges) and has not been checked visually.

### 20h. Other
- **Road equivalent:** keep the name "Road", change flavor text only.

### 20i. Commanders, schools and kings

Supersedes sections 6e and 11, the `commanders` table in 1b, and `get_available_commanders` / `recruit_commander` in section 14. Items marked (proposed) are not yet confirmed.

**Principle:** commanders are cheap carriers that move troops and are disposable. A commander who survives and wins becomes indispensable and a succession candidate. Symmetric in opportunity, not outcome.

**Hiring**
- Choose a school, pay a flat price (base 100 gold), receive a generated name and +1 level in one random ability of that school.
- No candidate offers, tiers, rerolls or hire paths. `commander_offers` is not needed.
- Schools are menu choices, not map locations. The school is a permanent record on the commander.

| School | Abilities |
|---|---|
| Battleschool | Valor, Tactics, Siegecraft |
| University | Muster, Steward, Scholar |
| Rangers | Pace, Scout, Plunder |

**Abilities**

All start at level 0 (no bonus). Max level 3 per ability; the schema CHECK allows up to 5 so the cap can be raised by a data change. Effect numbers are placeholders for sims.

| Ability | Effect at levels 1 / 2 / 3 | Applies when |
|---|---|---|
| Valor | +1 / +2 / +3 effective Armory | Battles he leads, attacking or defending |
| Tactics | +1 / +2 / +3 initiative, added to Watchtowers level | Open-field battles |
| Siegecraft | Leading a siege: starvation +1 / +2 / +3 pp. Leading the besieged garrison: -0.5 / -1 / -1.5 pp | Sieges |
| Muster | +10 / +20 / +30% troop production | Castle he leads |
| Steward | +10 / +20 / +30% gold | Castle he leads |
| Scholar | +10 / +20 / +30% prestige | Castle he leads |
| Pace | +10 / +20 / +30% march speed | His marches |
| Scout | +30 / +60 / +90 scan radius | Moving or idle, and at the castle he leads |
| Plunder | +25 / +50 / +75% salvage gold | On capture |

Tabled: Ironclad (enemy destroys 1 fewer troop per round, minimum 1). Rejected: Mentor, Command.

**Rank**
- Rank = total ability levels. Cap 20 (27 possible), so a commander can never have everything. At the cap, further XP is discarded.
- Rank is the commander's single "level" for display and leader selection.

**Leveling (automatic, no player choice)**
- Each ability has its own XP bar, fed only by that ability's activity. XP accrues to all nine abilities regardless of the commander's school or the ability's current level.
- Level n of an ability costs `1000 × n × (1 + 0.1 × rank)` XP (placeholder, proposed). Illustrative cumulative totals, cheapest levels first: rank 5 about 6k, rank 10 about 16k, rank 15 about 38k, rank 20 about 71k.
- **School affinity (proposed):** +50% XP gain in the commander's own school's three abilities, no penalty elsewhere (dial: x1.25).
- Considered and not adopted: one shared XP pool granting a random ability level at each threshold. It breaks "what he does makes what he becomes".
- XP sources (rates TBD by simulation):
  - Valor: troops destroyed in battles won, scaled by `min(1, enemy force / own force)`
  - Tactics: open-field battles fought, bonus for wins
  - Siegecraft: production cycles leading either side of a siege, bonus for breaking or holding
  - Muster / Steward / Scholar: troops / gold / prestige produced at the castle he leads
  - Pace: distance marched on marches that end at an enemy or neutral territory
  - Scout: production cycles with an enemy force or territory inside his scan range
  - Plunder: castles captured, weighted by tier
- Passive garrison XP must stay slower than combat XP; tune in the simulation.

**Battle resolution** (Neptune's Pride rules, adapted)
- Troops destroyed per round = effective Armory = realm Armory level + Valor of the leading commander. Bonuses are flat integers, no rounding. (proposed)
- Castle battle: the defender strikes first and gets +1 Armory. Rounds alternate until one side has no troops.
- Open field: both sides are attackers, no defense bonuses. Initiative score (Watchtowers + Tactics) decides who strikes first. Ties go to the force already present, otherwise the earlier departure.
- Leader of a force: the assigned garrison commander in a castle defense, otherwise highest Rank. Ties: king, then lower id. All troops in the territory fight as one pooled force under the leader.
- Simultaneous arrival at an unoccupied territory: the force that traveled the shortest distance in its final tick claims it and gets the defender bonus.
- Allied teams (formal alliance): all fight with the best Armory on the team, the defending team gets +1, the territory goes to the allied player with the most troops present, and remaining non-allied forces fight again.

**Garrison commander**
- Assignable per territory (one per territory) from any commander. He leads in defense and his castle abilities apply. He does not march until unassigned.

**Kings**
- One king per faction, crowned from the commander roster (`role = 'king'`; partial unique index: one living king per player).
- When crowned, the king's ability levels become realm effects:
  - Presence: Battle-school abilities (Valor, Tactics, Siegecraft) apply at the king's full level to the battle or siege he is in, when higher than the leader's.
  - Always on: Muster, Steward, Scholar, Pace, Scout and Plunder apply realm-wide at (king's level - 1). Every force and castle uses the higher of its own commander's level and the king's realm level.
- Guardrails: realm effects top out around one area level (about +20%); presence applies only to the fight he is in; no stacking; death removes all effects instantly; scarce XP makes high-level kings rare. Dial if floors crowd out garrison commanders: level - 2.
- Succession: on death, promote any commander. Kingless means no king effects, and the first commander hired is crowned by default. Coronation delay `games.coronation_ticks` (default 12) with no effects during the delay; 6 ticks with a named heir (heir designation, proposed).
- Kingless is not elimination (section 12b). Kings earn XP by the same rules.

**Combat losses (V1)**
- A commander whose force is destroyed dies, including the king and commanders in a castle that falls. No capture in V1. Later: captor's choice (execute / ransom / hold), `status = 'captured'`; a captured king stays king but his effects are suspended.

**Start of game (proposed)**
- Each player starts with a king and `starting_commanders` commanders (default 2), each hired by choosing a school at no cost, with the usual random +1.

**Open items**
- XP rates per activity and cost-formula constants (simulation).
- Simulation: `sim/xp_model.js` (assumes normal tick speed, 30 day game, 12-tick cycle).

**Capture salvage (confirmed):** capturing a territory destroys its Treasury levels and pays the captor 10 gold per level destroyed. Plunder scales the gold paid.

**Schema notes**
- `commanders`: `school`, `status` (`idle` / `moving` / `sieging` / `dead`), `role` text with CHECK (`commander` / `king`), `garrison_territory_id` nullable. Drop `is_named` and `level` (rank is derived).
- `commander_abilities(commander_id, ability, level, xp)`; level CHECK 0 to 5 (effective cap 3 in V1).
- `games.coronation_ticks`.

### 20j. Realm areas (replace the council)

Supersedes section 10 and the `council_seats` table. The council is not people; it is areas of the kingdom: abstract, realm-wide levels, not map buildings.

| Old seat | Area | Slug | Effect (section 10 formulas carry over) |
|---|---|---|---|
| Hand | Armory | `armory` | Base troops destroyed per round |
| Master of Coin | Mint | `mint` | Gold income multiplier |
| Lord Commander | Barracks | `barracks` | Troop production |
| Master of Laws | Guildhall | `guildhall` | Infrastructure upgrade cost |
| Whisperers | Watchtowers | `watchtowers` | Scan radius and open-field initiative |
| Grand Maester | Library | `library` | Invests bonus prestige in a random other area each cycle |
| Master of Horses | Stables | `stables` | March range |

- Table `realm_areas(game_id, player_id, area text, level, prestige_accumulated, is_active)`. `area` is text with a CHECK so Harbor can be added with naval. The focus seat becomes the active project. Prestige flow and advance cost (`144 × level × council_cost_mult`) carry over.
- Armory level is the base per-round damage, as in Neptune's Pride Weapons; the Westeros percent-per-commander-level formula is retired.
- Area names are display; slugs are the keys.
- V2_BACKLOG.md items "named council seat characters" and "AI council advisor" no longer fit this model and need rethinking.

### 20k. Lobby and start (implemented)

Supersedes `start_game`, `apply_game_settings` and the lobby parts of section 14.

- `create_game(p_settings jsonb)` (signed-in users): any subset of the game settings plus `name` and `faction_slug`; unknown keys are rejected; unset settings take the table defaults. Validates that `starting_territories` leaves at least 2 neutral territories per player. Creates the game in `lobby` and seats the creator (random faction if none given). Returns the game id.
- `join_game(p_game_id, p_faction_slug default null)` (signed-in users): lobby only, not already in the game, not full, faction free (random free faction if none given). Returns the player id.
- `set_starting_schools(p_game_id, p_schools text[])` (signed-in users): lobby only; exactly `1 + starting_commanders` schools, first is the king. Unset means random at start.
- `start_game(p_game_id, p_layout)` (server only): one transaction. Target players = `max_players` if `fill_with_ai`, else the humans seated (minimum 2). Fills AI players with the remaining factions, resolves AI seat placeholders (negative ids) in the layout, calls `commit_world`, then for every player: sets `starting_gold` and writes the ledger entry, creates the 7 realm areas at level 1 with Armory active, and creates the king plus `starting_commanders` commanders at the capital (chosen schools or random), each with +1 in one random ability of its school. Then creates all diplomacy pairs as neutral, a public `game_started` moment, an event, an inbox message for humans, and sets the game `active` at tick 0 (turn deadline set for turn-based games).
- Edge function `start-game` (creator only, game in lobby) generates the layout for the final player count and calls `start_game`. Browsers call this function, not the SQL function.
- Internal helpers (no client access): `create_commander` (also for hiring later) and `random_commander_name` (given name + family name, unique within the game).
- Not yet built: `leave_game`, `cancel_game`, `delete_game`, changing faction in the lobby.

### 20l. Economy and hiring (implemented)

All are client-callable (signed-in players) and require an active game and a non-eliminated player. Each locks the player's row first, so gold changes are serialized. Money moves are written to the `ledger` at the current tick.

- `hire_commander(game, territory, school)`: territory must be owned; costs `games.commander_cost` (flat); new commander appears idle at that territory with 0 troops and +1 in a random ability of the school. If the player has no living commander at all, the hire is crowned king with `coronation_tick = current_tick + coronation_ticks`.
- `transfer_troops(game, commander, amount)`: commander must be idle at one of your territories; positive moves garrison to commander, negative the reverse.
- `upgrade_infrastructure(game, territory, type)`: `type` is `treasury` / `recruitment` / `prestige` (levels `treasury_level` / `industry_level` / `prestige_level`). Cost `floor(base × (level + 1) / resources × infra_cost_mult)` with base 500 / 1000 / 4000, minimum 1. No level cap.
- `bulk_upgrade_infrastructure(game, type, budget)`: repeatedly upgrades the currently cheapest owned territory until the budget (capped at your gold) runs out. Returns `{upgraded, spent}`; one ledger row.
  - Client (Realm tab): the budget input defaults to the player's gold. `realmSection` runs the same greedy loop client-side (`infra_cost` formula, ties by territory id) on every input change to show what will be bought and the exact total, relabels the button `Spend N gold`, disables it when nothing is affordable, and applies the total optimistically through `order()`.
  - Client (Realm tab areas): each area row shows cycles and ticks to the next level, computed from the sum of `prestige_level` over owned castles (the scholar bonus is ignored here; `research_info` has the exact figure) and `production_cycle_ticks`.
- `build_road(game, territory)`: cost `floor(6 × resources × infra_cost_mult × (3 if expensive))`. `demolish_road` is free and refunds nothing.
- `send_gold(game, target_player, amount)`: ledger rows for both sides, inbox message for the receiver. Not allowed to self or to eliminated players.
- `set_active_area(game, area)`: sets the single active project; progress in other areas is kept.
- `assign_garrison_commander(game, commander)` / `unassign_garrison_commander(game, territory)`: the commander must be idle at one of your territories. Assigning replaces any current garrison commander there.
- `crown_commander(game, commander)`: only when you have no living king; effective after `coronation_ticks`. King effects are active when `role = 'king'`, alive, and `coronation_tick` is null or reached (start-of-game kings have a null tick).
- Internal (no client access): `acting_player`, `infra_cost`, `add_area_prestige` (adds prestige to an area and levels it up at `ceil(144 × level × area_cost_mult)` per level; Guildhall level-ups refresh `resources`), `refresh_effective_influence` (`natural_resources + 5 × Guildhall level`; also needed after a capture).
- Not built: heir designation, area prestige flow (tick engine), commander disbanding.

### 20m. Movement (orders implemented; execution is the tick engine's job)

- **Pathing:** Dijkstra over `territory_edges`, minimizing travel time. A commander may pass **only through territory owned by himself or an ally** (formal alliance). The destination can be anything, so contact with an enemy or neutral castle is always the end of an order, and castles block movement. No friendly corridor to the destination means no route.
- **Speed:** `17.5 × commander_speed_mult × (1 + 0.10 × Pace level)`, units per tick; Pace uses the higher of the commander's own level and the king's floor (king level - 1, king active only after `coronation_tick`). Each edge costs `length × move_cost_mult`, divided by `sqrt(3 + Stables level)` of the marching player when both of its end territories have a road.
- **Arrival ticks:** `ceil(cumulative cost / speed)` per node, never decreasing, at least 1 tick overall. Stored in `commander_movements.path_arrival_ticks` so mid-march position and intercepts can be computed.
- **Range:** `90 + 60 × Stables level` limits the raw (road-free) length of one order's path. **A single-edge hop is always allowed**, otherwise the longer edges (up to about 300 units, against a level-1 range of 150) could be unreachable for a long time. Range applies to each leg of a multi-stop route.
- `march_commander(game, commander, territory, march_type)` is a one-stop route. `send_on_route(game, commander, stops, march_type)` takes 1 to 10 stops (`{territory_id, march_type?}`), creates an active `commander_routes` row, and launches the first leg. Only the first leg is validated at order time; later legs must be re-planned when the engine starts them.
- `preview_march(game, commander, territory)`: read-only plan for the UI (path, ticks, arrival tick, raw length, range, whether it is in range).
- `abort_route`: the commander finishes the edge he is on and halts at the next node. `recall_route`: same, and the route is marked `recalled` so the engine sends him back to `origin_territory_id`.
- A marching commander has `status = 'moving'` and no `current_territory_id`; a garrison commander must be unassigned before marching.
- **Tick engine, stage 1 (production and the loop) is implemented in 20n; the stages below are still to build.**
- **The tick engine must:** move commanders to their next node and set `current_territory_id` on arrival; start the next leg of an active route (re-planning, aborting the route if blocked); send recalled routes home; resolve arrival at enemy or neutral territory by `march_type` (assault now, siege starts a siege); resolve open-field intercepts along edges; refuse to move through territory that has changed hands.

### 20n. Tick loop and production (implemented)

- `process_game(game)` (internal) advances a game by the ticks that are due, up to 200 per call, then moves `last_tick_processed_at` forward by whole intervals so the cadence never drifts. Real-time intervals: slow 2h, normal 1h, fast 30m, quad 15m. Turn-based games run `ticks_per_turn` ticks once every human player has called `submit_turn` or `current_turn_ends_at` passes, then clear all submissions and set the next deadline.
- Callers: `process_ticks(game)` (any member, any time; harmless if nothing is due), `submit_turn(game)` (processes immediately when it is the last human to submit), and the scheduled job `process-due-games` (pg_cron, every minute, runs `process_due_games()`), so games advance with nobody logged in. A failing game logs a `tick_error` event and does not stop the others.
- `run_tick(game)` per tick, in order: increment `current_tick`; troop production; prestige flow; and on every `production_cycle_ticks`-th tick: gold payout, Library bonus, intel snapshot. Combat, movement and sieges will slot in between production and the win check.
- **Troops:** per territory per tick `industry_level × (Barracks level + 4) × (1 + 0.10 × Muster) / production_cycle_ticks`, accumulated in `troop_accum`; the whole part is added immediately.
- **Prestige:** per player per tick `Σ prestige_level × (1 + 0.10 × Scholar)`, accumulated in `game_players.prestige_accum`; the whole part goes to the active area through `add_area_prestige`.
- **Gold (cycle end):** per player `floor(Σ treasury_level × (10 + 2 × Mint level) × (1 + 0.10 × Steward))`, one `production` ledger row.
- **Library (cycle end):** `72 × Library level` prestige into a random non-active area.
- **Ability levels used here:** a territory uses the level of its garrison commander or the king's floor (king level - 1, active after `coronation_tick`), whichever is higher.
- **Intel snapshot (cycle end):** per player territories, gold, troops, commanders, infrastructure totals and area levels, one row per tick.
- Not yet in the loop: combat, sieges, XP, win and elimination checks, AI behavior. Movement is in (see 20o).

### 20o. Movement and arrivals (implemented)

Runs inside `run_tick` right after production. Each tick, for every in-flight `commander_movements` row without a contact:
- **Interruption rule:** walk the nodes the commander has reached by this tick. The first node that is the final destination, or is not friendly (not his, not an ally's) or holds an enemy sieging commander, ends the movement there. Intermediate friendly nodes are passed through.
- **Arrival at a friendly node:** the commander becomes `idle` at that node, the movement row is deleted. Troops stay on the commander (no automatic merge into the garrison; use `transfer_troops`).
- **Contact (hostile node or besieged node):** the path is truncated to that node, `contact_territory_id` is set, the commander stays `moving` with no location. **The combat stage resolves contacts** (assault or siege by `march_type`, relief of a besieged friendly territory); until it exists they just wait.
- **Route progression** (`continue_route`) after an arrival: an `active` route that reached its current stop moves to the next stop by re-planning from where the commander stands; if that leg is impossible (blocked, out of range) the route is `aborted` and the player gets a "Route cancelled" inbox message with the reason. A finished route becomes `completed`. A `recalled` route sends the commander back to `origin_territory_id` (as a plain movement) and is marked `completed`. An `aborted` route does nothing further.
- `movement_position(movement, tick)` (internal) returns the interpolated map position along the path, for intercepts and the client.
- Helpers (internal): `are_allied`, `is_friendly_territory`, `has_hostile_siege`.
- `process_ticks` now also reports `arrivals` and `contacts`.

### 20p. Battles and capture (implemented)

Runs in `run_tick` after movement (`resolve_tick_events` = movement, then `resolve_contacts`). It resolves every `assault` contact; `siege` contacts and relief of a besieged friendly territory are left waiting for the siege stage.

- **Order:** contacts are taken in `(arrival_tick, movement id)` order. Commanders of the **same player** in contact at the same territory fight as one force. Different players fight one after another, so an earlier capture changes who defends against the next one. If the territory has become friendly (for example captured by an ally earlier in the tick), the later commanders simply arrive.
- **Defense pool:** the territory's garrison troops plus every idle commander of the owner **or an ally** stationed there, with their troops. A neutral territory has only its garrison.
- **Damage per round:** attacker `max(1, Armory + Valor)`; defender `max(1, Armory + Valor + 1)`. Armory is the player's realm level (best level among the defending players present; neutral = 1). Valor is the **leader's** level (assigned garrison commander first, else highest Rank, ties to the king, then lower id), or a present, crowned king's level if higher.
- **Outcome (defender strikes first):** `R_att = ceil(attackerTroops / defenderDamage)`, `R_def = ceil(defenderTroops / attackerDamage)`. If `R_att <= R_def` the defender wins with `defenderTroops - (R_att - 1) × attackerDamage` survivors; otherwise the attacker wins with `attackerTroops - R_def × defenderDamage`. An undefended territory (0 troops) always falls, even to a commander with 0 troops. An attacker with 0 troops against any defender loses.
- **Survivors** are shared among the winning side's commanders (and the garrison) in proportion to their troops, with any rounding remainder going to the largest.
- **Losing side:** every commander on it dies (status `dead`, troops 0, movement and active routes cleared, garrison assignment cleared). A killed king writes a public `king_killed` moment.
- **Capture:** the territory changes owner with **0 garrison troops** (the surviving attackers stand there as idle commanders and keep their troops), its Treasury level is destroyed and pays `10 × level × (1 + 0.25 × best Plunder level among the attackers)` gold (ledger `salvage`). Industry, Prestige and roads are kept. `resources` is refreshed for both owners. A public `castle_captured` moment is written. The attackers then continue their routes.
- **Reports:** a `battle` server event; a `combat` inbox message for the attacker and the previous owner (neutral owners get none).
- `process_ticks` now reports `combats` and a `combat_events` list (territory, winner, captured, survivors, salvage).
- **Not done yet:** nothing known. Allied attackers fight as one side (20ab, team assaults); sieges and open-field fights are in 20q.

### 20q. Sieges and open-field fights (implemented)

**Tick order now:** production, siege attrition, movement, intercepts, castle battles, siege contacts (siege start, relief, friendly arrivals), clean-up of stale sieges.

- **Open-field fight (shared rule):** both sides attack, damage per round `max(1, Armory + Valor)` with no defense bonus. Initiative = Watchtowers level + the leader's Tactics (a present king's Tactics counts if higher); the higher score strikes first. A side made of several players uses its best Armory and Watchtowers. Rounds alternate; the winner keeps `winnerTroops - rounds the other side fired × its damage`, the loser's commanders die. A side with 0 troops loses to any troops.
- **Starting a siege:** a `siege` march that reaches a hostile territory makes the commander `sieging` there (no fight); his movement ends, the route is marked completed, the owner is told, and a public `siege_started` moment is written. A sieging commander can be ordered to march away again.
- **Starvation:** every tick after the siege starts, the besieged garrison (the territory's troops only) loses `3% + 1 pp × sieger Siegecraft - 0.5 pp × garrison leader Siegecraft` of its troops (not below 0), with the fraction carried in `starve_accum`. The sieger's Siegecraft is the leading sieger's (or a present king's); the defender's is the garrison leader's. Neutral territories starve too.
- **Infrastructure damage:** each production cycle a besieged owned territory loses 1 level on one random track (Treasury, Recruitment or Prestige) that is above 0; the owner gets a message.
- **Sally out** (`sally_out(game, territory)`, owner only): the garrison plus idle commanders there (owner or allies) fight all hostile siegers in the open field now. Ties in initiative go to the siegers. A winning sally kills the siegers and lifts the siege, survivors share the troops. A losing sally empties the garrison and kills those commanders; the siegers keep their survivors.
- **Relief:** a commander (either march type) reaching a friendly territory that holds hostile siegers fights them in the open field (ties to the siegers). A win kills the siegers, lifts the siege, and the relief commanders end up idle there. A loss kills the relief force. The garrison does not take part.
- **Break siege and assault** (`break_siege_and_assault(game, territory)`): the player's sieging commanders there launch a normal castle battle (defender bonus applies) immediately.
- **Intercepts:** each tick, every pair of marching enemy commanders (different, non-allied players, both carrying troops, not at a contact) is checked by sweeping their movement over the last tick; if they came within 20.2 units they fight an open-field battle. Ties go to the earlier departure. The loser dies, the winner keeps marching with his survivors. Troopless commanders are never intercepted.
- **Stale sieges:** sieging commanders whose territory has become friendly turn idle.
- `process_ticks` `combats` / `combat_events` now include intercepts and reliefs.
- **Not done yet:** allied siege breaks fight individually (20ab, team assaults). Win and elimination are in 20r.

### 20r. Win and elimination (implemented)

Runs at the end of every tick (`evaluate_game_end`, last step of `resolve_tick_events`) and from `concede_defeat`.

- **Elimination:** a player who owns no territory at the end of a tick is eliminated (`eliminated_at_tick`), all of their commanders die, they receive an "eliminated" message and a public `player_eliminated` moment is written. Eliminated players cannot act (`acting_player` refuses them) and are skipped by production and turn-based submission.
- **Concede** (`concede_defeat(game)`): the same, immediately, and the player's territories become **unowned** (troops and infrastructure stay; `resources` falls back to base). The win check then runs at once.
- **Victory:** (1) **territory:** a living player owns at least `ceil(total territories × victory_pct)` (default 50%); (2) **last standing:** only one living player remains. If several qualify in the same tick, the one with the most territories wins, then the most troops (garrisons plus commanders), then the lowest id.
- **Finishing:** the game becomes `finished` with `winner_player_id`, a final intel snapshot is taken, every human gets a `Victory` or `Defeat` system message (`kind: game_over`), a public `game_won` moment and a `game_finished` event are written, and profiles get `total_games + 1` (and `total_wins + 1` for the winner). Honor and infamy are not awarded yet.
- **The tick loop stops** at the winning tick: a catch-up batch ends there and later calls do nothing.
- `check_win_condition(game)` (members): current standing (`total`, `win_at`, `castles` of the leader, `players_alive`, `winner`, `winner_id`, `reason`, plus the game `status` and `winner_player_id`).
- `process_ticks` now also returns `game_status` and `winner_player_id`.
- **Not done yet:** shared allied victory and surrender of a whole alliance (individual victory only in V1, see 20ab). A time limit is in 20ab.
- **Concurrency:** `concede_defeat` locks the game row first (the same order `process_game` uses) and refuses unless the game is active; `finish_game` only acts if the game is still `active`, so a game can finish exactly once (profile stats, events and messages are not duplicated).

### 20s. XP and leveling (implemented)

All numbers live in the table `xp_config` (key / value, readable by signed-in users, edited by migration or SQL), so tuning needs no code change. Starting values are placeholders for the simulation:

| Key | Value | Meaning |
|---|---|---|
| `xp_base_cost` | 1000 | Level n of an ability costs `base × n × (1 + step × rank)` |
| `xp_rank_step` | 0.1 | Per rank point |
| `rank_cap` | 20 | At the cap, further XP is discarded |
| `ability_max_level` | 3 | Per ability |
| `school_affinity` | 1.5 | XP multiplier for the three abilities of the commander's own school |
| `valor_per_troop`, `tactics_per_troop` | 20 | Per troop destroyed (see below) |
| `siegecraft_per_cycle`, `siegecraft_break_bonus` | 80, 300 | |
| `muster_per_troop`, `steward_per_gold`, `scholar_per_prestige` | 3, 0.6, 1 | |
| `pace_per_unit`, `scout_per_cycle`, `plunder_per_tier` | 1, 100, 400 | |

- `award_xp(commander, ability, amount)` (internal) adds XP (with affinity), then levels up automatically while the XP covers the next level, the ability is below its max, and rank is below the cap. Ability XP and level are kept per commander; a maxed ability or a capped commander stops accumulating. Dead commanders gain nothing. Each level-up writes a `commander_level_up` event and a system message to human owners.
- **Sources:**
  - **Valor** (and **Tactics** in open-field fights): the winning side's surviving commanders each get `loserTroops × min(1, loserTroops / winnerTroops) × rate`. Smaller enemies pay less. Applies to castle battles (attacker or defender), relief, sally and intercepts.
  - **Plunder:** capturing a castle gives each attacking commander `tier × plunder_per_tier`.
  - **Siegecraft:** each production cycle the leader of each side of a siege gets `siegecraft_per_cycle`; breaking a siege (relief, sally, or assaulting out of a siege and winning) or holding it (beating a relief or sally) gives `siegecraft_break_bonus` to the winners.
  - **Muster / Steward / Scholar:** each tick (Steward at cycle end) the garrison commander of a castle gets XP for the troops, gold or prestige that castle produces.
  - **Pace:** when a march ends in a contact (enemy, neutral, or besieged castle) the commander gets `pace_per_unit` per unit of road travelled by that leg.
  - **Scout:** each production cycle a commander gets `scout_per_cycle` if an enemy-owned territory or an enemy marching commander is within his scan radius (`45 + 15 × rank + 30 × Scout level`).
- Tick order gains `award_production_xp` and (cycle ticks) `award_scout_xp` just before the win check.
- **Tuned:** see 20aa for the simulation pass and the current rates.

### 20t. AI players (implemented)

AI players (`is_ai`, no user) play through the same internal rules as humans. `run_ai_players` is the first step of every tick (`resolve_tick_events`); every AI acts on every tick. `ai_difficulty` 1 to 5 changes how it decides (attack thresholds, gold spending, treaties, betrayal), not how often it moves. An error in one AI's turn is logged as an `ai_error` event and rolled back without affecting the tick.

A turn, in order:
1. **Active area:** the lowest-level of Mint, Barracks, Armory, Guildhall, Stables, Watchtowers, Library (in that preference order).
2. **Crown:** if there is no living king, the highest-rank living commander is crowned.
3. **Hire:** up to 2 commanders per turn, until `min(1 + difficulty, max(2, castles / 2))` are alive (schools 50% Battleschool, 30% Rangers, 20% University), at the capital.
4. **Commanders** (idle ones standing in their own territory, not garrison leaders, most troops first): pick up garrison troops above a reserve of `8 - difficulty`; with at least 6 troops, look at every non-friendly territory bordering friendly ground that is reachable and in range, predict the castle battle with the real damage formula against the defender's troops (plus production during travel) times a safety margin (1.6 / 1.4 / 1.2 / 1.1 / 1.0 for difficulty 1 to 5), and assault the best-scoring winnable target (tier, neutral bonus, Treasury level, travel time, small random term). Difficulty 1 and 2 misjudge defenders by up to 25%. With no winnable target, move to the owned territory closest to the nearest non-friendly territory.
5. **Spend:** after reserving the price of the next hire, spend `30% + 10% × (difficulty - 1)` of gold on the cheapest Recruitment or Treasury upgrades (Treasury weighted 1.2x more expensive).

- **Refactor:** `hire_commander`, `transfer_troops` and `upgrade_infrastructure` now call internal `*_core(game, player, ...)` versions that the AI shares, so cost rules live in one place.
- **Observed (3 players, 1 passive human, compact map, 100 ticks):** no errors; difficulty 5 AIs took neutral castles faster (6 castles each vs 5), made 16 upgrades vs 9, and fought 4 battles vs 2; neither attacked the human's heavily garrisoned castles.
- **Not done yet:** AI relief marches, roads, Prestige upgrades, hiring beyond the cap, holding back gold. AI diplomacy is in 20y, garrison leaders in 20aa and sallies in 20ab.

### 20u. Diplomacy (implemented)

Pair status lives in `diplomacy` (neutral, proposed, allied, grace_period, war). Only 'allied' counts for `are_allied` / `is_friendly_territory`.

- **Propose / accept / decline:** `propose_alliance`, `accept_alliance`, `decline_alliance`. Each notifies the other player's inbox. You cannot propose to yourself, twice, while at war, or during a grace period. If both sides propose, the second proposal forms the alliance immediately.
- **Break:** `break_alliance` moves the pair to `grace_period` for `games.grace_period_ticks` (default 24). Friendly status ends at once. Any of the breaker's or the other player's commanders standing in the other's territory are moved to their owner's nearest territory (`expel_commanders`).
- **War:** there is no declaration action. War starts automatically when a grace period expires (`advance_diplomacy`, how = alliance_broken) or when the first `battle`, `intercept` or `siege_started` event happens between non-allied players (trigger `game_events_hostile`, how = attack). An attack during a grace period ends it as war immediately. War ends only through a truce (20y).
- **Visibility:** alliance formation and breaks are private moments to the two players; war declarations are public.
- **AI:** `ai_diplomacy` runs at the start of each AI turn and answers pending proposals. Accept chance falls with difficulty (80 / 65 / 50 / 35 / 25% for difficulty 1 to 5; 27 of 30 in test at difficulty 1). It always declines a proposer holding at least 70% of the territories needed to win.
- **Verified (rolled-back tests):** propose, decline, accept, mutual proposal, all error paths, break with expulsion, grace expiry to war at tick 29, auto-war from a real battle, attack during grace, AI accept rate and leader decline.
- **Not done yet:** allied team fights (allies fight sequentially). Peace and AI diplomacy are in 20y, honor and infamy in 20aa.

### 20v. Lobby housekeeping (implemented)

- **`leave_game(game)`:** lobby only. A member's player row is removed. If the creator leaves, host passes to the earliest-joined remaining human; if none remain the game is deleted. Once a game has started, leaving is `concede_defeat`.
- **`cancel_game(game)`:** creator only, lobby only. Deletes the game.
- **`delete_game(game)`:** creator only, finished games only. Deletes the game and all its data (all child tables cascade).
- **Not done yet:** nothing known. Kicking and lobby cleanup are in 20ab; inactive players are auto-conceded (20ab, auto-concede).

### 20w. Map view (implemented, read-only)

`index.html` `showMap(game)`: SVG map with pan (drag) and zoom (wheel).

- **Cells:** Voronoi cells computed client-side from territory positions (half-plane clipping inside `map_w` x `map_h`), filled with the owner's faction color. Roads: territory edges drawn as lines, gold when both ends have roads.
- **Castles:** radius by tier, troop count above, name below, commanders as dots (gold ring = king), capital marked with a crown. Marching commanders are drawn at the position for the last processed tick (`viewTick()`); when `load()` sees `current_tick` advance by one to three ticks it sets `ms.slide = {from, at}` and `viewTick()` eases from the previous tick to the new one over 700 ms (`SLIDE_MS`, rendered at 25 fps by the fx timer, skipped under reduced motion). `tickF()` (the fractional tick from `last_tick_processed_at`) is still used for siege tracking, ETAs and anything the server computes within the tick, such as sight ranges and intercepts; own marches show a dotted route.
- **Fog (client-side, `fog_of_war` games):** own and allied castles and commanders are always visible. A castle scans `90 + 60 x Watchtowers level` (allied castles 90); a commander scans `45 + 15 x rank + 30 x Scout`. Anything else shows its last-known owner as a faded ghost with troops hidden, remembered in localStorage per game and user. Enemy commanders are shown only inside a scan range. Fog is enforced on the server (section 20x); `intel_snapshots`, which hold every player's gold and troop totals, are readable only after the game ends or in games without fog.
- **Panels:** top bar (tick, gold with the production countdown, castles toward the win threshold, scan-ring toggle); side panel for the realm and standings, a selected castle (owner, troops, levels, commanders, roads), or a selected commander (rank, troops, status, abilities).
- **Live updates:** realtime on games, game_players, game_territories, commanders, commander_movements, diplomacy and realm_areas, plus a 30 second poll as a backstop.
- **Marching orders (implemented):** select an own idle commander to get an Orders panel. Take or Leave garrison troops (`transfer_troops`); release a garrison leader (`unassign_garrison_commander`). March... turns on destination mode: a gold dotted ring shows the Stables range around the commander, clicking a castle calls `preview_march` and draws the route (green in range, red not) with travel ticks, arrival tick and real-time estimate, and non-friendly destinations offer Assault or Siege on arrival. March calls `march_commander`. A marching commander can be halted at the next stop (`abort_route`) or recalled (`recall_route`); the panel shows the halted or recalled state. Escape cancels destination mode. Multi-stop routes are in the UI (20aa).
- **Economy orders (implemented):** selecting an own castle shows a Build section: Treasury, Recruitment and Prestige upgrades with their live cost (`floor(base x (level + 1) / resources x infra_cost_mult)`), build or demolish road, and Hire a commander by school at that castle (`hire_commander`). Realm panel: each area's level and prestige toward the next level (`ceil(144 x level x area_cost_mult)`), Activate to change the active area, and a bulk upgrade (type and gold budget, cheapest castle first). Commander panel: Lead garrison, and Crown as king when the realm has none. Buttons are disabled when gold is short; server errors appear as toasts.
- **Feed and diplomacy (implemented):** the side panel has Info, News and Inbox tabs. News is the readable `game_moments` (public events and the viewer's private ones) rendered as sentences; Inbox is `player_inbox` with an unread count, new items highlighted on first open, then marked read. Both update live (`game_moments` is in the realtime publication). Standings now carry per-player diplomacy controls: Propose alliance, Accept or Decline an incoming proposal, Break alliance (with a confirm), and status text for a pending proposal, a grace period (war tick) or war. The top bar shows an "Alliance proposals (n)" button when proposals are waiting.
- **Siege orders (implemented):** a castle with sieging commanders gets a dashed red ring on the map and an Under siege section (besiegers and troops). The besieged owner sees their force (garrison plus idle commanders) and a Sally out button (`sally_out`, with a confirm that states the risk). A player with sieging commanders there gets Assault now (`break_siege_and_assault`, confirm). A sieging commander's panel shows the same Assault now, and he can still be ordered to march away.
- **Chat and messages (implemented):** RPCs `send_chat_message(game, message)` (members, 1 to 500 characters), `create_thread(game, participant_ids, first_message)` (human players only, 2 to 8 players including the sender; an existing thread with exactly the same participants is reused, so a DM is one thread) and `send_thread_message(thread, body)` (participants, 1 to 2000 characters). All trim, reject empty text, and allow at most 8 messages per 10 seconds per player; the tables themselves accept no direct writes (insert, update and delete revoked; only the `last_read_at` column of `thread_participants` stays updatable). UI: a Chat tab with General (everyone in the game) and Messages (thread list with unread dots, new message with a player picker, conversation view). A Message button in Standings opens or starts a DM. Unread counts show on the tab; general chat read position is kept in localStorage, thread read position in `thread_participants.last_read_at`. Live via realtime on `game_chat` and `thread_messages`. Dark faction colors fall back to the faction's second color for readability.
- **Not done yet:** muting or blocking players, a spectator view for eliminated players beyond the read-only map.

### 20x. Server-side fog of war (implemented)

Replaces the client-only fog of 20w for the data itself; the client still draws ghosts and remembers last-known owners locally.

- **`get_game_view(game)`** (members): the only way the map reads game state. With fog on and the game active it returns every territory's geometry (id, name, tier, region, position, terrain, base influence) with a `seen` flag, but owner, troops, levels, road, effective influence and garrison leader only for seen territories. A territory is seen when a friend (self or ally) owns it or it is within a scan radius. Castle radius is `90 + 60 x Watchtowers level` of the owning friend (allies' real levels are used); commander radius is `45 + 15 x rank + 30 x Scout` at the commander's current position (marching positions interpolated on the server at the current tick fraction). It also returns only visible commanders, abilities and marches (own and allied always), the caller's own routes, realm areas, diplomacy and gold, other players' public fields with gold hidden, public per-player territory counts (`standings`), and the scan sources for the rings. With fog off, or once the game is finished, everything is returned.
- **Direct reads revoked:** API clients can no longer select `commanders`, `commander_abilities`, `commander_movements` or `commander_routes`. `game_territories`, `game_players` and `games` expose only public columns (no owner, troops, levels, gold, capital, starting schools, world seed or generator version). `my_starting_schools(game)` returns the caller's own picks.
- **Realtime:** raw row changes would leak through payloads, so `games`, `game_players`, `game_territories`, `commanders` and `commander_movements` left the realtime publication. Statement-level triggers send one private broadcast per game per transaction on topic `game:<id>` (event `refresh`); a policy on `realtime.messages` lets only game members receive it. The page refetches on each pulse. Own-row streams (diplomacy, realm areas, inbox, chat, threads, moments) stay on `postgres_changes`.
- **News:** in fog games `castle_captured`, `siege_started` and `siege_lifted` moments are stored private to the players involved (trigger `game_moments_fog`); wars, eliminations, king deaths and wins stay public.
- **Public by design:** map geometry, each player's territory count, who is eliminated, faction and display name.
- **Known limits:** an enemy marching commander inside your vision reveals its full path and destination; commanders passing out of vision stay drawn until the next refresh (at most the 20 second poll or the next pulse); the home list refreshes by polling every 8 seconds.

### 20y. Peace and AI diplomacy (implemented)

- **Truce:** `propose_peace(game, player)`, `accept_peace`, `decline_peace`. A proposal is allowed from neutral (a non-aggression pact) or war. Statuses: `peace_proposed` (pending, with `prior_status` so a decline restores neutral or war) and `truce` (with `truce_ends_tick`). Both sides proposing forms the truce at once. Accepting sets `truce_ends_tick = tick + games.truce_ticks` (default 48, column only for now) and sends commanders standing in the partner's territory, including besiegers, to their own nearest territory. The truce cannot be broken; it expires back to **neutral** (`advance_diplomacy`), after which either side may attack again.
- **Enforcement:** `plan_march` refuses any destination owned by a truce partner (so previews, orders, route legs and AI scoring all refuse it with the end tick); `advance_movements` cancels a march that reaches a truce partner's territory (the commander stops idle on the last friendly node, the route is aborted, the owner is told); `resolve_intercepts` skips truce pairs; `mark_war` ignores truce pairs. A truce gives no shared vision and no passage through the other's territory. Alliances cannot be proposed during a truce or while peace is pending.
- **News:** `truce_formed` and `truce_ended` are public moments; both players also get inbox messages.
- **Refactor:** `break_alliance_core` and `propose_peace_core` serve both the client RPCs and the AI.
- **AI diplomacy** (`ai_diplomacy`, run at the start of each AI turn, scaled by `ai_difficulty`):
  - Answers alliance proposals as before (always declines a proposer holding 70% or more of the win threshold).
  - Answers peace: accepts 90% when it has fewer castles than the proposer, 15% when it has at least 1.5 times as many, otherwise 80 / 70 / 55 / 45 / 35% by difficulty 1 to 5.
  - Withdraws its own unanswered proposals after 24 ticks.
  - Betrays an ally who holds 70% or more of the win threshold: 20 / 35 / 50 / 70 / 90% per turn by difficulty (one betrayal per turn).
  - Proposes peace to a player it is at war with when it has under 80% of that player's castles (50% per turn, at least 12 ticks into the war or since the last decline).
  - Proposes an alliance (30% per turn, at most one pending proposal, at most 1 ally at difficulty 1 to 3 and 2 at 4 to 5) to a neutral, non-leading player, preferring close neighbors and players at war with its own enemies; 12 tick cooldown after a decline.
- **UI:** Standings show Propose alliance and Propose peace (neutral), At war with Propose peace, Accept or Decline for incoming peace, a pending note for outgoing, and Truce until tick N. The top bar counts waiting proposals of either kind.
- **Verified (rolled-back tests with triggers enabled):** propose, decline restoring war, accept with expulsion, all error paths, order and preview refusal, in-flight march cancelled on arrival, intercepts blocked in truce and happening at war, expiry, marching again after expiry; AI acceptance, proposal, withdrawal and betrayal rates against their targets over many trials; a 60 tick generated game at difficulty 5 with no AI errors, forming two AI alliances.
- **Not done yet:** truce for allies breaking into war. Truce length is a lobby setting (20aa).

### 20z. Battle reports (implemented)

- **Table `battle_reports`** (`game_id`, `tick`, `kind` of assault / sally / relief / intercept, `territory_id`, `territory_name`, `involved_player_ids`, `report` jsonb). Readable only by the players involved (RLS on `involved_player_ids`); nothing is public beyond the existing news lines, so fog is unaffected. No direct writes.
- **Recording:** `record_battle_report(...)` (internal) is called by `fight_castle` (assault, including assaults launched from a siege), `sally_out`, `resolve_relief` and `resolve_intercepts`, after the outcome is computed and before anyone dies or troops are reallocated, so commander snapshots show pre-battle troops. Castle salvage is added to the report when the castle is taken. Involved players are both sides' lead players plus the owners of every commander who fought (so allied defenders get the report).
- **Report JSON:** `sides[0..1]` (role, `player_id`, garrison, total troops, damage per strike, `died`, and each commander's id, name, school, role, owner, troops, rank and non-zero abilities), `first` (side index that strikes first), `winner`, `survivors`, `rounds` (troops of side 0 and side 1 after each strike; capped at 400 strikes with `rounds_truncated`), `captured`, `salvage`, `from_siege`. Sides: assault is attacker (0) and defender (1, strikes first); sally is sally force (0) and besiegers (1); relief is relief force (0) and besiegers (1); intercepts are the two marching commanders. Initiative decides `first` for open-field fights, with the existing tie rules.
- **Replay arithmetic:** strikes alternate starting with the first side, each removing the other's damage from its troops; the final entry matches the engine's closed-form `duel` result (checked over 300 random fights).
- **UI:** Inbox tab has Reports (the old messages) and Battles. Battles lists fights with result, place, tick and opponents, and a count of unseen ones is added to the Inbox badge. A detail view shows the result, survivors, capture and salvage, a replay chart with a slider, and a card per side with its commanders, ranks and abilities. A castle's panel lists Battles here.
- **Limits:** fights before this migration have no report (only their inbox message). XP and intercept locations were added in 20aa.

### 20aa. Reputation, routes, lobby settings and XP tuning (implemented)

- **Honor and infamy** (replaces the open section 17 amounts). Infamy accrues during a game in `game_players.infamy_delta` (hidden from clients): +20 to a player who breaks an alliance (`break_alliance_core`, including by AI), and +10 more when the breaker attacks the former ally during the grace period (`mark_war` with a non-grace how). At `finish_game` every human player's profile is updated once: honor +25 for the winner, +5 for not having been eliminated, +10 for each alliance still in force at the end; infamy +`infamy_delta`. Each player with a change gets a `Reputation` inbox message. Conceding carries no penalty. AI players have no profile. Standings show each human player's honor, infamy and wins in games.
- **Lobby settings:** `create_game` accepts `truce_ticks` (default 48, at least 1) and `grace_period_ticks` (default 24, at least 0); the create dialog has fields for both and the lobby page shows them.
- **Multi-stop routes (UI):** in march mode, previewing a first destination offers Start a route here; further castle clicks add stops (up to 10, each with an assault or siege choice and a remove button, drawn as a numbered dashed route on the map); Send route calls `send_on_route`. Only the first leg is validated by the server up front; later legs are planned when each stop is reached. A moving commander on a multi-stop route shows its stop list.
- **Battle reports:** each report now lists the experience the fight paid (`xp`: commander, ability, amount, level reached). `record_battle_report` leaves a transaction-local marker (`ss.battle_report`, report and tick) and `award_xp` appends valor, tactics, plunder and siegecraft awards that fall in the same tick to commanders named in that report. Intercept reports carry `location` (position and nearest castle), shown as "near X".
- **XP tuning:** `xp_base_cost` 1000 to 450, `muster_per_troop` 3 to 10, `steward_per_gold` 0.6 to 2.5, `scholar_per_prestige` 1 to 4. Rationale: `sim/xp_model.js` (now defaulting to the production base cost, with `BASE_COST`, `RANK_STEP` and `AFFINITY` overrides and survivor statistics) puts surviving commanders after a 30 day game at rank 8 to 10 (garrison leaders about 8 to 9, fighters about 10), 95th percentile 11 to 13, rank 15 or more rare, and the cap of 20 out of reach, where the old values gave about 4 to 6 and often under 3 for fighters. Measured in the real engine, a garrison leader paid about 15 / 7 / 12 XP per cycle for Muster / Steward / Scholar against the 60 each the model first assumed, hence the three garrison rate raises. A 250 tick AI-only game with the new values reached rank 4 with several 3s, no AI errors.
- **AI garrisons:** `ai_garrison` (called each AI turn after hiring) makes the idle non-king commander with the fewest troops at each ownerless-garrison castle its garrison leader, so AI commanders earn passive XP like players do (and are skipped by the AI attack loop).
- **Not done yet:** a custom email sender (needs a domain), XP tuning against real player data.

### 20ab. V1 completion: surrender, gold gifts, turn-based play, limits and lobby tools (implemented)

- **Concede and gifts (UI):** the Realm panel has Concede defeat (confirm; `concede_defeat`). Standings have Send gold for human players (modal; `send_gold`). An eliminated player keeps a read-only map with an "eliminated" notice; all order controls are hidden (`canAct`).
- **Turn-based games:** the create dialog offers Turn-based with ticks per turn (default 6) and turn timeout in minutes (default 1440). `turn_status(game)` returns the deadline, who has submitted and who is still waited on. The map shows a Submit turn button, then "Turn submitted, waiting for N players", and a countdown to the deadline. All humans submitting, or the deadline passing (cron), runs the turn and clears the flags.
- **Time limit:** optional `games.time_limit_ticks` (create dialog and lobby page). At the end of the tick that reaches it, if nobody has won, the game ends and the leader wins (most castles, then most troops, then lowest id) with reason `time_limit`; news reads "won the game at the time limit".
- **Lobby tools:** the host can remove players from a lobby (`kick_player`, lobby only, never themselves). Lobbies older than 7 days are deleted nightly (`cleanup_abandoned_lobbies`, cron `cleanup-abandoned-lobbies` at 03:17). The lobby page has a chat panel (`send_chat_message`, live on `game_chat`).
- **Touch:** the map supports two-finger pinch zoom (single-finger drag still pans).
- **AI defense:** `sally_out` is now a wrapper over `sally_core(game, player, territory)`. `ai_defend`, run each AI turn before `ai_commanders`, sallies from a besieged castle when a closed-form duel (siegers striking first) says the sally force wins; difficulty 1 and 2 hold back half the time.
- **Tick performance:** profiling a 4-seat all-AI game showed `ai_commanders` was about 90% of tick cost (~360ms per tick), because it called `is_friendly_territory` once per territory per edge for every idle commander. It now computes the friendly set, the frontier and the fallback-destination distances once per AI per turn (ownership cannot change inside the call). Tick cost dropped to ~110ms; the frontier was verified identical to the old query. Remaining cost is `plan_march` per candidate target (~1.3ms each).
- **Help, standings and leaderboard:** a "How to play" dialog (top bar and map HUD; opens once on a player's first map via localStorage `ss-help-seen`). `game_summary(game)` (players of a finished game only) returns final standings: castles, troops, battles, elimination tick, winner and end reason; shown by the "Final standings" HUD button on finished games. `get_leaderboard(limit)` returns profiles with at least one game ranked by honor, then wins; shown on the home screen. Both are security-definer RPCs granted to `authenticated`.
- **Automated tests:** `supabase/functions/start-game/generator.test.js` (run `node --test generator.test.js`, 11 tests) covers map generation. `supabase/tests/game_smoke.sql` is a database suite: paste it into the SQL runner (or `psql -f`); it builds a 4-seat AI game, runs 10 ticks, checks fog privileges, summary gating and leaderboard access, then deliberately raises `SUITE passed=N failed=M ...` so nothing persists. Expect `passed=7 failed=0`.
- **Abuse limits:** insert triggers cap a user at 5 games created per hour, 5 unfinished (lobby or active) games created at once, and 10 unfinished games joined (AI seats exempt). Chat and thread messages were already limited to 8 per 10 seconds. Limits are constants in `enforce_game_create_limits` and `enforce_game_join_limits`.
- **Auto-concede:** `game_players.last_active_at` (hidden from clients) is refreshed by `touch_activity(game)`, which the map calls on open and every 5 minutes while the tab is visible. An hourly cron (`auto-concede-inactive`) runs `auto_concede_inactive()`, which eliminates any human in an active game idle for 72 hours (reason `inactive`) and re-evaluates the game end. The smoke suite covers it (`passed=8`).
- **Mute:** each chat line from another human has a `mute` link; muted players' lines are hidden in General chat and message threads, and their messages stop counting as unread. A "Muted" row under the composer unmutes. This is client-side only (stored in localStorage per game and user), so it hides messages for the muter but does not stop the sender or other players seeing them.
- **AI sieges:** at difficulty 3 and above, when an AI commander finds a reachable frontier castle it cannot beat in a direct assault and has no winnable assault target, it sends a `siege` march at the best-scoring one (same score as assaults). `ai_sieges`, run each AI turn before `ai_commanders`, checks each AI siege and calls `fight_castle` once the same closed-form estimate (with the difficulty margin) says the assault wins, after starvation has thinned the garrison. Difficulty 1 and 2 never start sieges and hesitate half the time when ready. A rolled-back 150-tick game with 3 AIs (difficulty 4) produced 11 sieges, 6 battle reports and no AI errors.
- **Team assaults:** `resolve_assault` now gathers every assault-marching commander in contact with the same castle that belongs to the first-arriving player or to an ally of that player, and `fight_castle` fights them as one attacking side: troops add, damage uses the best Armory among the attackers' owners plus the best Valor, survivors are split by troop weight. The captured castle goes to the first-arriving (initiating) player; allied survivors end idle there. Every attacking and defending player involved gets the battle inbox message. Rolled-back test: a 12-troop commander plus an allied 12-troop commander with Armory 4 took a 20-troop castle, the castle went to the initiator, both survived with 8 troops each, and the damage used the ally's Armory. Limits: only allies of the initiator join (two attackers who are each allied to the initiator but not to each other do not fight together as one side beyond that rule); breaking a siege and open-field intercepts and reliefs remain individual. Victory stays individual (no shared allied win), by decision.
- **Mobile check:** the home and map screens were checked at 375x812 with a stubbed client: no horizontal overflow, map stacked above the side panel, whole territory cells are tap targets. Fix: on touch devices (`pointer: coarse`) buttons, selects and inputs are at least 44px tall. Not yet tried on a real phone.
- **Diplomacy v2 (non-aggression pacts, war declarations, marriage alliances, peace terms, trade, mediation):**
  - **Statuses:** `diplomacy.status` gains `nap`. `are_truced` treats `nap` like a truce (attacks blocked), `mark_war` leaves it alone, and `propose_alliance` treats it like neutral. `diplomacy.locked_until_tick` marks a marriage alliance.
  - **Offers:** a `diplomacy_offers` table (no client access; RPC only) holds pending offers of kind `nap`, `marriage`, `peace_terms`, `trade` and `mediation`; each expires after 24 ticks (`advance_offers`, every tick) and notifies the recipient through the inbox. `respond_offer(offer, accept)` answers, `withdraw_offer(offer)` cancels, `my_diplomacy_offers(game)` lists offers, active deals and locks.
  - **NAP:** `propose_nap` (neutral only), accepted gives `nap`. `break_nap` starts the same grace period as breaking an alliance (war after `grace_period_ticks`) and costs 10 infamy; a public `nap_broken` moment is written.
  - **War declaration:** `declare_war(game, target)` from neutral only, runs `mark_war(..., 'declared')`, which writes the public `war_declared` moment. Attacking a neutral still starts war automatically.
  - **Marriage:** `propose_marriage(game, target, lock_ticks 12 to 240)` between allies. While locked, `break_alliance_core` refuses; the AI never betrays a locked ally.
  - **Peace terms:** `propose_peace_terms(game, target, terms)` while at war. Terms: `payer` (`proposer` or `target`), `gold_now`, `tribute` per cycle for `cycles`, `give_territory` (proposer cedes) and `ask_territory` (target cedes). Castles must be held by the ceding player, not a capital, with no commanders in them and not besieged (`check_cedable`). Accepting moves the gold, creates a tribute deal, transfers castles, and sets a truce (`set_truce_core`).
  - **Trade:** `propose_trade(game, target, give, get, cycles)` when not at war; accepting creates up to two `gold_deals` rows linked by `offer_id`. `process_gold_deals` runs each production cycle: if either payer of a linked trade cannot cover their leg, both legs are cancelled and the defaulter takes 5 infamy (a tribute deal is a single leg); war cancels trade (not tribute); an eliminated party cancels everything linked. The AI only accepts a trade if the sender can cover their first payment.
  - **Mediation:** `offer_mediation(game, a, b)` by a third party creates one offer per side; when both accept a truce forms and a public `mediation_succeeded` moment is written; one decline withdraws the other.
  - **Reputation:** profile honor and infamy (already shown) now carry a Trusted, Unproven or Notorious word from `honor - 2 x infamy`. `player_reputations(game)` returns the same data as one RPC.
  - **AI:** `ai_offers` (each AI turn) answers pending offers: pacts by difficulty, marriage 40%, mediation 60%, trades if it receives at least what it pays, peace terms if it is paid or the cost is under 30% of its gold and no castle is involved. The AI does not originate these offers.
  - **Client:** Standings shows per-status buttons (pact, trade, declare war, break pact, marriage, peace terms), an Offers and agreements section and an Offer mediation button; News and the Proposals count include the new events.
  - **Tests:** `supabase/tests/diplomacy_v2.sql` (`passed=10 failed=0`). Not tested in a live game with two real players.
- **Military v2 (capture, named deaths, bulwark, promotion, smoother marches):**
  - **Capture:** a defeated commander is captured instead of killed with 30% chance (50% for a king) when the winning side has a living owner (`kill_or_capture`, used by castle battles, intercepts, reliefs and sallies; commanders lost any other way still die). A captive has status `captured`, no troops, and is held by `captured_by_player_id`. The captor can `set_ransom` (0 to 5000), `release_captive`, or `execute_captive` (kills, 5 infamy, public `captive_executed` moment). The owner can `pay_ransom` (gold moves to the captor, the commander returns idle with 0 troops at their capital or first castle). Each production cycle (`process_captives`) a captive escapes with 12% chance, is killed if its owner was eliminated, or is freed if the captor was eliminated. AI captors name a ransom of 60 + 30 x rank; AI owners pay when they hold the ransom plus 50. `get_game_view` returns a `captives` list (owner or captor only); captured commanders are not in `commanders`.
  - **Named deaths:** a king or a promoted commander who dies (not captured) costs their owner 60 prestige in the active area and puts `morale_until_tick` 24 ticks ahead. `morale_factor` multiplies troop and gold production by 0.75 while morale is low. Capture does not trigger it.
  - **Promotion:** `commanders.wins` counts battles won (via `award_combat_xp`); at 5 wins a plain commander is `promoted`: it gains an epithet in its name and +1 level (to the ability cap) in its school's lead ability (Valor, Steward or Scout). A promoted commander counts as named for death penalties.
  - **Siege defense track:** a new battleschool ability `bulwark` (Siege Defense, level cap and cost like the others). It replaces Siegecraft on the defending side: the garrison leader's Bulwark reduces starvation (0.5 percentage points per level), the leader earns Bulwark XP each production cycle under siege (`bulwark_per_cycle`), and a successful sally earns `bulwark_break_bonus`. Siegecraft is now the offense track; Valor and Tactics remain the field track. Existing commanders were backfilled with a level 0 Bulwark row.
  - **Client:** a Prisoners section in the Info tab, Bulwark in ability lists, News lines for captures and executions, and `renderDyn` runs four times a second while any army is moving so marches glide between ticks.
  - **Tests:** `supabase/tests/military_v2.sql` (`passed=10 failed=0`).
- **World v1 (seasons, mercenaries, random events):** all three are lobby settings (`seasons_enabled`, `season_length_ticks` 12 to 240, `events_enabled`, `mercenaries_enabled`; seasons and events default off, mercenaries on). Existing games are unchanged.
  - **Seasons:** the year is Spring, Summer, Autumn, Winter, each `season_length_ticks` long, starting in Spring at tick 0 (`season_of`). Winter multiplies troop production by 0.6 in the northern third of the map (y below a third of `map_h`) and 0.8 elsewhere (`season_troop_factor`) and march speed by 0.8 (`season_move_factor`, applied inside `march_speed` at launch). Autumn multiplies gold production by 1.15. The HUD shows the season and when it ends.
  - **Mercenaries:** `hire_mercenaries(game, castle, troops 10 to 60)` costs 5 gold per troop, creates a commander named "Company of ..." with that many troops, no abilities, and a 48 tick contract. At most 2 active companies per player. Mercenaries are never captured, cannot be promoted, and disband (die silently with their troops) when the contract ends (`expire_mercenaries`, every tick). The AI does not hire them.
  - **Random events:** with events on, each production cycle has a 40% chance to draw one (`draw_world_event`): 30% plague at a castle (open event: pay 60 gold within 6 ticks or lose 30% of its troops), 25% unrest at a castle (pay 80 gold within 6 ticks or lose half its troops and one infrastructure level), 25% bumper harvest (gold to the castle's owner), 20% comet (every living player gains 40 prestige). Open events are in `world_events` (RPC only): `my_world_events(game)` lists mine and `respond_event(game, event)` pays. Unanswered events resolve at expiry (`advance_world_events`). AI players answer an event when they hold at least twice its cost. All draws write a public `world_event` moment; plague and unrest also message the owner.
  - **Tests:** `supabase/tests/world_v1.sql` (`passed=10 failed=0`).
- **Council seats (named councillors):** the seven realm areas (Armory, Barracks, Mint, Library, Guildhall, Watchtowers, Stables) are the seven council seats. Every player gets one named councillor per seat when the game starts (an insert trigger on `realm_areas` creates `council_members` rows, which are RPC-only; existing games were backfilled).
  - **At court:** a seated councillor means the area works at its real level.
  - **Deploy:** `deploy_councillor(game, area, castle)` makes the councillor a commander (named as them, school by seat: Armory and Barracks battleschool, Watchtowers and Stables rangers, the others university) at one of your castles with 0 troops. The seat's real level is banked (`realm_areas.banked_level`) and the area drops to level 1, which is the floor, so every effect of that area reads level 1 (Guildhall influence is refreshed). Prestige still accrues while afield.
  - **Recall:** `recall_councillor(game, commander)` works when the commander is idle in one of your castles: their troops join the castle, the commander is retired without a death penalty, and the area returns to `greatest(level, banked_level)`.
  - **Death:** if a deployed councillor is killed (not captured), `councillor_fell` marks the member dead and the seat vacant. Councillors count as named, so the owner also takes the prestige loss and 24 tick morale penalty. A captive councillor's seat stays suppressed until they escape, are ransomed (then recall them), or die.
  - **Replacement:** `recruit_councillor(game, area)` costs 150 gold, seats a new named councillor at once and restores the banked level.
  - **Read:** `my_council(game)` returns each seat (area, level, banked level, councillor, status). `get_game_view` commanders carry `council_area`. The Info tab has a Council section (deploy with a castle picker, recall, recruit); the AI never deploys its councillors.
  - **Tests:** `supabase/tests/council_seats.sql` (`passed=10 failed=0`).
- **Real terrain (generator version 2):** new games get a generated landscape instead of a flat graph. Castle positions, tiers, ownership and the road graph are unchanged (so seats stay symmetric); terrain is built around them in `supabase/functions/start-game/terrain.js`.
  - **Generation:** land is a union of discs around castles and corridors along roads, with noisy coasts, so every castle and road is on land and the rest is ocean (inland bays and an outer sea). A height field (ridged noise, flattened near castles and roads) gives plains, hills and mountain ranges; a moisture field gives forest. Rivers start in high ground and run to the sea along a pit-filled flow field. A 192 by 192 grid of heights (two base-36 characters per cell) and moisture (one digit) plus the river polylines are stored in `games.map_art` (about 110 KB; readable by players, excluded from `get_game_view`, fetched once by the client). Twenty candidate terrains are built per game and the one with the smallest difference in terrain penalty between seats is kept (a pass costs a seat 2, a river crossing 1, a slow land link 1.5 per point of multiplier above 1, counted over links touching its starting castles).
  - **Castle terrain** (`game_territories.terrain`: plains, forest, hills, mountain, coast): about 12 percent of neutral tier 1 and 2 castles become mountain fortresses (raised onto a crag); starting castles are never mountain. **A mountain castle gives its defender +1 damage per strike** in castle battles (`fight_castle`), and the AI's attack and siege estimates account for it.
  - **Road terrain** (`territory_edges.kind` and `move_cost_mult`, which march planning already multiplies into distance): `pass` (crosses a mountain ridge) and `river` (crosses a river away from any castle, so a castle on a river is a bridge) are kinds; the cost multiplier is the mean terrain cost along the line (see the free travel section), so forest and hills slow a march continuously. Ocean is never crossable because roads only exist over land. Naval travel is not built.
  - **Client:** `paintTerrain` renders the terrain once to a canvas (ocean depth, beaches, grass, forest, hills, rock and snow with hillshading, tree and peak glyphs); `paintTint` overlays territory ownership, borders, selection and fog per territory; rivers and roads are SVG; castles are drawn as keeps (larger for higher tiers, banner in the owner's colour, a rock base for mountain fortresses). Clicks on ocean are ignored. Maps without `map_art` (games started before this version) keep the old circles-and-cells rendering.
  - **Tests:** `generator.test.js` (15 tests) covers determinism, unchanged positions and graph, castles on land, no starting mountains, edge costs, seat fairness and art size. The database path was checked with a rolled-back run (terrain, art and river edges stored, view omits `map_art`, mountain castles are tougher).
- **Big maps and free travel (generator, `world_scale` and `free_travel`):** new games default to `world_scale` 3 (castle spacing 450 instead of 150; options 1 to 5 in the lobby) and `free_travel` on. Games started earlier keep scale 1 and roads.
  - **Scale:** the generator multiplies spacing, margins and the map by the scale; castle counts per player are unchanged, so the map is much emptier. Distances in the rules scale with it: scan radii (`get_game_view`) and the intercept distance multiply by `world_scale`, and march speed is multiplied by `(1 + world_scale) / 2` (2x at scale 3), so a hop takes roughly one and a half times as many ticks as before. The client draws castles and labels at `world_scale` to the power 0.5 and opens centred on your capital, six spacings wide.
  - **No preset roads:** in a free-travel game `plan_march` takes the direct branch (`plan_march_free`): you can march a commander to any castle that has a link and lies within range, where range is `(210 + 60 x Stables level) x world_scale`. `territory_edges` holds every passable pair on the map, with no length cap (not a road graph; the AI and the client treat it as reachability), with its length, kind and terrain cost multiplier. The multiplier is the mean cost along the line (plains 1.0, hills 1.15, forest or wet ground 1.4, high foothills 1.4, mountain 2.0) plus 0.25 per river crossing, capped at 2.6. The client shows slow links as `slow xN`. Time is length x multiplier / speed (a built road between two castles that both have roads divides it by 3). A longer trip is a multi-stop route, one leg per hop. Out of range or no link returns an error naming the cause.
  - **Hard blocks:** the sea blocks a direct march. A river blocks a direct march unless the line crosses it at a ford, and a mountain range blocks it unless the line crosses at a pass. Fords and passes are generated (`art.fords`, `art.passes`, drawn as bridge and gap icons): every crossing the road graph makes is one, and any castle within about a fifth of a spacing of a river counts as a bridge. So to cross a river or range you travel to the strategic castle at the crossing first, then onward. Connectivity is guaranteed because the road graph's own crossings are all fords and passes.
  - **Client:** roads are no longer drawn except built roads between neighbours; selecting a commander in march mode dims castles you cannot reach (sprite and marker) and shows the range ring; once a route has stops, both the reachable set and the ring are measured from the last stop, and an out-of-range click names both castles; the castle panel lists castles within range with the crossing type.
  - **AI:** `ai_commanders` considers only castles within range that have a link, so it also respects the blocks.
  - **Tests:** `generator.test.js` (17 tests) adds scaled spacing and link checks; a rolled-back database run checked the direct plan, range, Stables, blocked pairs, `launch_leg`, and 90 AI ticks (3 sieges, no errors).
- **Deliberate V1 decisions (not gaps):** victory is individual, with no shared allied win.

---

*Source: `/Users/blaketaylor/Documents/Claude/Personal Game Code/Westeros/index.html` commit 483eb15. Distilled October 2026.*

### 20ac. Natural resources, roads as warp gates, Treasury (implemented)

Supersedes the tier and influence rules in sections 5 and 10 where they conflict.

- **Treasury:** the castle infrastructure that produces gold is `treasury_level` (was `gold_level`) and the lobby setting is `starting_treasury_level`. Gold stays the currency.
- **Natural resources:** every castle has `natural_resources` (1 to 60, was `base_influence`), and `resources` (was `effective_influence`) is natural resources plus 5 per Guildhall level, so Guildhall is the Terraforming tech: `resources = natural + 5 x level`. Upgrade cost is `base x (level + 1) / resources x infra_cost_mult` with bases 1250 Treasury, 2500 Recruitment, 10000 Prestige. The client draws a halo around each castle sized by natural resources.
- **Tiers follow resources:** 1 to 20 is Tier 1, 21 to 40 Tier 2, 41 to 60 Tier 3.
- **Standard start:** every seat starts with 4 castles with identical resources: a Tier 3 capital (50), a Tier 2 (30) and two Tier 1 (12, 12). Custom games may set 1 to 4 starting castles.
- **Neutral castles:** placed at random over the map (clumps and voids, only the home clusters are symmetric), with resources split 3 : 2 : 1 across Tier 1 : 2 : 3, values uniform inside each tier's range. Garrison is `starting_garrison x tier`.
- **Roads (warp gate logic):** a road is a per-castle build costing `30 x resources x infra_cost_mult` gold (richer castles cost more). A march between two castles that both have a road moves at `sqrt(Stables level + 3)` times the normal speed (about 2x at Stables 1, 3x at Stables 6). Range still applies: you cannot march to a castle outside march range, the bonus only changes the time. If either road is demolished while a commander is travelling the link, the remaining distance reverts to base speed immediately (arrival tick recomputed). Capturing a castle destroys its road. This applies to free-travel games.
- **Readout:** zoomed in, the map shows `Treasury / Industry / Prestige` above each castle's garrison.
- **Tests:** `supabase/tests/roads_resources.sql` (9 checks), `generator.test.js` (17).

### 20ad. Castle counts, continent map and no regions (implemented)

- **Castle counts:** map size is castles per player: compact 12, standard 24, large 36 (Neptune's Pride base is 24). Each player still starts with 4 owned, so a 4-player standard game has 96 castles (16 owned, 80 neutral). Supersedes the 6 / 9 / 14 presets in sections 16 and 17.
- **No regions:** ownership regions (Voronoi cells and borders) were client-only drawing; no rule used them, and they are gone on terrain maps. Ownership shows as a colored ring around each castle, and the gold ring marks the selected castle. Fog of war still uses scan rings and dims castles you cannot see. Games without terrain art keep the old cell drawing.
- **Continent land:** land is a noise-based continent filling the map (inland seas, lakes, ragged coast) rather than discs around castles. Small land patches around castles and narrow land bridges along the base road graph still guarantee every castle is on land and the map is connected. Mountain ridges cover about 12 to 20 percent of land.
- **Link cap:** in free travel, `territory_edges` holds passable pairs within 5 spacings (1500 links for 96 castles, about 5600 for a 288 castle map). This replaces "no length cap" in 20ab.
- **Generation cost:** the edge function has a CPU limit and a 96-castle game once failed with `CPU Time exceeded` (status 546), so terrain candidates are now 5 up to 60 castles, 4 up to 150 and 3 above, and the worst case measured locally is about 0.55 s of CPU.

### 20ae. Map shapes, dark fog and castle contrast (implemented)

- **Map shapes** (`games.map_shape`, lobby select): `continent` (noise continent, symmetric starts), `round` (near-circular landmass, symmetric starts, the balanced default), `ring` (land around a central sea, symmetric starts), `twin` (two lobes), `archipelago` (5 to 9 islands depending on players) and `rift` (a wavy sea splitting one landmass). Sea blocks marches, so shapes keep their parts joined: for twin, archipelago and rift only the 2 shortest, well-spaced crossing roads per pair of landmasses (3 for rift) are kept as thin land bridges. Twin, archipelago and rift place each start cluster (4 castles, identical resources) on its own part of the map by farthest-point spacing, alternating sides for twin and rift, instead of rotational symmetry; round, ring and continent keep rotational symmetry. The map area is sized per shape so castle density stays about the same.
- **Fog levels** (lobby select): No fog; Fog (`fog_of_war`: the whole map and every castle position is visible, but owner, troops and infrastructure only show inside your scan range, as before); Dark (`fog_dark` plus `fog_of_war`): the map is black until explored. Each human player has an `explored` string, a 48 by 48 grid of 0 and 1 over the map, refreshed by a trigger on every tick (and when the game starts) from the scan radius of their castles and armies, only ever growing. `get_game_view` then returns only castles that are in range or in an explored cell and returns `explored` to its owner. The client paints unexplored ground black, keeps explored terrain visible, and only updates castle details live inside scan range (last known owner is remembered). Terrain art is still downloaded in full and only masked in the client; castle positions, owners and armies are not leaked.
- **Castle markers:** each castle sits on a dark plate with a thick ring: yours (gold outer ring plus your color), other players (their color), unclaimed (grey), unknown (dashed grey). Troops are drawn large above and the name below, a legend sits at the bottom left, and the terrain is darkened slightly for contrast.
- **Spacing and clusters (20ae addendum):** each castle gets 2.4 times the land it used to (map radius up by about 55 percent), castles keep a minimum gap of 0.6 spacings (scatter) or 0.5 (continents), and a few strong density blobs gather castles into clusters and leave open stretches. On a 96 castle round map about 20 percent of the area is more than 1.3 spacings from any castle, the median nearest neighbour is about 350 units (270 minimum, up to about 1000 in the gaps), against 340 average and almost no gaps before. Castle plates on the map are smaller (radius 34, 28 and 23 by tier).

### 20af. Lobby settings, tech sharing, layouts and start choice (implemented)

Matches the Neptune's Pride create-game page where it makes sense for us. Defaults keep the old behavior.

- **Basics:** `victory_decay` (0 to 16 castles fewer needed per production, never below the larger of 2 and 15 percent of all castles; `game_standing` and the view's `win_at` use it), `password` (stored as a bcrypt hash in `games.password_hash`, joiners pass `p_password`, `has_password` is public), alliances `allow_alliances` (off means `propose_alliance` fails) plus the existing break warning `grace_period_ticks`.
- **Galaxy:** map sizes `tiny` 8, `compact` 12, `small` 16, `standard` 24, `large` 36 castles per player; `resource_richness` (sparse 6:2:1, standard 3:2:1, plentiful 2:2:2 of Tier 1 : 2 : 3 neutrals); `roads_mode` (`cheap` costs `6 x resources`, `expensive` 3 times that, `disabled`); `random_roads` (`rare` 10 percent or `common` 30 percent of neutral castles start with a road); starting castles up to 10 (starts after the first two are Tier 1 at 12).
- **Players:** existing `starting_gold`, `starting_garrison` (troops on each starting castle), starting Treasury, Industry and Prestige levels, `starting_commanders` and `commander_cost`; new per-type upgrade price `treasury_cost_mult`, `recruitment_cost_mult`, `prestige_cost_mult` (0.5, 1 or 2 in the lobby; applied in `upgrade_infrastructure_core`, bulk upgrades and AI spending).
- **Technology:** `terraforming_enabled` (off: Guildhall never levels and castles keep their natural resources), `experimentation_enabled` and `experiment_bonus_mult` (the Library's random research is 72 x level x the multiplier), `area_start_levels` (per area, 1 to 16) and `area_cost_mults` (per area research cost multiplier, 0 means no research; base advance cost is 144 x level x `area_cost_mult` x the area multiplier).
- **Trade:** `trade_cost` gold per level and `trade_requires_scan` (you can only trade with a player that has a castle inside your Watchtowers scan range, `can_trade`). `gift_tech(game, player, area)`: raises the other player's area by one level if you are ahead, you keep yours, you pay `trade_cost x new level`, their progress toward that level is lost; not available for disabled areas or at war.
- **Time:** `turn_fixed` (turn-based games advance only when the deadline passes and the next deadline is one duration after the last, even when everyone submitted), `production_cycle_ticks` exposed in the lobby, `auto_start` (a trigger on joins calls the `start-game` function through `pg_net` when every seat is taken; the function accepts that unsigned call only for auto-start games that are full).
- **Roads survive capture** (as warp gates do in Neptune's Pride); the earlier capture rule that destroyed them is gone.
- **Layouts:** `mirrored` (2, 4 or 8 players: neutrals come in groups of four mirrored on both axes with equal resources, home clusters sit in mirrored positions, and the terrain noise is folded so terrain is mirrored too; any remainder of neutrals past a multiple of four is placed freely) and `star_scatter = twin_rings` (about a third of neutral castles on an inner ring at resource 45, the rest on an outer ring at 18, evenly spaced; homes between the rings). Both force the round shape.
- **Start choice:** `start_selection = choose` (default `random`) with `pick_minutes`. `start_game` commits the world, stores each seat in `start_seats` (capital plus castles), leaves every castle unowned and sets the game to `picking`. Players call `pick_start(game, seat)`; `get_start_options(game)` returns seat markers (and all castles unless dark fog is on, when only the markers are returned). When every human has picked, or `finalize_due_picks` (cron, every minute) passes the deadline, `finalize_start` gives unpicked players the remaining seats at random (AI players included) and runs the per-player setup (gold, areas, commanders, diplomacy rows), then the game goes `active`. `start_game` now just commits the world and calls `finalize_start` or `begin_start_picking`.
- **Privacy fix:** members used to be able to read every castle (name, position, tier, resources, terrain) and every road straight from the `game_territories` and `territory_edges` tables, which defeated dark fog. Select on both tables is revoked; the client gets castles from `get_game_view` and roads from `get_game_edges`, which filters by explored cells in dark fog.
- **Fixture and tests:** `supabase/tests/fixtures.sql` defines `public.test_fixture_layout()` (a 12 castle, 2 seat layout) used by `lobby_settings.sql` (18 checks), `start_choice.sql` (13), and `roads_resources.sql` (9); `generator.test.js` (22) covers mirrored, twin rings, random roads, richness and sizes.

### 20ag. Trails, river castles and travel on the road network (generator implemented, engine and client not yet)

Neptune's Pride has no terrain: ships fly straight between stars. Here soldiers follow ground. This section defines the rules; the generator half is built (`generateWorld({ trails: true })`), the engine and client halves are the follow-up list at the end.

**Design rules**

1. **One network.** Every castle, including river castles, is a node on a single connected trail network. Trails are generated paths that bend around mountains, forests and water; they are not roads. The generator guarantees connectivity and fails the build rather than ship a map with an unreachable castle.
2. **Armies stay on trails.** A march has a start castle and a destination castle. The route is the cheapest path through the network by travel cost (trail length times its terrain multiplier, divided by the road speed bonus when that edge is roaded). The army walks the trails of that route, castle to castle. There is no straight-line march and no free travel in this mode.
3. **Roads upgrade a trail.** A road is built between two castles that share a trail edge, as today (cost `6 x resources`, speed `sqrt(Stables + 3)` between two roaded castles (trail-mode `plan_march` used a flat 3 until migration 20261023150000)). It follows the trail's path. A route's travel time is the sum over its edges, so a chain of roads makes a fast highway.
4. **Rivers are walls.** No trail crosses a river. The only way over is through a river castle. The river itself is never crossable on foot: no fords, no bridges except the one built into a river castle.
5. **River castles.** A river castle stands on the river with a fortified bank on each side and a bridge hall between them (the Twins). Rules:
   - Low value by design: Tier 1, 4 to 10 natural resources, a small starting garrison. They exist to be held for the crossing, not for production.
   - Neutral at the start, never a starting castle, never owned by seat assignment.
   - They are ordinary castles for ownership, garrisons, sieges and upgrades, with one addition: **a march may pass through a river castle only if the marching player or an ally owns it.** An enemy or neutral river castle stops the army there; it must be taken (a normal siege and battle) before anyone crosses. This is the chokepoint rule.
   - The edges at a river castle have `defense_mult` 1.25 (defending the bridge is easier) and are the only edges with kind `river`.
6. **Every castle stops a march (decided).** Any castle on a route that is not friendly (owned by the marcher or an ally) stops the army there. Combat resolves at that castle: the army is destroyed or wins and takes the castle. A route is built castle to castle; it may skip intermediate castles that are within range, but it is still castle to castle.
7. **Mountain passes (decided, generator change pending).** Mountains are impassable. Troops cross only through passes. A pass is a neutral castle-like node, like a river castle: low tier, held, and stopping non-friendly marches. The generator currently still emits `pass` edges across mountain runs; it must instead block mountain cells in the trail A* and place pass castles where a trail crosses a ridge.
8a. **Waypoint orders (decided).** A march is a chain of waypoint castles. Each waypoint has a delay and one action: Do nothing, Collect All, Drop All, Collect X, Drop X, Collect All But X, Drop All But X, Garrison to N. Quantities are never capped or failed: asking for more than the castle holds takes everything and the march continues. Orders run on arrival. A route can be set to loop (continuous resupply from backline to front); a looping route that meets a non-friendly castle resolves combat there like any march, and the loop ends if the army dies or the castle is taken and held by it.
8b. **Map presets (decided).** The host picks an Age of Empires 2 style preset that fixes which biomes, rivers and mountain passes appear. Not every map has every biome, rivers or mountain crossings. The generator takes the preset as input.
8. **Range.** The range ring is path distance along the network, not a circle. A castle's "reachable now" set is every castle within the path cost an army can cover before the ring's time limit, and the preview shows travel time as days and hours (travel is slow in this game; the prototype uses 10 map units per hour only as a placeholder).
9. **Fairness.** Map fairness already counts costly edges; river castles are counted as 1.5 per adjacent starting castle and passes as 2.

**Generator changes (implemented in `terrain.js` and `generator.js`)**

- New option `trails` (default off; legacy `freeTravel` layouts are unchanged and covered by a test).
- After rivers exist, candidate trail edges are all castle pairs within 1.9 spacings (plus the original base edges). An edge is dropped if it runs through sea. An edge that crosses no river is a free edge. An edge that crosses exactly one river becomes a river candidate: the crossing point is snapped to the river centerline.
- Connectivity: free edges are joined with union-find. Remaining river-separated groups are joined by the shortest river candidate that links two groups (Kruskal). If that is not enough, the closest pair of groups is joined with a chain of up to three river castles, one per river crossed. If sea cuts the map, the sea test is relaxed in steps (25 percent, then 60 percent of the line in water) so land bridges survive. If it still cannot connect, the world is rejected and another terrain candidate is tried (up to 6 more); after that generation fails with a clear error.
- Extra river castles are added only where the detour through the network would exceed twice the straight distance, at least 1.8 spacings apart from another, capped at about 10 percent of the castle count.
- Trails are a sparse spanner: a free edge is kept only if the network does not already reach its far end within 1.45 times its length.
- Paths: each edge gets a real polyline from an A* search over the terrain grid (rivers and sea blocked, mountains costly, forests and hills slower), smoothed. A path that would cross a river away from its own river castle, or is longer than 2.1 times the straight line, is replaced by the straight line if that is clean, otherwise the edge is dropped. `length` is the path length and `move_cost_mult` the average terrain cost of the path (1 to 2.6).
- Outputs: river castles appended after the normal castles (`crossing: true`, `river_idx`, `terrain: 'plains'`, Tier 1, 4 to 10 resources, garrison equal to the starting garrison), `edges[]` with `path`, `layout.trails = true`, `art.fords` = river castle positions, `art.passes` from the trail paths.
- Tests (`generator.test.js`): every castle joins one network, edges have paths and are deterministic, no path crosses a river except at a river castle, river edges are exactly the edges at river castles, river castles are Tier 1 neutral posts standing on a river with at least two edges, legacy layouts are unchanged. A sweep over all 6 shapes, 3 sizes, 2, 4 and 8 players and 2 seeds generated 108 of 108 connected maps; the 4 player large map gets 5 river castles, the 8 player large map 15.

**Still to build (engine, client, data)**

- **Data:** `territory_edges.path jsonb`; `game_territories.crossing boolean` and `river_idx int`; `start_game` and `get_game_edges` accept and return them; the `start-game` edge function passes `trails` (suggested lobby setting `travel_mode`: `trails` default, `free` legacy).
- **Engine:** `plan_march` and `march_commander` route over the edge graph with the rules above, a march stops at the first non-friendly castle on its route, and a trigger re-times marches when a road is built or lost on the route (already exists for roads). AI movement uses the same router.
- **Client:** draw trails from `path` (dirt tracks under the map), draw the route preview as the real route with total days and hours and the range ring as path distance, and show the river castle model (the 3D prototype has it).
- **Generator:** mountains impassable with pass castles (rule 7); map presets (rule 8b).
- **Engine and client:** waypoint chains with actions, delays and looping (rule 8a); the route builder shows the path-distance range ring re-centred on each waypoint.

### 20ah. Build plan: waypoint orders, passes, presets and Neptune's Pride UX (Phases 1 to 5 implemented; map-level client features not yet exercised by a signed-in player)

Findings from the Neptune's Pride live game: hourly tick vs 20-tick production cycle; carriers depart only on the hour; the route builder re-centres the range ring on each waypoint and shows cumulative ETA; each waypoint has delay and action (default Collect All, amount field only for numeric actions); looping is one toggle; build-carrier dialog picks how many ships to load; standalone combat calculator; Analysis (group players by colour or shape); Intel charts; Leaderboard with victory progress and concede; settings review; Options (map text zoom, default action); Recorder history; Inbox (Bulletin, Diplomacy, Events); host admin (pause, jump ticks).

**Phase 0, decisions:** whether the tick and production cycle are split (check 20n); commit the uncommitted UI work; keep or delete `proto-3d.html`.

**Phase 1, generator:** mountains impassable; neutral pass castles (Tier 1, low resources) where a trail crosses a ridge; host-picked map presets (Continental, Highlands, River Valley, Archipelago, Plains) that fix biomes, rivers and passes; tests for connectivity across every preset, size and player count, and no path crossing a ridge except at a pass.

**Phase 2, data and engine:** migrations (`territory_edges.path`, `game_territories.crossing`, `river_idx`, pass flag, `travel_mode` and `preset` settings); edge function passes `trails` and `preset`; march router over the edge graph where a non-friendly castle stops the army and combat resolves there; waypoint orders table (route, sequence, castle, delay, action, amount, loop) executed on arrival and never capped; hour-tick departures; AI uses the same router.

**Phase 3, client:** draw trails and passes; route builder with path-distance range ring re-centred per waypoint, cumulative ETA, per-waypoint editor, Save / Save & Edit / remove last / cancel; stack list of garrison and armies per castle; build-army dialog with ship slider; loop toggle.

**Phase 4, UX:** combat calculator; Analysis screen; Intel charts; Leaderboard with victory progress and concede; settings review at start; Options (text zoom, default action, audio, UI position); recorder history; Inbox tabs; host admin (pause, jump ticks).

**Phase 5, lobby settings:** stars-for-victory percentage and decay, tick rate, production ticks, starting stats, per-upgrade costs, natural resource level, road cost, dark galaxy.

**Unverified:** NP fog and scanning view when zoomed out; keyboard shortcuts; behaviour across a real tick.

**Phase 1 as built (generator, `terrain.js` and `generator.js`)**

- Mountains are walls in trail mode: cells above the mountain height are blocked in the trail A* (castle plates are opened). A candidate trail whose straight line crosses exactly one mountain run becomes a pass candidate, using the same connect, chain and extra-crossing logic as rivers. Chains may mix river and pass barriers (up to 4), and the chain fallback reaches castle pairs up to 5.6 spacings apart.
- A pass castle sits at the lowest point of the ridge along the candidate line. The heightfield is carved into a smooth gap along its approach so the ridge visibly opens there. Pass castles are neutral, Tier 1, 4 to 10 resources, named `<Name> Pass`, with `crossing: true` and `crossing_kind: 'pass'` (river castles carry `crossing_kind: 'river'` and keep `river_idx`). Edge kinds are `river` or `pass` at those castles and `land` everywhere else. `art.passes` is now the pass castle positions and `art.fords` the river castle positions.
- Presets (`preset` option, default `continental`, unknown values rejected): `continental` (rivers 1, mountains 1), `highlands` (rivers 0.6, mountains 1.3, drier), `river_valley` (rivers 2, almost no mountains), `forest` (wetter, few mountains), `plains` (no rivers, no mountains, no crossings). Mountain strength and river count scale per preset, and `plains` also skips mountain fortress castles.
- Tests: 29 pass, including trails stay below the ridge height except at castles, pass castle properties, every preset connected, plains has no rivers or crossings, highlands has passes, unknown preset rejected. A sweep of 5 presets x 6 shapes x 4 sizes x 2 seeds generated 240 of 240 connected maps, slowest 0.8 s.
- Not yet wired: the edge function and lobby do not pass `preset` (Phase 2, needs a `map_preset` column); `crossing_kind` is not yet stored in the database or drawn by the client.

**Phase 2 as built (data and engine; migrations `trails_and_presets`, `route_orders`, `route_looping_column`, all applied)**

- Games have `map_preset` (continental, highlands, river_valley, forest, plains) and `travel_mode` (`free` default, `trails`). `create_game` accepts both; `travel_mode = 'trails'` forces `free_travel` off so the existing path-based movement engine is used over the trail edges.
- `territory_edges.path` (polyline), `game_territories.crossing_kind` ('river' or 'pass') and `river_idx` are stored by `commit_world`. Crossing castles are excluded from the neutral-divides-evenly-among-seats check. `get_game_edges` returns `path`; `get_game_view` returns `crossing_kind` per castle.
- Trail travel tuning (changeable in `march_speed` and `plan_march`): march speed is multiplied by `world_scale` (one hop about 9 to 22 hours at normal tick speed), and a multi-hop route is in range if its length is at most `(300 + 120 x stables) x world_scale`, which lets a commander skip about one intermediate castle at level 0. Single hops are always in range.
- The existing engine already stops every march at the first non-friendly castle (`plan_march` does not expand past one, `advance_movements` stops there and starts the battle), so "every castle stops" needed no change.
- Waypoint orders: each stop carries `action` (nothing, collect_all, drop_all, collect, drop, collect_all_but, drop_all_but, garrison), `amount` and `delay` in ticks. Actions run on arrival at a castle the commander owns, never fail for lack of troops (they move what is there), and a delay holds the commander until `resume_routes` releases them on a later tick (called from `run_tick`). `send_on_route(game, commander, stops, march_type, options)` takes `options` with `loop` and `origin_order` (the action run each time the route returns to its start). `set_route_loop` toggles looping on an active route. A looping route needs a last stop that differs from its origin. Routes live in `commander_routes` (`looping`, `origin_order`, `resume_tick`).
- Tested in a rolled-back database transaction: collect, garrison with a delay, resume on tick, return to origin with drop_all, and restart of the loop all behaved as specified. `commit_world` accepts a trail layout with passes and rivers (21 castles, 21 edges with paths).
- Not done: deploy of the `start-game` edge function (sends `trails` and `preset`; default games are unaffected until it is deployed), client lobby settings, and the client route builder (Phase 3).

**Phase 3 as built (client `index.html`, edge function deployed as version 13, migration `route_replaces_route`)**

- Lobby (Realm step): `Terrain` (the five presets) and `Travel` (castle trails default, or free travel). The Articles of war panel shows both. `GAME_COLS` includes `travel_mode` and `map_preset`.
- Trail map: in trails games every edge is drawn from its `path` as a dirt track with a dark edge (gold on a road, dashed on a pass). Crossing castles are drawn smaller. A castle panel explains river crossings and passes and lists "Trails to".
- Route builder: the range shows as every castle reachable by path distance from the commander (or from the last stop), ringed in gold, with unreachable castles dimmed. Reach follows the server rule: routes pass only through castles you or an ally own, an enemy or neutral castle can be the end of a leg, a single hop is always allowed, and a longer route must fit the range `(300 + 120 x stables) x world_scale`. Each added stop is checked against the previous stop, and the route is drawn along the real trails.
- Each stop has an action (the eight actions), an amount and a wait in ticks, shown for castles you own; the default action is Do nothing. Each stop shows its arrival offset in ticks, and the route shows the total time. A Loop checkbox adds an order for each return to the start castle. Sending uses `send_on_route` with `p_options`.
- Active routes: the commander panel lists the stops with actions and waits, highlights the current stop, and has Loop route / Stop looping (`set_route_loop`). A commander waiting out a delay shows when it resumes and has Cancel route. Starting a new route cancels any older active route.
- Verified: the edge function started a real two-player highlands trails game on its own (20 castles including 4 passes, 21 edges all with paths); `plan_march` gave 10 to 16 tick hops at speed 52.5 and range 1260 at scale 3. The test game was deleted. The page loads with no console errors. The new client code has not been run by a signed-in player.

**Phase 4 as built (migration `host_tools_and_replay`, client `index.html`, `styles.css`)**

- HUD **Menu** button opens a list: Empires, Intel, Battle calculator, Game rules, Replay (finished games), Host tools (host of an active game), Options, How to play.
- **Battle calculator:** castle assault (defender strikes first with +1 damage) or open field (initiative picks who strikes first), using the 20p and 20q formulas: survivors for the side that needs fewer rounds, an undefended castle always falls, a side with no troops loses. Checked against hand calculations (30 vs 20 at damage 1 leaves the defender 6; at attacker damage 2 the attacker wins with 10).
- **Empires:** castles, progress toward the victory target, relation (You, Allied, Truce, offers, At war), troops seen in castles you can see, an eliminated mark, and Concede defeat with a confirmation. This replaces the NP leaderboard and ledger-style standings.
- **Intel:** line charts per house for castles, troops, gold, commanders and infrastructure, read from `intel_snapshots` (one point per production cycle). The existing database policy only returns rows after the game ends or in games without fog, so the dialog says when charts are not open yet. Alliance grouping by colour or shape from NP is not built.
- **Game rules:** the lobby's Articles of war panel is now one shared function and is also reachable in game.
- **Options:** default order for new route stops (default Do nothing), side panel left or right, sound. Stored in the browser (`ss-prefs`). Map text zoom thresholds from NP are not built.
- **Host tools:** `games.paused_at`; `admin_set_paused` stops ticks and, on resume, shifts the tick clock so the countdown continues; `process_game` returns without ticking while paused. `admin_jump_ticks(game, 1 to 5)` runs ticks at once, only for the host and only when no other human is in the game, and writes an `admin_jump` event. The HUD shows a Paused tag and "paused by the host".
- **Replay:** `territory_owner_log` records every castle's owner by tick through triggers (inserts and owner changes); `get_replay` returns it only to members of a finished game. The client replays ownership with a slider, play and exit controls. Games started before this migration have no log, and the client says so.
- Tested in rolled-back transactions: the log records a capture in the same tick, a paused game processes no ticks, resume clears the pause, a jump of 2 advanced the tick (the one-castle test game ended on the first tick). Browser: the calculator (both modes), options, menu, a sample chart and a sample Empires table render correctly. The map-level dialogs and the replay bar have not been run in a live game.
- Not done: the NP inbox tabs (the game already has reports, news, inbox and chat tabs), map text zoom thresholds, alliance grouping in Analysis, and an automatic rules review when a game starts (the rules are one click away in the Menu).

**Phase 5 as built (migration `home_distance_and_wormholes`, generator, edge function version 14, lobby)**

- **Audit:** most of the NP settings list already exists in the lobby (victory percent and decay, tick speed, production cycle, starting levels and costs, per-area research costs, richness, roads mode, dark fog, trade cost, terraforming, experimentation). Phase 5 therefore adds only what was missing:
- **Home distance** (`home_distance`: close, medium, far): shifts where capitals sit as a fraction of the map radius by -0.18, 0 or +0.2 (clamped to 0.25 to 0.92). Applies to round, continent, ring, mirrored and twin-ring starts; twin, archipelago and rift place houses by island or side and ignore it. Medium reproduces every existing map exactly.
- **Wormholes** (`wormholes`: none, rare, common; castle trails only): `ceil(castles / 40)` or `ceil(castles / 16)` links between neutral, non-crossing castles at least 4 spacings apart, at most one per castle. Each is an edge of kind `wormhole` with a straight two-point path, defense 1, and a cost that makes the trip take 24 ticks at base trail speed regardless of distance. They ignore range for a single hop. They are drawn as a violet dotted line.
- The `territory_edges` kind check now allows `wormhole`; `create_game` accepts both settings; the lobby has Home distance and Wormholes selectors; the Articles of war list them.
- Tests: 31 pass (close < medium < far capital radius on continent and mirrored round maps; wormhole links are neutral, distant, unique, 24 ticks, deterministic, leave every other edge identical, keep the map connected). A sweep of close and far homes with common wormholes over 6 shapes, 4 sizes and 2 seeds built 96 of 96 connected maps (about 9 wormholes each, slowest 0.5 s). A real two-player game (far homes, common wormholes) started through the deployed function with 2 wormholes costing exactly 1260.
- **Not built:** anonymity (names also appear in chat, so a partial version would mislead) and NP's scan-and-range or banking variants, which our tech tree does not use.

**Map preview in the lobby (client only)**

- The Realm step of the create dialog shows a live preview of the map. It runs the real `generateWorld` from `supabase/functions/start-game/generator.js` in a module Web Worker (so the page stays responsive), then paints it with the in-game terrain painter and overlays trails, wormholes, river castles, passes and each house's castles in its own colour (white ring on capitals). It reruns 450 ms after any relevant setting changes.
- **New map** picks a new seed. The previewed seed is sent as `world_seed`, so the game generates the same map the host saw. This holds only while the repo's generator matches the deployed edge function (redeploy after any generator change), and the preview assumes every seat fills (with AI fill off and fewer players joining, the map differs).
- Not built: picking a location on the preview to shape the terrain (the Age of Empires 2 idea); presets stay the way to choose terrain.

**3D map view (optional toggle, client only; `map3d.js`)**

- The HUD has a **3D map / 2D map** button. 2D stays the default; the choice is remembered per browser (`ss-view3d`). The 3D view loads on demand, so 2D players never download three.js (pinned `three@0.160.0` from jsDelivr via an import map).
- `map3d.js` is the prototype turned into a module (`createMap3D(host, spec)`), now driven by real game data instead of an embedded map: terrain from the game's `map_art`, roads drawn from each edge's real trail path, river castles built as twin bank fortresses at the river crossing, pass castles as gate forts, wormholes as violet arcs, castle banners coloured by owner with live troop counts, and armies that walk the real trails.
- It reuses the 2D game's logic for everything else: clicking a castle runs the same `select`, so the side panel, route builder, orders and menus are unchanged. The 2D map pushes reach rings and the planned route into the 3D view as ribbons.
- Controls: left-drag pans, right-drag rotates, wheel zooms; Tilted and Top-down camera, shadows and occlusion toggles; frame rate 60 on a compact map; build time about 1.3 s there. A lighter mode is used below 900 px wide.
- Also fixed in 2D: marching armies and the march line followed straight lines between castles; in trails games they now follow the trail paths.
- Tested in the browser against a real game's data (30 castles, passes, trails, an army, the route builder, 2D/3D toggling) and against a generated river-valley map with 3 river castles and 2 wormholes. Not tested: phones, very large maps (8 players, large), fog games, replay mode in 3D (the replay bar shows ownership only in 2D).

**Bigger maps (lobby map scale)**

- The lobby's Map scale now runs from Classic 1x to Titanic 6x, with **Colossal 5x as the new default** (it was Vast 3x). Castle spacing is `150 x scale`, so 5x puts castles about 67% further apart than before; castle models stay the same size, so there is more land between them. Nothing in the database limits the scale.
- Game pace does not change with scale: in trails games march speed is multiplied by the scale, so a hop still takes the same number of ticks, and range and scan radii scale too.
- A sweep of scales 5 and 6 over every shape, four sizes and two terrain presets built 96 of 96 connected maps, each in under 0.7 s. The largest map (8 players, large) is about 35,000 units wide at 5x and 42,000 at 6x.
- 3D at that size is the open question. On a 333-castle, 35,000-unit map the 3D view built in 18 s and ran 28 to 42 frames per second right after its terrain tiles finished loading, then dropped to about 1 in the test pane (cause not found). Maps with more than 200 castles now open 3D in its lighter quality mode, and a 2D fallback is always one click away.

**AI regrouping, terrain-only preview, anonymity, map text zoom and alliance groups**

- **AI stall fixed** (migration `ai_regroup`): an AI commander with fewer than 6 troops used to be skipped forever, so an AI whose only free commander sat in a castle with a garrison at or below its reserve never moved. Now such a commander marches to the owned castle with the largest garrison it can reach (needing `garrison - reserve + carried >= 6`), collects there and continues. In a test game the AI took a castle by tick 46 and a pass by tick 90 with a 42-troop commander in the field, and had no tick errors. The AI still keeps two commanders as garrison leaders, which keeps it cautious.
- **Lobby preview shows terrain only**: land, sea and rivers. Castles, trails, passes, wormholes and house colours are no longer drawn, and the terrain painter is not given castle positions. The status line gives only the castle and river counts and the map number.
- **Anonymity** (`games.anonymity`: normal or extra, set in the Rules step): when a game with Extra leaves the lobby, every human's display name is replaced by their faction name (real name kept in `game_players.real_name`) so every view, inbox message, report and chat line uses it; a trigger restores real names when the game finishes. `get_game_view` also hides other players' `user_id` while it is on, which removes their reputation stats from the standings. It is soft anonymity: a technical player could still read `game_players.user_id` and profiles through the API, AI players still carry an AI tag, and honor and infamy are hidden only through the view.
- **Map text zoom settings** (Options): castle name plates and troops, army troop counts, and castle upgrade levels each show Always, When zoomed in (view under 50% of the full map), Only when close up (under 25%) or Never. Stored in the browser and applied at once.
- **Alliance groups** (Empires dialog): each house can be put in a coloured group (Crimson, Azure, Emerald, Amber, Violet). A Group strength table sums castles (with progress toward the victory target and share of all castles) and troops seen per group; Group my alliance puts you and your allies in Azure; groups are private notes kept in the browser per game.

**Wormholes removed** (migration `remove_wormholes`)
- The `wormholes` setting, the wormhole edge kind and the Wormholes lobby selector are gone from the generator, edge function, `create_game`, lobby, map views and 3D view. `territory_edges.kind` allows land, river, pass and sea only, and `games.wormholes` is dropped. The Phase 5 notes above that describe wormholes no longer apply.

**Anonymity hardened** (migrations `harden_anonymity`, `revoke_player_user_id`)
- Signed-in users can no longer read `game_players.user_id`. The client gets what it needs from `room_players` (flags `is_me`, `is_host`), `my_games`, `get_game_view` (`is_me` per player) and `player_reputations` (keyed by player id).
- In an anonymous game that has not finished, `player_reputations` returns only the trust word (Trusted, Unproven or Notorious), never honor, infamy or win counts, because those numbers could be matched against the public `profiles` table. `room_players` hides the host flag in the same case.
- Eight row-level policies that looked up `game_players.user_id` directly now call the helpers `is_my_player` and `my_player_id`, which run with definer rights.
- Still visible: `games.created_by` identifies the host (the host is public in the lobby anyway). Recognising someone by play style or chat cannot be prevented.

**Friends** (migration `friends`)
- Each profile has a `friend_code` (8 characters from an unambiguous alphabet, shown as `XXXX-XXXX`) and `stats_visibility` (`friends` default, or `public`). `profiles` is now readable only for your own row; other players' stats come through functions.
- Table `friendships` (pending or accepted, one row per pair) has no client access. Functions: `my_social`, `set_stats_visibility`, `friend_request_by_code`, `friend_request_from_game` (finished games only), `respond_friend_request`, `remove_friend`, `list_friends`, `friend_profile`. A request sent to someone who already requested you is accepted at once. Limit: 30 pending requests.
- `friend_profile` shows honor, infamy, games, wins, favorite house and the last 8 finished games only, so a friend cannot learn which seat you hold in an anonymous game in progress.
- `get_leaderboard` lists only players whose `stats_visibility` is `public`.
- Not built: blocking, lobby invites, "friend is hosting" tags.

**Invites and visibility** (migration `invites`)
- `games.visibility` is `open` (listed for everyone), `friends` (listed for the host's friends) or `invite` (listed only for invited players and members). Every game has a unique `join_code` (`XXXX-XXXX`, eight characters from a 32-letter alphabet, generated with pgcrypto); the column is not readable by clients, only through `game_invite_info` (host) and `lookup_game_by_code`.
- `game_invites` has no client access. Functions: `invite_friend` (host, friends only, 20 per game), `my_game_invites`, `decline_game_invite`, `lookup_game_by_code`, `join_game_by_code`, `game_invite_info`.
- `join_game` now refuses non-open games unless the caller is the host, was invited, is a friend (friends games) or arrived through `join_game_by_code`. The code path sets a transaction-local setting that clients cannot set.
- `list_open_games` honours visibility. Share links look like `#join=ABC-123`; the client keeps the code across sign-in and opens the join dialog on the home screen.
- Wrong-code guesses are limited: more than 15 misses in 10 minutes blocks `lookup_game_by_code` and `join_game_by_code` for that user. A miss returns an error object (lookup) or null (join) instead of raising, so the failure is recorded in `join_code_failures` (no client access). Friend codes use the same generator.

**Setup overhaul** (migration `setup_overhaul`, start-game v15)
- Setup is five steps: Table (name, seats, who can join), Realm (with a live preview), Rules, Houses, Time. Every option has helper text and picture cards, steppers and switches replace most drop-downs. No templates.
- Seats: each seat is a player or an AI. AI seats are real `game_players` rows created at setup (`add_ai_seat`, `set_ai_seat`, `remove_ai_seat`; host only, lobby only), each with its own `ai_difficulty` 1 to 5 (Squire, Knight, Baron, Duke, Warlord: every AI acts every tick; strength sets decision quality). `run_ai_players` and `ai_take_turn` read the per-seat value. The host can change seats from the lobby; an empty player seat at start is dropped. `fill_with_ai` is no longer used.
- Defaults: production cycle 24 ticks, season length 96 ticks. New tick speed `blitz` (5 minutes); `quad` is shown as Rapid. Starting-location choosing is removed from the UI (starts are preset). Experimentation is always on; Terraforming is shown as "Land improvement".
- Shapes: twin continents, archipelago and the rift are built from lumpy overlapping blobs instead of circles, and the rift allows 5 crossings. The start-game function retries up to 6 seeds if a map cannot be connected.
- Fixed: an auth event while the setup form was open sent the user home and wiped the form.

- Setup hides seasons, random events and mercenaries: new games always send them off. The mechanics remain in the engine for a later release. Starting upgrade levels are no longer set in setup (castles keep their own levels). Guildhall and Watchtowers carry an Optional switch in the Realm areas list; off sets that area's research cost multiplier to 0, and Guildhall off also turns off terraforming.

- Road speed fix: trail-mode `plan_march` now divides roaded edges by `sqrt(3 + Stables)`, matching free-travel mode and the spec. Road build cost is `6 x castle resources x infra_cost_mult` (expensive x3), so richer castles cost more.

- **Junction nodes (crossroads), trails mode only.** Trails prefer to reuse existing corridors (cost x0.35 on shared cells), so paths merge and split. Where three or more trails meet away from a castle, the generator makes a junction: a `game_territories` row with `is_junction = true`, named Crossroads, ownerless, no garrison, no production, never capturable. Trails are then stored as segments between nodes (castle, crossing or junction), so a castle usually has 1 or 2 roads and a crossroads has 3 or more. Generator output marks them `junction: true`; `commit_world` stores `is_junction`. Avg about 4 to 5 junctions on a standard 4-player map, none guaranteed.
  - **Marching:** `plan_march` treats junctions as friendly passable nodes (never a destination). `advance_movements` never stops or makes contact at a junction. `in_range` and `hops` count castles only, so a march between two castles across a junction is always in range, like a direct road. Road speed uses `sqrt(3 + Stables)` on a segment when its castle end has a road (junctions count as roaded).
  - **Counts:** `game_standing` and `get_game_view.territory_total` exclude junctions, so victory thresholds are unchanged. `get_start_options` hides them.
  - **AI:** the frontier is computed through junction chains (`ai_commanders`), so AIs target the castles beyond a junction.
  - **Not changed:** armies cannot stop at, garrison or fight at a junction, and world events still pick from all territories (events are off). Roads are still per castle.
  - **Client:** 2D draws a crossroads marker (drawn above the trails) and skips junctions in castle drawing, voronoi and terrain placement. 3D builds a signpost with no label or selection. Castle panel "Trails to" lists castles reached through junctions, with summed length.

- **Placement and trail balance (trails mode).** Neutral castles are placed by best-candidate sampling: each new castle is the best of up to 14 valid random points, scored by distance to its nearest neighbour (capped at 0.95 spacing) plus a small bonus inside a few soft clusters (`clump x 5 x spacing`). This replaces the old rejection sampling around heavy Gaussian blobs, which left some regions crowded and others empty (nearest-neighbour spread 0.37 to 0.18, local density ratio 4.5 to 2.8).
  - **Greedy spanner:** a candidate road between two castles is built only if the existing roads would otherwise take more than 2.0 times the straight distance (`SPAN`). Roads that cross one river or one ridge become a ford or pass castle only when the detour would exceed 2.4 times (`CROSS_SPAN`), and such a crossing may bend the road by at most 1.4 times. Free roads are decided first, then crossings. A castle left with a single road gets a second one if a neighbour within 1.6 spacings lies at least 40 degrees away from the first road.
  - **Result over 36 standard maps:** typical route 1.3x a straight line, ninetieth percentile 1.75x, about 5 percent of castles with one road, average 2.8 roads per castle counting crossroads arms, about 17 crossing castles per map (was 56 under an uncapped spanner and 17 under the old 10 percent cap with 22 percent dead ends).
  - **Terrain:** mountain ridges are thinner (`smoothstep(0.92, 1.02, ridge)` for the continental preset, scaled by the preset) and there are fewer rivers (castles / 5.5 times the preset factor). Trail corridors still share cells (`SHARE` 0.2), so roads merge and split at crossroads.
  - Games created before this change keep their old maps.

- **AI staging (migration 20261023170000).** `ai_commanders` used to skip every target outside one march's range and then park the commander at the home castle nearest to any non-friendly castle. Once the targets near home were taken, the AIs sat idle with thousands of troops in garrisons while weak neutral castles 40 to 60 ticks away stayed free (soak test: castles frozen from tick 450 to 600 with gold piling up). Now the best beatable target outside range is remembered (`v_far`), and the commander marches to the first castle (not a crossroads) on the route to it, one hop per turn, attacking once the target is in range. Targets inside range are chosen first, as before.
- **Soak test findings (AI-only games on trails maps, run tick by tick in throwaway games on the live database and deleted afterwards):** no `ai_error` events in any run (about 2,300 ticks across four games). A 2-player Warlord game on a 25-castle map ended by victory at tick 307. A 4-player game (Squire, Knight, Duke, Warlord, 137 castles) grew steadily to 124 of 137 castles owned by tick 800, with the strengths ordering correctly (Warlord 37, Duke 31, Knight 30, Squire 26) and then stalled with 0 new battles in 50 ticks: only enemy castles remained and each side's garrisons (about 170 troops per castle) outweigh the 100 to 250 troops the AI commanders happened to carry. There is no cap on commander troops (the only constraint is troops >= 0); the AI keeps its armies small because it only draws the garrison of the castle it stands in, so the stall is an AI massing problem, not a rule. Tick cost grows with the world: about 0.13 s per tick at 25 castles, 0.5 s at 137 castles with 4 AIs and 1.5 s at 154 castles with 6 AIs (the AI step is about 70 percent of it, roughly 85 ms per AI turn). No victory is forced: with victory decay 0 and no time limit, a late-game stalemate does not end by itself.

- **Commander troop limit:** none. A commander can carry any number of troops. This is a design rule, not just current behavior: do not add a cap.

- **AI strategy pass (migrations 20261023180000 to 20261023210000).** Research basis: community guides and war diaries for Neptune's Pride (IHG forum strategy guides, Triton Codex notes, the Game Developer analysis, fan write-ups). The transferable principles: expand fast to near neighbours and keep a garrison on every castle (defender strikes first and with a bonus); compute the battle before committing and only attack when it wins; keep a steady flow of troops to the front instead of fighting with whatever is nearby; strike the largest threat rather than the nearest castle you can beat; alliances are cover, and the winning move is a timed betrayal when expansion runs out; fight where the opponent's reinforcements are far away. Not implemented yet from that list: supply loops that feed the front, threat-sized garrison reserves, chokepoint and capital valuation, early all-in expansion economics.
  - **Field commander guarantee:** `ai_garrison` no longer assigns the last free (non-king, non-garrison) commander to a castle, and `ai_hire` wants `min(2 + difficulty, max(3, castles / 2 + 1))` commanders and hires whenever no free field commander exists. Before this, a house that lost a commander could end up with every commander on garrison duty and never leave its 3 starting castles (seen: 3 castles, 411 unspent gold, tick 100 to 400).
  - **Allied-castle commanders:** `ai_commanders` now also manages idle commanders standing in an ally's castle (they cannot draw that castle's garrison). Staging hops can end in an ally castle, and those commanders used to be stranded forever.
  - **Massing:** when no target is beatable with the current army, the AI computes the troops the weakest (or highest priority) target needs and, if the rest of the realm's spare garrison covers it, sends the commander to the castle with the most spare troops, hop by hop, where it draws the garrison and tries again. Armies went from 35 to 90 troops to 360 to 1,265.
  - **Target priority:** a target owned by the current leader (when the leader has more castles than the AI) scores +4, one owned by a house at war with the AI +3. Massing aims at priority targets first.
  - **Strategic betrayal:** once at most 15 percent of castles are neutral, each AI of difficulty 2 or higher has a per-turn chance (0.4, 1, 2, 4 percent for difficulty 2 to 5) to pick a victim among neutral and allied houses it can match (own total troops at least 0.7 x theirs) and break the alliance if the victim is an ally. Victim score = 6 x victim castles / win threshold (strike the leader) + 3 x relative troop advantage - distance - 1 if allied + noise. Marriage-locked alliances are never broken. War with a neutral house needs no declaration: the AI simply attacks.
  - **Result (4 AIs, 48-castle map):** a stalled game (every house allied, 1 battle in 100 ticks, 1,000 to 2,000 troops idle in garrisons) became an active one (allied pairs 5 to 1, battles +17 in 125 ticks, castles changing hands). A full game still takes 900+ ticks, over 37 days at Normal speed, with the leader at 24 of 31 needed.

- **Threat-sized garrisons and chokepoint value (migration 20261023220000, generator in `start-game` v20).**
  - **Reserve per castle:** the AI used to keep a flat `8 - difficulty` troops in every castle and send the rest to the field. Now `ai_commanders` computes a reserve for each of its castles once per turn: base + `0.15 x` the garrisons of enemy castles one road away (through crossroads) + `0.35 x` the troops of enemy commanders idle in those castles + `0.8 x` the troops of enemy commanders already marching to the castle. Enemy means not the AI itself and not an ally. Pulling troops into an army, choosing a gathering castle and the spare-troop pool all use the per-castle reserve, so border castles facing a big stack keep their garrison.
  - **Chokepoints:** the generator (trails maps) computes weighted betweenness over castles (the share of shortest routes between castle pairs that pass through each castle, Brandes algorithm with length ties) and stores `game_territories.choke` 0 to 3: 3 at 75 percent or more of the busiest castle, 2 at 50 percent, 1 at 30 percent. Over 12 test maps about 5 percent of castles are level 3, 10 percent level 2 and 19 percent level 1. Junctions are always 0. `get_game_view` returns `choke`; the castle panel shows a Chokepoint or Major chokepoint note for level 2 and 3. Games made before this change have `choke` 0 everywhere.
  - **AI target value:** a target gets `1.5 x choke` plus `5` if it is the capital of another living house, added to its attack score (in addition to tier, treasury, travel time and leader or war priority). It does not change which target massing aims for.
  - **Soak result (4 AIs, 49 castles):** no AI errors through 489 ticks; alliances fell from 4 to 0 by tick 350 with up to 5 wars; battles kept increasing (64 by tick 450); castles 9/13/13/14, nobody near the 25 needed. Border castles hold more, so fewer troops go to the field than before (commander armies 54 to 186, garrisons 600 to 1,440), which slows conquest. Tuning knobs: the three threat weights above and the 1.5 and 5 target bonuses.

- **Stranded commanders at crossroads (migration 20261023230000).** When a truce cancelled a march, `advance_movements` put the commander back on the previous stop of its route, which is often a crossroads. A commander idle at a junction was invisible to the AI (it only managed commanders in its own or allied castles) and two armies of 913 and 1,178 troops sat there for over 120 ticks in the 4-AI watch game. Now the cancelled march returns to the last real castle on the route, `ai_commanders` also manages commanders found at a junction, and a one-time update moved existing ones to the nearest castle of their owner.
- **Watch-game findings (4 seats, standard map, tick 0 to 1630, roughly 68 days at Normal speed):** the three AIs expanded to 45 castles by tick 250 and 82 by tick 450, all allied and with no wars; all alliances broke at about tick 500, when fewer than 15 percent of castles were neutral. The passive human seat was eliminated at tick 1350. After the stranded-commander fix the AIs pooled troops into very large single armies (up to 27,605 troops in one commander). A mega-army wins slowly: each conquest is a 25 to 40 tick march plus a siege, and Ostrand went from 35 to 40 castles in about 150 ticks. By tick 1630 the castles stood at 29 / 40 / 27 with a win threshold of about 50 and about 4 battles per 70 ticks. Not yet addressed: the AI could leave surplus troops in the castle and attack several castles at once with separate commanders.

- **AI supply lines and commander use (migrations 20261023240000 to 20261023250000).** Prompted by experienced Neptune's Pride play: the game is a contest of who sets up the best supply lines, and strong teams run dozens of carriers (commanders) that constantly move troops toward the front. The AI used 3 to 6 commanders and kept most of them as castle garrison commanders.
  - **Garrison duty is for threatened castles only:** `ai_garrison` now assigns a garrison commander only to a castle that has an enemy-owned castle one road away (through crossroads), at most 30 percent of its commanders, always leaving at least 2 free; garrison commanders on safe castles are released every turn. This was the main fix: in a test game 8 of 13 commanders were standing guard.
  - **Hiring:** `ai_hire` wants `ceil(castles x ratio)` commanders, ratio 0.15, 0.25, 0.35, 0.45 and 0.55 for difficulty 1 to 5, capped at 60, hires up to 3 a turn at the castle with the most troops, and keeps 100 gold spare once it has 4 commanders. Cost is the game's commander cost (100). The engine has no commander cap.
  - **Supply loops (`ai_logistics`, difficulty 2 and up, 4 or more castles):** the AI aims for `ceil(castles / 4)` (max 16) looping routes. A front castle is one of its own with a non-allied castle (enemy or neutral) one road away. The target front is the one fed by the fewest loops and with the fewest troops. Each new loop starts at a rear castle with at least 15 spare troops and no loop yet, uses an idle commander there or hires one, and creates a `commander_routes` row (looping, `collect_all_but` reserve + 10 at the rear castle, `drop_all` at the front castle, castle hops in between and back). Up to 2 loops are created per turn. A route aborts on its own if a stop is lost, and the commander is picked up again.
  - **Boxed-in houses (migration 20261023260000):** a house with almost every castle on the front had no rear sources, so it ran no loops (Mereth in the 100-castle soak: 8 castles, 7 front, 0 loops; the one rear castle had no idle commander and gold was under the cost + 100 hiring reserve). Now rear castles are still preferred, but a front castle can feed a weaker front castle when it holds at least `2 x target troops + 30` (never the target itself), and it keeps half its troops at home instead of the usual reserve + 10. The 100-gold hiring reserve is waived while the house has fewer than 2 loops. A house with few castles and few loops is not a fault: the goal is `ceil(castles / 4)` (Brannoch, 6 castles, 2 loops, was on target).
  - **Gold reserve for supply loops (migration 20261023270000):** `ai_spend` runs every tick and spent 30% to 70% of all gold on infrastructure, so gold sat at 50 to 100 and `ai_logistics` (needs commander cost + 100 to hire a loop commander once a house has 2 loops) rarely got to hire. Now, at difficulty 2 and up with 4 or more castles, `ai_spend` keeps `commander_cost + 100` untouched while the house has fewer looping routes than `min(16, ceil(castles / 4))`. Soak (same 4-AI, 100-castle setup, tick 634): leaders ran 42 and 27 commanders with 11 and 8 loops (earlier run at tick 617: 22 and 20 commanders, 6 and 8 loops). Small boxed-in houses (5 to 14 castles, all front) still run 1 loop: they are limited by income (treasury level sum 21 to 26) and by the `2 x target + 30` front-source rule, not by the reserve.
  - **Parallel strikes:** `ai_commanders` skips commanders on a route, ignores targets another of its commanders is already marching on, looks only at the 12 nearest targets, handles at most `6 + difficulty` idle commanders a turn (plan_march cost), and when a commander carries more than `2.2 x need + 30` troops it returns the surplus to the castle garrison (keeping `1.6 x need + 20`) so others can use it.
  - **Result (4 AIs, 100 castles, same map as the earlier run):** by tick 440 battles were 97 (48 before the garrison change) with 96 castles taken (59), commanders 10 to 20 per house (3 to 4 before) with 3 to 9 supply loops each, armies 500 to 975 troops (75 to 412), and no AI errors through tick 608. Cost: about 1.3 s per tick with 55 commanders and 14 loops (was 0.5 s); the recursive reach queries run in several AI functions every turn and could be cached per tick if it matters.

## 21. House Lore and Leaders (migration 20261024100000)

- **World:** the Aldermark, once one realm (the Concord of the Eight Seals). A castle belonged to whoever held a charter stamped with the Throne's seal and their house's. Emperor Aldous died with no named heir and the Chancery burned the same week (the Hollow Year, year 0). The game is set sixty years later; "Road to victory" is the houses' way of taking the Throne. Tone: grounded medieval, no magic.
- **Data:** `factions` gained `motto`, `seat`, `blurb`, `history` (paragraphs separated by a blank line), `rival` (a faction slug) and `known_for`. New table `faction_leaders (faction_slug, ord 1..4, name, title, bio)`, readable by everyone, 4 leaders per house. `factions.modifier` is untouched and reserved for real house boosts.
- **Starting leaders:** `finalize_start` renames the starting commanders by creation order: order 1 is the king, 2 to 4 are the first starting commanders, taken from `faction_leaders`. Any further starting commanders keep random names. Schools, abilities and everything else are unchanged (the setup step still chooses schools). Hired commanders keep random names.
- **Houses:** Kaldran (wall-builders, watchtowers), Veyra (chancery, alliances and learning), Dravos (forges, arms and siege), Halcyr (road-riders, stables), Mereth (dye and banking, gold), Ostrand (fords and delta, crossings), Thornwick (forest, scouts and patient defence), Brannoch (hill clans, large levies). `known_for` is the player-facing hint toward a future boost. No boost is implemented.
- **UI:** Field Manual section "History of the realm" (world story plus a clickable list of the eight houses), the house picker (motto under each house, blurb and "Read their history and leaders" for the chosen house), and a clickable crest in the game HUD and in Standings. All open one house card with the crest, motto, seat, history, known-for, rival and the four leaders.

## 22. Commander Profiles (migration 20261024110000)

- **Data:** `commanders.profile` (jsonb): `sex` (f or m), `age`, `epithet`, `bio`, and `look` (skin, face, hair, hairc, beard, eyes, brow, nose, mouth, scar). The look values are kept as picker hints; today only `beard` is used. `commander_name_parts` (per-house given names for each sex plus family names) and `commander_bio_parts` (origin per house, event per school, quirk, epithet per school) are server-only tables of editable fragments.
- **Generation:** `create_commander` (used by hiring, the game start and AI hiring) calls `commander_identity` for a house-flavored name that is unique in the game, and `commander_profile` for the rest. Bio = origin + event + quirk, with pronouns filled from sex. Epithets: always for a king, 70% otherwise. Ages: king 42 to 62, others 20 to 55. Scars are likelier for Battleschool (45% vs 22%). Women never get beards.
- **Leaders:** `finalize_start` renames the first starting commanders to the house's `faction_leaders` row (name, sex) and uses its title as epithet and its bio as the bio. Existing commanders in running games were backfilled with a profile and kept their names. Each `faction_leaders` row also has a fixed `age`, `school` and `look` (including a `seed` that drives head tilt and mood), generated once from the leader's name (migration 20261024120000). `finalize_start` copies age and look onto the commander, so a leader has the same face in the house history card and in every game; their actual school still comes from the player's setup pick, so only the gear can differ from the house card.
- **View:** `get_game_view` returns `profile` with every commander it returns.
- **Portraits (rendered in the game engine):** `portrait3d.js` builds a stylized clay-look 3D bust per commander with three.js and renders it once (360 x 480, transparent background) to an image on a shared offscreen WebGL canvas.
  - **Head:** one high-resolution sculpted mesh (176 x 128 sphere) with the brow, eye sockets, cheeks, nose, lips, chin and age lines pushed in or out by smooth Gaussian features, so there are no seams between parts. Painted vertex colors give blush, lips, shaded creases, stubble and freckles. Small per-commander asymmetry (nose and chin offset, slightly different eye sizes). Women get a slimmer jaw, softer brow ridge, fuller lips, lashes and thinner brows.
  - **Expression:** each commander gets one of six moods (calm, warm smile with teeth, smirk, stern, weary, resolute), chosen from the commander id and the stored brow and mouth values. A mood sets brow height and slope, upper and lower lid coverage, mouth corners and cheek lift.
  - **Mouth and nose:** real glossy lip shapes (clearcoat), a dark mouth line that curves with the mood, nostril holes, and teeth for the warm smile.
  - **Eyes:** glossy spheres with a generated iris texture, two catchlights, and upper and lower lids.
  - **Hair and beards:** clumps of rounded caps, capsules and spheres with a strand texture; stubble is painted on the skin.
  - **Clothing and props:** Battleschool: quilted gambeson, chain-mail collar, riveted steel pauldrons, helm with rivets and cheek guard, surcoat with house emblem, sword hilt over the shoulder. University: woven robe with trim bands, rolled collar, chain of office, beret with a quill. Rangers: leather jerkin, woven hood and mantle, brooch, bowstring and quiver straps, arrows and bow tip behind the shoulders. Kings wear a gold circlet with gems. House colors drive surcoat, robe, hood and trim.
  - **Inputs:** `profile.look`, `profile.age`, `profile.sex`, school, role and the owner's house colors.
  - **Lighting and cost:** a strong warm key from the upper left, a cool rim and a dim studio environment map, so shadows give the faces form. The first render in a session takes about a second (lighting setup), then roughly 130 ms each. Results are cached by commander and house colors; the module loads lazily and cards fill in one at a time. Until a portrait is ready, or without WebGL, the card shows a house-colored silhouette. No external art is used.
- **UI:** `cmdCard` renders the framed card (house-colored backdrop; king gets a gold frame; large size adds school badge, rank badge and troops bar). Commander rows use the small card; selecting a commander shows the large card, epithet, age and background.
- **Not done:** council members (`council_members`) still use the old random names and have no profile.

## 23. Commander Chronicle (migrations 20261024130000, 20261024131000)

- **Table:** `commander_history (id, game_id, commander_id, tick, kind, text)`. RLS on with no policies; read only through `commander_chronicle(p_commander_id)`, which returns the last 80 entries plus `wins` (kinds win and capture), `losses` and `castles` (capture), and only for commanders owned by the calling user. Enemy commanders' chronicles are not exposed.
- **Writers:** `log_commander(commander, tick, kind, text)` writes one entry; `log_battle_history(...)` writes one entry for every commander on both sides of a battle and is called from `record_battle_report`, so assaults, sieges, sallies and field intercepts are all covered. Text is picked from three variants per case and names the place and the enemy house (a neutral castle reads as "the free garrison").
- **Kinds and where they are written:** `enlisted` (`create_commander`, which covers hires, the game start and AI hires; names the castle), `capture` / `win` / `loss` (battles), `captured` (`kill_or_capture`), `freed` (`release_captive_core`, ransomed or released), `executed` (`execute_captive_core`), `fell` (`kill_commanders`, skipped when an `executed` entry exists for that tick), `crowned` (`crown_commander`), `named` (`promote_veterans`, after five wins) and `skill` (`award_xp`, each time an ability reaches a level divisible by 3).
- **Backfill:** every commander that existed when the migration ran got an `enlisted` entry; earlier battles were not reconstructed.
- **UI:** a Chronicle section on the commander panel for your own commanders (summary line, the latest 8 entries, Show all), cached for 12 seconds per commander. The large commander card now shows the school icon at the left of the bottom bar (with the troops count on the right) instead of a badge on the face.
- **Map fix:** on the 2D map the commander dots under a castle now sit below the treasury, recruitment and prestige numbers instead of covering them. The castle panel line is now "Treasury / Recruitment / Prestige" (it said Industry).
- **Not done:** `ai_crown` and council deployments do not write chronicle entries; the garrison assignment is not logged (the AI reassigns constantly).

## 24. Commander and Castle Pages (migration 20261024140000)

- **Commander growth:** `commander_growth(commander)` (owner only) returns rank, rank cap, max level, the school affinity and every ability's level, XP and XP needed for the next level (`xp_base_cost * (level + 1) * (1 + xp_rank_step * rank)`, null at max level or rank cap). The panel shows a bar, the effect text and the XP still needed, school abilities first.
- **Now line:** built on the client from the movement and route data: marching (destination, arrival tick, whether on a route or loop), besieging, leading a garrison or waiting.
- **Record and rivals:** `commander_history` gained `foe_player` and `foe_commander`, written by `log_battle_history`. `commander_chronicle` now also returns `captured` (times taken prisoner), `nemesis` (the enemy commander who beat this one most, with their house and the count) and `old_foe` (the house fought most, with wins and losses).
- **Rename:** `rename_commander(commander, name)`: owner only, living commanders, 2 to 32 characters from letters, spaces, hyphens and apostrophes, once every 3 ticks per commander; logs a `renamed` chronicle entry.
- **Hall of the Fallen:** `fallen_commanders(game)` returns your dead commanders (latest 60) with profile, service ticks, wins, castles, last three deeds and the epitaph from their `fell` or `executed` entry. Opened from a button in the Realm panel.
- **Castle notes:** table `castle_notes (game, player, territory, tag, note up to 160)`, RPCs `my_castle_notes` and `set_castle_note` (empty tag and note deletes). Tags: staging, target, watch, fortress, supply, danger. The tag is drawn as a small pill beside the castle plate on the 2D map.
- **Castle report:** `castle_report(game, territory)` for your own and allied castles only (so it never leaks fogged data). Yield per cycle: troops `industry x (Barracks + 4) x (1 + 0.1 Muster)`, gold `treasury x (10 + 2 Mint) x (1 + 0.1 Steward)`, prestige per tick `prestige x (1 + 0.1 Scholar)`, each with the delta for the next level; Muster, Steward and Scholar are those of the garrison commander or the king floor. Defence: damage per round `max(1, Armory + Valor + 1 + 1 if mountain)` using the same functions as `fight_castle`, with the fewest troops an attacker needs for attacker damage 1 to 4 (`damage x ceil(defenders / attacker damage) + 1`).
- **Client-only sections:** Threats (visible hostile movements heading to the castle and the nearest hostile neighbours by trail), Supply lines (your active routes starting or stopping here), Last scouted (the existing fog memory now stores the tick as well) and the castle History (battle reports and public moments filtered to the castle, read through row-level security so only events you were part of or that were public appear).
- **Map fixes included earlier:** commander dots sit below the infrastructure numbers on 2D plates, and the castle panel line reads Treasury / Recruitment / Prestige.

## 25. AI Balance: Reinforcement and Coalition (migrations 20261024150000, 20261024151000)

- **Reinforcement (`ai_reinforce`, difficulty 2 and up, after `ai_defend` each turn):** for each of the AI's castles, it totals the troops of hostile commanders that are sieging it or marching to it (not allied, not truced). If the defenders (castle garrison plus idle commanders there) plus own troops already on the way are fewer than the threat times `1.25 + 0.1 x (difficulty - 2)`, it dispatches up to 3 idle non-king commanders per castle (4 per turn overall) from other castles, loading spare troops from their own castle (keeping `max(4, 10 - difficulty)`), on a one-way route whose last stop is `drop_all` in the threatened castle. A commander is skipped if it would arrive more than 3 ticks after a marching threat, or if the trip is longer than 40 ticks, or if it would carry fewer than 8 troops.
- **Dominant house (`dominant_house(game)`):** the leader in castles when it holds at least 30% of the win threshold and at least 1.35 times the runner-up; null otherwise.
- **Coalition behaviour when a dominant house exists:** AIs accept a peace offer from the dominant house only 10% of the time, accept peace from any other non-dominant house 85% of the time, refuse its alliance proposals, break alliances with it (regardless of the old 70% rule), do not offer it peace, and non-dominant AIs offer peace to each other (at war for 12 or more ticks, 50% a turn). `ai_commanders` raises the leader's target priority from 4 to 8.
- **Soak result (4 AIs, 100 castles, difficulties 3, 4, 4 and 5):** the Warlord AI led from tick 260 but its growth stalled: 34 castles at tick 322, 36 at 432, 40 at 646, with 18 reinforcement routes, 7 truces among the other houses and no winner by tick 646 (the earlier run had a winner at tick 812 after leading from about tick 300). Geography still limits the coalition: the AIs only attack castles they can reach.

## 26. The Story of the War (migration 20261024160000)

- `game_story(game)` returns, only for finished games and only to their players: the name, tick count and tick speed, the winner, the reason from `game_standing` (territory or last standing), the castle total, every house (final castles, castles its commanders took, commanders ever and fallen, elimination tick), three chapters of equal length (castles captured per house from the `castle_captured` moments, and up to six alliance, betrayal, king-killed and elimination events), the six commanders with the most victories (profile, house, wins, castles, fate and last three deeds) and totals (battles, captures, kings killed, commanders, fallen). Unlike the chronicle, this reveals every house's heroes because the war is over.
- The client builds the text from that data in `storyDialog`: a winner banner, an intro sentence, three chapters ("The Scramble", "The War", "The Reckoning"), a heroes list with portrait cards, and the houses' final line. It opens once automatically the first time a finished game is loaded (remembered in the browser), and from "The story" on the game screen and the campaigns list; "Final standings" opens the older list.

## 27. Marching Armies, Battle Animation and Council Faces (migration 20261024170000)

- **Army sizes (client only):** `armyTier(troops)`: under 30 is small, 30 to 119 medium, 120 or more large. 2D draws a small, medium or large figure group; 3D draws 5, 12 or 22 foot soldiers. Medium adds a captain and 3 cavalry, large adds a second flag, 6 cavalry, a battering ram and a catapult. Battles show 2 (medium) or 4 (large) cavalry per side in 3D, and the full 2D figure including siege engines. Enemy armies use the same tiers from the troop count the server already exposes.
- **Battle animation:** when a new battle report arrives (the 3 newest per refresh), the map plays a 5 second skirmish at the battle location: advance, clash with sparks and dust, losers fall, winner raises a banner. 3D uses `playBattle` in `map3d.js` (max 4 at once); 2D uses `battleFx2d` driven by a 90 ms timer. Skipped when `prefers-reduced-motion` is set. Purely cosmetic; combat still resolves instantly in the tick.
- **Council faces:** `council_members.profile` holds a generated commander profile (school from the area: armory and barracks battleschool, watchtowers and stables rangers, others university). New members get one on creation, existing ones were backfilled, and `deploy_councillor` copies it onto the commander. `my_council` returns `member_id` and `profile`; the council list shows the face.
- **AI crown logging:** `ai_crown` now writes a `crowned` chronicle entry for the new king.

## 28. Siege Visuals (client only)

- **Camp:** every castle with at least one visible sieging commander shows the besiegers' camp: 3, 5 or 8 tents by the same army tiers (total besieging troops, 30 assumed for hidden counts), a campfire with smoke, their banner and, in 3D, 2, 4 or 6 men. The 3D camp stands on a fixed side of the castle chosen from the castle id.
- **Trebuchets (3D):** 1 for small and medium camps, 2 for large. Each winds up, fires every 6.4 seconds and lands a stone on the castle wall with a flash, dust and debris. In 2D a trebuchet silhouette and stone arc are drawn with CSS animation (disabled under reduced motion).
- **Damage smoke:** smoke from the castle and up to 3 fires on the walls, scaled by siege age. The client starts counting when it first sees the siege (level 0.2) and reaches the maximum after about 20 ticks. A page reload restarts the count.
- **No effect on rules.** Starvation (3% of troops per tick) is unchanged.

## 29. Map Size Rebase and 3D Load (migration 20261024180000)

- **Rebase:** the lobby map sizes are now Classic 3, Wide 6, Vast 9, Immense 12, Colossal 15 and Titanic 18 (the stored `world_scale`), so even Classic has three times the castle spacing the old Classic had (450 instead of 150). The default is Colossal (15, spacing 2250). All rules that scale with `world_scale` (march speed, scan range, intercept distance) are unchanged in form, so travel takes about the same number of ticks. `games.world_scale` now allows 1 to 18 (it was capped at 5, which silently broke the old Titanic option). Existing games keep their stored scale.
- **3D load at large scale:** trees were placed on a fixed grid over the whole map, so cost grew with the square of map width. Tree chunks are now at most 1600 units wide, so distance culling works at any size; full tree models show only within about 1000 + 0.3 x camera distance of the view centre, with cheap cone trees beyond; far cone trees thin out in proportion to map width; and the broadleaf tree models drop one level of detail when the map is wider than 20000. At scale 15 this measured 10 fps before and about 50 after on the test machine (scale 5 measures about 70).
- **Camera:** the first view centres on your first castle when your starting castles are more than 1500 units from their centre; otherwise on their centre as before.
- **Siege camps:** placed on the side away from the nearest other castle. Camps, smoke and trebuchets beyond 5000 units from the camera stop animating, and beyond 9000 they are hidden.

## 30. Strategic Castle Placement and Path Clearings

- **Strategic placement (generator):** after the road network exists, the neutral castles' natural resources are reassigned in order of strategic importance. The set of resource values is unchanged (so the number of tier 1, 2 and 3 neutral castles and the map's total wealth are the same), but the highest values go to the castles with the highest betweenness (how many shortest routes between castles pass through them), plus a random jitter of +/-0.12 of the peak so every map is not identical. River and pass castles stay small posts, home castles are unchanged, and mirrored and twin-ring maps keep their fixed fair values. Applies to new games only. `strategic placement` test in `generator.test.js` checks tier 3 castles have a higher mean `choke` than tier 1.
- **Path clearings (3D):** trees are not placed within 30 units of any road, and between 30 and 66 units the chance of a tree falls off linearly, so every trail shows as an open lane through forest. This is general logic over all road polylines, not specific to any castle. Grass and rocks are unchanged.

## 31. Siege Polish and Performance

- **Siege progress bar (castle page):** a besieged castle shows "Garrison holding", the garrison's troops as a percentage of the most it had since the siege was first seen (green above 65%, amber to 35%, red below), with the numbers. The client records the starting garrison when it first sees the siege, so a reload mid-siege starts a new baseline.
- **Starvation cue (3D):** the castle banner droops up to about 65 degrees as the siege level rises, and the castle's map label is desaturated and dimmed.
- **Sally and relief:** both already force an open-field battle. The battle animation now plays at the point between the castle walls and the camp (3D) or beside the plate (2D) when the castle is under siege, and at the castle otherwise. When a siege ends the camp is removed with a puff of smoke.
- **Scale:** marching armies are drawn at about 70% of their earlier size, siege camps (tents, trebuchets, men, banner) at about 68% and battle figures at about 70%, and the 2D armies, battles and camp at 70% of their earlier size, so a whole army no longer rivals a castle. Large battles show a catapult behind each large side.
- **Note tag (2D):** a castle's note tag (Staging, Target and so on) now sits above the castle, centred, instead of beside the name plate, so it no longer overlaps neighbours.
- **Chronicle:** a commander who takes over a castle garrison gets a "Took command of the garrison at X" entry (kind `posted`), at most once per 12 ticks per commander. A database trigger on `game_territories.garrison_commander_id` writes it for players and the AI alike (migration 20261024190000).
- **`plan_march` rewrite (migration 20261024200000):** same results, checked against the old version on 1,080 route requests with zero differences. Adjacency is built once as a compact list instead of rescanned for every node, array building no longer re-copies, and the shortest-path search looks only at reachable nodes instead of every castle. Measured 38% faster per call; a full tick on a 4-house game with 55 commanders went from roughly 0.9 to 1.3 seconds before to 0.6 to 1.2 seconds after. What remains is mostly per-call overhead in `march_speed` (about 1.1 ms, mostly `ability_level` at 0.7 ms) and `dominant_house` (1.3 ms).
- **3D tiles at large scale:** terrain tile size grows with the map (`max(1024, width / 28)`), so a 15x map draws 784 tiles instead of 1,600.
- **Castle size (3D):** castle models are drawn much larger relative to trees, armies and camps: tier 1 outposts at 2.7x their earlier size, tier 2 at 2.1x and tier 3 at 1.7x, while trees are drawn at 72% of their earlier size. River castles are unchanged because they have to fit their crossing. The footprint (`pl`), the tree and rock clearance around each castle, the siege smoke and wall fire heights and the siege camp ring all scale with it.

## 32. Army Sizes (3D) and Instancing

- **Tiers (`armyTier`, client):** 1 to 100 troops is small, 101 to 250 medium, 251 or more large. An army whose size is unknown (hidden enemy) is drawn as medium.
- **Units drawn in 3D:** small: one soldier per troop, up to 20 (an army of 7 shows 7); medium: 40 foot soldiers, 10 cavalry (5 on each flank) and a captain; large: 75 foot soldiers, 20 cavalry (10 on each flank, two columns), 5 siege engines (alternating rams and catapults behind the block), a captain and a second banner. The unit count changes while a small army grows or shrinks, and the figures are rebuilt when the count changes.
- **2D:** unchanged in form (3, 7 or 13 figures with 0, 2 or 3 cavalry and siege engines on large armies) but on the new thresholds. Battles use the same tiers.
- **Performance:** each army draws its foot soldiers as one instanced mesh, its cavalry as another, and each siege engine as one merged mesh (vertex-coloured), so a full army costs about 10 draw calls instead of hundreds. Animation runs only within 4200 units of the camera, about 30 times a second. Geometry is cached per house colour pair, and removing an army disposes its buffers and its flag records. Measured 79 fps with a 300-troop, a 180-troop, a 100-troop and a 7-troop army on screen.
- **Army labels (2D and 3D):** every marching army shows its commander's name above its troop count (a "?" for troops you cannot see), on the 3D label beside the army and on the 2D plate under it. Labels were enlarged: the 3D army label is 17 px tall at 11 px type. 2D armies are drawn about 1.3x the earlier size, and the 2D map now zooms in up to 40x (it was 8x) so a single castle and the armies around it can fill the screen.
- **3D label layout:** castle and army labels now read shield, then the troop count in large bold gold, a thin divider, then the name. The shield no longer overlaps the text. Label sizes: count 16 px (18 px when zoomed far out), name 11 px (12 px far out).
- **Ownership colour:** every castle is ringed in its owner's colour. 3D: a solid ring plus a faint disc draped on the ground around the castle (neutral castles are grey), the label tinted with the owner's colour, and the castle flag now carries the house shield (also on army flags and siege camp banners). 2D: a larger two-tone glow of the owner's colour under each plate, a thicker owner ring, and the name tag outlined and edged in the owner colour.
- **Council section parked:** the named-councillor list (Deploy, Recall, Recruit) was taken off the Info panel and added to the parking lot in `V2_BACKLOG.md`. The seats and their councillors, the bonuses they give and the server functions are unchanged.

## 33. Playtest Fixes: Odds, Markers, Reports and AI (migrations 20261024210000 to 20261024270000)

- **Odds panel (`my_attack_stats`, client `assaultSection`/`assaultPreview`):** shows defenders, damage per round for both sides (neutral defence = `games.neutral_armory` + valor + 1, +1 on mountains), troops needed = defender damage x ceil(defenders / attacker damage) + 1, and whether the strongest idle army suffices. Uses the shared `combatSim`/`troopsNeeded` helpers that also drive the battle calculator.
- **2D markers:** marker layer scaled relative to the zoom (`--mk` = `ms.mkScale` / pixels per unit, where `mkScale = clamp(0.5 × sqrt(pxu / pxuFit), 0.5, 1.3)` and `pxuFit` is the pixels per unit when the whole map fits; classes `mk-on` below plate width 60, `mk-names` when zoomed in). The click resolver multiplies its hit radii and vertical bias by `mkScale` with floors of 14/24 px for armies and 24/36 px for castles (mouse/touch). Legend explains shapes. View is clamped to the map; Home and Castles table (`castlesDialog`) added to the HUD; threatened castles show a red chip and a pulsing ring in 2D and 3D.
- **News and reports:** `players_seeing` filters moments by fog; `post_cycle_reports` writes a production summary each cycle from `run_tick`. The client shows a "since you were last here" modal (localStorage `ss-lastseen-<game>`), arrival toasts with a bell sound, and a siege bar (`trackSieges`).
- **Lite reload:** actions refetch only view, moments, inbox, battles, offers and events (`load({lite:true})`) and no longer block on it.
- **AI fixes:** `ai_spend` keeps a smaller reserve and always affords the cheapest Recruitment/Treasury upgrade (spend 317 down to 246 hoarded gold); `ai_chatter` posts a greeting with the house motto and capture/revenge/lead remarks, at most once per 14 ticks (`game_chat.tick`); `siege_can_win` stops the AI starting sieges it cannot win within 28 ticks, and hopeless sieges send commanders home via `launch_leg`; neutral odds are exact (no production term, margin 1.0).
- **`games.neutral_armory` (0 to 3, default 1):** the Armory level used by neutral garrisons in `fight_castle`, `ai_sieges`, `ai_commanders`; settable through `create_game`; there is no lobby control for it yet.
- **Sim harness (`soak_step(game, n)`, `sim_report(game)`):** steps a paused all-AI game and reports captures, spend and growth, used for the balance comparisons. Internal only, not granted to clients.
- **Mobile (max-width 760 px):** HUD is one scrolling row, map above the side panel (about 54 vh), side panel capped at 36 vh.

## 34. Next Move, Quick Start, Income and Cues (client only)

- **Original castle icons restored at overview zoom:** the marker layer now draws the same castle sprite as the close-up plates (scaled to a constant screen size per tier), a filled owner-colour glow with a solid owner ring (dashed grey for neutral), a gold ring on your own castles, and a troop-count tag below. The shape-and-circle markers were removed, and the legend uses small castle swatches.
- **Next move box (`nextMoveSection`, top of the Info tab):** if no commander leads troops it offers "Take N troops with <commander>" from the biggest home castle (leaves 1). Otherwise it takes your strongest idle commander, finds the six nearest visible neutral castles, computes troops needed with the same `troopsNeeded` formula (neutral damage = `neutral_armory` + 1 + 1 on mountain; your damage = Armory + Valor), and offers "Send <commander> to <castle>" for the nearest one you can take, or names the easiest target and what is missing. The Send button selects the commander and opens the normal march preview (with odds); it does not commit the march. The same "Send" button appears in the "Taking this castle" panel when your strongest idle commander has enough.
- **Income in the header:** the Treasury box shows `+N in Kt`: N = sum over your castles of Treasury level x (10 + 2 x Mint level) (stewards, morale and seasons not included), K = ticks to the next production tick.
- **Quick start:** lobby button; creates a game with `max_players` 4 and default rules, adds three AI seats at difficulty 3, starts it and opens the map. Subject to the five unfinished games limit.
- **Host tools:** Jump 6 and Jump 24 ticks added; the client chains `admin_jump_ticks` calls of 5 or fewer, so the server cap is unchanged.
- **Sound cues:** `fanfare` when you gain a castle, `lost` when you lose one, `alarm` when a new castle becomes threatened (no cue on the first load).
- **Parity check:** the client troops-needed formula was compared with `castle_report` for 10 castles at 4 damage levels each (40 values, 0 differences).
- **Sim results at tick 66, 4 AI-only seats (castles per house / first capture / captures / first PvP battle):**
  - Current defaults: 6,5,5,5 / tick 49 / 5 / none.
  - March speed 2.5: 7,6,5,5 / tick 27 / 7 / none.
  - Speed 2.5 and neutral armory 0: 8,7,7,7 / tick 14 / 13 / none.
  - Same with world scale 9: 7,7,7,6 / tick 15 / 11 / none.
  - Neptune's Pride at the same tick: 17, 15, 13, 8 holdings.

## 35. Order Lock, Speed Basis and Neutral Armory Default (migration 20261024280000)

- **Order lock:** once a march has taken its first tick it cannot be turned back. `recall_route` is no longer callable (execute revoked from all client roles). New `cancel_march(game, commander)` undoes a march only while `commander_movements.departed_tick` equals the game's current tick and the route (if any) is on its first stop (`created_tick` = departed tick, `next_stop_index` 0). It deletes the movement, aborts the route, and restores the commander to the departure castle with the status recorded in the new `commander_movements.prev_status` (set by `launch_leg`; a sieging commander goes back to sieging). Later stops can still be dropped with `abort_route` (client: "Halt at next stop" while marching, "Drop remaining stops" while waiting). A follow-up to check against Neptune's Pride's behaviour in the next evaluation.
- **Speed basis:** `games.speed_basis` multiplies `commander_speed_mult` inside `march_speed`. Existing games have 1 (unchanged); new games default to 3, so the host's 1x now means three times the old speed. The create wizard and the speed multiplier setting are unchanged: 1 is the new standard.
- **Neutral armory default 0:** new games default `neutral_armory` to 0 (existing games keep their stored value). Neutral castles do not produce troops: `run_tick` adds troops only to castles with an owner, so a neutral garrison is fixed at its starting value (`starting_garrison` x tier).

## 36. Playtest B Fixes: Defaults, Route Validation, AI Styles, Messaging (migrations 20261024290000 to 20261024360000)

- **Base game size is 15x:** the sizes in the wizard are now labelled as multiples of the 15 base: Classic 0.2x, Wide 0.4x, Vast 0.6x, Immense 0.8x, Standard 1x, Titanic 1.2x. Stored `world_scale` is unchanged (3 to 18), so existing games are unaffected; the rules summary shows `world_scale / 15`. `games.world_scale` now defaults to 15 and `travel_mode` to `trails`, and `create_game` follows the column defaults (it used to force scale 3 and free travel, which is why Quick start produced a small free-travel map).
- **Route validation (`send_on_route`, `plan_march_from`):** every leg of a route, and the return leg of a loop, is checked at order time. Free travel: straight distance against (210 + 60 x Stables) x scale. Trails and roads: `plan_march_from(player, commander, from, to)` (a copy of `plan_march` with a start castle) and its `in_range` flag. The error names the stop ("stop 2 is out of range of stop 1"). `advance_route` (leg launch when an army arrives) now writes "Route cancelled: <commander> stopped at <castle> (next stop: <reason>)" to the inbox. The client builder also checks free-travel legs and sets the leg cost so the "reaches the last stop" time includes every leg.
- **Lock text:** the Orders panel says why Cancel march is missing ("Orders are locked: this army left at tick N. You can still halt at the next stop.").
- **Next move (rewritten):** uses `my_attack_stats` (server damage) for its odds, so it can no longer promise a win the preview calls a loss. Follow-ups after the first capture: gather troops from other castles when the pooled troops can fund the easiest target, an idle commander at a castle that holds troops, and a nudge when gold is 120 or more. A one-line link to the two-minute guide shows on a new game until it is hidden or tick 20 passes.
- **AI styles (`game_players.ai_style`: defensive, balanced, aggressive):** set per seat in the wizard, changeable in the lobby (`set_ai_seat(..., p_style)`), shown in the lobby seat list, and given by Quick start as one of each (`add_ai_seat(..., p_style)`). In `ai_commanders`: the attack margin against rivals is x1.5 (defensive) or x0.92, min 1.0 (aggressive); the home reserve is +6 (defensive) or -3; rival castles are pulled toward the front of the 12-castle target list (distance weight 1.6 defensive, 0.6 balanced, 0.25 aggressive) and score +3 for aggressive, while neutral castles score +4 for defensive and 0 for aggressive. `ai_reinforce` adds +0.3 margin and +4 reserve for defensive, -0.1 margin for aggressive.
- **Sim results at the true defaults (15x, trails, difficulty 3, 4 AI houses):** all balanced to tick 120: castles 18, 15, 15, 14; 46 captures, none against another house. Mixed (aggressive, balanced, defensive, aggressive) to tick 120: 21, 16, 16, 9; to tick 160: first house-versus-house battle at tick 125, 19 such battles by 160. All aggressive to tick 160: first house-versus-house battle at tick 93, 91 captures, castles 30, 26, 22, 17. At 3x free travel, tick 108: 13, 11, 11, 11, no stall. The playtest's house stuck at 4 castles did not reproduce.
- **AI chat:** captures are announced only when a human can see the castle (`ai_chat_visible`, based on `players_seeing`) in fogged games; the "holds N castles" taunt has four wordings, is skipped if anyone mentioned that rival in the last 30 ticks.
- **Messaging:** realm area level-ups arrive in the inbox ("Armory reached level 2"); `my_unread()` returns unread inbox counts per game and the lobby shows a red badge on each campaign card; private threads take an optional subject (`thread_messages.subject`, up to 80 characters, `create_thread(..., p_subject)`), and the message box is multi-line (Enter sends, Shift and Enter adds a line).
- **UI:** the Castles table closes when you pick a row; Sound and Scan rings leave the top bar below 1400 px (still in Options) so the game name and tick line keep their room; on phones Menu stays pinned at the right of the scrolling bar and the title is shortened; the income line is larger; the legend can be hidden and now sits above the 3D view; castles out of sight show their last scouted troop count with a "~"; the overview castle tag carries the house shield; neutral troop tags hide only at extreme zoom-out; 3D zoom-out limit is now max(22000, 2.2 x map width); arrival toasts are de-duplicated per tick; the bulk-spend message explains a purchase of zero; Options has "Play sample sounds".
- **Not done:** 3D label overlap near armies; making the AI hold gold lower (balance 140 to 215); a diagnosis of the preview vs order 3 vs 4 tick difference; testing private threads (needs a second human).

## 37. Playtest C Fixes: AI Strike Force, Unknown Owners, Chatter, UI (migrations 20261024370000 to 20261024390000)

- **Finding:** in Playtest C (and in a sim with an idle human seat) no AI house attacked another house or the human for 160 ticks. Cause: every commander spent its troops on neutral castles as they arrived, so none was strong enough to take a rival castle (6 to 40 troops plus a garrison commander), and expansion was not steered toward rivals, so rival frontiers touched late.
- **Strike commander (`ai_commanders`):** for Aggressive houses from tick 30, and Balanced houses from tick 90 with 10 or more castles, the idle commander at an own castle nearest a rival castle becomes the strike commander (`v_strike_cmd`). Its targets are rival castles only. If one is in range and winnable it assaults it; otherwise it lays siege to one it can starve; otherwise it gathers troops (pool goal = the weakest reachable rival castle's need), taking from castles with 4 or more spare troops (12 for other commanders) before marching. Defensive houses have no strike commander.
- **Expansion toward rivals:** the neutral-castle score gets a bonus of 0.8 (Aggressive) or 0.3 (Balanced) times (10 minus the distance to the nearest rival castle in castle spacings), floored at 0.
- **Sim results (default 15x trails, difficulty 3):** two Aggressive, one Balanced, one idle human: first house-vs-house battle none before tick 160 (before the change) and at tick 159 after the first patch; with the lowered gather threshold, all four houses Aggressive: first battle 130, 28 battles and 17 captures between houses by tick 180. Quick start mix (Defensive, Balanced, Aggressive, idle human) from a fresh game: first battle tick 146, 6 by tick 160, 5 captures between houses. The idle human, whose homes sit far from everyone, was never attacked: contact still depends on frontiers meeting, which on the 1x map happens around ticks 100 to 150.
- **AI diplomacy:** the chance per tick to propose an alliance is 0.04 for Aggressive, 0.45 for Defensive, 0.3 otherwise (was 0.3 for all).
- **AI chat:** idle lines are style-specific (four each for Defensive, Balanced and Aggressive), the motto is no longer posted alone, and an idle line is skipped if anyone said it in the last 80 ticks.
- **Unknown owners under fog:** the server masks the owner of castles outside scan range as null, and the client showed that as "Unclaimed". Castles never seen now read "Unknown, out of sight" (castle page and Castles table), draw a blue-grey dotted ring in 2D, and the legend explains it. Remembered owners still show as "last seen".
- **Next move:** only suggests castles within range (trails: `trailReach`; free travel: distance against the Stables range). If none is in range it says so.
- **UI:** wizard size description reworded; lobby badge tooltip says it counts inbox reports and messages (not chat); host Jump 6 and Jump 24 run in batches of 3 ticks and show progress on the button; 3D opens at the capital at distance 3200 so several castles show; phone header: the name and tick line no longer collapse to zero width.
- **Open:** whether fog should hide ownership at all (decision pending); why Jump 24 stalled in a background tab (progress label added); thin AI garrisons after captures; private threads untested (needs a second human); Quick start's 99 castles (extra river-crossing castles make the victory target 50).

## 38. Ownership Visible Under Fog, 10x Base, AI Style Label (migrations 20261024400000, 20261024410000)

- **Fog change:** `get_game_view` now includes `owner_player_id` for castles outside scan range unless the game is dark (`fog_dark`). Fog still hides troops, garrison leaders, upgrade levels, commanders, armies and movements. Dark games still hide unexplored ground and its owners. The client reads the owner whenever the field is present (`t.owner_player_id !== undefined`), so out-of-sight castles draw in their house colour; the "Unknown, out of sight" label, dotted ring and legend entry now apply only to dark-fog ground the player has never seen. News still hides captures outside scan range.
- **Base size is 10:** `games.world_scale` defaults to 10 (was 15) and the wizard sizes read Classic 0.3x (3), Wide 0.6x (6), Standard 1x (10), Immense 1.2x (12), Colossal 1.5x (15), Titanic 1.8x (18). The stored value and the generator are unchanged, so older games keep their scale; the rules summary shows `world_scale / 10`. This is map size only; the march speed basis stays at 3.
- **AI style visible:** `get_game_view` players include `ai_style` for AI seats, and Standings shows a Defensive, Balanced or Aggressive tag with the description as its tooltip.
- **AI expansion bias (second pass):** the neutral-castle bonus for being near a rival is now 1.5 (Aggressive) or 0.6 (Balanced) times (16 minus the distance to the nearest rival in castle spacings); Aggressive and Balanced houses search 20 and 16 candidate castles (12 for Defensive).
- **Sim result at 10x (two sims, Quick start mix with an idle human, difficulty 3):** at tick 140 castles were 23, 22, 13 and 4 (first pass) and 26, 20, 12 and 4 (after the bias change), with no house-vs-house battle in either. The closest two houses were still about 2 castle spacings apart, with roughly 40 neutral castles between them. Shrinking the map and strengthening the bias did not move contact earlier than the 130 to 150 range seen at 15x. The remaining levers are fewer castles per house (Compact is 12, Small 16, Standard 24) or faster troop production.

## 39. Leagues and the Ruler (migration 20261024420000)

- **The unit:** one league is 1,500 map units, the castle spacing at the base size (`world_scale` 10, spacing 150 x scale). Range, scan radius and march speed are now fixed in map units per game (the "unit scale", 10) and no longer scale with the map size.
- **`games.league` and `games.unit_scale`:** new games have `league = true` and `unit_scale = 10`. Games created before this change were set to `league = false` and `unit_scale = world_scale`, so their behaviour is unchanged. `world_scale` still sets only the map geometry (spacing, margins, map size).
- **What uses `unit_scale`:** `march_speed` (league games use `unit_scale` for every travel mode; legacy games keep the old per-mode factor), `plan_march`, `plan_march_from` and `plan_march_free` (range: trails (300 + 120 x Stables) x unit, free (210 + 60 x Stables) x unit, roads (90 + 60 x Stables) x unit in league games), `send_on_route` leg checks, scan radius in `get_game_view`, `players_seeing`, `update_explored`, trade range in `can_trade`, intercept distance in `resolve_intercepts`, and the AI's range in `ai_commanders`.
- **Effect:** at the base (10) a neighbouring castle is about 0.75 to 1.1 leagues away and a hop takes 2 to 4 ticks; at 15 the same hop takes about 5 ticks (measured: 3 ticks at 10, 5 ticks at 15 for the nearest castle; range stayed at 4,200 units, 2.8 leagues, at Stables 1). Larger maps are slower, smaller maps faster, so map size is now a real pacing choice.
- **`ruler(game, from, to, commander)`:** straight-line distance in units and leagues; the player's range and range in leagues; whether it is in range; Stables level needed (`stables_needed`); the commander's march speed; ETA on foot (ceil of distance over speed, at least 1 tick); whether both castles have roads and the ETA by road (speed x sqrt(3 + Stables)); defaults to the selected commander, else the king. Client: the Ruler button in the top bar, two castle clicks, a dashed line with the distance on the 2D map, and a panel in the Info tab (3D shows the panel only).
- **UI changes:** the march preview shows distance and range in leagues; the Castles table's "From you" column is in leagues.
- **To evaluate next playtest:** pace and spacing at the base size: ticks per hop, castles per house, first capture and contact timing, and whether 1 league per hop with 2 to 4 ticks per hop feels right.

## 40. Messaging AI Players (migration 20261024430000)

- **Why:** with no second human available for tests, and because NP lets you write to its AI, private threads now accept AI participants. `create_thread` only requires that every participant is a player in the game (it used to require humans); at most 8 participants, one thread per participant set, optional subject.
- **AI replies (`ai_thread_replies`, called from `ai_take_turn`):** on its next move each AI in a thread replies once to the latest human message (it checks that it has not already posted after it). The line is picked from a pool by AI style and the standing with the sender: allied (three lines), at war (two or three per style), otherwise three per style. About 40% of replies add "I hold N castles." Replies are statements, not negotiations; they do not parse the message or change diplomacy.
- **Client:** the new message list shows every other player not eliminated, with "AI replies on its next move" beside AI names, and Standings shows a Message button for AI players too.
- **Not covered:** AI-to-human first contact messages, AI replies to human messages inside group threads that contain only humans, and any parsing of what the human wrote.

## 41. Playtest D Fixes (migrations 20261024440000 to 20261024470000)

- **Next move under fog:** an unclaimed castle holds `starting_garrison x tier` troops and neutral garrisons never grow (neutral castles produce nothing), so the client uses that as the expected garrison for castles it cannot see (`expectedNeutral`). Next move, the "Taking this castle" panel and the march preview now work on fogged neutral castles; they are labelled "expected, out of sight". Enemy-owned castles you cannot see still have no estimate. When the army that would march is the king and the result cannot be predicted, the preview warns that a loss kills the king and suggests scouting or another commander.
- **Ruler follows the route:** `ruler` calls `plan_march_from` for the selected commander (or your king) on trail and road maps, so distance, hops, ETA and in-range are what the march will use; `straight_leagues` is returned for comparison, and `route_error` explains a missing route ("not reachable through friendly territory"). Verified equal to `preview_march` (route length and ticks) on three routes. Free-travel maps keep the straight line.
- **AI prey:** each AI computes `v_prey`, the rivals with fewer than 80% of its castles. Against prey, the expansion bias distance is x0.7, the strike commander's distance is x0.5, and non-Defensive houses score +4. Aggressive houses decline most alliance offers (accept chance x0.15) and rarely make them (0.005 per tick, was 0.04).
- **Sim, default 10x, idle human, 165 ticks:** Aggressive house first attacked a house at tick 114 and reached 37 castles; Defensive 20, Balanced 22; the idle human's four castles (each about 44 troops after 165 ticks) were never attacked, because no AI army was large enough. Tick cost grew from 220 ms (tick 60) to 373 ms (tick 110) to about 750 ms (tick 165).
- **AI replies by keyword:** alliance, peace or truce, gold or trade, and war or threat messages get their own pool per style; a reply never repeats the AI's previous line in that thread.
- **AI chat:** a house that fought another house in the last 6 ticks may comment (winning attack, lost attack, held walls, lost castle); a Defensive house no longer uses the "Enjoy it while it lasts" taunt, using a watchful line instead.
- **Phone header:** on narrow screens the Menu button now sits next to Games instead of overlaying the title.
- **Not changed:** the lobby unread badge counts inbox reports only (the in-game Inbox count also includes unseen battles, kept in the browser); Quick start's castle count includes river-crossing castles, so 24 per house gives about 97.

## 42. The Base Bundle, and AI That Plays to Win (migrations 20261024480000, 20261024490000)

**The base bundle (decided October 2026; map size and speed are variants of it):**
- Map size 10 (shown as 1x), castle trails, leagues on (`unit_scale` 10): one league = 1,500 map units = the spacing between neighbouring castles at 1x.
- March speed basis 3, speed multiplier 1: about 0.35 leagues per tick, so a neighbouring castle is 2 to 4 ticks away and one march reaches 2.8 leagues at Stables 1 (range 300 + 120 x Stables units x 10).
- 24 castles per house (the map has a few extra river-crossing castles), 4 starting castles with 10 troops each, starting gold 300, production every 24 ticks.
- Neutral armory 0; neutral garrisons are `starting_garrison x tier` and never grow. Fog on, with castle owners always visible and troops, commanders and armies hidden outside scan range.
- Variants change one thing at a time: map size (0.3x to 1.8x) changes spacing and therefore travel time; speed multiplier changes speed; fog, seasons, events and the rest are options.

**AI behaviour (all houses try to win, including against human players):**
- No tick or castle gates on the strike commander for Aggressive (from tick 20) or Balanced (from tick 40 with 6+ castles); Defensive strikes from 14+ castles and only at its higher confidence margin (x1.5). Weaker rivals (under 80% of the AI's castles), human or AI, are preferred targets.
- `ai_muster` (runs before `ai_commanders` each turn): picks the idle commander nearest a rival, finds the nearest rival castle within 5 castle spacings that is reachable and in range, estimates the troops needed (defenders x 1.2 against the AI's damage), and if the staging castle holds less, sends up to four other commanders there with "drop all" orders after loading their castle's garrison, so the strike commander can take it next turn.
- Smaller home reserves (Defensive 6, Balanced 2, Aggressive 1, plus threat-based extras), up to 12 + 2 x difficulty commanders moved per turn (was 6 + difficulty), `ai_hire` wants 5 or more commanders and hires up to 5 per turn at a ratio of 0.6 of owned castles (difficulty 3; was 0.35 and 3 per turn), and Aggressive houses spend up to 75% of surplus gold (was 50%).
- `ai_pick_area`: Aggressive levels Armory and Barracks first, Balanced favours Armory, Defensive favours Armory and Watchtowers, rather than levelling the lowest area.
- **Sim at the base, idle human seat, tick 165:** castles 35 (Aggressive), 29 (Defensive), 23 (Balanced), human 4; first house-vs-house battle tick 143, six by 165; no attack yet on the human, whose castles each held about 44 troops with Armory 3 (about 73 troops needed) while the nearest AI house was 1.1 leagues away with only 6 neutral castles left. Tick cost rose from about 240 ms (tick 60) to about 920 ms (tick 165).

## 43. Playtest E Fixes (migrations 20261024500000, 20261024510000)

- **Host jump timeouts:** `admin_jump_ticks` and `process_ticks` now carry `statement_timeout = 60s` (a function-level setting; verified through the API with an 11-second call), replacing the API's default of about 8 seconds, so waits on a busy game row no longer fail the jump. The client still jumps in batches of 3 ticks.
- **Next move:** "gather" now sends the army with a "collect all" order, so it picks up the castle's garrison on arrival (the old button moved the commander without collecting, so it ping-ponged); the preview says so. With no neutral target in range it offers visible rival castles it can beat (using the same damage and defence estimate as the odds panel). When any of your castles is under threat it leads with a defend suggestion and a button to send the strongest idle commander.
- **Threats panel and chip:** the panel now lists hostile armies already besieging the castle and the total force you can see; the header chip and pulsing ring count sieged castles, not only armies on the move.
- **King warning:** the assault preview warns when the king leads an attack on a garrison that is estimated, not seen.
- **Header at 1256 px:** between 900 and 1400 px the top bar uses tighter spacing and a narrower title so Proposals and the threat chip no longer overlap Road to victory (not re-checked at that width).
- **Ruler heading** says "along the trails" when it follows trails.
- **AI targets humans:** non-Defensive houses add +3 to the score of a human player's castle and weight the muster target distance by 0.7 for human owners. Sim (two Aggressive, one Balanced, idle human, tick 190): first battle between houses at tick 83, 31 battles, 24 captures between houses, and an Aggressive house attacked the human at tick 179 (human down to 3 castles).
- **Not changed:** AI replies still answer one message per tick per thread; chat templates still repeat across houses; the wizard still builds 97 castles.

## 44. Playtest F Fixes (migrations 20261024520000, 20261024530000)

- **AI musters for sieges, not just assaults (`ai_muster`):** it now scores up to six rival castles within 8 castle spacings (weighted toward weaker rivals and human players), for each works out the troops needed to assault (defender damage x ceil(defenders x margin / attacker damage) + 1; margin 1.05 Aggressive, 1.15 Balanced, 1.3 Defensive) and, at difficulty 3 or more, the troops needed to starve it out within 28 ticks (binary search over `siege_can_win`, x1.15 + 2). It musters for whichever is cheaper, up to six commanders per turn, and the strike commander lays siege when it has the siege force. Sim at the base with an idle human, tick 200: an Aggressive house sieged the human three times from tick 156 and took a castle (human down to 3); 13 battles between houses, first at tick 95; late-game tick cost about 1.16 s.
- **Jump and refresh timeouts:** `get_game_view` has a 30-second statement timeout (was the API default of about 8 s). The client skips its refresh while a host jump is running and refreshes once afterward, retries a failed refresh after 3 seconds instead of freezing, fetches player reputations at most every 20 to 60 seconds, no longer fetches the unused council on every tick, and skips lobby polling when the tab is hidden.
- **Next move:** prefers a non-king commander for attacks (the king only if the other is under 60% of its strength); marks a king attack on an uncertain garrison with the warning and a plain (not primary) button; says "just enough" when troops equal the need; only suggests collecting from castles the army can reach this order and that no other commander is already heading for; lists up to three idle commanders (the king too) standing with few troops in a castle that holds more; says "Your armies are out" when commanders are away instead of "not leading any troops".
- **Wizard:** the victory line now reads "about N of M; river crossings add 10 to 15 castles, so the exact target is set when the map is built".
- **Not changed:** the march preview can lag behind a Take until the next refresh; AI replies still answer one message per tick; chat templates repeat across houses.

## 45. Playtest G Preparation: Time Controls, Next Move Validation, AI Measurement (migrations 20261024540000, 20261024550000)

- **Root-cause work on jump and refresh timeouts.** Measured: `get_game_view` takes 10 to 27 ms inside the database (about 570 ms seen from the browser, mostly network); a tick costs about 0.5 s early and 0.7 to 1.2 s late (AI about 300 ms of that: `ai_commanders` 143, `ai_reinforce` 44, `ai_diplomacy` 34, `ai_muster` 32 for three AIs). Four concurrent pollers plus four realtime subscribers plus a jump ran at 0.66 s per tick with no errors, so plain API load does not reproduce the failures. The scheduler log (`cron.job_run_details`) shows 20 of 720 runs in 12 hours failing with "job startup timeout" after 12 to 16 s, which points to the database sometimes being unable to start work: the project reports `max_connections` 60, about 224 MB of shared buffers and 2 parallel workers, i.e. a very small compute tier. The performance advisor found nothing material. Conclusion: capacity on a small instance under heavy concurrency, not a lock bug; upgrading compute is a decision for the project owner.
- **Jumps are background jobs.** `admin_jump_ticks(game, 1..24)` only queues ticks (`games.jump_remaining`, capped at 48) and returns in about 0.14 s. `process_jumps()` runs every 3 seconds under pg_cron (`process-jumps`), up to 5 ticks per game per pass (`for update skip locked`). Measured: 24 ticks in 18 s with no errors. The client polls `current_tick` and `jump_remaining` every 1.5 s and refreshes once at the end. Because the work runs in the worker, the old per-function statement timeouts on `admin_jump_ticks` no longer matter.
- **Next move asks the server first.** Before it offers a target, a collect, or a defend suggestion it calls `preview_march` for that commander and castle and drops the suggestion unless `in_range` is true (results cached per commander, castle and tick). A suggestion the March button would refuse can no longer appear.
- **AI strike commander is the strongest, not the nearest.** In `ai_commanders` and `ai_muster` the strike commander is the strongest idle commander at an own castle that has a rival castle within 8 spacings (was the one nearest a rival, which was often a weak commander while the big armies chased neutrals).
- **AI pressure measurement (idle human on 4 castles holding about 46 to 58 troops each, Armory 3; two Aggressive and one Balanced AI; attack = siege or battle against the human by tick 200).** Before the strongest-commander change: 1 of 4 games. After: 2 of 4. With a stronger preference for human targets (+8 score, distance x0.4): 0 of 4 (reverted). Current setting, a fresh batch: 1 of 5. So across 9 games at the current logic about a third saw an attack; in the games that did not, the AIs fought each other from tick 51 to 115 and often lost their armies and commanders to each other, and the player's castles were the least attractive targets. The pass mark (3 of 4 or better) is not met; small samples make differences between settings unreliable. A batch harness exists: create games, set `ai_style`, pause them and set `jump_remaining = 200`; the worker advances them in the background.

## 46. Playtest G Fixes (migration 20261024560000)

- **Next move plans across all free armies.** Up to three idle commanders (non-kings first, king last; none standing in a threatened castle) each get their own reach (`trailReach` from their castle) and their own attack stats (`my_attack_stats` per commander). Options are unclaimed castles, rival castles and castles the player lost (`ms.lost`, filled when a refresh shows a castle leaving the player). Priority among options the server accepts (`preview_march` in_range): retake, then nearest unclaimed, then cheapest rival. If none is ready, the nearest-to-ready option drives the collect-on-arrival suggestion. Fixes the "nothing in range" message while neutrals sat 1.6 to 1.9 leagues from other castles.
- **Defend action.** For up to two threatened castles Next move shows the enemy force seen heading there or besieging, what the castle holds including commanders standing in it, and a Send button for the nearest idle commander that can march there. A commander already in the castle is told to stay and is never offered as the helper. Helpers are non-kings first, then the king with a warning and a plain button; one helper is never offered for two threatened castles in the same pass. (Found by the invariant check: the first version sent the king alone against a 34-troop attack.)
- **Jumps stop on a new threat.** `jump_threat(game)` runs after each background tick: a hostile commander moving to a human-owned castle with arrival within 4 ticks, or sieging one, halts the queue (`jump_remaining = 0`) once per commander and castle (recorded as a `jump_halt` game event). The client toast says why it stopped.
- **Worker delay cut.** `process-jumps` now runs every 1 second (was 3) and the client polls every 0.8 s, removing most of the floor on Jump 1.
- **Header.** Between 900 and 1400 px the title is capped at 130 px, the victory meter shrinks to 100 px, and Scan rings is hidden (its flex display beat the hide rule). Phone header: the threat chip is ordered right after Games and Menu, so it is visible without scrolling.

## 47. Playtest H Fixes (migration 20261024570000)

- **Next move cannot vanish.** `validMarch` treats a timeout or network failure from `preview_march` as acceptable (not cached) instead of dropping the suggestion; the whole paint is wrapped so a failure shows "Checking the roads" instead of an empty box; attack stats fall back to the Armory level if the stats call fails. Statement timeout raised to 30 s on `preview_march`, `my_attack_stats`, `ruler` and `castle_report`.
- **More than one order.** Besides the main suggestion, up to two more armies with a different target are listed. When 15 or more troops sit in castles with no commander and gold covers a hire, Next move says to hire one (troops only fight under a commander) and opens the richest uncommanded castle.
- **Selection.** "Take troops" no longer switches the panel to the commander; clicking the Info tab while a commander or castle is selected returns to the realm view.
- **Commander panel.** Orders (March, Start a route) now sit directly under the portrait, above the bio and chronicle.
- **Army labels.** An army you can see shows its troop count (the view only returns armies you can see, so the old "?" hid information the server already allowed). Army arrows have a 20-unit invisible tap target.
- **Jump stops respect fog.** `fog_sees(game, player, x, y)` repeats the view's scan rules (castle radius 90 + 60 per Watchtowers level, commander radius 45 + 15 per rank + 30 per Scout, times `unit_scale`, allies share). `jump_threat` halts only for armies the player could see, with three stages per army and castle: near (4 ticks or less), final (1 tick or less) and siege. A threat already known before a jump still stops at its final tick.
- **Finished games.** The header drops the victory meter and the threat chip. Final standings sort by winner, alive, castles, troops (was by seat). The story pluralises "victory" correctly. Story and standings gain Watch replay. The "49 of 98 castles" line is correct: 98 capturable castles plus 11 river crossings (junctions), which `game_standing` does not count.
- **Realm panel.** Upgrade everywhere comes before Concede defeat, defaults to Recruitment, and says what each track does.
- **Not changed (decisions or unverified):** neutral garrisons of 0, castle spacing, runaway-leader control, the 15 second intro (could not locate it), the dead-end king collect at tick 6 to 30, real-phone tap latency.

## 48. Neutral Castles Hold Nothing, Standard Map Is Twice As Wide (migration 20261024580000)

- **Neutral garrisons are 0.** `commit_world` creates every unclaimed castle (including river crossings) with 0 troops; they never produce, so one trooper takes one. The client's expected garrison for an unseen neutral castle is 0. `starting_garrison` now only sets the troops in each house's own starting castles.
- **Standard map spacing doubled.** `games.world_scale` defaults to 20 and the wizard labels 20 as Standard (1x): Classic 0.3x = 6, Wide 0.6x = 12, Standard 1x = 20, Immense 1.2x = 24, Colossal 1.5x = 30, Titanic 1.8x = 36. The table check now allows 1 to 40 (it capped at 18, so a default of 20 would have broken game creation). Range, scan radius and march speed stay fixed in map units, so a longer map means more ticks per hop and more reason to raise Stables.
- **Measured on two Quick start sims at the new base:** 97 and 96 castles; average edge 2.4 leagues (was about 1.3 nearest-neighbour before), average nearest edge 2.1; about 40 of 150 trails are longer than the 2.8 league range at Stables 1 (a single hop is always in range; only multi-hop routes are range-checked). Castles at tick 24: 7, 5, 5, 4 and 7, 6, 5, 4. At tick 66 the three AI houses held 19, 18, 14 and 20, 16, 10, which is close to NP's 19, 19, 18.
- **Why Northfield Crossing fell to a house with no adjacent castle (game 265, tick 171):** its only two trails led to castles of an ally (alliance formed at tick 37). Marching rules let an army cross allied castles, so Kaldran marched Dietmar Hartmann through his ally's territory. By design: allies share roads, and an enemy castle can never be crossed.

## 49. Leader Hunt And NP Parity Screens (migrations 20261024590000, 20261024600000)

- **Leader hunt (`ai_leader`).** A house holding at least 60 percent of the castles needed to win is the leader. Every AI treats it as prey: in `ai_commanders` it scores +8 on top of the usual prey bonus, for all styles including Defensive; in `ai_muster` its castles weigh 0.25 on distance (0.5 for ordinary prey). Diplomacy already broke alliances with, and refused offers from, a house at 70 percent or the dominant house.
- **Regard (`player_regard`, `regards`).** Derived, not stored: for observer and other, -4 per castle the other took from the observer, -8 per war the other declared on the observer, +gold/25 (max +6) per gift received, +5 per technology shared, +4 while allied, -3 while at war. Events fade linearly over 120 ticks to a floor of 25 percent. Result clamped to -10..+10. `ai_diplomacy` multiplies alliance acceptance by 1 + 0.08 x regard and adds 0.04 x regard to peace acceptance. Standings shows each AI house's regard for you.
- **Intel in play (`intel_live`).** Returns the intel snapshots with every other house's gold removed, so the charts work in fogged games. Totals only (castles, troops, commanders, building levels); positions stay hidden. The Intel dialog also adds up the numbers by the colour groups set in Empires (the NP Analysis screen).
- **Research (`research_info`).** Per area: level, prestige held, exact next-level cost (144 x level x game and per-area cost multipliers), active flag, plus prestige income per production (castle Prestige levels with the Scholar bonus), ticks to the next production, and the Library bonus. The client estimates cycles and ticks to the next level for the active area.
- **Ledger.** Menu, Ledger reads the existing `ledger` rows (production, starting gold, gold sent and received, technology fees) and totals gifts by house.
- **Recorder.** Menu, Recorder merges public and own moments with the player's battle reports, newest first, filtered by house and kind.
- **Abandon castle (`abandon_castle`).** Owner only; not the last castle; no own idle or sieging army inside; no enemy siege. Becomes unclaimed with 0 troops and no road, logged in `territory_owner_log` and as a public `castle_abandoned` moment.
- **Scores and badges (`game_awards`).** Finished games only: score = 10 per castle held + 3 per castle taken + 1 per battle + 50 for the winner. Badges: Conqueror (most castles taken), Iron Wall (fewest lost), Warlord (most battles), Last House Standing (most castles). Shown on Final standings.
- **Already covered, no change:** map label thresholds (Options has per-label rules for castle text, army counts and upgrade levels), default march action (Options), warp gates (roads).
- **Jump stops, tuned (migration 20261024610000).** A castle halts a jump at most once per stage (near, final, siege) in any 12 ticks, not once per army. `games.jump_halt_on_threat` (default true) lets a sim turn the halts off.
- **Commander hire price is 25 gold by default** (migration 20261024620000; was 100). The wizard stepper defaults to 25 in steps of 5. Games already created keep their price, so sims 270 and 271 still pay 100. Cheaper hires will let the AI (which hires toward a castle-based ratio) and the player field more armies earlier; re-check expansion and the leader's pace in the next sims.

## 50. AI Drive To Win, Victory Decay (migration 20261024630000)

Built from the NP observation study (research/np-observation, three all-AI games): NP's AI has a fast local opening and neighbour-first wars but never finishes a game, so ours keeps those two and adds a closing drive.

- **Victory decay on by default.** `games.victory_decay` defaults to 1 castle per production and `games.victory_decay_start` to 250. `game_standing` lowers the castles needed by `victory_decay x floor((tick - start) / production cycle)` (floor of 15 percent of all castles unchanged). Existing games keep their old decay (0). The wizard stepper defaults to 1.
- **Campaign focus (`ai_focus`).** Each AI picks one enemy at a time: not an ally, with a castle within 6 castle spacings of its own, preferring houses no bigger than 1.3 times its size and then the smallest. Kept for 72 ticks, dropped if it is eliminated or becomes an ally. In `ai_commanders` the focus house's castles get +6 priority, +4 more when it holds 4 castles or fewer (finish it), and castles taken from the AI in the last 36 ticks get +4 (retake). Balanced and Aggressive strike commanders may strike the focus from tick 40.
- **Final push.** A house within 10 castles of the win line uses a margin of 1.0 on every target, may always strike, and scores targets higher the fewer troops they need (`+ max(0, 8 - need / 12)`).
- **Land into army.** When 8 percent or fewer castles are unclaimed, `ai_spend` weighs Treasury at 3.0 against Recruitment 1.0 (was 1.2) and keeps a gold reserve of at most 60 (was 150), so gold turns into troops.
- **Backstabbing.** The chance per tick that an AI betrays an ally once neutral land is nearly gone is tripled: 0.012, 0.03, 0.06, 0.12 by difficulty 2 to 5 (was 0.004 to 0.04). The target is picked by size, troops and distance, as before.
- **Unchanged:** leader hunt at 60 percent of the win line; expansion and early-war logic (already at or ahead of NP's pace).
- **Shared database warning:** AI functions are global, so a change applies at once to every running game, including other sessions' sims.

---

## 20. Client Shell (map screen)

The map screen is one top bar, the map, and one side panel. The data layer (RPCs in section 14, realtime in section 15) is unchanged; this section describes how the client renders and sequences it.

### 20a. Top bar, menu and map corner

Three groups: left (back to games, crest, game name, tick number), centre (the tiles), right (Mail with the unread count of reports, battles, chat and threads, which opens the Inbox view, and Menu). The centre is five tiles: Production is locked in the middle (clock to the next production from `productionLeft()`, refreshed each second by `updateCountdown()`, tick and cycle position, a bar that fills over the cycle) and four slots come from `PREFS.bar` (default `victory, treasury, research, armies`; the choices are `BAR_TILES`: `victory` opens the leaderboard, `treasury` opens Spend, `research` shows the active area with cycles and ticks to its next level and opens Research, `armies` shows marching armies and the next arrival and opens Castles, `arrival`, `troops`, `threats` (click looks at the first threatened castle), `proposals` (click flashes the offers), `season`). While a castle is under threat and `threats` is not chosen it replaces slot 4; a pending proposal replaces the next slot from the end. The gear at the end of the bar opens a picker (`barPicker`) whose four selects write `PREFS.bar` and redraw at once; Options has the same four selects. Each group is rebuilt only when its rendered HTML changes. Under 760 px slots 3 and 4 are hidden unless forced, the Production tile moves first, and only values show; the Mail button stays.

The menu (`menuContent()`) is a tool row (Ruler V, Spend B, Legend, Rings Z in fog games, Sound, Refresh, each a toggle with `aria-pressed` where it has a state) and a list of destinations with their keys: Leaderboard L, Research R, Castles S, Ledger D, Intel G, Recorder, Battle calculator C, Inbox I, Chat, News, Replay (finished games), then Game rules, Host tools (host only), Options O, Help ?, Main menu Esc. `PREFS.menu` is `drop` (a `.menu-pop.drawer` under the Menu button, opened by `menuDialog` through `openPop`, closed on outside click, Escape, a second press or choosing an item) or `docked` (`drawRail()` keeps the same content in a `.rail` column on the left edge of the map and hides the Menu button; `.mapbody.railed` shifts the map corner controls and legend). Spend is `spendDialog()`: the Upgrade everywhere section (the realm section's second node) as a screen; it is no longer on the home state.

Keys (`onShortcut`, a window keydown listener that ignores modifier combinations, typing in inputs and open modals): L leaderboard, R research, S castles, D ledger, G intel, I inbox, N new message (opens Chat with an empty compose), C battle calculator, O options, ? help, V ruler, B spend, Z scan rings, H centre on your realm (`ms.goHome`), plus and minus zoom (`zoomBy`, factor 0.7 about the view centre, clamped like the wheel). A screen key pressed while that screen is open steps back (`toggleScreen`). Escape is handled separately (section 20b).

The map corner (`.mapctl`) holds only Centre on your realm and 2D/3D. The legend starts closed (`ms.legendOpen`, remembered in `ss-legend`), is toggled from the menu tool row or its own close button, and lists only the houses, Unclaimed and, in dark fog games, Out of sight.

### 20b. Panel stack and routing

The side panel is one slot with three states: home (the leaderboard, `atHome()`), a selection (`ms.sel`, castle `t` or commander `c`) and a screen (`ms.scr`, anything `screen()` opens: Research, Castles, Ledger, Intel, Recorder, Battle calculator, Host tools, Game rules) or a mail view (`ms.tab` of `news`, `inbox` or `chat`, opened from the menu by `openTab()`). `currentView()` describes the state and `pushView()` pushes it onto `ms.stack` (max 20) before any change: `select()` pushes when the selection changes, `openTab()` and `slotHost` always push. `goBack()` pops one entry and restores whichever of screen, tab or selection it held; `goRoot()` clears the stack and returns home. `slotHeader(title, sub, help)` renders every header: a back arrow (hidden at home), the title, a ? that opens `helpDialog(help)` with the manual page for that screen, and a close that calls `goRoot()` (hidden at home). `screen()` outside the map, or with `opts.modal`, still opens a modal; inside the map it hands its content to `slotHost`, which stores it in `ms.scr` and returns a close function that steps back only if that screen is still showing, so a screen that re-opens itself after an order (Research after Make active) lands on the same view. Selections write `#g<gameId>/<t|c><id>` to the URL with `pushState`; screens and mail views do not touch the hash. `popstate` applies the hash and clears any screen; Escape ends an active mode first, then steps back; leaving the game clears the hash and `slotHost`.

### 20b2. Selection pages and the phone strip

A castle renders on one page: `slotHeader` with the state chips as the subtitle; `.sel-hero` with the castle's own `castleSprite` as a portrait and three stats (troops with growth for your own, tier with resources and terrain, the three levels, or the last-seen tick when out of sight); for your own castles `buildSection(t, mintLv)` returns `.cols3` (one column per `INFRA` entry: level, what it yields now using the same formulas as the top bar, a `price` button labelled Buy for N with the optimistic update) and `.sel-actions` (Hire a commander, which toggles `ms.hireOpen` to show the school buttons; Hire mercenaries, which toggles `ms.mercOpen`; Build or Demolish roads); then one `.cmdline2` per commander present with March or Troops and View; then folds: Defence (and production), Trails and supply lines (one fold), Threats, Battles here, Your note and history (one fold); Abandon castle at the foot. `select()` resets `hireOpen`, `mercOpen` and `editStop`. A commander keeps the portrait block; the rename link moved to a pencil in the header; a live route is `routeLines()`, a `.rtable` of rows (number, stop, the order on arrival, ETA tick for the next stop, past stops struck through, the loop row when looping); in the route editor each stop shows a summary with an Edit link that sets `ms.editStop` and reveals the type select and `orderControls` for that stop only.

On phones `selStrip()` is the first child of the panel and only shows at `data-sheet="peek"` (all other children are hidden): the castle sprite or commander card, the troop count, the name, one quick action (the cheapest upgrade for your own castle, or March for an idle commander with troops) and View, which raises the sheet to half.

Marching armies draw as troop figures at every zoom: the `.ak` marker badge (counter-scaled with `--mk` like castle markers) carries `armyFigure()` at 1.25× instead of an arrow, with a shadow ellipse, a red ring when the army is hostile and bound for one of your castles, the selection ring, the troop count above and the name below; the map-unit `.army-fig` remains for the zoomed-in view.

### 20b3. Screens

- **Mail** (`ms.tab = 'mail'`, `ms.mailTab` of `reports`, `messages`, `chat`, `events`; `openTab(k)` maps the old names through `MAIL_SUB` and the view stack keeps the sub-tab). Reports is the former Inbox (reports and battles segments, Mark all read calls `markRead()` and `markBattlesSeen()`); Messages and Chat use `chatView(true)` (no inner bar) with `ms.chatTab` set by the tab; Events is the news feed with a button to `recorderDialog`. The top bar Mail button and the I key open it; N opens Messages with an empty compose.
- **Research**: a toolbar with Researching now (a select that calls `set_active_area` optimistically and re-opens) and Research next (stored in localStorage `ss-next-<gameId>` via `nextArea()`/`setNextArea()`); `load()` keeps the previous level of each area in `ms.areaLv` and, when the active area's level rises and a next area is set, calls `set_active_area` for it, clears the queue and toasts. The realm areas list and Upgrade everywhere left the home state: Spend is `spendSection()` in its own screen, Concede defeat and Host tools are in Options (`openOptions()` passes them to `optionsDialog(extras)`).
- **Castles** (`castlesDialog(tab)`): tabs Castles and Armies (every visible commander: house, troops, where, doing, ETA; row click selects and focuses) and an Expand toggle that adds `wide` to `.mapbody` (panel `min(920px, 78%)`); `slotHost` and leaving the screen remove it. F opens the Armies tab.
- **Empires** (`empireDialog(pid, tab)`, `ms.empirePid`, `ms.empireTab`): a toolbar with previous and next house (`empireStep`, ordered by castles; Left and Right arrows while open), crest, name, style and relation chip, then tabs Empire (castles of the win line, troops seen, commanders, `profileLine`, `diplomacyControls` with Message and Send gold, the house's castles), Production (base yields of the castles you can see: treasury × 10 gold, recruitment × 5 troops, prestige per tick), Research (own areas; others hidden) and Colour (`PALETTE` swatches or House colour, stored per game in `ss-colours-<gameId>` as `ms.colours`; `color(pid)` honours it and `setColour` clears the castle cache). Alt-click on a castle and the name on a leaderboard row open the owner's Empire screen. E opens your own.
- **Quick upgrade** (`ms.quick = { type }`, Q or the tool row; `toggleQuick` ends ruler and march modes): the SVG gets class `quick`, which shows the marker layer at every zoom; each owned castle's marker carries a `mk-q` plate with the track letter and price from `quickPrice()` (cheapest or the chosen track from the mode bar's select, remembered in `ms.quickType`), dimmed when unaffordable; the click resolver routes castle hits to `quickBuy()`, which runs the same optimistic `upgrade_infrastructure` order as the castle page. Escape or Done leaves the mode.
- **Help**: inside the map `helpDialog(section)` renders the manual into the slot (`screen('Help', …, { help: null })`, so the header has no ?): a search box, a collapsible Contents list and the page; outside the map it stays a modal.

### 20c. Keyed panel rendering

`drawSide()` builds the panel's top-level sections and passes them to `patchSide()`. If the view key (selection, tab, mode) changed, the panel is replaced and scrolled to the top. Otherwise each new section is compared with the existing one by `outerHTML`; equal sections are left untouched, so controls keep their identity and typed input values. A section that contains focus or is hovered is not replaced; the panel is marked dirty and redrawn when the pointer leaves the panel or moves to another section. The section that owns a control the player just activated is exempt from the hover guard until the follow-up load completes. The Next move box is a single persistent element, so its asynchronous content never flashes.

### 20d. Order pipeline

`act(button, fn, apply)` marks the button pending (spinner, no pointer events), runs `apply()` if given, which mutates local state and returns an undo function, re-renders, then awaits the RPC. On error the undo runs, the panel re-renders, and the error is shown as a toast. On success the button clears and a lite `load()` refreshes state. Optimistic `apply` functions exist for troop transfer (Take, Leave, the Next move Take button), infrastructure upgrades (level and gold), and setting the active realm area. Everything else gets the pending state only.

### 20e. Load sequencing

`load()` is called every 20 s, on every realtime event (debounced 300 ms) and after each order. Each call takes a sequence number; after each await inside `load()` the call aborts if a newer call has already applied its result, so a slow poll can never overwrite fresher state from a later order.

### 20f. Confirmations and toasts

Native `confirm()` is not used. `confirmDialog(message, label)` opens a modal with the consequence as body text and the action named on the primary button, and resolves to true or false. Toasts carry a dismiss button and stack to three.

### 20g. Home and lobby rendering

The home screen (`showHome`) and the lobby room (`showRoom`) use `patchKeyed(host, items)`: each item has a `key`, a `sig` (a JSON string of the data it renders) and a `build()` function. An item whose key and sig match the element already in the host is left untouched and `build()` is not called; otherwise the element is rebuilt. The home refreshes every 8 s (`list_open_games`, `my_games`, `my_game_invites`, `my_unread`, plus one `games` select for tick, speed, pause and winner of the player's games) and the leaderboard every eighth refresh. Card countdowns are filled from a `data-at` timestamp by a 30 s clock so they never change the signature. The room refreshes every 20 s and on realtime events and patches five sections: header, table, articles, chat and the Begin, Invite and Starting schools panels. The chat input is one persistent element, so focus and a half-typed message survive a refresh.

Castle counts, threats and turn state are not shown on campaign cards because `my_games` does not return them and `game_territories` and `game_players` are not readable by the client. Adding `castles_held`, `castles_to_win` and `under_threat` to `my_games` would allow a Road to victory meter on each card.

### 20h. Setup wizard

`createDialog()` is one screen: name, seat count, seats, land shape, castles per house and pace are always visible; Rules, Realm detail, Houses, Time and Who can join are `<details>` folds whose summary line is recomputed from the controls on every change. The realm preview and a settings summary sit in a sticky aside with the Raise campaign button; the same button repeats at the end of the form. Seats default to one human host plus AI opponents (Baron, balanced), and extra seats added with the stepper are AI. The settings object passed to `create_game` and the `add_ai_seat` calls are unchanged from the five-step wizard.

### 20i. Castle, commander and Realm panels

Castle view order: header; a hero block with state chips (owner and diplomatic standing, king's seat, under threat, besieged, crossing or chokepoint, out of sight) and the troop count and upgrade levels; siege and assault sections when they apply; Build (price buttons, mercenaries, hire a commander) for owned castles; Commanders here with a March or Troops shortcut per idle commander; the threats section only while the castle is threatened; then `pfold()` folds for defence and production (`castle_report`), trails, threats when none, supply lines, battles here, the note, and history; Abandon castle last. Commander view order: header; portrait card with chips, troops, rank and the current status line; Orders (`commanderActions`); a row to open the castle it stands in; folds for abilities (`commander_growth`), chronicle (`commander_chronicle`) and the bio. Realm view order: Next move, offers, events, prisoners, Upgrade everywhere, realm areas, standings as rows (sigil, name, AI style, diplomatic chip, castle count, with the diplomacy controls in an Actions fold per house), mediation and the Hall of the Fallen, and Surrender folded. Fold open state is kept in `ms.folds` by key and reapplied on every draw, so a refresh never closes a fold the player opened. The top bar KPI labels carry a long and a short text; CSS shows the short one under 760 px.

### 20j. Multi-leg marches

`legsTo(fromId, destId)` builds a route for a destination outside one-order range on a trail map. It repeats `trailReach()` from the current castle, and at each step picks the reachable castle held by the player or an ally that is nearest to the destination by straight line, stopping when the destination itself is reachable; it gives up after six legs or when no reachable castle gets closer. `sendLegs()` sends the result with `send_on_route`, intermediate stops with action `nothing` and the final stop with the chosen march type. The march preview uses it when `preview_march` reports `in_range: false`, offering March in N legs and Edit route (which seeds `ms.stops`). Next move uses it when no castle is in one-order reach of any free army: it considers unclaimed castles (garrison 0 when out of sight, as elsewhere) and visible rival castles, nearest first, and offers the first the army can take. No server rule changes: the server still checks each leg when the route runs.

### 20k. Secondary screens

`screen(title, body, opts)` wraps `modal()` and adds the `screen` class: a left-aligned title bar with a close button, optional `opts.sub` line, optional tabs (`opts.tabs` as `[key, label]` pairs with `opts.render(key)` building the body) and an optional `opts.toolbar`; `opts.wide` widens it. It returns `{ close, show, body }`. Menu, Research, Intel, Ledger, Recorder, Castles, Host tools, Game rules and Battle calculator use it; Options keeps a plain modal because it has Save and Cancel. The Empires dialog is gone: its standings live in the Realm panel (each row now has a castles-toward-win meter and troops seen), and its private group editor is the Groups tab of Intel, which the charts' group mode reads through `loadGroups()`. Research shows an ETA for every area, computed from `research_info` income as the active area's time to next level or the time it would take if made active, and Make active applies optimistically. The Inbox panel's Reports and Battles are a segmented control.

### 20l. Map layer interaction

The Treasury KPI in the top bar carries `productionText()`: the clock time until the next production (`last_tick_processed_at` + ticks left in the cycle × tick interval), refreshed each second by `updateCountdown()`. Home cards show the same as `Production in …` via `productionAt()` and `fillLive()`.

A capture-phase click listener on the map SVG resolves every click in screen pixels using `svg.getScreenCTM()`: first the nearest moving or besieging commander within 22 px (30 px on touch), skipped entirely while march or ruler mode is on so a destination click always lands on a castle, then the nearest non-junction castle within 40 px (48 px on touch), with a small downward bias so taps on the sprite body land on its base. A hit stops propagation and calls `select()`; a miss on the bare SVG clears the selection. Marker and plate `onclick` handlers remain as a fallback. The selected castle's mark and plate are moved to the end of their layers so they draw on top, with a `selring` dash animation. Troop badges render only when a count is known or remembered (no question mark). `ms.flash` records castles whose owner changed on a load; their marks and plates get a one-shot `mk-flash` ring and a re-render clears it after 1.7 s. The threat ring (`mk-threat`) pulses three times and then holds. `toggle3D()` adds an `xfade` class to the map wrapper for a 300 ms opacity crossfade. All of it is disabled under `prefers-reduced-motion`. Map art, sprites and terrain are untouched.

### 20m. Phone and tablet layouts

Under 760 px `.mapbody` stacks the map, a `.sheetbar` handle and the panel. The panel's height is `--sheet`, set by `data-sheet` on the body: `peek` (52 px, the tab strip), `half` (46 %) and `full` (84 %). The handle cycles the states on tap and steps them on a vertical drag of more than 30 px (pointer capture), and supports Enter, Space and the arrow keys. `select()` raises a `peek` sheet to `half` on a phone. The legend is hidden on phones and toggled by a Legend button in the map controls (`.mapwrap.legend-open`). Between 761 and 1000 px the side panel is 340 px wide and the victory meter shorter. Secondary screens fill the window under 760 px (section 20k). The 3D map stays off on touch devices.

### 20n. Loading, empty and error states

`showMap` mounts a `.maploading` overlay inside the map wrapper; the first successful `load()` fades it out, and a load that fails before any game data replaces it with a message and a Try again button. A `.connbar` under the top bar shows on the `offline` event and after two consecutive failed loads while online, and clears on `online` (which forces a load) or the next successful load. `skeleton(rows)` returns shimmer placeholder lines used by the castle report, chronicle, history, growth, friends and leaderboard while their RPCs run. `emptyState(text, action)` renders a dashed box with explanatory copy and an optional button; News, Reports and Battles use it. `toast(message, ok, action)` accepts an optional `{ label, fn }` button and then stays for 12 s. When a load shows the player gained a castle while sound is off, a one-time toast (flag `ss-sound-nudge` in localStorage) offers to turn sound on.

- **Only production is counted down (October 2026).** The top bar and the home campaign cards no longer show a countdown to the next tick, as in NP. The Treasury figure shows the clock time to the next production, the home cards show "Production in ...", and the tick number stays. Paused games say so; turn-based games still show the turn deadline.

## 51. Docked Panels, Drop-down Menu, No Next Move (October 2026)

- **Next move and in-game coaching removed.** The Realm panel no longer has a Next move box, the "read the two-minute guide" hint, the hire advice or the gold hint, and empty lists no longer offer to open Next move. The Realm panel now starts with offers and events, then Upgrade everywhere. The Help button and the manual remain. `nextMoveSection` and the server-checked `validMarch` were deleted; castle and commander panels keep their own March, route and reachability features.
- **Docked panels (superseded).** `screen()` briefly rendered as a `.dock` beside the side panel; since the slot rebuild every screen opens inside the side panel itself (section 20b).
- **Menu.** The Menu button opens a drop-down (`.menu-pop`) under the button instead of a full dialog, closing on outside click, Escape, a second press or choosing an item, with `aria-expanded`. Options, How to play, confirmations and action dialogs stay modal.
- **Production-only countdown.** See the earlier note in this section: the top bar and home cards count down to the next production, not the next tick.

## 52. Simplified Hiring And Castle Page (October 2026)

- **One hire button.** A castle page offers a single Hire a commander button at `games.commander_cost` (25 gold by default). The client calls `hire_commander` with the Battleschool, so every hired commander starts the same way. The school picker is gone; the server function, the three schools and the starting-school choice in the wizard are untouched, and schools are no longer shown in commander headers and lists. Parking lot: choosing a school at hire.
- **Mercenaries removed from the live game.** The Hire mercenaries button and its panel are deleted from the castle page. The server (`hire_mercenaries`, `mercenaries_enabled`, default false and hidden from setup) is untouched. Parking lot.
- **Castle page sections removed:** Defence and production (the castle report box), Threats (the folded section and the incoming-force box; a castle that is under threat only carries the red Under threat chip and the top-bar tile), Supply lines, and Your note with its tags and map badges. The `castle_notes` table and its RPCs stay for later. The Taking this castle panel still gives an enemy castle's defenders and the troops needed.
- **Linked castles.** The Trails section is now Linked castles: each castle joined to this one by a trail, with only the number of ticks an army takes to walk there, from the leg's length, its terrain cost and the march speed (17.5 x speed multiplier x speed basis x unit scale, or the speed of the last march preview). Distance, terrain and speed text are gone. `games.speed_basis` is now read by the client.
- **Top bar: no gear, no lock (October 2026).** The gear button that opened a tile picker and the lock icon on the Production tile are removed. The four tiles around Production are chosen only in Menu, Options, under Top bar (the same slot pickers that were already there). Production still sits in the centre.
- **Reload keeps you in the game (October 2026).** On sign-in, `onSession` reads the `#g<id>` part of the address and calls `openGame` for it instead of always showing the home screen, so a refresh lands back in the same game with the selected castle or army (`#g<id>/t<id>` or `/c<id>`) restored and the data reloaded. A game that no longer exists, or that you are not in, falls back to the home screen. Open screens (Research, Mail and so on) and the lobby are not part of the address and do not come back after a reload.

## 53. Move Troops And March On Commander Rows (October 2026)

- **Two buttons per commander.** On a castle page each of your idle commanders has Move troops and March; the old Troops and View buttons are gone. The commander's name is the link to the commander page.
- **Move troops** opens a slider under the row: castle count on the left, commander count on the right, All to commander, Half and All to castle presets, and one button that reads Take N or Leave N. It calls `transfer_troops` with a positive (take) or negative (leave) amount and updates the numbers at once (rolled back on error). The castle keeps at least 1 troop. The same control replaces the number box with separate Take and Leave buttons on the commander page.
- **March** is greyed out with the hint "Move troops to this commander first" while the commander has no troops; otherwise it opens the commander and arms the march destination picker.
- **Reference point:** NP's carrier is not auto-filled either; the player chooses how many ships go with it.
- **Panel buttons now respond while the pointer is over them.** The side panel never replaces a section the pointer is over or that holds focus, so a refresh does not move buttons under the player. That rule also swallowed button presses that only change what is shown, because the pointer is always over the button just pressed (Move troops opened its slider only when the pointer happened to be elsewhere). A click now marks its own section as allowed to redraw for that click (`ms.clickSec`), which fixes Move troops and the same pattern on stop editing, mail tabs, new message, thread and battle back buttons.

## 54. One March Builder And Editing A Route In Flight (migration 20261024640000)

- **One flow.** March puts the map straight into waypoint mode. Every click adds a stop (no separate single-destination preview or "Start a route here"). The lit-castle glow (and the dimming of everything else) recentres on the last stop each time, as before. A castle that cannot be reached from the last stop in one order but can through castles you or an ally hold gets the stops on the way added automatically (`legsTo`). One stop is a plain march.
- **Loop by clicking the start.** Clicking the castle the army started from, with at least one stop set, toggles the loop; the loop returns there and repeats. The panel shows "Waypoints: A, B, C, then back to X", the ETA to the last stop, Undo last, Clear and Send. ETAs use the march speed the server uses (17.5 x speed multiplier x speed basis x Pace x unit scale), so they show without a server preview.
- **Server fix.** `send_on_route` validated a loop's return leg from the last stop to the first stop; the army actually returns to its origin, so the return leg (last stop to origin) is validated now. `edit_route` does the same.
- **`edit_route(game, commander, stops, options)`.** Replaces the stops from the army's next stop onward on an active route. While the army is moving the first stop (its destination and march type) is locked: it must be repeated unchanged, though its action, amount and wait can change. Later stops can be changed, added or removed; each leg is checked against range as in `send_on_route`. While the army waits at a stop (`resume_tick` set) every remaining stop can change. Stops already passed are kept. At most 20 stops in all; loop and origin order can be changed with options. Refused when the army is on the way back to its origin.
- **Commander page.** A moving or waiting commander with an active route shows the stop table (stop, action on arrival, ETA) with Edit route and Loop. Edit route reopens the builder with the locked stop marked "on its way" and a Save route changes button.

## 55. Strict Range, Range Circle (migration 20261024650000)

- **No exemption for neighbours.** `plan_march` and `plan_march_from` used to treat a route of exactly two castles (one hop) as in range whatever its length. `in_range` is now `raw length <= range` for every route (raw length is trail length times terrain cost). The client's `trailReach` matches, so a castle joined to yours by a trail but beyond your range is not lit and cannot be targeted.
- **Range circle.** In march mode a dotted circle with the range as its radius is drawn around the commander, or around the last stop added (it was drawn only in free-travel games). Castles inside it that your trails reach glow.
- **Measured effect (sim game 286, three AIs, idle human, base range 2.8 leagues at Stables 1):** castles were 6, 4, 4, 4 at tick 40 and 11, 5, 4, 4 at tick 108, against about 35, 28, 19, 4 at tick 114 before. The first capture came at tick 27 instead of 8 to 14. About half of all trails (49 to 61 percent in three maps) are longer than the base range, and Stables research is too slow to change that early (about 144 prestige per level at a few prestige a cycle). Decision October 2026: keep it and see how it plays. Levers if it plays too slowly: raise the base range (3.6 leagues makes about 82 percent of trails usable), or make Stables research cheaper.

