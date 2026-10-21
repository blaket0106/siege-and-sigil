# Siege & Sigil — V2+ Feature Backlog

Everything here is out of scope for V1 but worth building toward. All items are generic — no IP dependencies.

---

## Diplomacy

These collectively make the diplomacy system significantly deeper than Neptune's Pride's binary neutral/allied model.

- **Non-Aggression Pact (NAP)** — sits between neutral and allied; breaking one costs prestige. Gives players a middle-ground commitment without full alliance.
- **Formal war declaration from neutral** — public announcement visible to all players; creates a "state of war" distinct from simply attacking.
- **Marriage Alliance** — locked for a fixed number of ticks; cannot be broken early. Higher-commitment alliance tier.
- **Peace terms / tribute offers** — formal war-ending proposals (surrender terms, ongoing tribute, territory transfer).
- **Mediation** — third-party arbitration between two factions at war. Mediator can broker a deal both sides accept.
- **Formal trade agreements** — recurring gold routes with a set amount per cycle; separate from one-off gold gifts. Can be part of peace terms.
- **Diplomatic reputation score** — cross-game trust rating visible to other players; accrued or lost based on pacts honored/broken, alliances betrayed, etc.

---

## Military

- **Commander capture** — after a losing battle, commander may be captured (random or skill-based chance) instead of killed. Captor can ransom, execute, or hold. Captured commander can attempt escape.
- **Named commander death consequences** — when a named commander dies, faction loses prestige and suffers a temporary morale penalty.
- **Split commander skill tracks** — commanders specialize along three tracks: Field (open combat), Siege Offense, Siege Defense. XP earned from relevant combat type.
- **Generic commander promotion** — unnamed sworn swords can earn a permanent name + bonus after enough combat wins (merit-based, not purchased).
- **Sub-tick army animation** — smooth marker movement between territories each tick rather than snap-to.

---

## Council

- **Named council seat characters** — each of the 7 seats is filled by a named character (procedurally generated per game). Character can be deployed to the field (losing seat bonus while away) or killed in battle (seat vacant until a replacement is recruited). Creates meaningful tension between field use and seat security.

---

## World

- **Seasons** — tick-based cycle (Spring → Summer → Autumn → Winter). Winter applies regional troop production penalties and movement speed penalties. Duration configurable per game.
- **Naval mechanics** — fleet building, naval transport, naval combat between fleets. Adds an 8th council seat (Admiral / Master of Ships equivalent). Coastal territories gain naval adjacency.
- **Mercenary companies** — neutral-faction units available for gold hire. No council loyalty, no prestige, but available to anyone who can pay. Disbands after a set number of ticks or when contract ends.
- **Random event deck** — periodic events drawn from a deck (plague, bumper harvest, rebellion, comet sighting, etc.). Some affect single territories, some affect whole regions. Players can respond or ignore.

---

## UI / Intelligence

- **News bulletin tab** — public record of major game events. Alliances stay private. War declarations, faction eliminations, and territory captures are public. Replaces or supplements the inbox for global events.
- **AI council advisor** — per-seat AI voice responds to live game state when queried. Each filled seat responds in character (Commander = military strategy, Treasurer = economic advice, Spymaster = intelligence summary, etc.). Capped to filled seats + most relevant 3–4. Pairs with named council characters for personality injection.
- **Character personalities in intel system** — procedurally generated personality traits for named commanders and council members, injected into AI-generated whispers and advisor responses.

---

*Added October 2026. V1 is pure PvP, single index.html, no co-op.*
