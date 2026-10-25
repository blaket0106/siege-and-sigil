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

---

*Added October 2026. V1 is pure PvP, single index.html, no co-op.*
