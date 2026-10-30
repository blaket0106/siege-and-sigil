export const GRID = 192;
export const SEA = 0.2;
const LAND_T = 0.36;
const MOUNT_T = 0.53;

export const PRESETS = {
  continental: { rivers: 1, mountain: 1, wet: 0 },
  highlands: { rivers: 0.6, mountain: 1.3, wet: -0.05 },
  river_valley: { rivers: 2, mountain: 0.35, wet: 0.05 },
  forest: { rivers: 1, mountain: 0.5, wet: 0.2 },
  plains: { rivers: 0, mountain: 0, wet: 0 },
};

export const riverClass = (w) => (w >= GREAT_W ? 2 : w >= RIVER_W ? 1 : 0);
const CROSS_SEP = [0.7, 1.7, 3.4];

function smoothstep(a, b, x) {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
}

function makeNoise(rng) {
  const perm = Uint8Array.from({ length: 256 }, (_, i) => i);
  for (let i = 255; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [perm[i], perm[j]] = [perm[j], perm[i]];
  }
  const vals = Float64Array.from({ length: 256 }, () => rng());
  const lat = (ix, iy) => vals[perm[(perm[ix & 255] + iy) & 255]];
  return (x, y) => {
    const ix = Math.floor(x);
    const iy = Math.floor(y);
    const fx = x - ix;
    const fy = y - iy;
    const u = fx * fx * (3 - 2 * fx);
    const v = fy * fy * (3 - 2 * fy);
    const a = lat(ix, iy);
    const b = lat(ix + 1, iy);
    const c = lat(ix, iy + 1);
    const d = lat(ix + 1, iy + 1);
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
  };
}

function fbm(noise, x, y, octaves) {
  let sum = 0;
  let amp = 0.5;
  let norm = 0;
  for (let o = 0; o < octaves; o++) {
    sum += noise(x, y) * amp;
    norm += amp;
    x *= 2.03;
    y *= 2.03;
    amp *= 0.5;
  }
  return sum / norm;
}

function segIntersect(p, p2, q, q2) {
  const d1x = p2.x - p.x;
  const d1y = p2.y - p.y;
  const d2x = q2.x - q.x;
  const d2y = q2.y - q.y;
  const den = d1x * d2y - d1y * d2x;
  if (Math.abs(den) < 1e-9) return null;
  const t = ((q.x - p.x) * d2y - (q.y - p.y) * d2x) / den;
  const u = ((q.x - p.x) * d1y - (q.y - p.y) * d1x) / den;
  if (t < 0 || t > 1 || u < 0 || u > 1) return null;
  return { x: p.x + t * d1x, y: p.y + t * d1y };
}

function chaikin(pts, rounds) {
  let out = pts;
  for (let r = 0; r < rounds; r++) {
    const next = [out[0]];
    for (let i = 0; i < out.length - 1; i++) {
      const a = out[i];
      const b = out[i + 1];
      next.push([0.75 * a[0] + 0.25 * b[0], 0.75 * a[1] + 0.25 * b[1]]);
      next.push([0.25 * a[0] + 0.75 * b[0], 0.25 * a[1] + 0.75 * b[1]]);
    }
    next.push(out[out.length - 1]);
    out = next;
  }
  return out;
}

class MinHeap {
  constructor() {
    this.k = [];
    this.v = [];
  }

  get size() {
    return this.k.length;
  }

  push(key, val) {
    const k = this.k;
    const v = this.v;
    let i = k.length;
    k.push(key);
    v.push(val);
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (k[p] <= key) break;
      k[i] = k[p];
      v[i] = v[p];
      i = p;
    }
    k[i] = key;
    v[i] = val;
  }

  pop() {
    const k = this.k;
    const v = this.v;
    const topV = v[0];
    const lastK = k.pop();
    const lastV = v.pop();
    const n = k.length;
    if (n > 0) {
      let i = 0;
      for (;;) {
        let c = 2 * i + 1;
        if (c >= n) break;
        if (c + 1 < n && k[c + 1] < k[c]) c += 1;
        if (k[c] >= lastK) break;
        k[i] = k[c];
        v[i] = v[c];
        i = c;
      }
      k[i] = lastK;
      v[i] = lastV;
    }
    return topV;
  }
}

function decorSeed(parts) {
  let h = 0x811c9dc5;
  for (let i = 0; i < parts.length; i += 7) {
    for (let k = 0; k < parts[i].length; k++) {
      h ^= parts[i].charCodeAt(k);
      h = Math.imul(h, 0x01000193);
    }
  }
  return h >>> 0;
}

export const trailDebug = { reason: '' };
const TRAIL_CAP = 1.9;
const SPAN = 2.0;
const CROSS_SPAN = 2.4;
const SHARE = 0.2;
const RIVER_SHARE = 0.011;
const RIVER_MAX_W = 8;
const RIVER_W = 3;
const GREAT_W = 4.8;

