export const GRID = 192;
export const SEA = 0.2;
const LAND_T = 0.36;
const MOUNT_T = 0.53;
const CANDIDATES = 20;

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

export function buildTerrain(o) {
  const { points, edges, mapW, spacing } = o;
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
      const cont = fbm(noiseE, x / (spacing * 3.4), y / (spacing * 3.4), 5);
      const rad = Math.hypot(x - mapW / 2, y - mapW / 2) / (mapW / 2);
      const cm = cont + 0.55 * Math.min(0, 0.85 - rad);
      const p = Math.max(near[i], 0.92 * corr[i], Math.min(1, Math.max(0, (cm - 0.43) * 2.2 + 0.4)));
      const fade = smoothstep(0, fadeLen, Math.min(x, y, mapW - x, mapW - y));
      const n1 = fbm(noiseA, x / (spacing * 1.6), y / (spacing * 1.6), 4);
      score[i] = (p + 0.42 * (n1 - 0.5)) * (0.3 + 0.7 * fade);
      isLand[i] = score[i] > LAND_T ? 1 : 0;

      const nr = fbm(noiseB, x / (spacing * 1.9), y / (spacing * 1.9), 5);
      const ridge = 1 - Math.abs(2 * nr - 1);
      const mount = smoothstep(0.82, 0.98, ridge);
      const flat = Math.max(near[i], 0.55 * corr[i]);
      const land = smoothstep(LAND_T, LAND_T + 0.12, score[i]);
      const roll = fbm(noiseC, x / (spacing * 0.9), y / (spacing * 0.9), 3);
      if (isLand[i]) {
        height[i] = SEA + 0.04 * land + land * (0.1 * roll + 0.55 * mount * (1 - 0.9 * flat));
      } else {
        height[i] = SEA * smoothstep(0, LAND_T, score[i]);
      }
      const wet = fbm(noiseD, x / (spacing * 1.3), y / (spacing * 1.3), 3);
      moist[i] = Math.min(1, Math.max(0, (wet - 0.5) * 2.4 + 0.5 - 0.12 * Math.max(0, height[i] - 0.5)));
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
  const fortressCount = Math.ceil(0.12 * neutralIdx.length);
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
  const riverCount = new Uint16Array(G * G);
  const wanted = Math.max(4, Math.round(points.length / 3.5));
  const candidates = [];
  for (let i = 0; i < G * G; i++) {
    if (isLand[i] && height[i] > SEA + 0.2) {
      const x = cx(i % G);
      const y = cx((i / G) | 0);
      candidates.push({ i, h: height[i] + 0.03 * noiseD(x / 90, y / 90) });
    }
  }
  candidates.sort((a, b) => b.h - a.h || a.i - b.i);
  const sources = [];
  for (const c of candidates) {
    if (sources.length >= wanted) break;
    const gx = c.i % G;
    const gy = (c.i / G) | 0;
    if (sources.some((s) => Math.hypot((s % G) - gx, ((s / G) | 0) - gy) < 9)) continue;
    sources.push(c.i);
  }
  for (const s of sources) {
    const path = [];
    let c = s;
    let merged = false;
    let guard = 0;
    while (c >= 0 && guard++ < 2000) {
      path.push(c);
      if (!isLand[c]) break;
      if (riverCount[c] > 0 && path.length > 1) {
        merged = true;
        break;
      }
      c = parent[c];
    }
    if (path.length < 10 && !merged) continue;
    for (const c2 of path) riverCount[c2] += 1;
    rivers.push(path);
  }

  const riverPolys = rivers.map((path) => {
    const raw = path.map((c) => [cx(c % G), cx((c / G) | 0)]);
    const pts = chaikin(raw, 2);
    let share = 1;
    for (const c of path) share = Math.max(share, riverCount[c]);
    return { w: Math.round((1.6 + 0.7 * (share - 1)) * 10) / 10, p: pts.map(([x, y]) => [Math.round(x * 10) / 10, Math.round(y * 10) / 10]) };
  });
  const riverSegs = [];
  for (const r of riverPolys) {
    for (let k = 0; k < r.p.length - 1; k++) {
      const sa = { x: r.p[k][0], y: r.p[k][1] };
      const sb = { x: r.p[k + 1][0], y: r.p[k + 1][1] };
      riverSegs.push({ a: sa, b: sb, x0: Math.min(sa.x, sb.x), x1: Math.max(sa.x, sb.x), y0: Math.min(sa.y, sb.y), y1: Math.max(sa.y, sb.y) });
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
    const runs = [];
    let run = null;
    for (let s = 0; s <= steps; s++) {
      const t = s / steps;
      const x = A.x + (B.x - A.x) * t;
      const y = A.y + (B.y - A.y) * t;
      const h = sample(height, x, y);
      if (h < SEA) ocean = true;
      let c = 1;
      if (h > MOUNT_T) c = 2;
      else if (h > 0.42) c = 1.4;
      else if (sample(moist, x, y) > 0.58) c = 1.4;
      else if (h > SEA + 0.17) c = 1.15;
      cost += c;
      if (t * len > spacing * 0.3 && (1 - t) * len > spacing * 0.3 && h > MOUNT_T) {
        if (!run) run = { sx: x, sy: y };
        run.ex = x;
        run.ey = y;
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
    return { len, ocean, cost: cost / (steps + 1), runs: runs.map((r) => ({ x: (r.sx + r.ex) / 2, y: (r.sy + r.ey) / 2 })), crossings };
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

  const links = (cap = Infinity) => {
    const out = [];
    for (let a = 0; a < points.length; a++) {
      for (let b = a + 1; b < points.length; b++) {
        const length = Math.hypot(points[a].x - points[b].x, points[a].y - points[b].y);
        if (length > cap) continue;
        const c = classify(a, b);
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
  const pen = new Array(seats).fill(0);
  edges.forEach(([a, b], k) => {
    const w = edgeInfo[k].kind === 'pass' ? 2 : edgeInfo[k].kind === 'river' ? 1 : (edgeInfo[k].mult - 1) * 1.5;
    if (!w) return;
    for (const t of [a, b]) if (o.owned[t]) pen[seatOf[t]] += w;
  });
  const spread = Math.max(...pen) - Math.min(...pen);
  const total = pen.reduce((s, v) => s + v, 0);
  const fairness = spread * 10 + total / seats;

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
    art: {
      v: 1,
      grid: G,
      sea: SEA,
      seed: decorSeed(hStr),
      h: hStr.join(''),
      m: mStr.join(''),
      rivers: riverPolys,
      fords: fords.map((f) => [Math.round(f.x * 10) / 10, Math.round(f.y * 10) / 10]),
      passes: passes.map((f) => [Math.round(f.x * 10) / 10, Math.round(f.y * 10) / 10]),
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
  const count = o.points.length > 150 ? CANDIDATES / 2 : CANDIDATES;
  for (let salt = 0; salt < count; salt++) {
    const result = buildTerrain({ ...o, salt });
    if (!best || result.fairness < best.fairness) best = result;
  }
  return best;
}
