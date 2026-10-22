import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateWorld, assignSeats, SPACING } from './generator.js';

const SIZES = { compact: 6, standard: 9, large: 14 };
const SEEDS = [1, 42, 987654321, 9007199254740991];
const near = (a, b, eps = 1e-2) => Math.abs(a - b) <= eps;

function cases() {
  const out = [];
  for (const style of ['scatter', 'continents']) {
    for (const mapSize of Object.keys(SIZES)) {
      for (const players of [2, 3, 4, 5, 6, 7, 8]) {
        for (const seed of SEEDS) {
          out.push({ style, mapSize, players, seed, startingTerritories: 4, startingGarrison: 10, terrain: false });
        }
      }
    }
  }
  return out;
}

function label(c) {
  return `${c.style}/${c.mapSize}/${c.players}p/seed ${c.seed}`;
}

function isConnected(layout) {
  const adj = layout.territories.map(() => []);
  for (const e of layout.edges) {
    adj[e.a].push(e.b);
    adj[e.b].push(e.a);
  }
  const seen = new Set([0]);
  const stack = [0];
  while (stack.length) {
    for (const n of adj[stack.pop()]) {
      if (!seen.has(n)) {
        seen.add(n);
        stack.push(n);
      }
    }
  }
  return seen.size === layout.territories.length;
}

test('generation is deterministic', () => {
  for (const c of cases().filter((_, i) => i % 7 === 0)) {
    assert.deepEqual(generateWorld(c), generateWorld(c), label(c));
  }
});

test('different seeds give different maps', () => {
  const base = { style: 'scatter', mapSize: 'standard', players: 4, startingTerritories: 4, startingGarrison: 10, terrain: false };
  const a = generateWorld({ ...base, seed: 1 });
  const b = generateWorld({ ...base, seed: 2 });
  assert.notDeepEqual(a.territories.map((t) => [t.x, t.y]), b.territories.map((t) => [t.x, t.y]));
});

test('territory counts, tiers and ownership are equal for every seat', () => {
  for (const c of cases()) {
    const layout = generateWorld(c);
    const perPlayer = SIZES[c.mapSize];
    assert.equal(layout.territories.length, c.players * perPlayer, label(c));
    assert.equal(layout.seats.length, c.players, label(c));
    const profile = (seat) => {
      const owned = layout.territories.filter((t) => t.owner_seat === seat);
      assert.equal(owned.length, c.startingTerritories, label(c));
      return owned.map((t) => t.tier).sort().join();
    };
    const first = profile(0);
    assert.equal(first, '1,1,1,3', label(c));
    for (let s = 1; s < c.players; s++) assert.equal(profile(s), first, label(c));
    const neutral = layout.territories.filter((t) => t.owner_seat === null);
    assert.equal(neutral.length, c.players * (perPlayer - c.startingTerritories), label(c));
    const tiers = (list) => list.map((t) => t.tier).sort().join();
    const perWedge = (k) => layout.territories.slice(k * perPlayer, (k + 1) * perPlayer).filter((t) => t.owner_seat === null);
    for (let k = 1; k < c.players; k++) assert.equal(tiers(perWedge(k)), tiers(perWedge(0)), label(c));
  }
});

test('capitals are symmetric: same radius, same pairwise distances', () => {
  for (const c of cases()) {
    const layout = generateWorld(c);
    const mid = layout.map_w / 2;
    const capitals = layout.seats.map((s) => layout.territories[s.capital_idx]);
    const radius = Math.hypot(capitals[0].x - mid, capitals[0].y - mid);
    for (const cap of capitals) assert.ok(near(Math.hypot(cap.x - mid, cap.y - mid), radius), label(c));
    const dist = (a, b) => Math.hypot(capitals[a].x - capitals[b].x, capitals[a].y - capitals[b].y);
    for (let k = 1; k < c.players; k++) {
      const ref = dist(0, k);
      for (let i = 0; i < c.players; i++) assert.ok(near(dist(i, (i + k) % c.players), ref), label(c));
    }
  }
});

test('every seat has a congruent start cluster and neighborhood', () => {
  for (const c of cases()) {
    const layout = generateWorld(c);
    const perPlayer = SIZES[c.mapSize];
    const degree = layout.territories.map(() => 0);
    for (const e of layout.edges) {
      degree[e.a] += 1;
      degree[e.b] += 1;
    }
    const signature = (k) => {
      const cap = layout.territories[k * perPlayer];
      const dists = layout.territories
        .slice(k * perPlayer, (k + 1) * perPlayer)
        .map((t) => Math.round(Math.hypot(t.x - cap.x, t.y - cap.y)));
      return { dists: dists.join(), degrees: degree.slice(k * perPlayer, (k + 1) * perPlayer).join() };
    };
    const ref = signature(0);
    for (let k = 1; k < c.players; k++) {
      assert.deepEqual(signature(k).dists.split(',').map(Number).map((n, i) => near(n, ref.dists.split(',').map(Number)[i], 1)), new Array(perPlayer).fill(true), label(c));
      assert.equal(signature(k).degrees, ref.degrees, label(c));
    }
  }
});

