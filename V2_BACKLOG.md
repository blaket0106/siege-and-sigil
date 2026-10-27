# Siege & Sigil — V2+ Feature Backlog

All items are generic — no IP dependencies. Built items are listed with where the spec describes them (`MECHANICS_REFERENCE.md`, section 20ab). What is left is at the bottom.

---

## Built

### Diplomacy
- Non-aggression pact, formal war declaration, marriage alliance, peace terms and tribute, mediation, trade agreements.
- Diplomatic reputation: honor and infamy from profiles, shown as Trusted, Unproven or Notorious.

### Military
- Commander capture with ransom, release, execution and escape.
- Named commander death consequences (prestige loss, temporary morale penalty).
- Split skill tracks: Field (Valor, Tactics), Siege Offense (Siegecraft), Siege Defense (Bulwark).
- Generic commander promotion at five wins.
- Smoother army movement between ticks.

### World
- Seasons (winter penalties, autumn gold bonus). Built but hidden from setup for now.
- Mercenary companies. Built but hidden from setup for now.
- Random event deck (plague, unrest, harvest, comet) with optional responses. Built but hidden from setup for now.

### Council
- Named council seat characters: seven seats, seven named councillors per player, deployable to the field (seat bonus lost while away) or killable (seat vacant until a replacement is recruited). Built, with the player-facing section parked (see the parking lot below).

### UI / Intelligence
- News bulletin tab: the News tab already carries the public record (war declarations, eliminations, captures, sieges, world events); alliances and pacts stay private.

---

## Left

- **Naval mechanics** — fleet building, naval transport, naval combat, an 8th council seat (Admiral), coastal adjacency. Needs map generation to mark coastal territories and a new unit type across movement, combat and AI.
- **AI council advisor** — per-seat AI voice answering live game state in character. Needs an Anthropic API key, a server-side call and a per-question cost budget.
- **Character personalities in the intel system** — procedurally generated traits for named commanders and council members, used by the advisor and AI-written whispers (councillors are ready to carry them). Councillors now exist, so this depends only on the advisor.

