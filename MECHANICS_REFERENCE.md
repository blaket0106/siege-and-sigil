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
| Road | `floor(10000 / natural_resources)` |

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
road_speed = base_speed × 3   (52.5 leagues/tick at 1.0 multiplier)
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
- `build_road(game, territory)`: cost `floor(10000 / natural_resources × infra_cost_mult)`. `demolish_road` is free and refunds nothing.
- `send_gold(game, target_player, amount)`: ledger rows for both sides, inbox message for the receiver. Not allowed to self or to eliminated players.
- `set_active_area(game, area)`: sets the single active project; progress in other areas is kept.
- `assign_garrison_commander(game, commander)` / `unassign_garrison_commander(game, territory)`: the commander must be idle at one of your territories. Assigning replaces any current garrison commander there.
- `crown_commander(game, commander)`: only when you have no living king; effective after `coronation_ticks`. King effects are active when `role = 'king'`, alive, and `coronation_tick` is null or reached (start-of-game kings have a null tick).
- Internal (no client access): `acting_player`, `infra_cost`, `add_area_prestige` (adds prestige to an area and levels it up at `ceil(144 × level × area_cost_mult)` per level; Guildhall level-ups refresh `resources`), `refresh_effective_influence` (`natural_resources + 5 × Guildhall level`; also needed after a capture).
- Not built: heir designation, area prestige flow (tick engine), commander disbanding.

### 20m. Movement (orders implemented; execution is the tick engine's job)

- **Pathing:** Dijkstra over `territory_edges`, minimizing travel time. A commander may pass **only through territory owned by himself or an ally** (formal alliance). The destination can be anything, so contact with an enemy or neutral castle is always the end of an order, and castles block movement. No friendly corridor to the destination means no route.
- **Speed:** `17.5 × commander_speed_mult × (1 + 0.10 × Pace level)`, units per tick; Pace uses the higher of the commander's own level and the king's floor (king level - 1, king active only after `coronation_tick`). Each edge costs `length × move_cost_mult`, divided by 3 when both of its end territories have a road.
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

AI players (`is_ai`, no user) play through the same internal rules as humans. `run_ai_players` is the first step of every tick (`resolve_tick_events`); each AI acts when `(tick + player id) % interval = 0`, where interval is 6 / 4 / 3 / 2 / 1 ticks for `ai_difficulty` 1 to 5. An error in one AI's turn is logged as an `ai_error` event and rolled back without affecting the tick.

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
- **Castles:** radius by tier, troop count above, name below, commanders as dots (gold ring = king), capital marked with a crown. Marching commanders are interpolated along `commander_movements.path` using `path_arrival_ticks` and the fraction of the current tick elapsed (`last_tick_processed_at` plus the tick interval); own marches show a dotted route.
- **Fog (client-side, `fog_of_war` games):** own and allied castles and commanders are always visible. A castle scans `90 + 60 x Watchtowers level` (allied castles 90); a commander scans `45 + 15 x rank + 30 x Scout`. Anything else shows its last-known owner as a faded ghost with troops hidden, remembered in localStorage per game and user. Enemy commanders are shown only inside a scan range. Fog is enforced on the server (section 20x); `intel_snapshots`, which hold every player's gold and troop totals, are readable only after the game ends or in games without fog.
- **Panels:** top bar (tick, countdown to next tick, gold, castles toward the win threshold, scan-ring toggle); side panel for the realm and standings, a selected castle (owner, troops, levels, commanders, roads), or a selected commander (rank, troops, status, abilities).
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
  - **Client:** roads are no longer drawn except built roads between neighbours; selecting a commander in march mode dims castles you cannot reach and shows the range ring; the castle panel lists castles within range with the crossing type.
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
3. **Roads upgrade a trail.** A road is built between two castles that share a trail edge, as today (cost `6 x resources`, speed `sqrt(Stables + 3)` between two roaded castles). It follows the trail's path. A route's travel time is the sum over its edges, so a chain of roads makes a fast highway.
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
