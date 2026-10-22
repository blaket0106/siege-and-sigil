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
- Seasons (winter penalties, autumn gold bonus).
- Mercenary companies.
- Random event deck (plague, unrest, harvest, comet) with optional responses.

### UI / Intelligence
- News bulletin tab: the News tab already carries the public record (war declarations, eliminations, captures, sieges, world events); alliances and pacts stay private.

---

## Left

- **Naval mechanics** — fleet building, naval transport, naval combat, an 8th council seat, coastal adjacency. Needs map generation to mark coastal territories and a new unit type across movement, combat and AI.
- **Named council seat characters** — each of the 7 seats filled by a named character who can be deployed to the field (losing the seat bonus) or killed (seat vacant until replaced). Needs a council seat system to exist first.
- **AI council advisor** — per-seat AI voice answering live game state in character. Needs an Anthropic API key, a server-side call and a per-question cost budget.
- **Character personalities in the intel system** — procedurally generated traits for named commanders and council members, used by the advisor and AI-written whispers. Depends on the two items above.

---

*Added October 2026. V1 is pure PvP, single index.html, no co-op.*
