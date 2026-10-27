import { generateWorld } from '../supabase/functions/start-game/generator.js';

const LEAGUE = 1500;
const SPEED = 577.5;
const A = Number(process.env.RANGE_A ?? 0.8);
const B = Number(process.env.RANGE_B ?? 0.2);
const LEVELS = [1, 2, 3, 4, 5];
const SEEDS = (process.env.SEEDS || '1,2,3,4,5,6,7,8').split(',').map(Number);
const PLAYERS = (process.env.PLAYERS || '2,4,6,8').split(',').map(Number);
const SIZES = (process.env.SIZES || 'standard').split(',');
const SHAPES = (process.env.SHAPES || 'continent').split(',');
const PRESETS = (process.env.PRESETS || 'continental').split(',');

const median = (a) => { const s = [...a].sort((x, y) => x - y); return s.length ? s[Math.floor(s.length / 2)] : 0; };
const pct = (a, p) => { const s = [...a].sort((x, y) => x - y); return s.length ? s[Math.min(s.length - 1, Math.floor(p * s.length))] : 0; };
const mean = (a) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : 0);

function links(layout) {
  const T = layout.territories;
  const adj = T.map(() => []);
  layout.edges.forEach((e) => { adj[e.a].push({ to: e.b, len: e.length }); adj[e.b].push({ to: e.a, len: e.length }); });
  const out = new Map();
  T.forEach((t, i) => {
    if (t.junction) return;
    const walk = (id, len, seen) => {
      adj[id].forEach((n) => {
        if (seen.has(n.to)) return;
        const nl = len + n.len;
        if (T[n.to].junction) walk(n.to, nl, new Set([...seen, n.to]));
        else if (n.to !== i) {
          const key = i < n.to ? `${i}-${n.to}` : `${n.to}-${i}`;
          if (!out.has(key) || out.get(key).len > nl) out.set(key, { a: Math.min(i, n.to), b: Math.max(i, n.to), len: nl });
        }
      });
    };
    walk(i, 0, new Set([i]));
  });
  return [...out.values()].map((l) => ({ ...l, straight: Math.hypot(T[l.a].x - T[l.b].x, T[l.a].y - T[l.b].y) }));
}

function bfs(n, edges, src) {
  const adj = Array.from({ length: n }, () => []);
  edges.forEach((e) => { adj[e.a].push(e.b); adj[e.b].push(e.a); });
  const d = new Array(n).fill(-1);
  d[src] = 0;
  const q = [src];
  for (let h = 0; h < q.length; h++) adj[q[h]].forEach((v) => { if (d[v] < 0) { d[v] = d[q[h]] + 1; q.push(v); } });
  return d;
}

const rows = [];
let worlds = 0;
let failed = 0;
for (const mapSize of SIZES) for (const shape of SHAPES) for (const preset of PRESETS) for (const players of PLAYERS) for (const seed of SEEDS) {
  let layout;
  try {
    layout = generateWorld({ seed, players, mapSize, startingTerritories: 4, style: 'scatter', startingGarrison: 10, scale: 20, trails: true, shape, preset, homeDistance: 'medium' });
  } catch (e) { failed++; continue; }
  worlds++;
  const T = layout.territories;
  const castles = T.map((t, i) => i).filter((i) => !T[i].junction);
  const L = links(layout);
  const gap = median(L.map((l) => l.len));
  const homes = new Map();
  T.forEach((t, i) => { if (t.owner_seat !== null && t.owner_seat !== undefined && !t.junction) { if (!homes.has(t.owner_seat)) homes.set(t.owner_seat, []); homes.get(t.owner_seat).push(i); } });
  const caps = (layout.seats || []).map((s) => s.capital_idx);
  LEVELS.forEach((lv) => {
    const R = gap * (A + B * lv);
    const inr = L.filter((l) => l.straight <= R);
    const deg = new Map(castles.map((c) => [c, 0]));
    inr.forEach((l) => { deg.set(l.a, deg.get(l.a) + 1); deg.set(l.b, deg.get(l.b) + 1); });
    const withOne = castles.filter((c) => deg.get(c) > 0).length;
    let hopsToEnemy = [];
    let connected = 0;
    let pairs = 0;
    caps.forEach((c, si) => {
      const d = bfs(T.length, inr, c);
      const enemy = caps.filter((_, sj) => sj !== si).map((o) => d[o]).filter((x) => x >= 0);
      if (enemy.length) hopsToEnemy.push(Math.min(...enemy));
      castles.forEach((o) => { pairs++; if (d[o] >= 0) connected++; });
    });
    const ratios = L.filter((l) => l.straight <= R).map((l) => l.len / l.straight);
    rows.push({ mapSize, shape, preset, players, seed, lv, gapLeagues: gap / LEAGUE, rangeLeagues: R / LEAGUE, castles: castles.length,
      pctCastles: withOne / castles.length, pctLinks: inr.length / L.length, avgOpts: (2 * inr.length) / castles.length,
      hopsEnemy: hopsToEnemy.length ? mean(hopsToEnemy) : NaN, reach: connected / pairs, ratio90: pct(ratios, 0.9), ticksPerHop: mean(inr.map((l) => l.len)) / SPEED });
  });
}

const by = (key) => { const m = new Map(); rows.forEach((r) => { const k = key(r); if (!m.has(k)) m.set(k, []); m.get(k).push(r); }); return m; };
const f = (x, d = 2) => (Number.isFinite(x) ? x.toFixed(d) : '-');
console.log(`worlds ${worlds}, failed ${failed}, range = gap x (${A} + ${B} x level), ${SIZES} ${SHAPES} ${PRESETS}`);
const gaps = by((r) => r.players);
console.log('\nplayers  castles  gap(leagues)');
gaps.forEach((rs, p) => { const one = rs.filter((r) => r.lv === 1); console.log(String(p).padEnd(8), f(mean(one.map((r) => r.castles)), 0).padEnd(8), f(mean(one.map((r) => r.gapLeagues)))); });
const header = 'level range(lg)  castles>=1  links  options  hops-to-enemy(%worlds)  reach-all  path/straight p90  ticks/hop';
const table = (rs) => {
  console.log(header);
  LEVELS.forEach((lv) => {
    const x = rs.filter((r) => r.lv === lv);
    console.log(String(lv).padEnd(6), f(mean(x.map((r) => r.rangeLeagues))).padEnd(11), (f(100 * mean(x.map((r) => r.pctCastles)), 0) + '%').padEnd(11), (f(100 * mean(x.map((r) => r.pctLinks)), 0) + '%').padEnd(7), f(mean(x.map((r) => r.avgOpts))).padEnd(9), (f(mean(x.map((r) => r.hopsEnemy).filter(Number.isFinite))) + ' (' + f(100 * x.filter((r) => Number.isFinite(r.hopsEnemy)).length / x.length, 0) + '%)').padEnd(23), (f(100 * mean(x.map((r) => r.reach)), 0) + '%').padEnd(11), f(mean(x.map((r) => r.ratio90))).padEnd(19), f(mean(x.map((r) => r.ticksPerHop))));
  });
};
console.log('\nALL WORLDS');
table(rows);
PLAYERS.forEach((p) => { console.log(`\n${p} players`); table(rows.filter((r) => r.players === p)); });
