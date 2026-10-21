export const GENERATOR_VERSION = 1;
export const SPACING = 150;

const MARGIN = 60;
const TERRITORIES_PER_PLAYER = { compact: 6, standard: 9, large: 14 };
const BASE_INFLUENCE = { 1: 2, 2: 4, 3: 6 };
const INFLUENCE_PER_GUILDHALL_LEVEL = 5;
const START_GUILDHALL_LEVEL = 1;
const TIER_TWO_SHARE = 0.4;
const STYLES = {
  scatter: { minDist: 0.7, prune: 2.0, clustered: false },
  continents: { minDist: 0.55, prune: 1.4, clustered: true },
};

const PREFIXES = [
  'Ash', 'Black', 'Bran', 'Cold', 'Dun', 'East', 'Elm', 'Fen', 'Gray', 'High',
  'Iron', 'Kings', 'Low', 'Mar', 'Oak', 'Pike', 'Red', 'Rook', 'Salt', 'Silver',
  'Stone', 'Thorn', 'West', 'White', 'Fair', 'Mill', 'North', 'South', 'Birch',
];
const SUFFIXES = [
  'hold', 'mere', 'wick', 'ford', 'gate', 'haven', 'watch', 'crest', 'moor', 'fell',
  'stead', 'bridge', 'hollow', 'barrow', 'cliff', 'dale', 'keep', 'march', 'wood', 'field',
];

function mixSeed(seed, salt) {
  let h = (0x9e3779b9 ^ salt) >>> 0;
  const parts = [seed >>> 0, Math.floor(seed / 4294967296) >>> 0, GENERATOR_VERSION];
  for (const part of parts) {
    h = Math.imul(h ^ part, 0x85ebca6b);
    h ^= h >>> 13;
    h = Math.imul(h, 0xc2b2ae35);
    h ^= h >>> 16;
  }
  return h >>> 0;
}

