import { bestTerrain, PRESETS } from './terrain.js';

export const GENERATOR_VERSION = 4;
export const SPACING = 150;

const MARGIN = 60;
const LINK_CAP = 5;
const AREA_PER_CASTLE = 2.4;
const TERRITORIES_PER_PLAYER = { tiny: 8, small: 16, compact: 12, standard: 24, large: 36 };
const RICHNESS = { sparse: [6, 2, 1], standard: [3, 2, 1], plentiful: [2, 2, 2] };
const ROAD_CHANCE = { none: 0, rare: 0.1, common: 0.3 };
const RING_VALUES = { inner: 45, outer: 18 };
const HOME_SHIFT = { close: -0.18, medium: 0, far: 0.2 };
const WORMHOLE_DIVISOR = { none: 0, rare: 40, common: 16 };
const WORMHOLE_TICKS = 24;
const clampRadius = (v) => Math.min(0.92, Math.max(0.25, v));

export const tierOf = (resources) => (resources <= 20 ? 1 : resources <= 40 ? 2 : 3);
const START_RESOURCES = [50, 30, 12, 12, 12, 12, 12, 12, 12, 12];
const TIER_RANGE = { 1: [4, 20], 2: [21, 40], 3: [41, 60] };
const RESOURCES_PER_TERRAFORM_LEVEL = 5;
const START_TERRAFORM_LEVEL = 1;
const STYLES = {
  scatter: { minDist: 0.6, prune: 3.4, clump: 0.03 },
  continents: { minDist: 0.5, prune: 3.0, clump: 0.06 },
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

function round4(value) {
  return Math.round(value * 1e4) / 1e4;
}

function placeWedge({ rng, players, start, radius, wedge, minDist, rMin = 0, capRange = [0.5, 0.65], shift = 0 }) {
  const placed = [];
  const locals = [];
  const innerMin = Math.max(rMin, minDist / (2 * Math.sin(Math.PI / players)));
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

  const capR = radius * (clampRadius(capRange[0] + shift) + rng() * (clampRadius(capRange[1] + shift) - clampRadius(capRange[0] + shift)));
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


export const SHAPES = ['continent', 'round', 'ring', 'twin', 'archipelago', 'rift'];
const AREA_FRAC = { continent: 1, round: 1, ring: 0.78, twin: 0.5, archipelago: 0.42, rift: 0.8 };
const CROSS_CAP = { twin: 2, archipelago: 2, rift: 3 };
const RING_INNER = 0.46;

const smooth = (a, b, x) => {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
};

function makeShape(kind, R, rng, players) {
  const phi = rng() * 2 * Math.PI;
  const rot = (p) => ({ x: p.x * Math.cos(-phi) - p.y * Math.sin(-phi), y: p.x * Math.sin(-phi) + p.y * Math.cos(-phi) });
  const dist = (p) => Math.hypot(p.x, p.y);
  const disc = (p, c, r) => Math.hypot(p.x - c.x, p.y - c.y) <= r;
  const discLand = (p, c, r) => 1 - smooth(0.88 * r, 1.1 * r, Math.hypot(p.x - c.x, p.y - c.y));
  const out = { kind, symmetric: kind === 'continent' || kind === 'round' || kind === 'ring', label: () => 0, crossCap: CROSS_CAP[kind] || 0 };

  if (kind === 'continent' || kind === 'round') {
    out.rMin = 0;
    out.capRange = [0.5, 0.65];
    out.inside = (p) => dist(p) <= 0.97 * R;
    out.land = (p) => 1 - smooth(0.88 * R, 1.08 * R, dist(p));
  } else if (kind === 'ring') {
    out.rMin = RING_INNER * R * 1.12;
    out.capRange = [0.66, 0.86];
    out.inside = (p) => dist(p) <= 0.97 * R && dist(p) >= RING_INNER * R * 1.12;
    out.land = (p) => Math.min(1 - smooth(0.88 * R, 1.08 * R, dist(p)), smooth(RING_INNER * R * 0.85, RING_INNER * R * 1.08, dist(p)));
  } else if (kind === 'twin') {
    const c = [{ x: -0.52 * R, y: 0 }, { x: 0.52 * R, y: 0 }];
    const rr = 0.5 * R;
    out.inside = (p) => { const q = rot(p); return c.some((m) => disc(q, m, rr * 0.95)); };
    out.land = (p) => { const q = rot(p); return Math.max(...c.map((m) => discLand(q, m, rr))); };
    out.label = (p) => (rot(p).x < 0 ? 0 : 1);
    out.homeLabel = (k) => k % 2;
  } else if (kind === 'archipelago') {
    const n = players <= 4 ? 5 : players <= 6 ? 7 : 9;
    const islands = [];
    for (let tries = 0; islands.length < n && tries < 4000; tries++) {
      const r = R * (0.17 + 0.1 * rng());
      const a = 2 * Math.PI * rng();
      const d = (0.78 * R - r) * Math.sqrt(rng());
      const c = { x: d * Math.cos(a), y: d * Math.sin(a), r };
      if (islands.every((o) => Math.hypot(o.x - c.x, o.y - c.y) > (o.r + c.r) * 1.2)) islands.push(c);
    }
    out.islands = islands;
    out.inside = (p) => islands.some((m) => disc(p, m, m.r * 0.95));
    out.land = (p) => Math.max(...islands.map((m) => discLand(p, m, m.r)));
    out.label = (p) => {
      let best = 0;
      let bd = Infinity;
      islands.forEach((m, i) => { const d = Math.hypot(p.x - m.x, p.y - m.y) / m.r; if (d < bd) { bd = d; best = i; } });
      return best;
    };
  } else {
    const amp = 0.14 * R;
    const k = (2 * Math.PI * (1 + Math.floor(rng() * 2))) / (2 * R);
    const ph = rng() * 2 * Math.PI;
    const hw = 0.09 * R;
    const off = (p) => { const q = rot(p); return q.y - amp * Math.sin(k * q.x + ph); };
    out.inside = (p) => dist(p) <= 0.97 * R && Math.abs(off(p)) >= hw * 1.5;
    out.land = (p) => Math.min(1 - smooth(0.88 * R, 1.08 * R, dist(p)), smooth(hw * 0.7, hw * 1.3, Math.abs(off(p))));
    out.label = (p) => (off(p) < 0 ? 0 : 1);
    out.homeLabel = (k2) => k2 % 2;
  }
  return out;
}

function placeClusters({ rng, players, start, shape, minDist, R }) {
  const base = [{ x: 0, y: 0 }];
  for (let j = 1; j < start; j++) {
    const a = (2 * Math.PI * (j - 1)) / Math.max(1, start - 1) + 0.4;
    base.push({ x: minDist * 1.15 * Math.cos(a), y: minDist * 1.15 * Math.sin(a) });
  }
  const homes = [];
  const centers = [];
  for (let k = 0; k < players; k++) {
    let best = null;
    let bestScore = -1;
    for (let t = 0; t < 400; t++) {
      const a = 2 * Math.PI * rng();
      const d = R * 0.97 * Math.sqrt(rng());
      const c = { x: d * Math.cos(a), y: d * Math.sin(a) };
      if (!shape.inside(c)) continue;
      if (shape.homeLabel && shape.label(c) !== shape.homeLabel(k)) continue;
      const ang = 2 * Math.PI * rng();
      const pts = base.map((b) => ({ x: c.x + b.x * Math.cos(ang) - b.y * Math.sin(ang), y: c.y + b.x * Math.sin(ang) + b.y * Math.cos(ang) }));
      if (!pts.every((q) => shape.inside(q))) continue;
      if (pts.some((q) => homes.some((h) => Math.hypot(h.x - q.x, h.y - q.y) < minDist))) continue;
      const score = centers.length ? Math.min(...centers.map((o) => Math.hypot(o.x - c.x, o.y - c.y))) : 1;
      if (score > bestScore) { bestScore = score; best = pts; }
    }
    if (!best) return null;
    centers.push(best[0]);
    homes.push(...best);
  }
  return homes;
}


const quad = (p) => [p, { x: -p.x, y: p.y }, { x: p.x, y: -p.y }, { x: -p.x, y: -p.y }];

function placeMirrored({ rng, players, start, radius, minDist, clump, neutralCount, shift = 0 }) {
  const copies = (p) => (players === 2 ? [p, { x: -p.x, y: -p.y }] : quad(p));
  const all = [];
  const minSq = minDist * minDist;
  const limit = radius * 0.97;

  const tryAdd = (list) => {
    if (list.some((q) => Math.hypot(q.x, q.y) > limit)) return false;
    for (let i = 0; i < list.length; i++) {
      for (let j = i + 1; j < list.length; j++) {
        if ((list[i].x - list[j].x) ** 2 + (list[i].y - list[j].y) ** 2 < minSq) return false;
      }
      if (all.some((o) => (o.x - list[i].x) ** 2 + (o.y - list[i].y) ** 2 < minSq)) return false;
    }
    all.push(...list);
    return true;
  };

  const clusters = players === 2 ? 1 : players / 4;
  const clusterCopies = [];
  for (let ci = 0; ci < clusters; ci++) {
    let placed = null;
    for (let t = 0; t < 600 && !placed; t++) {
      const mark = all.length;
      const r = radius * clampRadius(0.45 + shift + 0.25 * rng());
      const a = ((15 + 60 * rng()) * Math.PI) / 180;
      const cap = { x: r * Math.cos(a), y: r * Math.sin(a) };
      const members = [copies(cap)];
      let ok = tryAdd(members[0]);
      for (let j = 1; j < start && ok; j++) {
        let added = null;
        for (let u = 0; u < 120 && !added; u++) {
          const ang = rng() * 2 * Math.PI;
          const d = minDist * (1 + 0.8 * rng());
          const p = { x: cap.x + d * Math.cos(ang), y: cap.y + d * Math.sin(ang) };
          if (p.x < minDist * 0.5 || p.y < minDist * 0.5) continue;
          const list = copies(p);
          if (tryAdd(list)) added = list;
        }
        if (!added) ok = false;
        else members.push(added);
      }
      if (ok) placed = members;
      else all.length = mark;
    }
    if (!placed) return null;
    clusterCopies.push(placed);
  }

  const homes = [];
  for (const members of clusterCopies) {
    for (let j = 0; j < members[0].length; j++) for (const list of members) homes.push(list[j]);
  }

  const quads = Math.floor(neutralCount / 4);
  const blobs = Array.from({ length: 3 + Math.floor(quads / 8) }, () => {
    const r = radius * 0.8 * Math.sqrt(rng());
    const a = (Math.PI / 2) * rng();
    return { x: r * Math.cos(a), y: r * Math.sin(a) };
  });
  const sigma = radius * 0.16;
  const density = (p) => Math.min(1, (clump + blobs.reduce((s, b) => s + Math.exp(-((p.x - b.x) ** 2 + (p.y - b.y) ** 2) / (2 * sigma * sigma)), 0)) / 1.1);
  const neutrals = [];
  for (let i = 0; i < quads; i++) {
    let done = false;
    for (let t = 0; t < 3000 && !done; t++) {
      const r = limit * Math.sqrt(rng());
      const a = (Math.PI / 2) * rng();
      const p = { x: r * Math.cos(a), y: r * Math.sin(a) };
      if (rng() > density(p)) continue;
      if (tryAdd(quad(p))) {
        neutrals.push(...quad(p));
        done = true;
      }
    }
    if (!done) return null;
  }
  for (let i = quads * 4; i < neutralCount; i++) {
    let done = false;
    for (let t = 0; t < 3000 && !done; t++) {
      const r = limit * Math.sqrt(rng());
      const a = 2 * Math.PI * rng();
      const p = { x: r * Math.cos(a), y: r * Math.sin(a) };
      if (tryAdd([p])) {
        neutrals.push(p);
        done = true;
      }
    }
    if (!done) return null;
  }
  return { homes, neutrals, quads };
}

function placeTwinRings({ rng, players, start, radius, wedge, minDist, ringMin, neutralCount, shift = 0 }) {
  const local = placeWedge({ rng, players, start, radius, wedge, minDist, rMin: 0, capRange: [0.55, 0.68], shift });
  if (!local) return null;
  const homePhase = rng() * 2 * Math.PI;
  const homes = [];
  for (let k = 0; k < players; k++) for (const l of local) homes.push(rotate(l, homePhase + k * wedge));

  const inner = players * Math.max(1, Math.round(neutralCount / 3 / players));
  const outer = neutralCount - inner;
  if (outer < players) return null;
  const rings = [
    { n: inner, r: radius * 0.36 },
    { n: outer, r: radius * 0.86 },
  ];
  const out = [];
  for (const ring of rings) {
    if ((2 * Math.PI * ring.r) / ring.n < ringMin) return null;
    let best = null;
    let bestD = -1;
    for (let t = 0; t < 36; t++) {
      const phase = (2 * Math.PI * t) / (36 * ring.n);
      const pts = Array.from({ length: ring.n }, (_, i) => ({ x: ring.r * Math.cos(phase + (2 * Math.PI * i) / ring.n), y: ring.r * Math.sin(phase + (2 * Math.PI * i) / ring.n) }));
      const d = Math.min(...pts.map((p) => Math.min(...homes.map((h) => Math.hypot(h.x - p.x, h.y - p.y)))));
      if (d > bestD) { bestD = d; best = pts; }
    }
    if (bestD < ringMin * 0.9) return null;
    out.push(...best);
  }
  return { homes, neutrals: out, inner, outer };
}

function placeNeutrals({ rng, count, radius, center, minDist, clump, taken, inside }) {
  const blobs = Array.from({ length: 3 + Math.floor(count / 32) }, () => {
    const r = radius * 0.9 * Math.sqrt(rng());
    const a = 2 * Math.PI * rng();
    return { x: r * Math.cos(a), y: r * Math.sin(a) };
  });
  const sigma = radius * 0.16;
  const density = (p) => {
    let w = clump;
    for (const b of blobs) w += Math.exp(-((p.x - b.x) ** 2 + (p.y - b.y) ** 2) / (2 * sigma * sigma));
    return Math.min(1, w / 1.1);
  };
  const out = [];
  const all = taken.map((p) => ({ x: p.x - center, y: p.y - center }));
  for (let i = 0; i < count; i++) {
    let p = null;
    for (let t = 0; t < 2400 && !p; t++) {
      const r = radius * 0.97 * Math.sqrt(rng());
      const a = 2 * Math.PI * rng();
      const c = { x: r * Math.cos(a), y: r * Math.sin(a) };
      if (!inside(c)) continue;
      if (rng() > density(c)) continue;
      const md = minDist * (t > 1200 ? 0.8 : 1);
      if (all.every((o) => (o.x - c.x) ** 2 + (o.y - c.y) ** 2 >= md * md)) p = c;
    }
    if (!p) return null;
    out.push(p);
    all.push(p);
  }
  return out;
}

function neutralResources(rng, count, ratio) {
  const total = ratio.reduce((s, v) => s + v, 0);
  const exact = ratio.map((v) => (count * v) / total);
  const counts = exact.map(Math.floor);
  const order = exact.map((e, i) => i).sort((a, b) => exact[b] - Math.floor(exact[b]) - (exact[a] - Math.floor(exact[a])) || a - b);
  for (let i = 0, rest = count - counts.reduce((x, y) => x + y, 0); rest > 0; i++, rest--) counts[order[i]] += 1;
  const values = [];
  counts.forEach((c, i) => {
    const [lo, hi] = TIER_RANGE[i + 1];
    for (let k = 0; k < c; k++) values.push(lo + Math.floor(rng() * (hi - lo + 1)));
  });
  for (let i = values.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [values[i], values[j]] = [values[j], values[i]];
  }
  return values;
}

export function generateWorld({ seed, players, mapSize, startingTerritories, style, startingGarrison, terrain = true, scale = 1, freeTravel = false, shape: requestedShape = 'continent', richness = 'standard', randomRoads = 'none', starScatter = 'random', mirrored = false, trails = false, preset = 'continental', homeDistance = 'medium', wormholes = 'none' }) {
  const perPlayer = TERRITORIES_PER_PLAYER[mapSize];
  const styleConfig = STYLES[style];
  if (!perPlayer) throw new Error(`unknown map size: ${mapSize}`);
  if (!SHAPES.includes(requestedShape)) throw new Error(`unknown map shape: ${requestedShape}`);
  if (!PRESETS[preset]) throw new Error(`unknown map preset: ${preset}`);
  if (!(homeDistance in HOME_SHIFT)) throw new Error(`unknown home distance: ${homeDistance}`);
  if (!(wormholes in WORMHOLE_DIVISOR)) throw new Error(`unknown wormholes setting: ${wormholes}`);
  if (!RICHNESS[richness]) throw new Error(`unknown resource richness: ${richness}`);
  if (!(randomRoads in ROAD_CHANCE)) throw new Error(`unknown random roads setting: ${randomRoads}`);
  if (starScatter !== 'random' && starScatter !== 'twin_rings') throw new Error(`unknown star scatter: ${starScatter}`);
  if (mirrored && ![2, 4, 8].includes(players)) throw new Error('mirrored stars need 2, 4 or 8 players');
  const shapeKind = mirrored || starScatter === 'twin_rings' ? 'round' : requestedShape;
  const ratio = RICHNESS[richness];
  if (!styleConfig) throw new Error(`unknown map style: ${style}`);
  if (!Number.isInteger(players) || players < 2 || players > 8) throw new Error(`players must be 2 to 8, got ${players}`);
  if (!Number.isInteger(startingTerritories) || startingTerritories < 1 || startingTerritories > START_RESOURCES.length || perPlayer - startingTerritories < 2) {
    throw new Error(`starting_territories must be 1 to ${START_RESOURCES.length} and leave at least 2 neutral territories per player on a ${mapSize} map`);
  }

  const spacing = SPACING * scale;
  const total = players * perPlayer;
  const startTotal = players * startingTerritories;
  const neutralTotal = total - startTotal;
  const radius = spacing * Math.sqrt((total * AREA_PER_CASTLE) / (Math.PI * AREA_FRAC[shapeKind]));
  const center = radius + MARGIN * scale;
  const wedge = (2 * Math.PI) / players;
  const rng = makeRng(seed, 1);
  const phase = rng() * 2 * Math.PI;

  const shape = makeShape(shapeKind, radius, makeRng(seed, 5), players);
  const shapeAbs = {
    inside: (p) => shape.inside(p),
    land: (x, y) => shape.land({ x: x - center, y: y - center }),
  };

  let locals = null;
  let neutrals = null;
  let neutralValues = null;
  for (let attempt = 0; attempt < 40 && !neutrals; attempt++) {
    const minDist = spacing * styleConfig.minDist * 0.96 ** attempt;
    const homeDist = Math.max(minDist, spacing * 0.7);
    let homes = [];
    let placed = null;
    if (mirrored) {
      placed = placeMirrored({ rng, players, start: startingTerritories, radius, minDist: homeDist, clump: styleConfig.clump, neutralCount: neutralTotal, shift: HOME_SHIFT[homeDistance] });
      if (!placed) continue;
      homes = placed.homes;
      neutrals = placed.neutrals;
    } else if (starScatter === 'twin_rings') {
      placed = placeTwinRings({ rng, players, start: startingTerritories, radius, wedge, minDist: homeDist, ringMin: minDist, neutralCount: neutralTotal, shift: HOME_SHIFT[homeDistance] });
      if (!placed) continue;
      homes = placed.homes;
      neutrals = placed.neutrals;
    } else {
      if (shape.symmetric) {
        const local = placeWedge({ rng, players, start: startingTerritories, radius, wedge, minDist: homeDist, rMin: shape.rMin, capRange: shape.capRange, shift: HOME_SHIFT[homeDistance] });
        if (!local) continue;
        for (let k = 0; k < players; k++) {
          for (const l of local) {
            const q = rotate(l, phase + k * wedge);
            homes.push({ x: q.x, y: q.y });
          }
        }
      } else {
        homes = placeClusters({ rng, players, start: startingTerritories, shape, minDist: homeDist, R: radius });
        if (!homes) continue;
      }
      neutrals = placeNeutrals({ rng, count: neutralTotal, radius, center: 0, minDist, clump: styleConfig.clump, taken: homes, inside: (p) => shape.inside(p) });
    }
    if (neutrals) {
      locals = homes.map((p) => ({ x: center + p.x, y: center + p.y }));
      neutrals = neutrals.map((p) => ({ x: center + p.x, y: center + p.y }));
      if (mirrored) {
        const valueRng = makeRng(seed, 4);
        const quarter = neutralResources(valueRng, placed.quads, ratio);
        neutralValues = [...quarter.flatMap((v) => [v, v, v, v]), ...neutralResources(valueRng, neutralTotal - placed.quads * 4, ratio)];
      } else if (starScatter === 'twin_rings') {
        neutralValues = [...Array(placed.inner).fill(RING_VALUES.inner), ...Array(placed.outer).fill(RING_VALUES.outer)];
      } else {
        neutralValues = neutralResources(makeRng(seed, 4), neutralTotal, ratio);
      }
    }
  }
  if (!neutrals) throw new Error('could not place territories for these settings');

  const points = [...locals, ...neutrals];
  const resourcesAt = [
    ...Array.from({ length: players }, () => START_RESOURCES.slice(0, startingTerritories)).flat(),
    ...neutralValues,
  ];
  const roadRng = makeRng(seed, 6);

  const names = makeNames(total, makeRng(seed, 2));
  const territories = points.map((p, g) => {
    const owned = g < startTotal;
    const natural = resourcesAt[g];
    const tier = tierOf(natural);
    return {
      idx: g,
      name: names[g],
      slug: names[g].toLowerCase(),
      tier,
      natural_resources: natural,
      x: round4(p.x),
      y: round4(p.y),
      owner_seat: owned ? Math.floor(g / startingTerritories) : null,
      troops: owned ? null : startingGarrison * tier,
      treasury_level: owned ? null : tier - 1,
      industry_level: owned ? null : 1,
      prestige_level: owned ? null : 0,
      resources: natural + (owned ? RESOURCES_PER_TERRAFORM_LEVEL * START_TERRAFORM_LEVEL : 0),
      ...(!owned && roadRng() < ROAD_CHANCE[randomRoads] ? { has_road: true } : {}),
    };
  });

  const keyOf = (a, b) => (a < b ? `${a},${b}` : `${b},${a}`);
  const lengthOf = (a, b) => Math.hypot(points[a].x - points[b].x, points[a].y - points[b].y);

  const kept = new Map();
  const removed = [];
  for (const [a, b] of delaunayEdges(points)) {
    const length = lengthOf(a, b);
    if (length > styleConfig.prune * spacing) removed.push({ a, b, length });
    else kept.set(keyOf(a, b), [Math.min(a, b), Math.max(a, b)]);
  }

  if (shape.crossCap) {
    const labelOf = points.map((p) => shape.label({ x: p.x - center, y: p.y - center }));
    const crossing = [...kept.values()].filter(([a, b]) => labelOf[a] !== labelOf[b]).sort((x, y) => lengthOf(x[0], x[1]) - lengthOf(y[0], y[1]) || x[0] - y[0] || x[1] - y[1]);
    const taken = new Map();
    for (const [a, b] of crossing) {
      const pair = labelOf[a] < labelOf[b] ? `${labelOf[a]}-${labelOf[b]}` : `${labelOf[b]}-${labelOf[a]}`;
      const picked = taken.get(pair) || [];
      const mid = { x: (points[a].x + points[b].x) / 2, y: (points[a].y + points[b].y) / 2 };
      const ok = picked.length < shape.crossCap && picked.every((m) => Math.hypot(m.x - mid.x, m.y - mid.y) > spacing * 1.5);
      if (ok) {
        picked.push(mid);
        taken.set(pair, picked);
      } else {
        kept.delete(keyOf(a, b));
        removed.push({ a, b, length: lengthOf(a, b) });
      }
    }
  }

  const parent = Array.from({ length: total }, (_, i) => i);
  for (const [a, b] of kept.values()) parent[findRoot(parent, a)] = findRoot(parent, b);
  removed.sort((x, y) => x.length - y.length || x.a - y.a || x.b - y.b);
  for (const { a, b } of removed) {
    if (findRoot(parent, a) === findRoot(parent, b)) continue;
    kept.set(keyOf(a, b), [Math.min(a, b), Math.max(a, b)]);
    parent[findRoot(parent, a)] = findRoot(parent, b);
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
    capital_idx: k * startingTerritories,
    territory_idxs: Array.from({ length: startingTerritories }, (_, j) => k * startingTerritories + j),
  }));

  const layout = {
    generator_version: GENERATOR_VERSION,
    map_w: round4(2 * center),
    map_h: round4(2 * center),
    seats,
    territories,
    edges,
  };

  if (terrain) {
    const world = bestTerrain({
      makeRng,
      seed,
      points,
      edges: edges.map((e) => [e.a, e.b]),
      mapW: layout.map_w,
      spacing,
      tiers: territories.map((t) => t.tier),
      owned: territories.map((t) => t.owner_seat !== null),
      seatOf: territories.map((t) => (t.owner_seat === null ? -1 : t.owner_seat)),
      players,
      shapeLand: shapeKind === 'continent' ? null : shapeAbs.land,
      mirror: mirrored,
      trails: trails && terrain,
      preset,
    });
    territories.forEach((t, g) => {
      t.terrain = world.terrain[g];
    });
    edges.forEach((e, k) => {
      e.kind = world.edgeInfo[k].kind;
      e.move_cost_mult = world.edgeInfo[k].mult;
    });
    layout.art = world.art;
    if (world.trails) {
      const tr = world.trails;
      const cnames = makeNames(tr.crossings.length, makeRng(seed, 8));
      const crng = makeRng(seed, 9);
      const base = points.length;
      tr.crossings.forEach((c, k) => {
        const natural = 4 + Math.floor(crng() * 7);
        territories.push({
          idx: c.idx,
          name: c.pass ? `${cnames[k]} Pass` : `${cnames[k]} Crossing`,
          slug: `${cnames[k]}-${c.pass ? 'pass' : 'crossing'}`.toLowerCase(),
          tier: 1,
          natural_resources: natural,
          x: round4(c.x),
          y: round4(c.y),
          owner_seat: null,
          troops: startingGarrison,
          treasury_level: 0,
          industry_level: 1,
          prestige_level: 0,
          resources: natural,
          terrain: c.pass ? 'hills' : 'plains',
          crossing: true,
          crossing_kind: c.pass ? 'pass' : 'river',
          river_idx: c.pass ? null : c.ri,
        });
      });
      layout.edges = tr.edges.map((e) => ({ a: Math.min(e.a, e.b), b: Math.max(e.a, e.b), kind: e.kind, length: round4(e.length), move_cost_mult: e.mult, defense_mult: e.a >= base || e.b >= base ? 1.25 : 1, path: e.a < e.b ? e.path : [...e.path].reverse() }));
      layout.trails = true;
      if (WORMHOLE_DIVISOR[wormholes]) {
        const wrng = makeRng(seed, 10);
        const used = new Set();
        const pool = [];
        for (let g = startTotal; g < base; g++) pool.push(g);
        const far = 4 * spacing;
        for (let k = 0, want = Math.ceil(total / WORMHOLE_DIVISOR[wormholes]); k < want; k++) {
          const pairs = [];
          for (let i = 0; i < pool.length; i++) {
            if (used.has(pool[i])) continue;
            for (let j = i + 1; j < pool.length; j++) {
              if (!used.has(pool[j]) && Math.hypot(points[pool[i]].x - points[pool[j]].x, points[pool[i]].y - points[pool[j]].y) >= far) pairs.push([pool[i], pool[j]]);
            }
          }
          if (!pairs.length) break;
          const [a, b] = pairs[Math.floor(wrng() * pairs.length)];
          used.add(a);
          used.add(b);
          const len = Math.hypot(points[a].x - points[b].x, points[a].y - points[b].y);
          layout.edges.push({ a, b, kind: 'wormhole', length: round4(len), move_cost_mult: round4(Math.max(0.05, (WORMHOLE_TICKS * 17.5 * scale) / len)), defense_mult: 1, path: [[round4(points[a].x), round4(points[a].y)], [round4(points[b].x), round4(points[b].y)]] });
        }
      }
    } else if (freeTravel) {
      layout.edges = world.links(LINK_CAP * spacing).map((l) => ({ a: l.a, b: l.b, kind: l.kind, length: round4(l.length), move_cost_mult: l.mult, defense_mult: 1 }));
    }
  }
  layout.world_scale = scale;

  return layout;
}