test('edge set is invariant under seat rotation', () => {
  for (const c of cases()) {
    const layout = generateWorld(c);
    const perPlayer = SIZES[c.mapSize];
    const keys = new Set(layout.edges.map((e) => `${e.a},${e.b}`));
    const rotateIndex = (g, s) => (((Math.floor(g / perPlayer) + s) % c.players) * perPlayer) + (g % perPlayer);
    for (const e of layout.edges) {
      for (let s = 1; s < c.players; s++) {
        const a = rotateIndex(e.a, s);
        const b = rotateIndex(e.b, s);
        assert.ok(keys.has(a < b ? `${a},${b}` : `${b},${a}`), `${label(c)} edge ${e.a}-${e.b} missing rotation ${s}`);
      }
    }
  }
});

test('graph is connected with valid, unique edges', () => {
  for (const c of cases()) {
    const layout = generateWorld(c);
    assert.ok(isConnected(layout), label(c));
    const seen = new Set();
    for (const e of layout.edges) {
      assert.ok(e.a < e.b, label(c));
      assert.ok(e.a >= 0 && e.b < layout.territories.length, label(c));
      const key = `${e.a},${e.b}`;
      assert.ok(!seen.has(key), label(c));
      seen.add(key);
      const a = layout.territories[e.a];
      const b = layout.territories[e.b];
      assert.ok(near(e.length, Math.hypot(a.x - b.x, a.y - b.y)), label(c));
      assert.equal(e.kind, 'land');
    }
  }
});

test('territories are spread out, in bounds, and uniquely named', () => {
  for (const c of cases()) {
    const layout = generateWorld(c);
    const names = new Set();
    const slugs = new Set();
    for (const t of layout.territories) {
      assert.ok(t.x >= 0 && t.x <= layout.map_w && t.y >= 0 && t.y <= layout.map_h, label(c));
      names.add(t.name);
      slugs.add(t.slug);
    }
    assert.equal(names.size, layout.territories.length, label(c));
    assert.equal(slugs.size, layout.territories.length, label(c));
    let closest = Infinity;
    for (let i = 0; i < layout.territories.length; i++) {
      for (let j = i + 1; j < layout.territories.length; j++) {
        const a = layout.territories[i];
        const b = layout.territories[j];
        closest = Math.min(closest, Math.hypot(a.x - b.x, a.y - b.y));
      }
    }
    assert.ok(closest >= SPACING * 0.4, `${label(c)} closest pair ${closest}`);
  }
});

test('neutral territories carry garrisons and start unowned', () => {
  const layout = generateWorld({ style: 'scatter', mapSize: 'standard', players: 4, seed: 7, startingTerritories: 4, startingGarrison: 10, terrain: false });
  for (const t of layout.territories.filter((x) => x.owner_seat === null)) {
    assert.equal(t.troops, 10 * t.tier);
    assert.equal(t.effective_influence, t.base_influence);
  }
  for (const t of layout.territories.filter((x) => x.owner_seat !== null)) {
    assert.equal(t.troops, null);
    assert.equal(t.effective_influence, t.base_influence + 5);
  }
});

test('invalid settings are rejected', () => {
  const ok = { seed: 1, players: 4, mapSize: 'standard', startingTerritories: 4, style: 'scatter', startingGarrison: 10 };
  assert.throws(() => generateWorld({ ...ok, players: 1 }));
  assert.throws(() => generateWorld({ ...ok, players: 9 }));
  assert.throws(() => generateWorld({ ...ok, mapSize: 'compact', startingTerritories: 5 }));
  assert.throws(() => generateWorld({ ...ok, style: 'swamp' }));
});

test('seat assignment is a deterministic permutation', () => {
  const ids = [11, 12, 13, 14];
  assert.deepEqual(assignSeats(5, ids), assignSeats(5, ids));
  assert.deepEqual([...assignSeats(5, ids)].sort(), ids);
});

const TERRAIN_CASES = [
  { style: 'scatter', mapSize: 'compact', players: 4, seed: 1 },
  { style: 'scatter', mapSize: 'standard', players: 4, seed: 42 },
  { style: 'continents', mapSize: 'standard', players: 6, seed: 7 },
  { style: 'scatter', mapSize: 'large', players: 8, seed: 99 },
  { style: 'continents', mapSize: 'compact', players: 2, seed: 5 },
].map((c) => ({ ...c, startingTerritories: 4, startingGarrison: 10 }));

function heightAt(art, layout, x, y) {
  const cell = layout.map_w / art.grid;
  const ix = Math.min(art.grid - 1, Math.max(0, Math.floor(x / cell)));
  const iy = Math.min(art.grid - 1, Math.max(0, Math.floor(y / cell)));
  return parseInt(art.h.substr((iy * art.grid + ix) * 2, 2), 36) / 1295;
}