function mulberry32(a) {
  return function () {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function makeRng(seed, salt) {
  return mulberry32(mixSeed(seed, salt));
}

function rotate(p, angle) {
  const c = Math.cos(angle);
  const s = Math.sin(angle);
  return { x: p.x * c - p.y * s, y: p.x * s + p.y * c };
}

function gaussian(rng) {
  const u = Math.max(rng(), 1e-12);
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * rng());
}

function round4(value) {
  return Math.round(value * 1e4) / 1e4;
}

function placeWedge({ rng, players, perPlayer, start, radius, wedge, minDist, clustered }) {
  const placed = [];
  const locals = [];
  const innerMin = minDist / (2 * Math.sin(Math.PI / players));
  const minSq = minDist * minDist;

  const fits = (p) => {
    const rr = Math.hypot(p.x, p.y);
    if (rr > radius * 0.97 || rr < innerMin) return false;
    for (let k = 0; k < players; k++) {
      const q = rotate(p, k * wedge);
      for (const o of placed) {
        if ((q.x - o.x) ** 2 + (q.y - o.y) ** 2 < minSq) return false;
      }
    }
    return true;
  };

  const commit = (p) => {
    for (let k = 0; k < players; k++) placed.push(rotate(p, k * wedge));
    locals.push(p);
  };

  const capR = radius * (0.5 + rng() * 0.15);
  const capT = wedge * (0.4 + rng() * 0.2);
  const capital = { x: capR * Math.cos(capT), y: capR * Math.sin(capT) };
  if (!fits(capital)) return null;
  commit(capital);

  for (let j = 1; j < start; j++) {
    let p = null;
    for (let t = 0; t < 300 && !p; t++) {
      const a = rng() * 2 * Math.PI;
      const d = minDist * (1 + rng() * 0.8);
      const c = { x: capital.x + d * Math.cos(a), y: capital.y + d * Math.sin(a) };
      if (fits(c)) p = c;
    }
    if (!p) return null;
    commit(p);
  }

  const centers = [capital];
  if (clustered) {
    for (let c = 0; c < 2; c++) {
      for (let t = 0; t < 120; t++) {
        const r = radius * (0.3 + rng() * 0.55);
        const a = wedge * rng();
        const cand = { x: r * Math.cos(a), y: r * Math.sin(a) };
        const apart = centers.every((o) => Math.hypot(cand.x - o.x, cand.y - o.y) >= SPACING * 2.2);
        if (apart) {
          centers.push(cand);
          break;
        }
      }
    }
  }

  const sample = () => {
    if (!clustered) {
      const r = radius * 0.97 * Math.sqrt(rng());
      const a = wedge * rng();
      return { x: r * Math.cos(a), y: r * Math.sin(a) };
    }
    const home = rng() < 0.4 || centers.length === 1;
    const center = home ? centers[0] : centers[1 + Math.floor(rng() * (centers.length - 1))];
    return { x: center.x + gaussian(rng) * SPACING * 0.55, y: center.y + gaussian(rng) * SPACING * 0.55 };
  };

  for (let j = start; j < perPlayer; j++) {
    let p = null;
    for (let t = 0; t < 400 && !p; t++) {
      const c = sample();
      if (fits(c)) p = c;
    }
    if (!p) return null;
    commit(p);
  }

  return locals;
}

function circumcircle(a, b, c) {
  const d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y));
  if (Math.abs(d) < 1e-12) return { cx: 0, cy: 0, r2: Infinity };
  const a2 = a.x * a.x + a.y * a.y;
  const b2 = b.x * b.x + b.y * b.y;
  const c2 = c.x * c.x + c.y * c.y;
  const cx = (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d;
  const cy = (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d;
  return { cx, cy, r2: (a.x - cx) ** 2 + (a.y - cy) ** 2 };
}

function delaunayEdges(points) {
  const n = points.length;
  const xs = points.map((p) => p.x);
  const ys = points.map((p) => p.y);
  const minX = Math.min(...xs);
  const maxX = Math.max(...xs);
  const minY = Math.min(...ys);
  const maxY = Math.max(...ys);
  const span = Math.max(maxX - minX, maxY - minY) || 1;
  const midX = (minX + maxX) / 2;
  const midY = (minY + maxY) / 2;
  const verts = points.concat([
    { x: midX - 20 * span, y: midY - span },
    { x: midX, y: midY + 20 * span },
    { x: midX + 20 * span, y: midY - span },
  ]);

  const makeTri = (a, b, c) => ({ a, b, c, ...circumcircle(verts[a], verts[b], verts[c]) });
  let triangles = [makeTri(n, n + 1, n + 2)];

  for (let i = 0; i < n; i++) {
    const p = verts[i];
    const bad = [];
    const good = [];
    for (const t of triangles) {
      ((p.x - t.cx) ** 2 + (p.y - t.cy) ** 2 < t.r2 - 1e-7 ? bad : good).push(t);
    }
    const counts = new Map();
    for (const t of bad) {
      for (const [u, v] of [[t.a, t.b], [t.b, t.c], [t.c, t.a]]) {
        const key = u < v ? `${u},${v}` : `${v},${u}`;
        counts.set(key, (counts.get(key) || 0) + 1);
      }
    }
    triangles = good;
    for (const [key, count] of counts) {
      if (count !== 1) continue;
      const [u, v] = key.split(',').map(Number);
      triangles.push(makeTri(u, v, i));
    }
  }

  const edges = new Set();
  for (const t of triangles) {
    if (t.a >= n || t.b >= n || t.c >= n) continue;
    for (const [u, v] of [[t.a, t.b], [t.b, t.c], [t.c, t.a]]) {
      edges.add(u < v ? `${u},${v}` : `${v},${u}`);
    }
  }
  return [...edges].map((key) => key.split(',').map(Number));
}

function makeNames(count, rng) {
  const used = new Set();
  const names = [];
  while (names.length < count) {
    const name = PREFIXES[Math.floor(rng() * PREFIXES.length)] + SUFFIXES[Math.floor(rng() * SUFFIXES.length)];
    if (used.has(name)) continue;
    used.add(name);
    names.push(name);
  }
  return names;
}

function findRoot(parent, x) {
  while (parent[x] !== x) {
    parent[x] = parent[parent[x]];
    x = parent[x];
  }
  return x;
}

export function assignSeats(seed, playerIds) {
  const rng = makeRng(seed, 3);
  const seats = [...playerIds];
  for (let i = seats.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [seats[i], seats[j]] = [seats[j], seats[i]];
  }
  return seats;
}

export function generateWorld({ seed, players, mapSize, startingTerritories, style, startingGarrison }) {
  const perPlayer = TERRITORIES_PER_PLAYER[mapSize];
  const styleConfig = STYLES[style];
  if (!perPlayer) throw new Error(`unknown map size: ${mapSize}`);
  if (!styleConfig) throw new Error(`unknown map style: ${style}`);
  if (!Number.isInteger(players) || players < 2 || players > 8) throw new Error(`players must be 2 to 8, got ${players}`);
  if (!Number.isInteger(startingTerritories) || startingTerritories < 1 || perPlayer - startingTerritories < 2) {
    throw new Error(`starting_territories must leave at least 2 neutral territories per player on a ${mapSize} map`);
  }

  const total = players * perPlayer;
  const radius = SPACING * Math.sqrt(total / Math.PI);
  const center = radius + MARGIN;
  const wedge = (2 * Math.PI) / players;
  const rng = makeRng(seed, 1);
  const phase = rng() * 2 * Math.PI;

  let locals = null;
  for (let attempt = 0; attempt < 40 && !locals; attempt++) {
    locals = placeWedge({
      rng,
      players,
      perPlayer,
      start: startingTerritories,
      radius,
      wedge,
      minDist: SPACING * styleConfig.minDist * 0.96 ** attempt,
      clustered: styleConfig.clustered,
    });
  }
  if (!locals) throw new Error('could not place territories for these settings');

  const neutralLocals = locals
    .map((p, j) => ({ j, r: Math.hypot(p.x, p.y) }))
    .filter((e) => e.j >= startingTerritories)
    .sort((a, b) => a.r - b.r || a.j - b.j);
  const tierTwoCount = Math.max(1, Math.round(TIER_TWO_SHARE * neutralLocals.length));
  const tierTwo = new Set(neutralLocals.slice(0, tierTwoCount).map((e) => e.j));

  const tierOf = (j) => {
    if (j === 0) return 3;
    if (j < startingTerritories) return 1;
    return tierTwo.has(j) ? 2 : 1;
  };

  const points = [];
  for (let k = 0; k < players; k++) {
    for (let j = 0; j < perPlayer; j++) {
      const q = rotate(locals[j], phase + k * wedge);
      points.push({ x: center + q.x, y: center + q.y });
    }
  }

  const names = makeNames(total, makeRng(seed, 2));
  const territories = points.map((p, g) => {
    const k = Math.floor(g / perPlayer);
    const j = g % perPlayer;
    const tier = tierOf(j);
    const owned = j < startingTerritories;
    const base = BASE_INFLUENCE[tier];
    return {
      idx: g,
      name: names[g],
      slug: names[g].toLowerCase(),
      tier,
      base_influence: base,
      x: round4(p.x),
      y: round4(p.y),
      owner_seat: owned ? k : null,
      troops: owned ? null : startingGarrison * tier,
      gold_level: owned ? null : tier - 1,
      industry_level: owned ? null : 1,
      prestige_level: owned ? null : 0,
      effective_influence: base + (owned ? INFLUENCE_PER_GUILDHALL_LEVEL * START_GUILDHALL_LEVEL : 0),
    };
  });

  const rotateIndex = (g, s) => (((Math.floor(g / perPlayer) + s) % players) * perPlayer) + (g % perPlayer);
  const keyOf = (a, b) => (a < b ? `${a},${b}` : `${b},${a}`);
  const lengthOf = (a, b) => Math.hypot(points[a].x - points[b].x, points[a].y - points[b].y);

  const symmetrize = (edgeList) => {
    const present = new Set(edgeList.map(([a, b]) => keyOf(a, b)));
    const done = new Set();
    const out = [];
    for (const [a, b] of edgeList) {
      const images = new Map();
      for (let s = 0; s < players; s++) {
        const ra = rotateIndex(a, s);
        const rb = rotateIndex(b, s);
        images.set(keyOf(ra, rb), [Math.min(ra, rb), Math.max(ra, rb)]);
      }
      const canonical = [...images.entries()].sort(([, x], [, y]) => x[0] - y[0] || x[1] - y[1])[0][0];
      if (done.has(canonical)) continue;
      done.add(canonical);
      let count = 0;
      for (const key of images.keys()) if (present.has(key)) count += 1;
      if (count * 2 > images.size || (count * 2 === images.size && present.has(canonical))) {
        out.push(...images.values());
      }
    }
    return out;
  };

  const kept = new Map();
  const removed = [];
  for (const [a, b] of symmetrize(delaunayEdges(points))) {
    if (a % perPlayer === b % perPlayer && players >= 4) {
      const diff = (Math.floor(b / perPlayer) - Math.floor(a / perPlayer) + players) % players;
      if (diff !== 1 && diff !== players - 1) continue;
    }
    const length = lengthOf(a, b);
    if (length > styleConfig.prune * SPACING) removed.push({ a, b, length });
    else kept.set(keyOf(a, b), [a, b]);
  }

  const parent = Array.from({ length: total }, (_, i) => i);
  for (const [a, b] of kept.values()) parent[findRoot(parent, a)] = findRoot(parent, b);

  removed.sort((x, y) => x.length - y.length || x.a - y.a || x.b - y.b);
  for (const { a, b } of removed) {
    if (findRoot(parent, a) === findRoot(parent, b)) continue;
    for (let s = 0; s < players; s++) {
      const ra = rotateIndex(a, s);
      const rb = rotateIndex(b, s);
      kept.set(keyOf(ra, rb), [Math.min(ra, rb), Math.max(ra, rb)]);
      parent[findRoot(parent, ra)] = findRoot(parent, rb);
    }
  }

  const edges = [...kept.values()]
    .sort((x, y) => x[0] - y[0] || x[1] - y[1])
    .map(([a, b]) => ({
      a,
      b,
      kind: 'land',
      length: round4(lengthOf(a, b)),
      move_cost_mult: 1,
      defense_mult: 1,
    }));

  const seats = Array.from({ length: players }, (_, k) => ({
    seat: k,
    capital_idx: k * perPlayer,
    territory_idxs: Array.from({ length: startingTerritories }, (_, j) => k * perPlayer + j),
  }));

  return {
    generator_version: GENERATOR_VERSION,
    map_w: round4(2 * center),
    map_h: round4(2 * center),
    seats,
    territories,
    edges,
  };
}