function planTrails(c, lenient = 0) {
  const wet = (sc) => (lenient ? sc.oceanFrac > lenient : sc.ocean);
  const { points, edges, spacing, cell, G, sample, height, moist, riverSegs, scanLine, nearestOnSegment, MOUNT_T, SEA: sea } = c;
  const N0 = points.length;
  const dist = (p, q) => Math.hypot(p.x - q.x, p.y - q.y);
  const key = (a, b) => (a < b ? `${a},${b}` : `${b},${a}`);
  const SG = cell * 2;
  const segGrid = new Map();
  for (const seg of riverSegs) {
    for (let gx = Math.floor(seg.x0 / SG); gx <= Math.floor(seg.x1 / SG); gx++) {
      for (let gy = Math.floor(seg.y0 / SG); gy <= Math.floor(seg.y1 / SG); gy++) {
        const k = gx * 100003 + gy;
        const l = segGrid.get(k);
        if (l) l.push(seg);
        else segGrid.set(k, [seg]);
      }
    }
  }
  const riverCross = (A, B) => {
    const out = [];
    const seen = new Set();
    const lx0 = Math.min(A.x, B.x);
    const lx1 = Math.max(A.x, B.x);
    const ly0 = Math.min(A.y, B.y);
    const ly1 = Math.max(A.y, B.y);
    for (let gx = Math.floor(lx0 / SG); gx <= Math.floor(lx1 / SG); gx++) {
      for (let gy = Math.floor(ly0 / SG); gy <= Math.floor(ly1 / SG); gy++) {
        const l = segGrid.get(gx * 100003 + gy);
        if (!l) continue;
        for (const seg of l) {
          if (seen.has(seg)) continue;
          seen.add(seg);
          if (seg.x1 < lx0 || seg.x0 > lx1 || seg.y1 < ly0 || seg.y0 > ly1) continue;
          const q = segIntersect(A, B, seg.a, seg.b);
          if (q) out.push({ x: q.x, y: q.y, ri: seg.ri, w: seg.w });
        }
      }
    }
    return out;
  };

  const cands = new Map();
  for (const [a, b] of edges) cands.set(key(a, b), { a: Math.min(a, b), b: Math.max(a, b), len: dist(points[a], points[b]) });
  for (let a = 0; a < N0; a++) {
    for (let b = a + 1; b < N0; b++) {
      const len = dist(points[a], points[b]);
      if (len <= TRAIL_CAP * spacing && !cands.has(key(a, b))) cands.set(key(a, b), { a, b, len });
    }
  }
  const free = [];
  const cross1 = [];
  for (const cd of cands.values()) {
    const A = points[cd.a];
    const B = points[cd.b];
    const sc0 = scanLine(A, B);
    if (wet(sc0)) continue;
    const hits = riverCross(A, B);
    if (!hits.length && !sc0.runs.length) {
      free.push(cd);
    } else if (!hits.length && sc0.runs.length === 1) {
      const low = sc0.runs[0].low;
      cross1.push({ a: cd.a, b: cd.b, pts: [{ x: low.x, y: low.y, pass: true }], len: cd.len, direct: cd.len });
    } else if (hits.length === 1 && !sc0.runs.length) {
      let best = null;
      let bd = Infinity;
      for (const seg of riverSegs) {
        const q = nearestOnSegment(hits[0], seg);
        const d = Math.hypot(q.x - hits[0].x, q.y - hits[0].y);
        if (d < bd) {
          bd = d;
          best = { x: q.x, y: q.y, ri: seg.ri, w: seg.w };
        }
      }
      if (!best || sample(height, best.x, best.y) < sea + 0.02) continue;
      const P = { x: best.x, y: best.y };
      const d1 = dist(A, P);
      const d2 = dist(P, B);
      if (d1 < spacing * 0.2 || d2 < spacing * 0.2) continue;
      const bad = (S, T) => wet(scanLine(S, T)) || riverCross(S, T).some((h) => Math.hypot(h.x - P.x, h.y - P.y) > spacing * 0.07);
      if (bad(A, P) || bad(P, B)) continue;
      cross1.push({ a: cd.a, b: cd.b, pts: [{ x: P.x, y: P.y, ri: best.ri, w: best.w }], len: d1 + d2, direct: cd.len });
    }
  }

  const snapRiver = (h) => {
    let best = null;
    let bd = Infinity;
    for (const seg of riverSegs) {
      if (seg.x1 < h.x - spacing || seg.x0 > h.x + spacing || seg.y1 < h.y - spacing || seg.y0 > h.y + spacing) continue;
      const q = nearestOnSegment(h, seg);
      const d = Math.hypot(q.x - h.x, q.y - h.y);
      if (d < bd) {
        bd = d;
        best = { x: q.x, y: q.y, ri: seg.ri, w: seg.w };
      }
    }
    return best;
  };
  const parent = Array.from({ length: N0 }, (_, i) => i);
  const root = (i) => {
    while (parent[i] !== i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  };
  for (const e of free) parent[root(e.a)] = root(e.b);
  const picked = [];
  cross1.sort((x, y) => x.len - y.len || x.a - y.a || x.b - y.b);
  for (const cd of cross1) {
    if (root(cd.a) === root(cd.b)) continue;
    parent[root(cd.a)] = root(cd.b);
    picked.push(cd);
  }
  let roots = new Set(Array.from({ length: N0 }, (_, i) => root(i)));
  for (let guard = 0; roots.size > 1 && guard < 40; guard++) {
    const pairs = [];
    for (let a = 0; a < N0; a++) {
      for (let b = a + 1; b < N0; b++) {
        if (root(a) === root(b)) continue;
        const len = dist(points[a], points[b]);
        if (len <= 5.6 * spacing) pairs.push({ a, b, len });
      }
    }
    pairs.sort((x, y) => x.len - y.len || x.a - y.a || x.b - y.b);
    let joined = false;
    for (const pr of pairs.slice(0, 80)) {
      const A = points[pr.a];
      const B = points[pr.b];
      const scAB = scanLine(A, B);
      if (wet(scAB)) continue;
      const hits = riverCross(A, B);
      const snapped = hits.map(snapRiver);
      if (snapped.some((s) => !s || sample(height, s.x, s.y) < sea + 0.02)) continue;
      const barriers = [...snapped, ...scAB.runs.map((r) => ({ x: r.low.x, y: r.low.y, pass: true }))].sort((x, y) => dist(A, x) - dist(A, y));
      if (!barriers.length || barriers.length > 4) continue;
      const chain = [A, ...barriers, B];
      let valid = true;
      for (let k = 0; k < chain.length - 1 && valid; k++) {
        if (dist(chain[k], chain[k + 1]) < spacing * 0.05) valid = false;
        else if (wet(scanLine(chain[k], chain[k + 1]))) valid = false;
        else {
          if (riverCross(chain[k], chain[k + 1]).some((h) => chain.every((p) => Math.hypot(h.x - p.x, h.y - p.y) > spacing * 0.12))) valid = false;
        }
      }
      if (!valid) continue;
      parent[root(pr.a)] = root(pr.b);
      picked.push({ a: pr.a, b: pr.b, pts: barriers, len: pr.len, direct: pr.len });
      joined = true;
      break;
    }
    if (!joined) break;
    roots = new Set(Array.from({ length: N0 }, (_, i) => root(i)));
  }
  if (roots.size > 1) {
    let mind = Infinity;
    for (let a = 0; a < N0; a++) for (let b = a + 1; b < N0; b++) if (root(a) !== root(b)) mind = Math.min(mind, dist(points[a], points[b]));
    trailDebug.reason = `components ${roots.size} candidates ${cross1.length} gap ${(mind / spacing).toFixed(2)} spacings`;
    return null;
  }

  const adj = Array.from({ length: N0 + 64 }, () => []);
  const nodes = points.map((p) => ({ x: p.x, y: p.y }));
  const out = [];
  const link = (a, b, w, kind) => {
    while (adj.length <= Math.max(a, b)) adj.push([]);
    adj[a].push([b, w]);
    adj[b].push([a, w]);
    out.push({ a, b, kind });
  };
  const sp = (from, to, limit) => {
    const best = new Map([[from, 0]]);
    const h = new MinHeap();
    h.push(0, from);
    while (h.size) {
      const u = h.pop();
      const du = best.get(u);
      if (u === to) return du;
      if (du > limit) return Infinity;
      for (const [v, w] of adj[u] || []) {
        const nd = du + w;
        if (nd < (best.get(v) ?? Infinity)) {
          best.set(v, nd);
          h.push(nd, v);
        }
      }
    }
    return Infinity;
  };
  const crossings = [];
  const carve = (A, B) => {
    const rad = cell * 3;
    const base = MOUNT_T - 0.1;
    const dx = B.x - A.x;
    const dy = B.y - A.y;
    const len2 = dx * dx + dy * dy || 1;
    const gx0 = Math.max(0, Math.floor((Math.min(A.x, B.x) - rad) / cell));
    const gx1 = Math.min(G - 1, Math.floor((Math.max(A.x, B.x) + rad) / cell));
    const gy0 = Math.max(0, Math.floor((Math.min(A.y, B.y) - rad) / cell));
    const gy1 = Math.min(G - 1, Math.floor((Math.max(A.y, B.y) + rad) / cell));
    for (let gy = gy0; gy <= gy1; gy++) {
      for (let gx = gx0; gx <= gx1; gx++) {
        const i = gy * G + gx;
        if (height[i] <= base) continue;
        const px = (gx + 0.5) * cell - A.x;
        const py = (gy + 0.5) * cell - A.y;
        const t = Math.min(1, Math.max(0, (px * dx + py * dy) / len2));
        const d = Math.hypot(px - t * dx, py - t * dy);
        if (d >= rad) continue;
        const target = base + smoothstep(0, rad, d) * (height[i] - base);
        if (height[i] > target) height[i] = target;
      }
    }
  };
  const addCrossing = (cd) => {
    let prev = cd.a;
    let prevPt = points[cd.a];
    const chainPts = [points[cd.a], ...cd.pts, points[cd.b]];
    for (let k = 0; k < chainPts.length - 1; k++) if (chainPts[k].pass || chainPts[k + 1].pass) carve(chainPts[k], chainPts[k + 1]);
    for (const pt of cd.pts) {
      const idx = N0 + crossings.length;
      nodes.push({ x: pt.x, y: pt.y });
      crossings.push({ idx, x: pt.x, y: pt.y, ri: pt.ri, pass: !!pt.pass, cls: pt.pass ? 0 : riverClass(pt.w || 0), a: cd.a, b: cd.b });
      link(prev, idx, dist(prevPt, pt), pt.pass ? 'pass' : 'river');
      prev = idx;
      prevPt = pt;
    }
    link(prev, cd.b, dist(prevPt, points[cd.b]), 'river');
  };
  picked.forEach(addCrossing);
  const pickedKeys = new Set(picked.map((p) => key(p.a, p.b)));
  const rest = [
    ...free.map((e) => ({ kind: 'free', a: e.a, b: e.b, len: e.len, direct: e.len })),
    ...cross1.filter((cd) => !pickedKeys.has(key(cd.a, cd.b))).map((cd) => ({ kind: 'cross', ...cd })),
  ].sort((x, y) => x.direct - y.direct || x.a - y.a || x.b - y.b);
  const tooClose = (pt) => {
    const c = pt.pass ? 0 : riverClass(pt.w || 0);
    return crossings.some((q) => Math.hypot(q.x - pt.x, q.y - pt.y) < spacing * CROSS_SEP[Math.max(c, q.cls)]);
  };
  const consider = (cd) => {
    const limit = cd.kind === 'free' ? SPAN : CROSS_SPAN;
    if (sp(cd.a, cd.b, cd.direct * limit * 1.01) <= cd.direct * limit) return false;
    if (cd.kind === 'free') {
      link(cd.a, cd.b, cd.len, 'land');
      return true;
    }
    if (cd.len > cd.direct * 1.4) return false;
    if (tooClose(cd.pts[0])) return false;
    addCrossing(cd);
    return true;
  };
  for (const cd of rest) if (cd.kind === 'free') consider(cd);
  for (const cd of rest) if (cd.kind === 'cross') consider(cd);
  const angleOf = (a, b) => Math.atan2(points[b].y - points[a].y, points[b].x - points[a].x);
  for (let a = 0; a < N0; a++) {
    if (adj[a].length !== 1) continue;
    const first = adj[a][0][0];
    const base = first < N0 ? angleOf(a, first) : Math.atan2(nodes[first].y - points[a].y, nodes[first].x - points[a].x);
    const opts = rest.filter((cd) => (cd.a === a || cd.b === a) && cd.direct <= spacing * 1.6).sort((x, y) => x.direct - y.direct);
    for (const cd of opts) {
      const other = cd.a === a ? cd.b : cd.a;
      if (adj[a].some(([v]) => v === other)) continue;
      let diff = Math.abs(angleOf(a, other) - base);
      diff = Math.min(diff, 2 * Math.PI - diff);
      if (diff < 0.7) continue;
      if (cd.kind === 'free') {
        link(cd.a, cd.b, cd.len, 'land');
        break;
      }
      if (cd.len > cd.direct * 1.4) continue;
      if (tooClose(cd.pts[0])) continue;
      addCrossing(cd);
      break;
    }
  }

  const G2 = G * G;
  const gcost = new Float32Array(G2);
  const blocked = new Uint8Array(G2);
  for (let gy = 0; gy < G; gy++) {
    for (let gx = 0; gx < G; gx++) {
      const i = gy * G + gx;
      const h = height[i];
      if (h < sea || h > MOUNT_T) blocked[i] = 1;
      gcost[i] = h > MOUNT_T ? 3.2 : h > 0.42 ? 1.5 : moist[i] > 0.58 ? 1.45 : h > sea + 0.17 ? 1.2 : 1;
    }
  }
  const riverCell = new Uint8Array(G2);
  for (const seg of riverSegs) {
    const len = Math.hypot(seg.b.x - seg.a.x, seg.b.y - seg.a.y);
    const n = Math.max(1, Math.ceil(len / (cell * 0.25)));
    let pgx = -1;
    let pgy = -1;
    for (let s = 0; s <= n; s++) {
      const x = seg.a.x + ((seg.b.x - seg.a.x) * s) / n;
      const y = seg.a.y + ((seg.b.y - seg.a.y) * s) / n;
      const gx = Math.min(G - 1, Math.max(0, Math.floor(x / cell)));
      const gy = Math.min(G - 1, Math.max(0, Math.floor(y / cell)));
      riverCell[gy * G + gx] = 1;
      if (pgx >= 0 && gx !== pgx && gy !== pgy) riverCell[pgy * G + gx] = 1;
      pgx = gx;
      pgy = gy;
    }
  }
  for (let i = 0; i < G2; i++) if (riverCell[i]) blocked[i] = 1;
  const opened = new Uint8Array(G2);
  const openAround = (p, rad) => {
    const gx0 = Math.floor(p.x / cell);
    const gy0 = Math.floor(p.y / cell);
    const r = Math.ceil(rad / cell);
    for (let gy = Math.max(0, gy0 - r); gy <= Math.min(G - 1, gy0 + r); gy++) {
      for (let gx = Math.max(0, gx0 - r); gx <= Math.min(G - 1, gx0 + r); gx++) {
        if (Math.hypot((gx + 0.5) * cell - p.x, (gy + 0.5) * cell - p.y) <= rad) opened[gy * G + gx] = 1;
      }
    }
  };
  for (const cr of crossings) openAround(cr, cell * 2.4);
  for (const p of points) openAround(p, sample(height, p.x, p.y) > MOUNT_T ? Math.max(cell * 1.1, spacing * 0.32) : cell * 1.1);

  const used = new Uint8Array(G2);
  const gstamp = new Uint32Array(G2);
  const gscore = new Float64Array(G2);
  const came = new Int32Array(G2);
  let stampId = 0;
  const astar = (A, B) => {
    const sx = Math.min(G - 1, Math.max(0, Math.floor(A.x / cell)));
    const sy = Math.min(G - 1, Math.max(0, Math.floor(A.y / cell)));
    const tx = Math.min(G - 1, Math.max(0, Math.floor(B.x / cell)));
    const ty = Math.min(G - 1, Math.max(0, Math.floor(B.y / cell)));
    const pad = 7;
    const x0 = Math.max(0, Math.min(sx, tx) - pad);
    const x1 = Math.min(G - 1, Math.max(sx, tx) + pad);
    const y0 = Math.max(0, Math.min(sy, ty) - pad);
    const y1 = Math.min(G - 1, Math.max(sy, ty) + pad);
    stampId += 1;
    const open = new MinHeap();
    const s = sy * G + sx;
    const t = ty * G + tx;
    gstamp[s] = stampId;
    gscore[s] = 0;
    came[s] = -1;
    open.push(Math.hypot(tx - sx, ty - sy), s);
    while (open.size) {
      const cur = open.pop();
      if (cur === t) {
        const cells = [];
        for (let k = cur; k >= 0; k = came[k]) cells.push(k);
        return cells.reverse();
      }
      const cgx = cur % G;
      const cgy = (cur / G) | 0;
      const gc = gscore[cur];
      for (let dy = -1; dy <= 1; dy++) {
        for (let dx = -1; dx <= 1; dx++) {
          if (!dx && !dy) continue;
          const nx = cgx + dx;
          const ny = cgy + dy;
          if (nx < x0 || nx > x1 || ny < y0 || ny > y1) continue;
          const n = ny * G + nx;
          if (blocked[n] && !opened[n] && n !== t) continue;
          if (riverCell[n] && !opened[n]) continue;
          if (dx && dy && ((riverCell[cgy * G + nx] && !opened[cgy * G + nx]) || (riverCell[ny * G + cgx] && !opened[ny * G + cgx]))) continue;
          const step = (dx && dy ? 1.4142 : 1) * (gcost[n] * (used[n] ? SHARE : 1) + gcost[cur] * (used[cur] ? SHARE : 1)) * 0.5;
          const ng = gc + step;
          if (gstamp[n] !== stampId || ng < gscore[n]) {
            gstamp[n] = stampId;
            gscore[n] = ng;
            came[n] = cur;
            open.push(ng + Math.hypot(tx - nx, ty - ny), n);
          }
        }
      }
    }
    return null;
  };

  const pending = [];
  const edgeKind = (e) => {
    const ends = [e.a, e.b].filter((n) => n >= N0 && n < N0 + crossings.length).map((n) => crossings[n - N0]);
    if (!ends.length) return 'land';
    return ends.every((c) => c.pass) ? 'pass' : 'river';
  };
  const plen = (poly) => poly.reduce((s, p, k) => (k ? s + Math.hypot(p[0] - poly[k - 1][0], p[1] - poly[k - 1][1]) : 0), 0);
  for (const e of out) {
    const A = nodes[e.a];
    const B = nodes[e.b];
    const straight = dist(A, B);
    let pts = null;
    let usedCells = null;
    const cells = astar(A, B);
    if (cells) {
      const raw = [[A.x, A.y], ...cells.slice(1, -1).map((k) => [((k % G) + 0.5) * cell, (((k / G) | 0) + 0.5) * cell]), [B.x, B.y]];
      pts = chaikin(raw, 2);
    }
    const crosses = (poly) => {
      for (let k = 0; k < poly.length - 1; k++) {
        const hits = riverCross({ x: poly[k][0], y: poly[k][1] }, { x: poly[k + 1][0], y: poly[k + 1][1] });
        for (const h of hits) {
          const near = [e.a, e.b].some((n) => n >= N0 && Math.hypot(nodes[n].x - h.x, nodes[n].y - h.y) < spacing * 0.09);
          if (!near) return true;
        }
      }
      return false;
    };
    if (pts && (crosses(pts) || plen(pts) > 2.1 * straight)) pts = null;
    if (pts && cells) {
      usedCells = cells;
      for (const k of cells) used[k] = 1;
    }
    if (!pts) {
      const direct = [[A.x, A.y], [B.x, B.y]];
      const scD = scanLine(A, B);
      if (!wet(scD) && !scD.runs.length && !crosses(direct)) pts = direct;
    }
    if (!pts) continue;
    pending.push({ a: e.a, b: e.b, pts, cells: usedCells });
  }

  const nbr = new Map();
  for (const p of pending) {
    if (!p.cells) continue;
    const cs = p.cells;
    for (let k = 0; k < cs.length; k++) {
      const set = nbr.get(cs[k]) || new Set();
      if (k) set.add(cs[k - 1]);
      if (k < cs.length - 1) set.add(cs[k + 1]);
      nbr.set(cs[k], set);
    }
  }
  const cellXY = (k) => ({ x: ((k % G) + 0.5) * cell, y: (((k / G) | 0) + 0.5) * cell });
  const stops = [...points, ...crossings];
  const reps = [];
  for (const [k, set] of nbr) {
    if (set.size < 3) continue;
    const q = cellXY(k);
    if (stops.some((s) => Math.hypot(s.x - q.x, s.y - q.y) < spacing * 0.35)) continue;
    if (reps.some((r) => Math.hypot(r.x - q.x, r.y - q.y) < spacing * 0.3)) continue;
    reps.push({ x: q.x, y: q.y });
  }
  const J0 = N0 + crossings.length;
  const repCache = new Map();
  const repOf = (k, active) => {
    let v = repCache.get(k);
    if (v === undefined) {
      const q = cellXY(k);
      v = -1;
      let bd = spacing * 0.3;
      reps.forEach((r, i) => {
        const d = Math.hypot(r.x - q.x, r.y - q.y);
        if (d < bd) {
          bd = d;
          v = i;
        }
      });
      repCache.set(k, v);
    }
    return v >= 0 && active[v] ? v : -1;
  };
  const nodeXY = (n) => (n >= J0 ? reps[n - J0] : nodes[n]);
  const build = (active) => {
    const segs = new Map();
    const loose = [];
    for (const p of pending) {
      if (!p.cells) {
        loose.push({ a: p.a, b: p.b, pts: p.pts });
        continue;
      }
      const cs = p.cells;
      const hits = [{ node: p.a, idx: 0 }];
      for (let i = 1; i < cs.length - 1; i++) {
        const r = repOf(cs[i], active);
        if (r < 0) continue;
        let j = i;
        while (j + 1 < cs.length - 1 && repOf(cs[j + 1], active) === r) j++;
        if (hits[hits.length - 1].node !== J0 + r) hits.push({ node: J0 + r, idx: Math.round((i + j) / 2) });
        i = j;
      }
      hits.push({ node: p.b, idx: cs.length - 1 });
      for (let h = 0; h < hits.length - 1; h++) {
        const h0 = hits[h];
        const h1 = hits[h + 1];
        if (h0.node === h1.node) continue;
        const key2 = key(h0.node, h1.node);
        if (segs.has(key2)) continue;
        const P = nodeXY(h0.node);
        const Q = nodeXY(h1.node);
        const mid = cs.slice(h0.idx + 1, h1.idx).map((k) => [cellXY(k).x, cellXY(k).y]);
        segs.set(key2, { a: h0.node, b: h1.node, pts: chaikin([[P.x, P.y], ...mid, [Q.x, Q.y]], 2) });
      }
    }
    return { segs: [...segs.values(), ...loose] };
  };
  const active = reps.map(() => true);
  let built = build(active);
  for (let guard = 0; guard < 10; guard++) {
    const deg = reps.map(() => 0);
    for (const sg of built.segs) {
      if (sg.a >= J0) deg[sg.a - J0] += 1;
      if (sg.b >= J0) deg[sg.b - J0] += 1;
    }
    let dropped = false;
    reps.forEach((_, i) => {
      if (active[i] && deg[i] < 3) {
        active[i] = false;
        dropped = true;
      }
    });
    if (!dropped) break;
    built = build(active);
  }
  const junctions = [];
  const jmap = new Map();
  reps.forEach((r, i) => {
    if (!active[i]) return;
    jmap.set(J0 + i, J0 + junctions.length);
    junctions.push({ idx: J0 + junctions.length, x: r.x, y: r.y });
  });
  const remap = (n) => (n >= J0 ? jmap.get(n) : n);
  const finals = [];
  for (const sg of built.segs) {
    const pts = sg.pts;
    const a = remap(sg.a);
    const b = remap(sg.b);
    const length = plen(pts);
    let costSum = 0;
    let count = 0;
    for (let k = 0; k < pts.length - 1; k++) {
      const sx = pts[k][0];
      const sy = pts[k][1];
      const ex = pts[k + 1][0];
      const ey = pts[k + 1][1];
      const n = Math.max(1, Math.ceil(Math.hypot(ex - sx, ey - sy) / (cell * 0.5)));
      for (let s = 0; s < n; s++) {
        const x = sx + ((ex - sx) * s) / n;
        const y = sy + ((ey - sy) * s) / n;
        const h = sample(height, x, y);
        costSum += h > MOUNT_T ? 2 : h > 0.42 ? 1.4 : sample(moist, x, y) > 0.58 ? 1.4 : h > sea + 0.17 ? 1.15 : 1;
        count += 1;
      }
    }
    const mult = Math.round(Math.min(2.6, costSum / Math.max(1, count)) * 100) / 100;
    finals.push({ a, b, kind: edgeKind({ a, b }), length, mult, path: pts.map(([x, y]) => [Math.round(x * 10) / 10, Math.round(y * 10) / 10]) });
  }
  const total = nodes.length + junctions.length;
  const par2 = Array.from({ length: total }, (_, i) => i);
  const root2 = (i) => {
    while (par2[i] !== i) {
      par2[i] = par2[par2[i]];
      i = par2[i];
    }
    return i;
  };
  for (const e of finals) par2[root2(e.a)] = root2(e.b);
  const rs = new Set(par2.map((_, i) => root2(i)));
  if (rs.size > 1) {
    trailDebug.reason = `paths left ${rs.size} components`;
    return null;
  }
  const at = (q) => ({ x: q.x, y: q.y });
  return { junctions, crossings, edges: finals, passes: crossings.filter((q) => q.pass).map(at), fords: crossings.filter((q) => !q.pass).map(at) };
}

export function buildTerrain(o) {
  const { points, edges, mapW, spacing } = o;
  const preset = PRESETS[o.preset || 'continental'];
  const G = GRID;
  const cell = mapW / G;
  const noiseA = makeNoise(o.makeRng(o.seed, 100 + o.salt * 10));
  const noiseB = makeNoise(o.makeRng(o.seed, 101 + o.salt * 10));
  const noiseC = makeNoise(o.makeRng(o.seed, 102 + o.salt * 10));
  const noiseD = makeNoise(o.makeRng(o.seed, 103 + o.salt * 10));
  const noiseE = makeNoise(o.makeRng(o.seed, 104 + o.salt * 10));
  const R = spacing * 0.5;
  const CORR = spacing * 0.22;
  const cx = (gx) => (gx + 0.5) * cell;

  const near = new Float32Array(G * G);
  const corr = new Float32Array(G * G);
  const reach = Math.ceil((2.2 * R) / cell);
  for (const p of points) {
    const gx0 = Math.floor(p.x / cell);
    const gy0 = Math.floor(p.y / cell);
    for (let gy = Math.max(0, gy0 - reach); gy <= Math.min(G - 1, gy0 + reach); gy++) {
      for (let gx = Math.max(0, gx0 - reach); gx <= Math.min(G - 1, gx0 + reach); gx++) {
        const dx = cx(gx) - p.x;
        const dy = cx(gy) - p.y;
        const v = Math.exp(-(dx * dx + dy * dy) / (R * R));
        const i = gy * G + gx;
        if (v > near[i]) near[i] = v;
      }
    }
  }
  const creach = Math.ceil((2.4 * CORR) / cell);
  for (const [a, b] of edges) {
    const A = points[a];
    const B = points[b];
    const dx = B.x - A.x;
    const dy = B.y - A.y;
    const len2 = dx * dx + dy * dy || 1;
    const gx0 = Math.max(0, Math.floor(Math.min(A.x, B.x) / cell) - creach);
    const gx1 = Math.min(G - 1, Math.floor(Math.max(A.x, B.x) / cell) + creach);
    const gy0 = Math.max(0, Math.floor(Math.min(A.y, B.y) / cell) - creach);
    const gy1 = Math.min(G - 1, Math.floor(Math.max(A.y, B.y) / cell) + creach);
    for (let gy = gy0; gy <= gy1; gy++) {
      for (let gx = gx0; gx <= gx1; gx++) {
        const px = cx(gx) - A.x;
        const py = cx(gy) - A.y;
        const t = Math.min(1, Math.max(0, (px * dx + py * dy) / len2));
        const ex = px - t * dx;
        const ey = py - t * dy;
        const v = Math.exp(-(ex * ex + ey * ey) / (CORR * CORR));
        const i = gy * G + gx;
        if (v > corr[i]) corr[i] = v;
      }
    }
  }

  const score = new Float32Array(G * G);
  const height = new Float32Array(G * G);
  const moist = new Float32Array(G * G);
  const isLand = new Uint8Array(G * G);
  const fadeLen = spacing * 0.55;
  for (let gy = 0; gy < G; gy++) {
    for (let gx = 0; gx < G; gx++) {
      const i = gy * G + gx;
      const x = cx(gx);
      const y = cx(gy);
      const fx = o.mirror ? mapW / 2 + Math.abs(x - mapW / 2) : x;
      const fy = o.mirror ? mapW / 2 + Math.abs(y - mapW / 2) : y;
      const cont = fbm(noiseE, fx / (spacing * 3.4), fy / (spacing * 3.4), 5);
      const rad = Math.hypot(x - mapW / 2, y - mapW / 2) / (mapW / 2);
      const cm = cont + 0.55 * Math.min(0, 0.85 - rad);
      const base = o.shapeLand ? o.shapeLand(x, y) : Math.min(1, Math.max(0, (cm - 0.43) * 2.2 + 0.4));
      const p = Math.max(near[i], 0.92 * corr[i], base);
      const fade = smoothstep(0, fadeLen, Math.min(x, y, mapW - x, mapW - y));
      const n1 = fbm(noiseA, fx / (spacing * 1.6), fy / (spacing * 1.6), 4);
      score[i] = (p + 0.42 * (n1 - 0.5)) * (0.3 + 0.7 * fade);
      isLand[i] = score[i] > LAND_T ? 1 : 0;

      const nr = fbm(noiseB, fx / (spacing * 1.9), fy / (spacing * 1.9), 5);
      const ridge = 1 - Math.abs(2 * nr - 1);
      const mount = smoothstep(0.92 - 0.12 * (preset.mountain - 1), 1.02 - 0.08 * (preset.mountain - 1), ridge);
      const flat = Math.max(near[i], 0.55 * corr[i]);
      const land = smoothstep(LAND_T, LAND_T + 0.12, score[i]);
      const roll = fbm(noiseC, fx / (spacing * 0.9), fy / (spacing * 0.9), 3);
      if (isLand[i]) {
        height[i] = SEA + 0.04 * land + land * (0.1 * roll + 0.55 * preset.mountain * mount * (1 - 0.9 * flat));
      } else {
        height[i] = SEA * smoothstep(0, LAND_T, score[i]);
      }
      const wet = fbm(noiseD, fx / (spacing * 1.3), fy / (spacing * 1.3), 3);
      moist[i] = Math.min(1, Math.max(0, (wet - 0.5) * 2.4 + 0.5 + preset.wet - 0.12 * Math.max(0, height[i] - 0.5)));
    }
  }

  const sample = (grid, x, y) => {
    const fx = Math.min(G - 1.001, Math.max(0, x / cell - 0.5));
    const fy = Math.min(G - 1.001, Math.max(0, y / cell - 0.5));
    const ix = Math.floor(fx);
    const iy = Math.floor(fy);
    const tx = fx - ix;
    const ty = fy - iy;
    const a = grid[iy * G + ix];
    const b = grid[iy * G + ix + 1];
    const c = grid[(iy + 1) * G + ix];
    const d = grid[(iy + 1) * G + ix + 1];
    return a * (1 - tx) * (1 - ty) + b * tx * (1 - ty) + c * (1 - tx) * ty + d * tx * ty;
  };
  const meanHeight = (p, rad) => {
    let sum = sample(height, p.x, p.y);
    let n = 1;
    for (let k = 0; k < 8; k++) {
      const ang = (k * Math.PI) / 4;
      sum += sample(height, p.x + rad * Math.cos(ang), p.y + rad * Math.sin(ang));
      n += 1;
    }
    return sum / n;
  };
  const oceanNear = (p, rad) => {
    for (let k = 0; k < 8; k++) {
      const ang = (k * Math.PI) / 4;
      if (sample(height, p.x + rad * Math.cos(ang), p.y + rad * Math.sin(ang)) < SEA) return true;
    }
    return false;
  };

  const neutralIdx = [];
  for (let t = 0; t < points.length; t++) if (!o.owned[t] && o.tiers[t] <= 2) neutralIdx.push(t);
  neutralIdx.sort((a, b) => meanHeight(points[b], spacing * 0.6) - meanHeight(points[a], spacing * 0.6) || a - b);
  const fortressCount = preset.mountain ? Math.ceil(0.12 * neutralIdx.length) : 0;
  const fortress = new Set(neutralIdx.slice(0, fortressCount));
  for (const t of fortress) {
    const p = points[t];
    const gx0 = Math.floor(p.x / cell);
    const gy0 = Math.floor(p.y / cell);
    const rr = Math.ceil((spacing * 0.4) / cell);
    for (let gy = Math.max(0, gy0 - rr); gy <= Math.min(G - 1, gy0 + rr); gy++) {
      for (let gx = Math.max(0, gx0 - rr); gx <= Math.min(G - 1, gx0 + rr); gx++) {
        const dx = cx(gx) - p.x;
        const dy = cx(gy) - p.y;
        const bump = 0.34 * Math.exp(-(dx * dx + dy * dy) / ((spacing * 0.2) ** 2));
        const i = gy * G + gx;
        if (isLand[i]) height[i] = Math.min(1, height[i] + bump);
      }
    }
  }

  const flowH = new Float32Array(G * G);
  for (let i = 0; i < G * G; i++) flowH[i] = height[i] + (isLand[i] ? 0.25 * Math.min(1, score[i]) : 0);
  const filled = new Float32Array(G * G).fill(Infinity);
  const parent = new Int32Array(G * G).fill(-1);
  const heap = new MinHeap();
  for (let i = 0; i < G * G; i++) {
    if (!isLand[i]) {
      filled[i] = flowH[i];
      heap.push(filled[i], i);
    }
  }
  const done = new Uint8Array(G * G);
  while (heap.size) {
    const c = heap.pop();
    if (done[c]) continue;
    done[c] = 1;
    const gx = c % G;
    const gy = (c / G) | 0;
    for (let dy = -1; dy <= 1; dy++) {
      for (let dx = -1; dx <= 1; dx++) {
        if (!dx && !dy) continue;
        const nx = gx + dx;
        const ny = gy + dy;
        if (nx < 0 || ny < 0 || nx >= G || ny >= G) continue;
        const n = ny * G + nx;
        if (done[n]) continue;
        const val = Math.max(flowH[n], filled[c] + 1e-5 * (dx && dy ? 1.4 : 1));
        if (val < filled[n]) {
          filled[n] = val;
          parent[n] = c;
          heap.push(val, n);
        }
      }
    }
  }

  const rivers = [];
  const landCells = [];
  const acc = new Float32Array(G * G);
  for (let i = 0; i < G * G; i++) {
    if (isLand[i]) {
      landCells.push(i);
      acc[i] = 0.6 + moist[i];
    }
  }
  landCells.sort((a, b) => filled[b] - filled[a] || a - b);
  for (const c of landCells) {
    const p = parent[c];
    if (p >= 0 && isLand[p]) acc[p] += acc[c];
  }
  const sortedAcc = landCells.map((c) => acc[c]).sort((a, b) => a - b);
  const cut = preset.rivers ? Math.max(40, sortedAcc[Math.floor(sortedAcc.length * (1 - Math.min(0.2, RIVER_SHARE * preset.rivers)))] || 0) : Infinity;
  const hasUp = new Uint8Array(G * G);
  const riverId = new Int16Array(G * G).fill(-1);
  const heads = [];
  for (const c of landCells) {
    if (acc[c] < cut) continue;
    const p = parent[c];
    if (p >= 0 && isLand[p] && acc[p] >= cut) hasUp[p] = 1;
  }
  for (const c of landCells) if (acc[c] >= cut && !hasUp[c]) heads.push(c);
  heads.sort((a, b) => filled[b] - filled[a] || a - b);
  for (const s of heads) {
    const path = [];
    let c = s;
    let merged = false;
    let guard = 0;
    while (c >= 0 && guard++ < 2000) {
      path.push(c);
      if (!isLand[c]) break;
      if (riverId[c] >= 0 && path.length > 1) {
        merged = true;
        break;
      }
      c = parent[c];
    }
    if (path.length < 12 && !merged) continue;
    for (const c2 of path) if (riverId[c2] < 0) riverId[c2] = rivers.length;
    rivers.push(path);
  }

  const accMax = Math.max(1, ...landCells.map((c) => acc[c]));
  const widthAt = (c) => 1.4 + (RIVER_MAX_W - 1.4) * Math.pow(Math.max(0, Math.min(1, (acc[c] - cut) / Math.max(1, accMax - cut))), 0.62);
  const riverPolys = rivers.map((path) => {
    const wc = path.map((c) => (isLand[c] ? widthAt(c) : widthAt(path[path.length - 2] ?? c)));
    const raw = path.map((c) => [cx(c % G), cx((c / G) | 0)]);
    const pts = chaikin(raw, 2);
    const ws = pts.map((_, j) => {
      const t = (j / (pts.length - 1)) * (path.length - 1);
      const a = Math.floor(t);
      const b = Math.min(path.length - 1, a + 1);
      return Math.round((wc[a] + (wc[b] - wc[a]) * (t - a)) * 10) / 10;
    });
    const w = Math.max(...ws);
    return { w, cls: riverClass(w), ws, p: pts.map(([x, y]) => [Math.round(x * 10) / 10, Math.round(y * 10) / 10]) };
  });
  const riverSegs = [];
  for (const [ri, r] of riverPolys.entries()) {
    for (let k = 0; k < r.p.length - 1; k++) {
      const sa = { x: r.p[k][0], y: r.p[k][1] };
      const sb = { x: r.p[k + 1][0], y: r.p[k + 1][1] };
      riverSegs.push({ ri, w: Math.max(r.ws[k], r.ws[k + 1]), a: sa, b: sb, x0: Math.min(sa.x, sb.x), x1: Math.max(sa.x, sb.x), y0: Math.min(sa.y, sb.y), y1: Math.max(sa.y, sb.y) });
    }
  }

  const nearestOnSegment = (p, seg) => {
    const dx = seg.b.x - seg.a.x;
    const dy = seg.b.y - seg.a.y;
    const len2 = dx * dx + dy * dy || 1;
    const t = Math.min(1, Math.max(0, ((p.x - seg.a.x) * dx + (p.y - seg.a.y) * dy) / len2));
    return { x: seg.a.x + t * dx, y: seg.a.y + t * dy };
  };

  const scanLine = (A, B) => {
    const len = Math.hypot(B.x - A.x, B.y - A.y);
    const steps = Math.max(4, Math.ceil(len / (cell * 0.7)));
    let cost = 0;
    let ocean = false;
    let oceanCount = 0;
    const runs = [];
    let run = null;
    for (let s = 0; s <= steps; s++) {
      const t = s / steps;
      const x = A.x + (B.x - A.x) * t;
      const y = A.y + (B.y - A.y) * t;
      const h = sample(height, x, y);
      if (h < SEA) {
        ocean = true;
        oceanCount += 1;
      }
      let c = 1;
      if (h > MOUNT_T) c = 2;
      else if (h > 0.42) c = 1.4;
      else if (sample(moist, x, y) > 0.58) c = 1.4;
      else if (h > SEA + 0.17) c = 1.15;
      cost += c;
      if (t * len > spacing * 0.3 && (1 - t) * len > spacing * 0.3 && h > MOUNT_T) {
        if (!run) run = { sx: x, sy: y, lx: x, ly: y, lh: h };
        run.ex = x;
        run.ey = y;
        if (h < run.lh) {
          run.lx = x;
          run.ly = y;
          run.lh = h;
        }
      } else if (run) {
        runs.push(run);
        run = null;
      }
    }
    if (run) runs.push(run);
    const crossings = [];
    const lx0 = Math.min(A.x, B.x);
    const lx1 = Math.max(A.x, B.x);
    const ly0 = Math.min(A.y, B.y);
    const ly1 = Math.max(A.y, B.y);
    for (const seg of riverSegs) {
      if (seg.x1 < lx0 || seg.x0 > lx1 || seg.y1 < ly0 || seg.y0 > ly1) continue;
      const q = segIntersect(A, B, seg.a, seg.b);
      if (q && !crossings.some((c) => Math.hypot(c.x - q.x, c.y - q.y) < spacing * 0.08)) crossings.push(q);
    }
    return { len, ocean, oceanFrac: oceanCount / (steps + 1), cost: cost / (steps + 1), runs: runs.map((r) => ({ x: (r.sx + r.ex) / 2, y: (r.sy + r.ey) / 2, low: { x: r.lx, y: r.ly } })), crossings };
  };

  const fords = [];
  const passes = [];
  const addUnique = (list, p, rad) => {
    if (!list.some((f) => Math.hypot(f.x - p.x, f.y - p.y) < rad)) list.push(p);
  };
  for (const [a, b] of edges) {
    const sc = scanLine(points[a], points[b]);
    sc.crossings.forEach((q) => addUnique(fords, q, spacing * 0.08));
    sc.runs.forEach((r) => addUnique(passes, r, spacing * 0.15));
  }
  for (const p of points) {
    let best = null;
    let bd = spacing * 0.22;
    for (const seg of riverSegs) {
      const q = nearestOnSegment(p, seg);
      const d = Math.hypot(q.x - p.x, q.y - p.y);
      if (d < bd) {
        bd = d;
        best = q;
      }
    }
    if (best) addUnique(fords, best, spacing * 0.08);
  }

  const classify = (a, b) => {
    const sc = scanLine(points[a], points[b]);
    if (sc.ocean) return null;
    for (const q of sc.crossings) if (!fords.some((f) => Math.hypot(f.x - q.x, f.y - q.y) <= spacing * 0.2)) return null;
    for (const r of sc.runs) if (!passes.some((f) => Math.hypot(f.x - r.x, f.y - r.y) <= spacing * 0.35)) return null;
    const mult = Math.round(Math.min(2.6, sc.cost + 0.25 * sc.crossings.length) * 100) / 100;
    if (sc.runs.length) return { kind: 'pass', mult };
    if (sc.crossings.length) return { kind: 'river', mult };
    return { kind: 'land', mult };
  };

  const edgeInfo = edges.map(([a, b]) => classify(a, b) || { kind: 'land', mult: 1 });

  const baseKeys = new Set(edges.map(([a, b]) => (a < b ? `${a},${b}` : `${b},${a}`)));
  const links = (cap = Infinity) => {
    const out = [];
    for (let a = 0; a < points.length; a++) {
      for (let b = a + 1; b < points.length; b++) {
        const length = Math.hypot(points[a].x - points[b].x, points[a].y - points[b].y);
        const base = baseKeys.has(`${a},${b}`);
        if (length > cap && !base) continue;
        const c = classify(a, b) || (base ? { kind: 'land', mult: 1 } : null);
        if (c) out.push({ a, b, kind: c.kind, mult: c.mult, length });
      }
    }
    return out;
  };

  const terrain = points.map((p, t) => {
    if (fortress.has(t)) return 'mountain';
    const hm = meanHeight(p, spacing * 0.3);
    if (oceanNear(p, spacing * 0.34)) return 'coast';
    if (hm > SEA + 0.17) return 'hills';
    if (sample(moist, p.x, p.y) > 0.56) return 'forest';
    return 'plains';
  });

  const seatOf = o.seatOf;
  const seats = o.players;
  const trailCtx = { points, edges, spacing, cell, G, sample, height, moist, riverSegs, scanLine, nearestOnSegment, MOUNT_T, SEA };
  const trails = o.trails ? planTrails(trailCtx) || planTrails(trailCtx, 0.25) || planTrails(trailCtx, 0.6) : null;
  const pen = new Array(seats).fill(0);
  const penEdges = trails
    ? trails.edges.map((e) => ({ a: e.a, b: e.b, w: e.kind === 'pass' ? 2 : e.kind === 'river' ? 1.5 : (e.mult - 1) * 1.5 }))
    : edges.map(([a, b], k) => ({ a, b, w: edgeInfo[k].kind === 'pass' ? 2 : edgeInfo[k].kind === 'river' ? 1 : (edgeInfo[k].mult - 1) * 1.5 }));
  for (const { a, b, w } of penEdges) {
    if (!w) continue;
    for (const t of [a, b]) if (t < points.length && o.owned[t]) pen[seatOf[t]] += w;
  }
  const spread = Math.max(...pen) - Math.min(...pen);
  const total = pen.reduce((s, v) => s + v, 0);
  const fairness = o.trails && !trails ? Infinity : spread * 10 + total / seats;

  const hStr = [];
  const mStr = [];
  for (let i = 0; i < G * G; i++) {
    const hv = Math.min(1295, Math.max(0, Math.round(Math.min(1, height[i]) * 1295)));
    hStr.push(hv.toString(36).padStart(2, '0'));
    mStr.push(String(Math.min(9, Math.round(moist[i] * 9))));
  }

  return {
    fairness,
    terrain,
    edgeInfo,
    links,
    trails,
    art: {
      v: 1,
      grid: G,
      sea: SEA,
      seed: decorSeed(hStr),
      h: hStr.join(''),
      m: mStr.join(''),
      rivers: riverPolys,
      fords: (trails ? trails.fords : fords).map((f) => [Math.round(f.x * 10) / 10, Math.round(f.y * 10) / 10]),
      passes: (trails ? trails.passes.filter((p, i, arr) => arr.findIndex((q) => Math.hypot(q.x - p.x, q.y - p.y) < spacing * 0.15) === i) : passes).map((f) => [Math.round(f.x * 10) / 10, Math.round(f.y * 10) / 10]),
    },
    stats: {
      landShare: isLand.reduce((s, v) => s + v, 0) / (G * G),
      mountainShare: height.reduce((s, v, i) => s + (isLand[i] && v > MOUNT_T ? 1 : 0), 0) / Math.max(1, isLand.reduce((s, v) => s + v, 0)),
      rivers: riverPolys.length,
      penalties: pen,
    },
  };
}

export function bestTerrain(o) {
  let best = null;
  const count = o.points.length > 150 ? 3 : o.points.length > 60 ? 4 : 5;
  const extra = o.trails ? 6 : 0;
  for (let salt = 0; salt < count + extra; salt++) {
    if (salt >= count && best && Number.isFinite(best.fairness)) break;
    const result = buildTerrain({ ...o, salt });
    if (!best || result.fairness < best.fairness) best = result;
  }
  if (o.trails && (!best || !Number.isFinite(best.fairness))) throw new Error('could not connect every castle with trails for these settings');
  return best;
}