test('terrain is deterministic and leaves positions and graph untouched', () => {
  for (const c of TERRAIN_CASES) {
    const withTerrain = generateWorld(c);
    assert.deepEqual(withTerrain, generateWorld(c), label(c));
    const bare = generateWorld({ ...c, terrain: false });
    assert.deepEqual(withTerrain.territories.map((t) => [t.x, t.y, t.tier, t.owner_seat]), bare.territories.map((t) => [t.x, t.y, t.tier, t.owner_seat]), label(c));
    assert.deepEqual(withTerrain.edges.map((e) => [e.a, e.b]), bare.edges.map((e) => [e.a, e.b]), label(c));
    assert.ok(isConnected(withTerrain), label(c));
  }
});

test('every castle stands on land, starting castles are never mountain fortresses', () => {
  for (const c of TERRAIN_CASES) {
    const layout = generateWorld(c);
    for (const t of layout.territories) {
      assert.ok(heightAt(layout.art, layout, t.x, t.y) >= layout.art.sea, `${label(c)} ${t.name} is at sea`);
      assert.ok(['plains', 'forest', 'hills', 'mountain', 'coast'].includes(t.terrain), label(c));
      if (t.owner_seat !== null) assert.notEqual(t.terrain, 'mountain', label(c));
    }
  }
});

test('edges carry terrain costs and each seat gets a comparable start', () => {
  for (const c of TERRAIN_CASES) {
    const layout = generateWorld(c);
    const pen = new Array(c.players).fill(0);
    for (const e of layout.edges) {
      assert.ok(['land', 'pass', 'river'].includes(e.kind), label(c));
      assert.ok(e.move_cost_mult >= 1 && e.move_cost_mult <= 2.6, label(c));
      const w = e.kind === 'pass' ? 2 : e.kind === 'river' ? 1 : (e.move_cost_mult - 1) * 1.5;
      for (const t of [e.a, e.b]) if (layout.territories[t].owner_seat !== null) pen[layout.territories[t].owner_seat] += w;
    }
    const mean = pen.reduce((x, y) => x + y, 0) / pen.length;
    assert.ok(Math.max(...pen) - Math.min(...pen) <= 0.8 * mean + 4, `${label(c)} spread ${pen.join()}`);
  }
});

test('terrain art is well formed and compact', () => {
  for (const c of TERRAIN_CASES) {
    const { art, map_w: mapW } = generateWorld(c);
    assert.equal(art.h.length, art.grid * art.grid * 2, label(c));
    assert.equal(art.m.length, art.grid * art.grid, label(c));
    assert.ok(/^[0-9a-z]+$/.test(art.h) && /^[0-9]+$/.test(art.m), label(c));
    for (const r of art.rivers) {
      assert.ok(r.p.length >= 2 && r.w > 0, label(c));
      for (const [x, y] of r.p) assert.ok(x >= 0 && x <= mapW && y >= 0 && y <= mapW, label(c));
    }
    assert.ok(JSON.stringify(art).length < 220000, label(c));
  }
});

test('free travel: scaled world, links cover every road, ocean and unforded rivers or ranges block', () => {
  for (const c of TERRAIN_CASES.slice(0, 4)) {
    const base = { ...c, scale: 3 };
    const road = generateWorld(base);
    const free = generateWorld({ ...base, freeTravel: true });
    const label3 = `${label(c)} x3`;
    assert.equal(free.world_scale, 3, label3);
    assert.ok(free.map_w > road.map_w * 0 + 1000, label3);
    const keys = new Set(free.edges.map((e) => `${e.a},${e.b}`));
    for (const e of road.edges) assert.ok(keys.has(`${e.a},${e.b}`), `${label3} road ${e.a}-${e.b} missing from links`);
    assert.ok(isConnected(free), label3);
    assert.ok(free.edges.length > road.edges.length, label3);
    assert.ok(free.edges.length < 9000, label3);
    for (const e of free.edges) {
      const a = free.territories[e.a];
      const b = free.territories[e.b];
      assert.ok(near(e.length, Math.hypot(a.x - b.x, a.y - b.y)), label3);
      assert.ok(['land', 'pass', 'river'].includes(e.kind), label3);
      assert.ok(heightAt(free.art, free, (a.x + b.x) / 2, (a.y + b.y) / 2) >= free.art.sea - 0.05, `${label3} midpoint at sea`);
    }
    assert.ok(Array.isArray(free.art.fords) && Array.isArray(free.art.passes), label3);
  }
});

test('scaled spacing: castles are three times further apart', () => {
  const c = { style: 'scatter', mapSize: 'standard', players: 4, seed: 42, startingTerritories: 4, startingGarrison: 10, terrain: false };
  const one = generateWorld(c);
  const three = generateWorld({ ...c, scale: 3 });
  const closest = (layout) => Math.min(...layout.territories.flatMap((a, i) => layout.territories.slice(i + 1).map((b) => Math.hypot(a.x - b.x, a.y - b.y))));
  assert.ok(near(closest(three), closest(one) * 3, 1), `${closest(three)} vs ${closest(one) * 3}`);
});