- **Named councillors in the Info panel (parking lot)** — the Council section of the right-hand Info panel (named councillor per seat with portraits, Deploy to the field, Recall to court, Recruit a replacement) has been taken off the screen for now. Everything behind it still runs: every seat keeps its named councillor at court, so seat bonuses still apply, and the server functions (`deploy_councillor`, `recall_councillor`, `recruit_councillor`), AI behaviour, profiles and portraits are untouched. The section was removed from `index.html` in the commit after 312bbd2; restore it from git history (`councilSection`) when the idea comes back. Open questions: whether deploying a seat's councillor is worth the bonus loss, and where it should live (Realm panel or a dedicated council page).
- **House boosts (parking lot)** — each house gets a real gameplay identity that matches its lore `known_for` line (Kaldran stronger walls and watchtowers, Veyra alliances and learning, Dravos arms and siege engines, Halcyr fast marches and stables, Mereth gold and hired captains, Ostrand river crossings and coastal levies, Thornwick scouts and patient defence, Brannoch large cheap levies). Step one is a design doc proposing one boost per house for review, then balancing with sims. `factions.modifier` (jsonb) is reserved for it.
- **Supply-line helper for players (parked)** — a one-click looping route builder and map flow arrows. Parked until after the AI balance and end-game work.
- **Commander fate and capture (parking lot)** — how commanders are treated after a lost battle (today they die with the army) and whether commanders can be captured, ransomed or spared on a first loss. Decided October 2026 to leave the current rule (they die) until this is designed as one system.
- **Territory shading (watch)** — a region tint for ownership. Not built; revisit if testing shows ownership is still hard to read with the castle glow and ring. Neptune's Pride does not tint regions, so this is not required to match it.
- **AI attitude indicator (parking lot)** — show how each AI feels about you in Standings, with what raises or lowers it, like Neptune's Pride's regard meter. Needs AI diplomacy to react to player behaviour first. Decided October 2026 to revisit later.
- **Pace and spacing review (next playtest)** — with leagues in, evaluate ticks per hop, castle spacing in leagues, castles per house and production together, and decide the base bundle (speed basis, spacing, castles per house, production) and which settings are variants of it. Decided October 2026: the base is one tuned bundle (see MECHANICS_REFERENCE.md section 42) with map size and speed as named variants. Re-check it against each playtest.
- **Party mode: the board game in a room (the dream, parking lot, Oct 2026).** Friends in one room play one game. A host (game master) shares or casts a big-screen view to a TV. Everyone joins from their own phone or laptop with a short room code, as in Jackbox, plans orders privately on their device and presses End turn. When everyone is ready the TV plays the whole turn out cinematically in real time (marches, sieges, battles, captures, diplomacy beats), then the next planning round starts.
  - **What already exists:** turn-based mode (`submit_turn`, `turn_status`, ticks per turn, turn timeout), join by code (`lookup_game_by_code`), host controls, AI seats to fill the table, a replay engine over `territory_owner_log`, battle reports, the 3D map and the portraits.
  - **What is missing:** a TV/host display client with no controls (a spectator role that sees the whole board); a phone controller layout built for one-handed planning; a turn playback director that replays one resolved turn from the event log (movement per tick, battles, captures) with camera cuts, pacing and sound; a room lobby with live roster and ready states; reconnect after a dropped phone; a rule for fog (the shared TV shows public information, so either fog is off in party mode or the TV shows only what everyone can see and secrets stay on the phones).
  - **Open questions:** length of a turn (probably 6 ticks, about 45 to 90 s of playback); length of a session (60 to 90 minutes, which implies faster victory pacing and decay); simultaneous orders versus a short timer; how much the TV narrates (names, banners, a chronicler's voice); whether the host can also play.
  - **First steps when it comes up:** a feasibility spike for the playback director on a finished game (replay one turn with camera cuts), and a spectator role on the server. Everything else builds on those.
- **Mercenaries (parking lot, removed from the live game October 2026)** — 5 gold per troop, 48-tick companies hired at a castle. Server (`hire_mercenaries`, `mercenaries_enabled`) is intact; the castle page button is removed and setup hides it. Needs a proper design for upkeep, expiry and AI use before it returns.
- **School-based commander hires (parking lot, simplified October 2026)** — Battleschool, University and Rangers, chosen at hire. Today one Hire a commander button pays the flat price and hires a Battleschool commander. Revisit with commander fate and house boosts.
- **Supply-line view on castles (parking lot)** — which of your routes start or stop at a castle and what the commander does there. Removed from the castle page; the route data still exists. Fits with the supply-line helper above.
- **Castle notes and tags (parking lot, removed October 2026)** — a private tag (Staging, Target, Watch, Fortress, Supply, Danger) and note per castle. The table and RPCs stay.
- **Story line and our own world map (parking lot, Oct 2026).** A real story background for the game, and a hand-made base map that carries it, so the game is set in its own world with its own lore and rivalries between its houses and factions, not a stand-in for Westeros or Middle-earth.
  - **What exists:** the Aldermark lore (the Concord of the Eight Seals, the Hollow Year, the Hollow Crown) in the manual's History of the realm, eight houses with heraldry, a `known_for` line, named leaders and portraits, a generated end-of-game story, and a generator that makes a new terrain map for every game.
  - **What is missing:** a fixed canonical map (named regions, rivers, passes, a capital, historic battlefields) that houses start on in a meaningful place; house-versus-house backstory (old feuds, marriages, betrayals) that the AI and the chat can quote; story beats that react to what players do; a campaign structure or scenario set that uses the map.
  - **Open questions:** one fixed map or a family of hand-drawn maps with the generator filling the rest; how much lore is shown in game and how much is a separate codex; whether the AI personalities should follow house lore (ties to house boosts); who writes it and in what voice.
  - **Links:** house boosts, AI attitude indicator and the party-mode chronicler's voice all want this lore.
- **NP parity (closed October 2026):** regard meter, research screen, ledger, group analysis in Intel, Recorder, scores and badges, abandon castle (see MECHANICS_REFERENCE.md section 49). Not built: carrier default action and per-label numeric zoom thresholds (Options already has per-label rules).

---

*Added October 2026. V1 is pure PvP, single index.html, no co-op.*
