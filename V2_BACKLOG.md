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
- Named council seat characters: seven seats, seven named councillors per player, deployable to the field (seat bonus lost while away) or killable (seat vacant until a replacement is recruited).

### UI / Intelligence
- News bulletin tab: the News tab already carries the public record (war declarations, eliminations, captures, sieges, world events); alliances and pacts stay private.

---

## Left

- **Naval mechanics** — fleet building, naval transport, naval combat, an 8th council seat (Admiral), coastal adjacency. Needs map generation to mark coastal territories and a new unit type across movement, combat and AI.
- **AI council advisor** — per-seat AI voice answering live game state in character. Needs an Anthropic API key, a server-side call and a per-question cost budget.
- **Character personalities in the intel system** — procedurally generated traits for named commanders and council members, used by the advisor and AI-written whispers (councillors are ready to carry them). Councillors now exist, so this depends only on the advisor.

- **House boosts (parking lot)** — each house gets a real gameplay identity that matches its lore `known_for` line (Kaldran stronger walls and watchtowers, Veyra alliances and learning, Dravos arms and siege engines, Halcyr fast marches and stables, Mereth gold and hired captains, Ostrand river crossings and coastal levies, Thornwick scouts and patient defence, Brannoch large cheap levies). Step one is a design doc proposing one boost per house for review, then balancing with sims. `factions.modifier` (jsonb) is reserved for it.
- **Supply-line helper for players (parked)** — a one-click looping route builder and map flow arrows. Parked until after the AI balance and end-game work.

---

*Added October 2026. V1 is pure PvP, single index.html, no co-op.*
