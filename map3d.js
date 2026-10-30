import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { Sky } from 'three/addons/objects/Sky.js';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { mergeGeometries as mg0 } from 'three/addons/utils/BufferGeometryUtils.js';

const mergeGeometries = (a) => mg0(a.map((g) => (g.index ? g.toNonIndexed() : g)));

export async function createMap3D(host, spec) {
const $ = (id) => host.querySelector('#' + id);
host.classList.add('map3d');
const RICH = spec.quality !== 'lean';
const X = RICH ? { Water: (await import('three/addons/objects/Water.js')).Water, Bloom: (await import('three/addons/postprocessing/UnrealBloomPass.js')).UnrealBloomPass, SAO: (await import('three/addons/postprocessing/SAOPass.js')).SAOPass } : null;
host.innerHTML = '<div id="wrap"></div><div id="labels"></div><div id="ui"><button id="b3d" class="on">Tilted</button><button id="bflat">Top-down</button><button id="bshadow" class="on">Shadows</button>' + (RICH ? '<button id="bao">Occlusion</button>' : '') + '</div><div id="load">Raising the realm...</div>';
let running = true;
const PROFILE = spec.profile || 'all';
const PF = ({ all: { desert: 1, swamp: 1, snow: 1, lakes: 1, forest: 1, frost: 0 }, temperate: { desert: 0, swamp: 0, snow: 0, lakes: 1, forest: 1, frost: 0 }, arid: { desert: 1, swamp: 0, snow: 0, lakes: 1, forest: .25, frost: 0 }, frozen: { desert: 0, swamp: 0, snow: 1, lakes: 1, forest: .7, frost: 1 }, swampy: { desert: 0, swamp: 1, snow: 0, lakes: 1, forest: 1, frost: 0 } })[PROFILE] || { desert: 1, swamp: 1, snow: 1, lakes: 1, forest: 1, frost: 0 };
const art = spec.art, W = spec.map_w, G = art.grid;
const hg = new Float32Array(G * G), mg = new Float32Array(G * G);
for (let i = 0; i < G * G; i++) { hg[i] = parseInt(art.h.substr(i * 2, 2), 36) / 1295; mg[i] = Number(art.m[i]) / 9; }
for (let pass = 0; pass < 2; pass++) { const c = hg.slice(); for (let y = 1; y < G - 1; y++) for (let x = 1; x < G - 1; x++) { let s = 0; for (let j = -1; j <= 1; j++) for (let i = -1; i <= 1; i++) s += c[(y + j) * G + x + i] * (i === 0 && j === 0 ? 4 : 1); hg[y * G + x] = s / 12; } }
{ const b = hg.slice(); for (let pass = 0; pass < 6; pass++) { const c = b.slice(); for (let y = 1; y < G - 1; y++) for (let x = 1; x < G - 1; x++) { let s = 0; for (let j = -1; j <= 1; j++) for (let i = -1; i <= 1; i++) s += c[(y + j) * G + x + i]; b[y * G + x] = s / 9; } } for (let i = 0; i < G * G; i++) { const e = (hg[i] - art.sea) / (1 - art.sea), w = Math.min(1, Math.max(0, (e - .22) / .3)); hg[i] = hg[i] * (1 - w * .85) + b[i] * w * .85; } }
const SEA = art.sea, cell = W / G;
const bil = (g, fx, fy) => { fx = Math.min(G - 1.001, Math.max(0, fx)); fy = Math.min(G - 1.001, Math.max(0, fy)); const ix = Math.floor(fx), iy = Math.floor(fy), tx = fx - ix, ty = fy - iy; return g[iy*G+ix]*(1-tx)*(1-ty)+g[iy*G+ix+1]*tx*(1-ty)+g[(iy+1)*G+ix]*(1-tx)*ty+g[(iy+1)*G+ix+1]*tx*ty; };
const H = (x, z) => bil(hg, x / cell - 0.5, z / cell - 0.5);
const Mo = (x, z) => bil(mg, x / cell - 0.5, z / cell - 0.5);
const hash = (x, y) => { let n = (Math.imul(x | 0, 374761393) + Math.imul(y | 0, 668265263)) ^ 0x5bd1e995; n = Math.imul(n ^ (n >>> 13), 1274126177); return ((n ^ (n >>> 16)) >>> 0) / 4294967295; };
const vn = (x, y) => { const xi = Math.floor(x), yi = Math.floor(y), xf = x - xi, yf = y - yi, u = xf*xf*(3-2*xf), v = yf*yf*(3-2*yf); return hash(xi,yi)*(1-u)*(1-v)+hash(xi+1,yi)*u*(1-v)+hash(xi,yi+1)*(1-u)*v+hash(xi+1,yi+1)*u*v; };
const fbm = (x, y, o = 4) => { let a = .5, t = 0, f = 1; for (let i = 0; i < o; i++) { t += a * vn(x*f, y*f); f *= 2.1; a *= .5; } return t; };
const ridge = (x, y) => { let a = .5, t = 0, f = 1; for (let i = 0; i < 4; i++) { t += a * (1 - Math.abs(vn(x*f, y*f) * 2 - 1)); f *= 2.05; a *= .5; } return t; };
const CF = 2.1, CK = .6, WS = W / 8067, HMAX = 470 * Math.pow(Math.max(.55, WS), .5);
const BG = W > 11000 ? 192 : 128, BS = 5, BIO = new Float32Array(BG * BG * BS);
const MoS = (() => { let a = mg.slice(); for (let p = 0; p < 4; p++) { const b = a.slice(); for (let y = 1; y < G - 1; y++) for (let x = 1; x < G - 1; x++) { let s = 0; for (let j = -1; j <= 1; j++) for (let i = -1; i <= 1; i++) s += b[(y + j) * G + x + i]; a[y * G + x] = s / 9; } } return a; })();
const sstep = (a, b, x) => { const u = Math.min(1, Math.max(0, (x - a) / (b - a))); return u * u * (3 - 2 * u); };
const REG = {};
{ const GS = 24, cs = W / GS, cells = []; for (let gy = 0; gy < GS; gy++) for (let gx = 0; gx < GS; gx++) { let land = 0, m = 0, el = 0, n = 0; for (let j = -1; j <= 1; j++) for (let i = -1; i <= 1; i++) { const x = (gx + .5 + i * .45) * cs, z = (gy + .5 + j * .45) * cs, h = H(x, z); n++; if (h >= SEA) { land++; el += (h - SEA) / (1 - SEA); m += bil(MoS, x / cell - .5, z / cell - .5); } } cells.push({ x: (gx + .5) * cs, z: (gy + .5) * cs, land: land / n, m: land ? m / land : .5, el: land ? el / land : 0 }); }
  const taken = [], pick = (name, R, score) => { if (!PF[name]) return; let best = null, bs = -1e9; cells.forEach((c) => { if (c.land < .8 || taken.some((q) => Math.hypot(q.x - c.x, q.z - c.z) < (q.R + R) * 1.05)) return; const s = score(c); if (s > bs) { bs = s; best = c; } }); if (best) { REG[name] = { x: best.x, z: best.z, R, s: hash(Math.round(best.x), Math.round(best.z)) * 50 }; taken.push(REG[name]); } };
  const big = (k) => W * k;
  if (PROFILE === 'arid') pick('desert', big(.3), (c) => (1 - c.m) * (1 - c.el * 1.4) + c.land);
  else pick('desert', big(.15), (c) => (1 - c.m) * (1 - c.el * 1.4) + c.land);
  if (PROFILE === 'swampy') pick('swamp', big(.27), (c) => c.m * (1 - c.el * 3) + c.land);
  else pick('swamp', big(.12), (c) => c.m * (1 - c.el * 3) + c.land);
  if (!PF.frost) pick('snow', big(.15), (c) => (1 - c.z / W) * (.7 + c.el) + c.land * .5); }
const regW = (r, x, z) => r ? 1 - sstep(r.R * .55, r.R * 1.0, Math.hypot(x - r.x, z - r.z) + (fbm(x / 1300 + r.s, z / 1300 + r.s * .7, 3) - .5) * r.R * .7) : 0;
{ const ssj = sstep;
  for (let gy = 0; gy < BG; gy++) for (let gx = 0; gx < BG; gx++) { const x = (gx + .5) / BG * W, z = (gy + .5) / BG * W, h = H(x, z), land = h >= SEA ? 1 : 0, el = Math.max(0, (h - SEA) / (1 - SEA)), mS = bil(MoS, x / cell - .5, z / cell - .5), n = fbm(x / 900 + 5, z / 900 + 9, 3) - .5;
    const mm = ssj(.26, .5, el + n * .04) * land; const dd = regW(REG.desert, x, z) * (1 - ssj(.2, .38, el)) * land * (1 - mm * .9);
    const inland = [[1, 0], [-1, 0], [0, 1], [0, -1], [.7, .7], [-.7, .7], [.7, -.7], [-.7, -.7]].every(([a, b]) => H(x + a * 420, z + b * 420) >= SEA ? 1 : 0) ? 1 : 0; const sw = inland * regW(REG.swamp, x, z) * (1 - ssj(.1, .2, el)) * (1 - dd) * (1 - mm) * land;
    const ff = ssj(.48, .66, mS + n * .15) * (1 - ssj(.28, .46, el)) * (1 - dd) * (1 - mm * .8) * (1 - sw * .85) * land * PF.forest;
    const sn = (PF.frost ? 1 : regW(REG.snow, x, z)) * land * (1 - dd);
    const k = (gy * BG + gx) * BS; BIO[k] = dd * (1 - sn * .8); BIO[k + 1] = ff * (1 - sn * .3); BIO[k + 2] = mm; BIO[k + 3] = sw * (1 - sn * .6); BIO[k + 4] = sn; } }
const biome = (x, z) => { const fx = Math.min(BG - 1.001, Math.max(0, x / W * BG - .5)), fy = Math.min(BG - 1.001, Math.max(0, z / W * BG - .5)), ix = Math.floor(fx), iy = Math.floor(fy), tx = fx - ix, ty = fy - iy, o = [0, 0, 0, 0, 0]; for (let c = 0; c < BS; c++) { const g = (xx, yy) => BIO[(yy * BG + xx) * BS + c]; o[c] = g(ix, iy) * (1 - tx) * (1 - ty) + g(ix + 1, iy) * tx * (1 - ty) + g(ix, iy + 1) * (1 - tx) * ty + g(ix + 1, iy + 1) * tx * ty; } return o; };
const sites = spec.sites.map((t) => ({ ...t }));
const rawY = (x, z) => {
  const h = H(x, z); if (h < SEA) return -(1 - h / SEA) * 80 - 8;
  const el = (h - SEA) / (1 - SEA);
  const wx = x + (fbm(x / 500, z / 500, 3) - .5) * 160, wz = z + (fbm(z / 500 + 9, x / 500, 3) - .5) * 160;
  let y = Math.pow(el, 1.3) * HMAX + (fbm(wx / 150, wz / 150) - .45) * (18 + el * 46) + (ridge(wx / 420, wz / 420) - .5) * el * el * 120;
  const [bd, bf, bm, bsw] = biome(x, z); { const ro = sstep(.15, .45, el); y += ((ridge(wx / 70, wz / 70) - .5) * 30 + (fbm(wx / 38, wz / 38) - .5) * 10) * ro * (.35 + bm); } y *= 1 + .12 * bm; if (bsw > 0) y = y + (4 + (fbm(wx / 120, wz / 120) - .5) * 5 - y) * bsw * .85; if (bd > 0) y = y * (1 - .42 * bd) + bd * ((ridge(wx / 260, wz / 260) - .5) * 30 + (fbm(wx / 90, wz / 90) - .5) * 9) + Math.min(1, bd * 3) * (fbm(wx / 330, wz / 330) - .5) * 44;
  return Math.max(y, 3.5);
};
sites.forEach((s, i) => { s.gy = Math.max(7, rawY(s.x, s.y)); const tier = s.tier || 1, v = s.riv ? 'riverTwins' : s.crossing_kind === 'pass' ? 'passGate' : pickVariant(tier, s.terrain, i), S0 = (tier >= 3 ? 1.35 : tier === 2 ? 1.05 : .72) * 1.25, mult = s.riv ? 1 : tier >= 3 ? 1.7 : tier === 2 ? 2.1 : 2.7; s.v = v; s.pl = (v === 'citadel' ? 170 : v === 'passGate' ? 120 : 110) * mult; s.moat = null; const near = sites.filter((o) => o !== s).sort((p, q) => Math.hypot(p.x - s.x, p.y - s.y) - Math.hypot(q.x - s.x, q.y - s.y))[0]; s.face = near ? Math.atan2(near.x - s.x, near.y - s.y) : 0;
  const ml = s.riv ? null : moatLocal(v, tier, i, S0);
  if (ml) { const M = CK * mult, wd = ml.wd * M; if (ml.r) { const r0 = ml.r * M; s.moat = { r0, wd }; s.pl = r0 + wd + 22; } else { const cf = Math.cos(s.face), sf = Math.sin(s.face), pl = ml.pl.map(([nx, nz, o]) => [nx * cf + nz * sf, -nx * sf + nz * cf, o * M]), vo = planeVerts(pl, wd), vi = planeVerts(pl, 0); s.moat = { pl, wd, vo, vi }; s.pl = Math.max(...vo.map(([x, z]) => Math.hypot(x, z))) + 10; } }
});
const ssf = (a, b, x) => { const u = Math.min(1, Math.max(0, (x - a) / (b - a))); return u * u * (3 - 2 * u); };
const gk = (a, b) => (a + 8) * 4096 + (b + 8);
const RVX = [], RVZ = [], RVB = [], RVW = [], rgrid = new Map(), RIVERS = [];
const RV_HW = (w) => 22 + 38 * Math.max(0, w - 1.4);
const RV_DEPTH = (hw) => 5 + hw * .06;
(art.rivers || []).forEach((r) => {
  const p0 = r.p, n0 = p0.length; if (n0 < 6) return;
  const w0 = r.ws || p0.map(() => r.w || 2);
  const sm = p0.map((_, i) => { let sx = 0, sy = 0, sw = 0, c = 0; for (let k = -5; k <= 5; k++) { const j = Math.min(n0 - 1, Math.max(0, i + k)); sx += p0[j][0]; sy += p0[j][1]; sw += w0[j]; c++; } return [sx / c, sy / c, sw / c]; }); sm[0] = [p0[0][0], p0[0][1], sm[0][2]]; sm[n0 - 1] = [p0[n0 - 1][0], p0[n0 - 1][1], sm[n0 - 1][2]];
  const out = [sm[0]]; let acc = 0; for (let i = 1; i < n0; i++) { const a = sm[i - 1], b = sm[i], d = Math.hypot(b[0] - a[0], b[1] - a[1]); acc += d; if (acc >= 12) { out.push(b); acc = 0; } } out.push(sm[n0 - 1]);
  const ys = out.map((q) => rawY(q[0], q[1])); const k5 = Math.min(5, ys.length >> 1); const hs = ys.slice(0, k5).reduce((a, b) => a + b, 0), he = ys.slice(-k5).reduce((a, b) => a + b, 0);
  if (hs < he) { out.reverse(); ys.reverse(); }
  const ysm = ys.map((_, i) => { let s = 0, c = 0; for (let k = -24; k <= 24; k++) { const j = Math.min(ys.length - 1, Math.max(0, i + k)); s += ys[j]; c++; } return s / c; });
  let s = ysm[0]; const prof = ysm.map((y) => { s = Math.min(s, y); return s; });
  const m = out.length, path = out.map((q, i) => { const spring = .5 + .5 * Math.min(1, i / 8), hw = RV_HW(q[2]) * spring * (.94 + .12 * fbm(q[0] / 260 + 3, q[1] / 260, 2)); return { x: q[0], z: q[1], y: prof[i], hw }; }); { const src = path.map((q) => [q.x, q.z]), L = path.length; path.forEach((q, i) => { const n = Math.min(16, Math.ceil(q.hw / 22)); if (n < 2 || i === 0 || i === L - 1) return; let sx = 0, sz = 0, c = 0; for (let k = -n; k <= n; k++) { const j = Math.min(L - 1, Math.max(0, i + k)); sx += src[j][0]; sz += src[j][1]; c++; } q.x = sx / c; q.z = sz / c; }); } path.merge = null; RIVERS.push(path);
});
const clearCastles = (path) => { const L = path.length, land = sites.filter((t) => !t.junction && t.crossing_kind !== 'river' && t.crossing_kind !== 'pass' && t.pl);
  for (let it = 0; it < 6; it++) { const sh = path.map((q, i) => { let ax = 0, az = 0; if (i === 0 || i === L - 1) return [0, 0]; for (const t of land) { const dx = q.x - t.x, dz = q.z - t.y, d = Math.hypot(dx, dz) || 1, D = q.hw * 1.4 + t.pl + 70; if (d < D) { ax += dx / d * (D - d); az += dz / d * (D - d); } } return [ax, az]; });
    if (!sh.some(([u, v]) => u || v)) break;
    path.forEach((q, i) => { let sx = 0, sz = 0, c = 0; for (let k = -8; k <= 8; k++) { const j = Math.min(L - 1, Math.max(0, i + k)); sx += sh[j][0]; sz += sh[j][1]; c++; } q.x += sx / c * 1.6; q.z += sz / c * 1.6; }); } };
RIVERS.forEach((path, i) => { const e = path[path.length - 1]; if (H(e.x, e.z) < SEA || e.y < 6) return; let best = 1e9, bj = -1, bk = -1; RIVERS.forEach((o, j) => { if (j === i) return; o.forEach((q, k) => { const d = Math.hypot(q.x - e.x, q.z - e.z); if (d < best) { best = d; bj = j; bk = k; } }); }); if (best < 260 && !(RIVERS[bj].merge && RIVERS[bj].merge.j === i)) { path.merge = { j: bj, k: bk }; const P = RIVERS[bj][bk]; path.push({ x: P.x, z: P.z, y: P.y, hw: P.hw * .95 }); for (let m = path.length - 2; m >= 0; m--) path[m].y = Math.max(path[m].y, path[m + 1].y); }
  else { let x = e.x, z = e.z, y = e.y, steps = 0, reached = false; const hw0 = e.hw; while (steps++ < 160) { let bd = 1e9, bx = 0, bz = 0; for (let a = 0; a < 16; a++) { const an = a / 16 * 6.2832, nx = x + Math.cos(an) * 36, nz = z + Math.sin(an) * 36, hh = H(nx, nz) + (rawY(nx, nz) * 1e-5); if (hh < bd) { bd = hh; bx = nx; bz = nz; } } if (bd >= H(x, z) - 1e-5) break; x = bx; z = bz; y = Math.max(-1.5, Math.min(y, rawY(x, z) - 1)); path.push({ x, z, y: y * .96, hw: hw0 * (1 + Math.min(.6, steps / 100)) }); if (H(x, z) < SEA) { reached = true; break; } } if (!reached && path.length > 2) { const a0 = path[path.length - 3], b0 = path[path.length - 1], l = Math.hypot(b0.x - a0.x, b0.z - a0.z) || 1, ux = (b0.x - a0.x) / l, uz = (b0.z - a0.z) / l; x = b0.x; z = b0.z; for (let k = 0; k < 90 && H(x, z) >= SEA; k++) { x += ux * 24; z += uz * 24; y = Math.max(-1.5, y - .6); path.push({ x, z, y, hw: hw0 * 1.4 }); } } path.extended = true; } });
RIVERS.forEach(clearCastles);
const RVPI = [];
RIVERS.forEach((path, pi) => path.forEach((q, qi) => { const k = RVX.length; RVPI.push([pi, qi]); RVX.push(q.x); RVZ.push(q.z); RVB.push(q.y - RV_DEPTH(q.hw)); RVW.push(q.hw); const key = gk(Math.floor(q.x / 200), Math.floor(q.z / 200)); (rgrid.get(key) || rgrid.set(key, []).get(key)).push(k); }));
const segD = (x, z, k, k2) => { const ax = RVX[k], az = RVZ[k], bx = RVX[k2], bz = RVZ[k2], dx = bx - ax, dz = bz - az, l2 = dx * dx + dz * dz || 1, t = Math.min(1, Math.max(0, ((x - ax) * dx + (z - az) * dz) / l2)); return Math.hypot(x - (ax + dx * t), z - (az + dz * t)); };
const rvq = (x, z) => { let best = 1e9, bi = -1; const cx = Math.floor(x / 200), cz = Math.floor(z / 200); for (let a = -1; a <= 1; a++) for (let b = -1; b <= 1; b++) { const l = rgrid.get(gk(cx + a, cz + b)); if (!l) continue; for (const k of l) { const d = Math.hypot(x - RVX[k], z - RVZ[k]); if (d < best) { best = d; bi = k; } } } if (bi >= 0) { const [pi, qi] = RVPI[bi], len = RIVERS[pi].length; if (qi > 0) best = Math.min(best, segD(x, z, bi, bi - 1)); if (qi < len - 1) best = Math.min(best, segD(x, z, bi, bi + 1)); } return [best, bi]; };
const LAKES = [];
const nearLake = (x, z, k = 1.25) => LAKES.some((l) => Math.hypot(x - l.x, z - l.z) < l.r * k);
const lakeR = (l, th) => l.r * (1.08 + .16 * Math.sin(3 * th + l.s) + .09 * Math.sin(5 * th + 2 * l.s));
const mkBioTex = (fill) => { const d = new Uint8Array(BG * BG * 4); for (let gy = 0; gy < BG; gy++) for (let gx = 0; gx < BG; gx++) { const i = gy * BG + gx, x = (gx + .5) / BG * W, z = (gy + .5) / BG * W; fill(d, i * 4, i, x, z); } const tx = new THREE.DataTexture(d, BG, BG, THREE.RGBAFormat); tx.magFilter = tx.minFilter = THREE.LinearFilter; tx.needsUpdate = true; return tx; };
const bioTex = mkBioTex((d, o, i) => { d[o] = BIO[i * BS] * 255; d[o + 1] = BIO[i * BS + 1] * 255; d[o + 2] = BIO[i * BS + 2] * 255; d[o + 3] = BIO[i * BS + 3] * 255; });
const bio2Tex = mkBioTex((d, o, i, x, z) => { const [dr, kr] = rvq(x, z), rv = kr >= 0 ? 1 - ssf(RVW[kr] * 1.4, RVW[kr] * 1.4 + 520, dr) : 0, lk = LAKES.reduce((m, l) => Math.max(m, 1 - ssf(l.r * .9, l.r * 1.9, Math.hypot(x - l.x, z - l.z))), 0); d[o] = rv * 255; d[o + 1] = BIO[i * BS + 4] * 255; d[o + 2] = lk * 255; d[o + 3] = 255; });
const PLATS = [], RIVCAST = [];
{ sites.forEach((s, i) => { if (s.crossing_kind !== 'river') return; const [d, k] = rvq(s.x, s.y); if (k < 0 || d > 1200) return; const [pi, qi0] = RVPI[k], path = RIVERS[pi]; if (path.length < 6) return; const qi = Math.min(path.length - 3, Math.max(2, qi0)), q = path[qi];
    const a = path[qi - 2], b = path[qi + 2]; let tx = b.x - a.x, tz = b.z - a.z; const l = Math.hypot(tx, tz) || 1; tx /= l; tz /= l; const nx = -tz, nz = tx, off = q.hw * 1.1 + 84, B1 = { x: q.x + nx * off, z: q.z + nz * off }, B2 = { x: q.x - nx * off, z: q.z - nz * off }, H0 = Math.max(q.y + 16, (rawY(B1.x, B1.z) + rawY(B2.x, B2.z)) / 2);
    s.x = q.x; s.y = q.z; s.gy = H0; s.v = 'riverTwins'; s.tier = Math.max(2, s.tier || 1); s.moat = null; s.noflat = true; s.pl = 0; s.riv = { nx, nz, off, hw: q.hw, depth: H0 - (q.y - RV_DEPTH(q.hw)) + 10 };
    PLATS.push({ x: B1.x, y: B1.z, gy: H0, pl: 88, moat: null }, { x: B2.x, y: B2.z, gy: H0, pl: 88, moat: null }); RIVCAST.push({ x: q.x, z: q.z, i }); }); }
const FLATS = sites.concat(PLATS);
const PASS = (art.passes || []).map(([x, z]) => ({ x, z, y: rawY(x, z) })), pgrid = new Map();
PASS.forEach((p, i) => { const key = gk(Math.floor(p.x / 200), Math.floor(p.z / 200)); (pgrid.get(key) || pgrid.set(key, []).get(key)).push(i); });
const hAt = (x, z) => { let y = rawY(x, z); { const cx0 = Math.floor(x / 200), cz0 = Math.floor(z / 200); for (let a = -1; a <= 1; a++) for (let b = -1; b <= 1; b++) { const l = pgrid.get(gk(cx0 + a, cz0 + b)); if (!l) continue; for (const i of l) { const p = PASS[i], d = Math.hypot(x - p.x, z - p.z); if (d < 150) { const w = 1 - ssf(35, 150, d), tg = p.y * .8 - 6; if (tg < y) y += (tg - y) * w; } } } } const rq = rvq(x, z); { const [d, k] = rq; if (k >= 0) { const hw = RVW[k], reach = hw * 3.6; if (d < reach) { const surf = RVB[k] + RV_DEPTH(hw); if (d < hw) { const bowl = surf - RV_DEPTH(hw) * (1 - (d / hw) * (d / hw)); if (y > bowl) y = bowl; } else { const t = ssf(hw, reach, d), ramp = surf + 1.4 + (d - hw) * .2, cut = Math.min(y, ramp); y = cut + (y - cut) * t; } if (d < hw * 1.9) { const floorY = surf + 1.4 * (1 - ssf(hw, hw * 1.9, d)); if (y < floorY) y = floorY; } } } } for (const l of LAKES) { const dx = x - l.x, dz = z - l.z, d0 = Math.hypot(dx, dz); if (d0 > l.r * 2) continue; const tt = d0 / lakeR(l, Math.atan2(dz, dx)); if (tt < 1.6) { const wc = 1 - ssf(.7, 1.5, tt), bed = l.y - 10 * (1 - ssf(0, .9, tt)); if (bed < y) y += (bed - y) * wc; const berm = l.y + 2.4, wb = ssf(.95, 1.08, tt) * (1 - ssf(1.15, 1.6, tt)); if (y < berm) y += (berm - y) * wb; } }
  for (const s of FLATS) { if (s.noflat) continue; const ddx = x - s.x, ddz = z - s.y, lim2 = (s.pl + 170) * (s.pl + 170); if (ddx * ddx + ddz * ddz >= lim2) continue; const d = Math.hypot(ddx, ddz); if (d < s.pl + 170) { let w = Math.pow(Math.min(1, Math.max(0, (s.pl + 170 - d) / 170)), 1.5); { const [dr, kr] = rq; if (kr >= 0) w *= ssf(RVW[kr] * 1.1, RVW[kr] * 1.7, dr); } y = y + (s.gy - y) * w; if (s.moat) { let sd = d - (s.moat.r0 || 0); if (s.moat.pl) { sd = -1e9; for (const p of s.moat.pl) { const t = ddx * p[0] + ddz * p[1] - p[2]; if (t > sd) sd = t; } } if (sd > -4 && sd < s.moat.wd + 4) { const c = sd - s.moat.wd / 2, wm = 1 - ssf(s.moat.wd * .42, s.moat.wd * .5 + 7, Math.abs(c)); y += (s.gy - 7 - y) * wm; } } } } return y; };
const LO = !!spec.lowQuality;
const marks = [['start', performance.now()]];
const stage = async (m) => { const el = $('load'); if (el) el.textContent = m; if (spec.onProgress) spec.onProgress(m); marks.push([m, performance.now()]); await new Promise((r) => requestAnimationFrame(() => setTimeout(r))); };

const wrap = $('wrap');
const renderer = new THREE.WebGLRenderer({ antialias: false, alpha: false, powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(devicePixelRatio, LO ? 1 : 1.25));
renderer.setSize(host.clientWidth, host.clientHeight);
renderer.shadowMap.enabled = true; renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = spec.exposure != null ? spec.exposure : .95;
wrap.appendChild(renderer.domElement);
const scene = new THREE.Scene();
const HORIZON = new THREE.Color(spec.horizon != null ? spec.horizon : 0xb4cfdc);
scene.fog = new THREE.FogExp2(HORIZON, 0.000068);
const cam = new THREE.PerspectiveCamera(36, host.clientWidth / host.clientHeight, 40, 120000);
const uTime = { value: 0 };

{ const hz = new THREE.Mesh(new THREE.CylinderGeometry(52000, 52000, 4200, 48, 1, true), new THREE.ShaderMaterial({ transparent: true, depthWrite: false, fog: false, side: THREE.BackSide, vertexShader: 'varying float vY; void main(){ vY = position.y; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.); }', fragmentShader: 'varying float vY; void main(){ float tt = (vY + 2100.) / 4200.; gl_FragColor = vec4(vec3(.71, .81, .86), (1. - smoothstep(0., .5, tt)) * .95); }' })); hz.position.set(W / 2, 1600, W / 2); hz.renderOrder = -2; scene.add(hz); }
const sunDir = new THREE.Vector3(); { const el = THREE.MathUtils.degToRad(spec.sun && spec.sun.el != null ? spec.sun.el : 24), az = THREE.MathUtils.degToRad(spec.sun && spec.sun.az != null ? spec.sun.az : 235); sunDir.setFromSphericalCoords(1, Math.PI / 2 - el, az); }
const sky = new Sky(); sky.scale.setScalar(80000);
{ const c = document.createElement('canvas'); c.width = 4; c.height = 512; const g = c.getContext('2d'), gr = g.createLinearGradient(0, 0, 0, 512); gr.addColorStop(0, '#2f5f98'); gr.addColorStop(.45, '#6f9cc6'); gr.addColorStop(.58, '#a9c8dc'); gr.addColorStop(.7, '#b4cfdc'); gr.addColorStop(1, '#b4cfdc'); g.fillStyle = gr; g.fillRect(0, 0, 4, 512); const bt = new THREE.CanvasTexture(c); bt.colorSpace = THREE.SRGBColorSpace; scene.background = bt; }
Object.assign(sky.material.uniforms, { turbidity: { value: 1.6 }, rayleigh: { value: 3.2 }, mieCoefficient: { value: .003 }, mieDirectionalG: { value: .82 } }); sky.material.uniforms.sunPosition.value.copy(sunDir);
const pm = new THREE.PMREMGenerator(renderer); const envScene = new THREE.Scene(); const envSky = sky.clone(); envSky.material = sky.material.clone(); envSky.material.uniforms.sunPosition.value.copy(sunDir); envScene.add(envSky);
scene.environment = pm.fromScene(envScene, 0, 1, 100000).texture;

await stage('Painting the land');
const TEX = LO ? 768 : Math.min(1152, Math.round(1024 * Math.max(1, Math.sqrt(WS)) / 16) * 16);
const cv = document.createElement('canvas'); cv.width = cv.height = TEX;
const cx = cv.getContext('2d'); const img = cx.createImageData(TEX, TEX);
const mix = (a, b, t) => [a[0]+(b[0]-a[0])*t, a[1]+(b[1]-a[1])*t, a[2]+(b[2]-a[2])*t];
const ss = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t*t*(3-2*t); };
const deep=[10,44,66], shallow=[48,128,142], foam=[190,214,205], sand=[196,178,128], dry=[142,132,74], wet=[78,118,58], forestC=[38,78,44], hillC=[128,108,72], rockC=[112,102,92], snow=[238,240,244];
for (let py = 0; py < TEX; py++) for (let px = 0; px < TEX; px++) {
  const x = (px + .5) / TEX * W, z = (py + .5) / TEX * W; const h = H(x, z); let c;
  if (h < SEA) { const k = .8 + vn(x / 90, z / 90) * .3; c = [sand[0] * k, sand[1] * k, sand[2] * k]; }
  else {
    const el = (h - SEA) / (1 - SEA), m = Mo(x, z), n = vn(x / 90, z / 90), n2 = vn(x / 22, z / 22), n3 = vn(x / 340, z / 340);
    c = mix(dry, wet, Math.min(1, m + (n3 - .5) * .5)); c = mix(c, forestC, ss(.55, .72, m) * (1 - ss(.35, .55, el)));
    c = mix(c, hillC, ss(.2, .4, el) * .85); c = mix(c, rockC, ss(.36, .55, el)); c = mix(c, snow, ss(.7, .85, el + (n - .5) * .08)); c = mix(sand, c, ss(0, .05, el));
    { const [bd, bf, bm] = biome(x, z); c = mix(c, [150, 138, 78], ss(0, .5, bd) * .6); c = mix(c, [176, 138, 84], ss(.35, .85, bd) * .85); c = mix(c, [26, 62, 32], bf * .6); c = mix(c, rockC, bm * .3); }
    const k = .8 + n * .3 + (n2 - .5) * .14; c = [c[0]*k, c[1]*k, c[2]*k];
  }
  const o = (py * TEX + px) * 4; img.data[o] = c[0]; img.data[o+1] = c[1]; img.data[o+2] = c[2]; img.data[o+3] = 255;
}
cx.putImageData(img, 0, 0);
const toPx = (v) => v / W * TEX;
sites.forEach((s) => { const g = cx.createRadialGradient(toPx(s.x), toPx(s.y), 0, toPx(s.x), toPx(s.y), toPx(s.pl + 20)); g.addColorStop(0, 'rgba(126,104,70,.7)'); g.addColorStop(.6, 'rgba(126,104,70,.42)'); g.addColorStop(1, 'rgba(126,104,70,0)'); cx.fillStyle = g; cx.fillRect(toPx(s.x - 240), toPx(s.y - 240), toPx(480), toPx(480)); });
const FIELDS = [];
sites.forEach((s, i) => { const tier = s.tier || 1; if (s.junction) return; const nF = tier >= 3 ? 9 : tier === 2 ? 6 : 3; for (let k = 0; k < nF; k++) { const a = (k / nF) * 6.28 + hash(i, k * 3 + 1) * .6, r = (tier >= 3 ? 520 : 440) + hash(i, k * 3 + 2) * (tier >= 3 ? 560 : 420), x = s.x + Math.cos(a) * r, z = s.y + Math.sin(a) * r, hh = H(x, z); if (hh < SEA + .03 || (hh - SEA) / (1 - SEA) > .36 || Mo(x, z) < .15 || biome(x, z)[0] > .3) continue; if (sites.some((o) => o !== s && Math.hypot(o.x - x, o.y - z) < 250)) continue; const wU = (tier >= 3 ? 150 : 120) + hash(i, k) * 110, dU = (tier >= 3 ? 110 : 90) + hash(k, i) * 90, w = toPx(wU), d = toPx(dU), kind = Math.floor(hash(i + 3, k) * 4), rot = a + hash(i, k) * .6; { const [dr, kr] = rvq(x, z); if (kr >= 0 && dr < RVW[kr] * 1.9 + Math.max(wU, dU) * .6) continue; } FIELDS.push([x, z, wU, dU, rot, tier >= 3 && k % 3 === 0, kind]); } });
cx.lineCap = 'round'; cx.lineJoin = 'round';
const EDG = spec.edges, ROADS = [], ROADMAP = new Map(), EMAP = new Map();
const KIND = { land: 0, river: 1, pass: 2 };
EDG.forEach((e) => EMAP.set(Math.min(e.a, e.b) + '-' + Math.max(e.a, e.b), [e.length, e.mult, KIND[e.kind] ?? 0]));
cx.lineCap = 'round'; cx.lineJoin = 'round';
EDG.forEach((e) => { const A = sites[e.a], B = sites[e.b]; const raw = e.path && e.path.length > 1 ? e.path.map(([x, z]) => ({ x, z })) : [{ x: A.x, z: A.y }, { x: B.x, z: B.y }]; raw[0] = { x: A.x, z: A.y }; raw[raw.length - 1] = { x: B.x, z: B.y };
  const pts = []; raw.forEach((q, k) => { if (!k) { pts.push(q); return; } const q0 = raw[k - 1], L = Math.hypot(q.x - q0.x, q.z - q0.z), n = Math.max(1, Math.ceil(L / 45)); for (let s = 1; s <= n; s++) pts.push({ x: q0.x + (q.x - q0.x) * s / n, z: q0.z + (q.z - q0.z) * s / n }); });
  const road = { a: e.a, b: e.b, k: KIND[e.kind] ?? 0, len: e.length, m: e.mult, pts }; ROADS.push(road); ROADMAP.set(Math.min(e.a, e.b) + '-' + Math.max(e.a, e.b), road);
  });
const ROADGRID = new Map(), RGC = 100;
ROADS.forEach((r) => r.pts.forEach((q) => { const k = Math.floor(q.x / RGC) + ',' + Math.floor(q.z / RGC); (ROADGRID.get(k) || ROADGRID.set(k, []).get(k)).push(q); }));
const roadDist = (x, z) => { const cx0 = Math.floor(x / RGC), cz0 = Math.floor(z / RGC); let d = 1e9; for (let a = -1; a <= 1; a++) for (let b = -1; b <= 1; b++) { const l = ROADGRID.get((cx0 + a) + ',' + (cz0 + b)); if (l) for (const q of l) { const e = Math.hypot(x - q.x, z - q.z); if (e < d) d = e; } } return d; };
const tex = new THREE.CanvasTexture(cv); tex.colorSpace = THREE.SRGBColorSpace; tex.anisotropy = 8;

await stage('Raising the mountains');
const NOISE_GLSL = `
float h31(vec3 p){ p = fract(p*.1031); p += dot(p, p.zyx+31.32); return fract((p.x+p.y)*p.z); }
float vn2(vec2 p){ vec2 i=floor(p), f=fract(p); f=f*f*(3.-2.*f); float a=h31(vec3(i,1.)), b=h31(vec3(i+vec2(1,0),1.)), c=h31(vec3(i+vec2(0,1),1.)), d=h31(vec3(i+vec2(1,1),1.)); return mix(mix(a,b,f.x),mix(c,d,f.x),f.y); }
float fb2(vec2 p){ float a=.5,t=0.; for(int i=0;i<4;i++){ t+=a*vn2(p); p*=2.07; a*=.5; } return t; }`;
const tmat = new THREE.MeshStandardMaterial({ map: tex, roughness: .96, metalness: 0 });
const richTerrain = (sh) => {
  sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nvarying vec3 vWPos; varying vec3 vWNor;').replace('#include <begin_vertex>', '#include <begin_vertex>\nvWPos = (modelMatrix * vec4(transformed, 1.)).xyz; vWNor = normalize(mat3(modelMatrix) * objectNormal);');
  sh.uniforms.uTime = uTime; sh.uniforms.uBio = { value: bioTex }; sh.uniforms.uBio2 = { value: bio2Tex }; sh.uniforms.uRockN = { value: rockNTex }; sh.uniforms.uW = { value: W };
  sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nvarying vec3 vWPos; varying vec3 vWNor; uniform float uTime; uniform sampler2D uBio; uniform sampler2D uBio2; uniform sampler2D uRockN; uniform float uW;\n' + NOISE_GLSL + '\nfloat gPool = 0.; float gIce = 0.; float gRockH = .5; vec3 gRockPert = vec3(0.);\n')
    .replace('#include <map_fragment>', `#include <map_fragment>
    {
      vec4 bio = texture2D(uBio, vWPos.xz / uW); float bd = bio.r, bf = bio.g, bm = bio.b;
      vec4 b2 = texture2D(uBio2, vWPos.xz / uW);
      vec3 wn = normalize(vWNor); float slope = 1. - clamp(wn.y, 0., 1.);
      float land = smoothstep(-2., 14., vWPos.y);
      float n1 = fb2(vWPos.xz*.012), n2 = fb2(vWPos.xz*.11), n3 = fb2(vWPos.xz*.9);
      float rockM = smoothstep(.44 - .12*bm, .64 - .1*bm, slope + (n1-.5)*.2 + bm*.06) * land;
      vec3 tw = pow(abs(wn), vec3(4.)); tw /= (tw.x + tw.y + tw.z);
      vec4 rx = texture2D(uRockN, vWPos.zy*.011), ry = texture2D(uRockN, vWPos.xz*.011), rz = texture2D(uRockN, vWPos.xy*.011);
      vec4 rx2 = texture2D(uRockN, vWPos.zy*.046), ry2 = texture2D(uRockN, vWPos.xz*.046), rz2 = texture2D(uRockN, vWPos.xy*.046);
      gRockH = (rx.a*tw.x + ry.a*tw.y + rz.a*tw.z)*.62 + (rx2.a*tw.x + ry2.a*tw.y + rz2.a*tw.z)*.38;
      vec3 pxa = rx.xyz*2.-1., pya = ry.xyz*2.-1., pza = rz.xyz*2.-1., pxb = rx2.xyz*2.-1., pyb = ry2.xyz*2.-1., pzb = rz2.xyz*2.-1.;
      gRockPert = vec3((pya.x+pyb.x*.6)*tw.y + (pza.x+pzb.x*.6)*tw.z, (pxa.y+pxb.y*.6)*tw.x + (pza.y+pzb.y*.6)*tw.z, (pxa.x+pxb.x*.6)*tw.x + (pya.y+pyb.y*.6)*tw.y);
      float yw = vWPos.y + (fb2(vWPos.xz*.008)-.5)*90. + (fb2(vWPos.xz*.05)-.5)*14.;
      float strata = smoothstep(.3, .7, fb2(vec2(yw*.05, n1*3.)));
      float crack = 1. - abs(2.*fb2(vec2(vWPos.x*.03 + vWPos.z*.025, yw*.11 + n1*3.)) - 1.);
      float crack2 = 1. - abs(2.*fb2(vWPos.xz*.16 + yw*.02) - 1.);
      vec3 rock = mix(mix(vec3(.31,.28,.24), vec3(.19,.16,.13), strata), vec3(.37,.29,.21), smoothstep(.55,.8,fb2(vWPos.xz*.006+3.)));
      rock *= (.42 + crack*.5 + crack2*.2 + n3*.22) * (.55 + gRockH*.95);
      rock = mix(rock, rock*vec3(.82,.9,1.05), smoothstep(.2,.7,fb2(vWPos.xz*.004)));
      float moss = smoothstep(.52, .28, slope) * smoothstep(.45, .72, fb2(vWPos.xz*.05)) * (1. - bd);
      rock = mix(rock, vec3(.17,.23,.09) * (.8 + n3*.5), moss * .6);
      rock *= .8 + .4 * smoothstep(.28, .5, slope) * n3;
      vec3 col = diffuseColor.rgb * (.72 + n2*.55) * (.88 + n3*.24);
      vec3 dune = mix(vec3(.6,.4,.2), vec3(.46,.3,.15), n2) * (.88 + n3*.22) * (1. - .1*(.5+.5*sin(vWPos.x*.045 + vWPos.z*.021 + n1*9.)));
      float sc = smoothstep(.0, .5, bd) * (1. - smoothstep(.5, .9, bd));
      col = mix(col, vec3(.55,.48,.24) * (.85 + n3*.3), sc * .55 * land);
      col = mix(col, dune, smoothstep(.35, .85, bd) * land * (1. - b2.r * .85));
      col = mix(col, vec3(.18,.36,.1) * (.8 + n3*.45), b2.r * bd * .8 * land);
      col *= 1. - bf*.14;
      rock = mix(rock, rock*vec3(1.35,.95,.7), bd);
      col = mix(col, rock, rockM);
      float swp = bio.a * land;
      col = mix(col, vec3(.13,.15,.07) * (.7 + n3*.6), swp * .85);
      gPool = smoothstep(.53, .59, fb2(vWPos.xz*.014 + 7.)) * swp;
      col = mix(col, vec3(.03,.09,.1), gPool);
      col = mix(col, vec3(.25,.21,.13) * (.8 + n3*.4), b2.b * .7 * land);
      float drift = .5 + .5*sin(vWPos.x*.018 + vWPos.z*.011 + fb2(vWPos.xz*.012)*7.);
      float cov = clamp(b2.g * smoothstep(.85, .3, slope + (n1-.5)*.35 + (gRockH-.5)*.16), 0., 1.);
      cov *= smoothstep(.1, .45, fb2(vWPos.xz*.004 + 9.) + .35 + b2.g*.3 - (gRockH-.45)*.3*rockM);
      vec3 snowC = mix(vec3(.62,.72,.84), vec3(.86,.9,.95), drift*.55 + n3*.3) * (.88 + n2*.14);
      col = mix(col, snowC, cov * land * (1. - gPool));
      gIce = smoothstep(.1, .02, slope) * b2.g * smoothstep(.62, .8, fb2(vWPos.xz*.006 + 4.)) * land;
      col = mix(col, vec3(.64,.82,.93) * (.9 + n3*.12), gIce * .55);
      float snowM = smoothstep(360. - 250.*b2.g, 440. - 250.*b2.g, vWPos.y + (n1-.5)*120.) * smoothstep(.62, .22, slope);
      col = mix(col, vec3(.8,.84,.9), snowM * land * (1. - bd));
      float beach = smoothstep(11., 2., vWPos.y) * smoothstep(-3., .5, vWPos.y); col = mix(col, vec3(.66,.58,.38) * (.85 + n3*.25), beach * .7 * (1. - rockM) * (1. - bio.a));
      float shore = smoothstep(4.5, 1., vWPos.y) * smoothstep(-4., -.5, vWPos.y);
      float fo = smoothstep(.42, .68, fb2(vWPos.xz*.085 + vec2(uTime*.035, -uTime*.025)));
      col *= 1. - .3*smoothstep(16., 0., vWPos.y)*smoothstep(-4., 1., vWPos.y);
      col = mix(col, vec3(.96,.97,.94), shore*fo*.9);
      float uw = clamp(smoothstep(0., -16., vWPos.y)*.55 + smoothstep(-10., -90., vWPos.y)*.45, 0., 1.);
      col = mix(col, vec3(.04,.24,.3), uw);
      float cl = smoothstep(.5, .78, fb2(vWPos.xz*.00055 + vec2(uTime*.004, uTime*.0025)));
      col *= 1. - .28*cl*land;
      diffuseColor.rgb = col;
    }`)
    .replace('#include <roughnessmap_fragment>', '#include <roughnessmap_fragment>\n roughnessFactor = mix(mix(roughnessFactor, .1, gPool), .16, gIce);')
    .replace('#include <normal_fragment_maps>', `#include <normal_fragment_maps>
    {
      vec2 p = vWPos.xz; float e = .6;
      float k1 = 1.0, k2 = .45;
      vec2 g1 = vec2(fb2((p+vec2(e,0.))*.06)-fb2((p-vec2(e,0.))*.06), fb2((p+vec2(0.,e))*.06)-fb2((p-vec2(0.,e))*.06));
      vec2 g2 = vec2(fb2((p+vec2(e,0.))*.4)-fb2((p-vec2(e,0.))*.4), fb2((p+vec2(0.,e))*.4)-fb2((p-vec2(0.,e))*.4));
      float rockK = smoothstep(.3, .55, 1. - clamp(normalize(vWNor).y,0.,1.));
      vec2 g3 = vec2(fb2((p+vec2(e,0.))*.16)-fb2((p-vec2(e,0.))*.16), fb2((p+vec2(0.,e))*.16)-fb2((p-vec2(0.,e))*.16));
      vec2 g = g1*(k1*(1.+rockK*1.5)) + g2*k2*.35*(1.+rockK*1.5) + g3*rockK*1.8;
      normal = normalize(normal + mat3(viewMatrix) * (vec3(-g.x, 0., -g.y) * 1.5 + gRockPert * rockK * 1.15));
    }`);
};

const mkDetTex = () => {
  const S = 256, d = new Uint8Array(S * S * 4), cfg = [[4, 11], [8, 23], [16, 37], [24, 53]];
  const val = (n, sd, x, y) => { const u = x / S * n, v = y / S * n, xi = Math.floor(u), yi = Math.floor(v), fx = u - xi, fy = v - yi, a = fx * fx * (3 - 2 * fx), b = fy * fy * (3 - 2 * fy), g = (i, j) => hash(((i % n) + n) % n * 7 + sd, ((j % n) + n) % n * 13 + sd * 3); return g(xi, yi) * (1 - a) * (1 - b) + g(xi + 1, yi) * a * (1 - b) + g(xi, yi + 1) * (1 - a) * b + g(xi + 1, yi + 1) * a * b; };
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) cfg.forEach(([n, sd], c) => { d[(y * S + x) * 4 + c] = Math.min(255, (val(n, sd, x, y) * .65 + val(n * 2, sd + 5, x, y) * .35) * 255); });
  const t = new THREE.DataTexture(d, S, S, THREE.RGBAFormat); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.magFilter = THREE.LinearFilter; t.minFilter = THREE.LinearMipmapLinearFilter; t.generateMipmaps = true; t.anisotropy = 4; t.needsUpdate = true; return t;
};
let detTex = null;
const leanTerrain = (sh) => {
  if (!detTex) detTex = mkDetTex();
  sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nvarying vec3 vWPos; varying vec3 vWNor;').replace('#include <begin_vertex>', '#include <begin_vertex>\nvWPos = (modelMatrix * vec4(transformed, 1.)).xyz; vWNor = normalize(mat3(modelMatrix) * objectNormal);');
  sh.uniforms.uBio = { value: bioTex }; sh.uniforms.uBio2 = { value: bio2Tex }; sh.uniforms.uDet = { value: detTex }; sh.uniforms.uW = { value: W };
  sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nvarying vec3 vWPos; varying vec3 vWNor; uniform sampler2D uBio; uniform sampler2D uBio2; uniform sampler2D uDet; uniform float uW;\n')
    .replace('#include <map_fragment>', `#include <map_fragment>
    {
      vec4 bio = texture2D(uBio, vWPos.xz / uW); float bd = bio.r, bf = bio.g, bm = bio.b;
      vec4 b2 = texture2D(uBio2, vWPos.xz / uW);
      vec3 wn = normalize(vWNor); float slope = 1. - clamp(wn.y, 0., 1.);
      float land = smoothstep(-2., 14., vWPos.y);
      vec4 dA = texture2D(uDet, vWPos.xz * .0011), dB = texture2D(uDet, vWPos.xz * .0075), dC = texture2D(uDet, vWPos.xz * .052);
      float n1 = dA.r, n2 = dB.g, n3 = dC.b;
      float rockM = smoothstep(.44 - .12*bm, .64 - .1*bm, slope + (n1-.5)*.2 + bm*.06) * land;
      vec3 rock = mix(vec3(.31,.28,.24), vec3(.19,.16,.13), dB.r) * (.5 + dC.g*.9 + dA.b*.3);
      rock = mix(rock, rock*vec3(1.35,.95,.7), bd);
      vec3 col = diffuseColor.rgb * (.74 + n2*.5) * (.9 + n3*.2);
      vec3 dune = mix(vec3(.6,.4,.2), vec3(.46,.3,.15), n2) * (.9 + n3*.2);
      float sc = smoothstep(.0, .5, bd) * (1. - smoothstep(.5, .9, bd));
      col = mix(col, vec3(.55,.48,.24) * (.85 + n3*.3), sc * .55 * land);
      col = mix(col, dune, smoothstep(.35, .85, bd) * land * (1. - b2.r * .85));
      col = mix(col, vec3(.18,.36,.1) * (.8 + n3*.45), b2.r * bd * .8 * land);
      col *= 1. - bf*.14;
      float canopy = bf * smoothstep(.3, .62, dC.r*.55 + dB.r*.45) * land;
      col = mix(col, vec3(.07,.2,.07) * (.7 + dC.g*.6), canopy * .7);
      col = mix(col, rock, rockM);
      float swp = bio.a * land;
      col = mix(col, vec3(.13,.15,.07) * (.7 + n3*.6), swp * .85);
      col = mix(col, vec3(.25,.21,.13) * (.8 + n3*.4), b2.b * .7 * land);
      float cov = clamp(b2.g * smoothstep(.85, .3, slope + (n1-.5)*.35), 0., 1.) * smoothstep(.1, .45, dA.g + .35 + b2.g*.3);
      col = mix(col, mix(vec3(.62,.72,.84), vec3(.86,.9,.95), .5*n2 + .3*n3), cov * land);
      float snowM = smoothstep(360. - 250.*b2.g, 440. - 250.*b2.g, vWPos.y + (n1-.5)*120.) * smoothstep(.62, .22, slope);
      col = mix(col, vec3(.8,.84,.9), snowM * land * (1. - bd));
      float beach = smoothstep(11., 2., vWPos.y) * smoothstep(-3., .5, vWPos.y); col = mix(col, vec3(.66,.58,.38) * (.85 + n3*.25), beach * .7 * (1. - rockM) * (1. - bio.a));
      col *= 1. - .3*smoothstep(16., 0., vWPos.y)*smoothstep(-4., 1., vWPos.y);
      float uw = clamp(smoothstep(0., -16., vWPos.y)*.55 + smoothstep(-10., -90., vWPos.y)*.45, 0., 1.);
      col = mix(col, vec3(.04,.24,.3), uw);
      diffuseColor.rgb = col;
    }`);
};

tmat.onBeforeCompile = RICH ? richTerrain : leanTerrain;
tmat.side = THREE.DoubleSide;
const TILE = Math.max(1024, W / 28), NT = Math.ceil(W / TILE), TS = W / NT, LODS = LO ? [48, 24, 12, 6] : [64, 32, 16, 8], tileGroup = new THREE.Group(), tiles = [], tcache = new Map();
scene.add(tileGroup);
function buildTile(tx, tz, lod) {
  const S = LODS[lod], x0 = tx * TS, z0 = tz * TS, st = TS / S, n = S + 1, P = [], U = [], Nm = [], I = [];
  for (let j = 0; j <= S; j++) for (let i = 0; i <= S; i++) { const x = x0 + i * st, z = z0 + j * st, y = hAt(x, z), e = Math.max(st, 8), hx = hAt(x + e, z) - hAt(x - e, z), hz = hAt(x, z + e) - hAt(x, z - e), l = Math.hypot(hx, 2 * e, hz); P.push(x, y, z); U.push(x / W, 1 - z / W); Nm.push(-hx / l, 2 * e / l, -hz / l); }
  for (let j = 0; j < S; j++) for (let i = 0; i < S; i++) { const a = j * n + i, b = a + 1, c = a + n, d = c + 1; I.push(a, c, b, b, c, d); }
  const edge = (idx) => { const base = P.length / 3; idx.forEach((k) => { P.push(P[k * 3], P[k * 3 + 1] - 55, P[k * 3 + 2]); U.push(U[k * 2], U[k * 2 + 1]); Nm.push(Nm[k * 3], Nm[k * 3 + 1], Nm[k * 3 + 2]); }); for (let q = 0; q < idx.length - 1; q++) { const a = idx[q], b = idx[q + 1], c = base + q, d = base + q + 1; I.push(a, b, c, b, d, c); } };
  edge(Array.from({ length: n }, (_, i) => i)); edge(Array.from({ length: n }, (_, i) => S * n + i)); edge(Array.from({ length: n }, (_, j) => j * n)); edge(Array.from({ length: n }, (_, j) => j * n + S));
  const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(P, 3)); g.setAttribute('uv', new THREE.Float32BufferAttribute(U, 2)); g.setAttribute('normal', new THREE.Float32BufferAttribute(Nm, 3)); g.setIndex(I); g.computeBoundingSphere(); return g;
}
const getTileGeo = (ti, lod) => { const key = ti * 4 + lod; let g = tcache.get(key); if (!g) { g = buildTile(ti % NT, Math.floor(ti / NT), lod); tcache.set(key, g); } return g; };
for (let ti = 0; ti < NT * NT; ti++) { const m = new THREE.Mesh(getTileGeo(ti, 3), tmat); m.receiveShadow = true; m.castShadow = false; m.userData.lod = 3; m.userData.ti = ti; tileGroup.add(m); tiles.push(m); }
{
  const pos = [], col = [], ind = [], HW = 16;
  ROADS.forEach((r) => {
    const A = sites[r.a], B = sites[r.b], keep = r.pts.filter((q) => Math.hypot(q.x - A.x, q.z - A.y) > (A.pl || 90) * .8 && Math.hypot(q.x - B.x, q.z - B.y) > (B.pl || 90) * .8);
    if (keep.length < 2) return;
    const base = pos.length / 3, rocky = r.k === 2;
    keep.forEach((q, i) => {
      const a = keep[Math.max(0, i - 1)], b = keep[Math.min(keep.length - 1, i + 1)]; let tx = b.x - a.x, tz = b.z - a.z; const l = Math.hypot(tx, tz) || 1; tx /= l; tz /= l;
      const nx = -tz, nz = tx, w = HW * (.88 + .3 * hash(i + 3, r.a * 31 + r.b)), edge = Math.min(1, i / 2, (keep.length - 1 - i) / 2);
      [[-1, 0], [-.45, .85], [0, 1], [.45, .85], [1, 0]].forEach(([sd, al]) => { const x = q.x + nx * w * sd, z = q.z + nz * w * sd; pos.push(x, hAt(x, z) + 1.2, z); const c = rocky ? [.2, .18, .16] : [.3 - Math.abs(sd) * .06, .22 - Math.abs(sd) * .05, .14 - Math.abs(sd) * .03]; col.push(c[0], c[1], c[2], al * .9 * edge); });
    });
    for (let i = 0; i < keep.length - 1; i++) { const a = base + i * 5, b = a + 5; for (let k = 0; k < 4; k++) ind.push(a + k, a + k + 1, b + k, a + k + 1, b + k + 1, b + k); }
  });
  const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); g.setAttribute('color', new THREE.Float32BufferAttribute(col, 4)); g.setIndex(ind); g.computeVertexNormals();
  const m = new THREE.Mesh(g, new THREE.MeshStandardMaterial({ vertexColors: true, transparent: true, roughness: 1, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -3, polygonOffsetUnits: -3 })); m.renderOrder = 1; m.receiveShadow = true; scene.add(m); scene.userData.roads = m;
}
{
  const TS2 = 256, atlas = document.createElement('canvas'); atlas.width = TS2 * 4; atlas.height = TS2; const ax = atlas.getContext('2d');
  const crops = [['#cdb454', '#a58f36', 1], ['#6aa543', '#4b8030', 1], ['#7d5a36', '#5a3f24', 0], ['#b0c25a', '#7f9a3c', 1]];
  crops.forEach(([c1, c2, lines], k) => {
    const tc = document.createElement('canvas'); tc.width = tc.height = TS2; const tx = tc.getContext('2d');
    tx.fillStyle = c1; tx.fillRect(0, 0, TS2, TS2);
    for (let y = 0; y < TS2; y += 10) { tx.fillStyle = c2; tx.globalAlpha = .5 + hash(k, y) * .3; tx.fillRect(0, y, TS2, lines ? 4 : 3); if (!lines) { tx.globalAlpha = .25; tx.fillStyle = '#c9a56e'; tx.fillRect(0, y + 5, TS2, 2); } }
    for (let n = 0; n < 700; n++) { tx.globalAlpha = .12 + hash(n, k) * .12; tx.fillStyle = hash(n, k + 9) > .5 ? '#fff6c8' : '#2d3f1a'; tx.fillRect(hash(n, 1) * TS2, hash(n, 2) * TS2, 3, 2); }
    tx.globalAlpha = 1; tx.strokeStyle = 'rgba(40,60,22,.6)'; tx.lineWidth = 9; tx.strokeRect(10, 10, TS2 - 20, TS2 - 20);
    tx.globalCompositeOperation = 'destination-in'; const rg = tx.createRadialGradient(TS2 / 2, TS2 / 2, TS2 * .34, TS2 / 2, TS2 / 2, TS2 * .74); rg.addColorStop(0, '#000'); rg.addColorStop(.72, '#000'); rg.addColorStop(1, 'rgba(0,0,0,0)'); tx.fillStyle = rg; tx.fillRect(0, 0, TS2, TS2);
    ax.drawImage(tc, k * TS2, 0);
  });
  const ftex = new THREE.CanvasTexture(atlas); ftex.colorSpace = THREE.SRGBColorSpace; ftex.anisotropy = 8;
  const pos = [], uv = [], ind = [], NU = 8, NV = 5;
  FIELDS.forEach(([fx, fz, fw, fd, ang, , kind], fi) => {
    const ca = Math.cos(ang), sa = Math.sin(ang), j = (u, v) => [hash(fi, u * 7 + v * 13) - .5, hash(fi + 5, u * 11 + v * 3) - .5], base = pos.length / 3;
    for (let v = 0; v <= NV; v++) for (let u = 0; u <= NU; u++) {
      const fu = u / NU - .5, fv = v / NV - .5, [jx, jz] = (u % NU && v % NV) ? [0, 0] : j(u, v), lu = (fu + jx * .06) * fw, lv = (fv + jz * .08) * fd, x = fx + lu * ca - lv * sa, z = fz + lu * sa + lv * ca;
      pos.push(x, hAt(x, z) + 1.0, z); uv.push((kind + u / NU) / 4, v / NV);
    }
    for (let v = 0; v < NV; v++) for (let u = 0; u < NU; u++) { const a = base + v * (NU + 1) + u, b = a + 1, c = a + NU + 1, d2 = c + 1; ind.push(a, c, b, b, c, d2); }
  });
  if (pos.length) {
    const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2)); g.setIndex(ind); g.computeVertexNormals();
    const m = new THREE.Mesh(g, new THREE.MeshStandardMaterial({ map: ftex, roughness: 1, transparent: true, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 })); m.renderOrder = 1; m.receiveShadow = true; scene.add(m); scene.userData.fields = m;
  }
}
const tileRiver = new Uint8Array(NT * NT); for (let k = 0; k < RVX.length; k++) if (RVW[k] >= 70) { const tx = Math.min(NT - 1, Math.max(0, Math.floor(RVX[k] / TS))), tz = Math.min(NT - 1, Math.max(0, Math.floor(RVZ[k] / TS))); tileRiver[tz * NT + tx] = 1; }
const lodFor = (ti, cp) => { const tx = ti % NT, tz = Math.floor(ti / NT), cxx = (tx + .5) * TS, czz = (tz + .5) * TS, d = Math.hypot(cxx - cp.x, czz - cp.z, cp.y * .85), l = d < 2300 ? 0 : d < 5200 ? 1 : d < 10500 ? 2 : 3; return tileRiver[ti] && l > 1 ? 1 : l; };
let tileBudget = 10; const updateTiles = (force) => { const cp = cam.position, order = tiles.map((m) => [m, lodFor(m.userData.ti, cp)]).filter(([m, l]) => m.userData.lod !== l).sort((a, b) => { const da = Math.hypot(((a[0].userData.ti % NT) + .5) * TS - cp.x, (Math.floor(a[0].userData.ti / NT) + .5) * TS - cp.z), db = Math.hypot(((b[0].userData.ti % NT) + .5) * TS - cp.x, (Math.floor(b[0].userData.ti / NT) + .5) * TS - cp.z); return da - db; }); let used = 0; for (const [m, l] of order) { if (used >= (force ? 9999 : tileBudget)) break; if (!tcache.has(m.userData.ti * 4 + l)) used++; m.geometry = getTileGeo(m.userData.ti, l); m.userData.lod = l; m.castShadow = l <= 1; } if (used) renderer.shadowMap.needsUpdate = true; };
const terrain = tiles[0];

const nsz = 512, wn = document.createElement('canvas'); wn.width = wn.height = nsz; const wnx = wn.getContext('2d'); const wni = wnx.createImageData(nsz, nsz);
const hf = new Float32Array(nsz * nsz); for (let y = 0; y < nsz; y++) for (let x = 0; x < nsz; x++) { const u = x / nsz * 8, v = y / nsz * 8; hf[y*nsz+x] = vn(u, v) * .55 + vn(u * 2.3, v * 2.3) * .3 + vn(u * 5, v * 5) * .15; }
for (let y = 0; y < nsz; y++) for (let x = 0; x < nsz; x++) { const l = hf[y*nsz+(x+nsz-1)%nsz], r = hf[y*nsz+(x+1)%nsz], u = hf[((y+nsz-1)%nsz)*nsz+x], d = hf[((y+1)%nsz)*nsz+x]; const nx = (l - r) * 3, ny = (u - d) * 3, nz = 1, len = Math.hypot(nx, ny, nz); const o = (y*nsz+x)*4; wni.data[o] = (nx / len * .5 + .5) * 255; wni.data[o+1] = (ny / len * .5 + .5) * 255; wni.data[o+2] = (nz / len * .5 + .5) * 255; wni.data[o+3] = 255; }
wnx.putImageData(wni, 0, 0); const wtex = new THREE.CanvasTexture(wn); wtex.wrapS = wtex.wrapT = THREE.RepeatWrapping;
let water;
if (RICH) {
water = new X.Water(new THREE.PlaneGeometry(W * 5, W * 5), { textureWidth: 384, textureHeight: 384, waterNormals: wtex, sunDirection: sunDir.clone(), sunColor: 0xffe6c0, waterColor: 0x167a98, distortionScale: 4.2, fog: true, alpha: .84, size: 2.4 });
water.material.fragmentShader = water.material.fragmentShader.replace('reflectionSample * 0.9 + reflectionSample * specularLight', 'reflectionSample * 0.5 + reflectionSample * specularLight * 1.3').replace('vec3 scatter = max( 0.0, dot( surfaceNormal, eyeDirection ) ) * waterColor;', 'vec3 scatter = (max( 0.0, dot( surfaceNormal, eyeDirection ) ) * 1.4 + .25) * waterColor;');
water.rotation.x = -Math.PI / 2; water.position.set(W / 2, 0, W / 2); scene.add(water);
} else {
const wn2 = wtex.clone(); wn2.wrapS = wn2.wrapT = THREE.RepeatWrapping; wn2.repeat.set(W * 5 / 900, W * 5 / 900); wn2.needsUpdate = true;
water = new THREE.Mesh(new THREE.PlaneGeometry(W * 5, W * 5), new THREE.MeshStandardMaterial({ color: 0x167a98, roughness: .2, metalness: .2, transparent: true, opacity: .86, normalMap: wn2, normalScale: new THREE.Vector2(.55, .55), envMapIntensity: 1.1, depthWrite: false }));
water.rotation.x = -Math.PI / 2; water.position.set(W / 2, 0, W / 2); water.renderOrder = 0; scene.add(water);
}
const flowTex = (() => { const c = document.createElement('canvas'); c.width = 128; c.height = 256; const g = c.getContext('2d'); const gr = g.createLinearGradient(0, 0, 128, 0); gr.addColorStop(0, 'rgba(255,255,255,.0)'); gr.addColorStop(.08, 'rgba(210,228,232,.38)'); gr.addColorStop(.18, 'rgba(40,100,130,.8)'); gr.addColorStop(.5, 'rgba(18,70,104,.95)'); gr.addColorStop(.82, 'rgba(40,100,130,.8)'); gr.addColorStop(.92, 'rgba(210,228,232,.38)'); gr.addColorStop(1, 'rgba(255,255,255,0)'); g.fillStyle = gr; g.fillRect(0, 0, 128, 256); for (let i = 0; i < 140; i++) { const x = 24 + hash(i, 1) * 80, y = hash(i, 2) * 256, l = 14 + hash(i, 3) * 40; g.strokeStyle = `rgba(255,255,255,${.1 + hash(i, 4) * .28})`; g.lineWidth = 1 + hash(i, 5) * 2; g.beginPath(); g.moveTo(x, y); g.quadraticCurveTo(x + (hash(i, 6) - .5) * 10, y + l / 2, x, y + l); g.stroke(); } const t = new THREE.CanvasTexture(c); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.colorSpace = THREE.SRGBColorSpace; return t; })();
const riverMat = new THREE.MeshStandardMaterial({ color: 0xffffff, vertexColors: true, map: flowTex, transparent: true, opacity: 1, roughness: .12, metalness: 0, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 });
const stratMat = new THREE.MeshBasicMaterial({ color: 0xffffff, vertexColors: true, transparent: true, opacity: 0, depthWrite: false, fog: false }), STRAT = [];
RIVERS.forEach((path) => {
  const build = (wmul, wmin, yoff, strat, mud) => {
    const n = path.length, pos = [], uvs = [], ind = [], cols = []; let len = 0;
    path.forEach((q, i) => { const a = path[Math.max(0, i - 3)], b = path[Math.min(n - 1, i + 3)]; let tx = b.x - a.x, tz = b.z - a.z; const l = Math.hypot(tx, tz) || 1; tx /= l; tz /= l; if (i) len += Math.hypot(q.x - path[i - 1].x, q.z - path[i - 1].z);
      const mouth = 1 - ssf(-1.5, 3.4, q.y), nx = -tz, nz = tx, hw = Math.max(q.hw * 1.05 * wmul * (1 + 1.1 * mouth), wmin), y = q.y + yoff, al = (strat ? .92 : .96) * (1 - mouth * mouth) * LAKES.reduce((m, l) => Math.min(m, ssf(l.r * .5, l.r * 1.05, Math.hypot(q.x - l.x, q.z - l.z))), 1);
      const cr = .05 + mouth * -.01, cg = .27 - mouth * .04, cb = .42, sn = biome(q.x, q.z)[4] * .65, r1 = cr + (.72 - cr) * sn, g1 = cg + (.84 - cg) * sn, b1 = cb + (.92 - cb) * sn;
      pos.push(q.x + nx * hw, y, q.z + nz * hw, q.x - nx * hw, y, q.z - nz * hw); if (mud) cols.push(.2, .17, .11, al * .55, .2, .17, .11, al * .55); else if (strat) cols.push(.12 + sn * .6, .42 + sn * .4, .62 + sn * .3, al, .12 + sn * .6, .42 + sn * .4, .62 + sn * .3, al); else cols.push(r1, g1, b1, al, r1, g1, b1, al);
      uvs.push(0, len / 130, 1, len / 130); if (i < n - 1) { const k = i * 2; ind.push(k, k + 2, k + 1, k + 1, k + 2, k + 3); } });
    const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); g.setAttribute('uv', new THREE.Float32BufferAttribute(uvs, 2)); g.setAttribute('color', new THREE.Float32BufferAttribute(cols, 4)); g.setIndex(ind); g.computeVertexNormals(); return g;
  };
  const ms0 = new THREE.Mesh(build(1.16, 0, .15, false, true), riverMat); ms0.renderOrder = 1.5; ms0.receiveShadow = true; scene.add(ms0);
  const m = new THREE.Mesh(build(1, 0, -.8, false), riverMat); m.renderOrder = 2; m.receiveShadow = true; scene.add(m);
  const m2 = new THREE.Mesh(build(2.0, 64, 1.5, true), stratMat); m2.renderOrder = 3; m2.visible = false; scene.add(m2); STRAT.push(m2);
});


const lakeN = wtex.clone(); lakeN.needsUpdate = true;
const lakeMat = new THREE.MeshStandardMaterial({ vertexColors: true, transparent: true, roughness: .05, metalness: .15, envMapIntensity: .9, normalMap: lakeN, normalScale: new THREE.Vector2(.3, .3), depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 });
LAKES.forEach((l) => { const SEG = 56, RG = 6, pos = [], uvs = [], cols = [], ind = [], frozen = biome(l.x, l.z)[4] > .45; pos.push(l.x, l.y, l.z); uvs.push(l.x / 200, l.z / 200); cols.push(...(frozen ? [.78, .88, .93, .97] : [.03, .2, .3, .96])); for (let r = 1; r <= RG; r++) for (let s = 0; s < SEG; s++) { const th = s / SEG * 6.2832, R = lakeR(l, th) * 1.12 * r / RG, x = l.x + Math.cos(th) * R, z = l.z + Math.sin(th) * R; pos.push(x, l.y, z); uvs.push(x / 200, z / 200); const al = r <= 4 ? .96 : r === 5 ? .55 : 0; { const k = r / RG; cols.push(...(frozen ? [.78, .88, .93, al] : [.03 + k * .06, .2 + k * .17, .3 + k * .15, al])); } } for (let s = 0; s < SEG; s++) ind.push(0, 1 + (s + 1) % SEG, 1 + s); for (let r = 1; r < RG; r++) for (let s = 0; s < SEG; s++) { const a0 = 1 + (r - 1) * SEG + s, a1 = 1 + (r - 1) * SEG + (s + 1) % SEG, b0 = 1 + r * SEG + s, b1 = 1 + r * SEG + (s + 1) % SEG; ind.push(a0, a1, b0, a1, b1, b0); } const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); g.setAttribute('uv', new THREE.Float32BufferAttribute(uvs, 2)); g.setAttribute('color', new THREE.Float32BufferAttribute(cols, 4)); g.setIndex(ind); g.computeVertexNormals(); const m = new THREE.Mesh(g, lakeMat); m.renderOrder = 2; m.receiveShadow = true; scene.add(m); });
const rockNTex = (() => { const S = 512, h = new Float32Array(S * S), P = 9, hp = (x, y, s) => hash((((x % P) + P) % P) * 7 + s, (((y % P) + P) % P) * 13 + s * 3), hq = (x, y) => hash((((x % 8) + 8) % 8) * 5 + 1, (((y % 8) + 8) % 8) * 11 + 2);
  const vp = (u, v) => { const x = u * 8, y = v * 8, xi = Math.floor(x), yi = Math.floor(y), xf = x - xi, yf = y - yi, a = xf * xf * (3 - 2 * xf), b = yf * yf * (3 - 2 * yf); return hq(xi, yi) * (1 - a) * (1 - b) + hq(xi + 1, yi) * a * (1 - b) + hq(xi, yi + 1) * (1 - a) * b + hq(xi + 1, yi + 1) * a * b; };
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) { const u = x / S, v = y / S, px = u * P, py = v * P, ci = Math.floor(px), cj = Math.floor(py); let f1 = 9, f2 = 9; for (let j = -1; j <= 1; j++) for (let i = -1; i <= 1; i++) { const cxx = ci + i, cyy = cj + j, fx = cxx + hp(cxx, cyy, 1), fy = cyy + hp(cxx, cyy, 2), d = Math.hypot(px - fx, py - fy); if (d < f1) { f2 = f1; f1 = d; } else if (d < f2) f2 = d; } const plate = Math.min(1, (f2 - f1) / .16); h[y * S + x] = plate * .55 + vp(u * 2 % 1, v * 2 % 1) * .25 + vp(u * 5 % 1, v * 5 % 1) * .12 + hash(x, y) * .08; }
  const d = new Uint8Array(S * S * 4); for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) { const l = h[y * S + (x + S - 1) % S], r = h[y * S + (x + 1) % S], u2 = h[((y + S - 1) % S) * S + x], dn = h[((y + 1) % S) * S + x]; const nx = (l - r) * 4.5, ny = (u2 - dn) * 4.5, ln = Math.hypot(nx, ny, 1), o = (y * S + x) * 4; d[o] = (nx / ln * .5 + .5) * 255; d[o + 1] = (ny / ln * .5 + .5) * 255; d[o + 2] = (1 / ln * .5 + .5) * 255; d[o + 3] = Math.min(255, Math.max(0, h[y * S + x]) * 255); }
  const tx = new THREE.DataTexture(d, S, S, THREE.RGBAFormat); tx.wrapS = tx.wrapT = THREE.RepeatWrapping; tx.magFilter = THREE.LinearFilter; tx.minFilter = THREE.LinearMipmapLinearFilter; tx.generateMipmaps = true; tx.anisotropy = 4; tx.needsUpdate = true; return tx; })();
const sun = new THREE.DirectionalLight(0xffd9a6, 3.4); sun.castShadow = true;
sun.shadow.mapSize.set(LO ? 2048 : 4096, LO ? 2048 : 4096); renderer.shadowMap.autoUpdate = false; const SC = 3000; Object.assign(sun.shadow.camera, { left: -SC, right: SC, top: SC, bottom: -SC, near: 100, far: 12000 }); sun.shadow.bias = -0.0005; sun.shadow.normalBias = 3.5; sun.shadow.radius = 3;
scene.add(sun, sun.target);
scene.add(new THREE.HemisphereLight(0xb7cdee, 0x5d4d32, .55));

await stage('Planting forests');
const rnd = (() => { let s = 12345; return () => { s = (s + 0x6d2b79f5) | 0; let t = Math.imul(s ^ (s >>> 15), 1 | s); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; })();
const windify = (mat) => { mat.onBeforeCompile = (sh) => { sh.uniforms.uTime = uTime; sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nuniform float uTime;').replace('#include <begin_vertex>', `#include <begin_vertex>
  #ifdef USE_INSTANCING
    float ph = instanceMatrix[3].x * .013 + instanceMatrix[3].z * .009;
  #else
    float ph = 0.;
  #endif
  float sway = pow(max(position.y, 0.) / 46., 1.6);
  transformed.x += sin(uTime * 1.5 + ph) * sway * 2.4; transformed.z += cos(uTime * 1.2 + ph * 1.3) * sway * 1.6;`); }; return mat; };
function paint(geom, fn) { const p = geom.attributes.position, c = new Float32Array(p.count * 3); for (let i = 0; i < p.count; i++) { const col = fn(p.getX(i), p.getY(i), p.getZ(i)); c[i*3] = col[0]; c[i*3+1] = col[1]; c[i*3+2] = col[2]; } geom.setAttribute('color', new THREE.BufferAttribute(c, 3)); return geom; }
const jitter = (geom, a, seed) => { const p = geom.attributes.position; for (let i = 0; i < p.count; i++) { const x = p.getX(i), y = p.getY(i), z = p.getZ(i); const n = (hash(Math.round(x * 7) + seed, Math.round(z * 7) + Math.round(y * 5)) - .5) * a; p.setXYZ(i, x + n, y + n * .6, z + n); } geom.computeVertexNormals(); return geom; };
const clamp01 = (x) => Math.min(1, Math.max(0, x));
const TD = 0;
function spruce() {
  const parts = [], tr = new THREE.CylinderGeometry(1.4, 2.2, 14, 6); tr.translate(0, 7, 0); parts.push(paint(tr, () => [.2, .13, .08]));
  for (let i = 0; i < 6; i++) { const r = 13 - i * 1.9, h = 15 - i * .9, c = new THREE.ConeGeometry(r, h, 11, 1, true); c.translate(0, 9 + i * 7.6 + h / 2, 0); jitter(c, 2.6, i * 13); parts.push(paint(c, (x, y) => { const tt = clamp01((y - 9) / 52); return [.05 + tt * .1, .14 + tt * .16, .07 + tt * .06]; })); }
  return mergeGeometries(parts);
}
function fir() {
  const parts = [], tr = new THREE.CylinderGeometry(1.2, 2, 12, 6); tr.translate(0, 6, 0); parts.push(paint(tr, () => [.2, .13, .08]));
  for (let i = 0; i < 9; i++) { const r = 10 - i * 1.0, h = 14 - i * .6, c = new THREE.ConeGeometry(r, h, 10, 1, true); c.translate(0, 8 + i * 7.4 + h / 2, 0); jitter(c, 2.0, i * 7 + 3); parts.push(paint(c, (x, y) => { const tt = clamp01((y - 8) / 74); return [.04 + tt * .08, .12 + tt * .15, .08 + tt * .07]; })); }
  return mergeGeometries(parts);
}
function pine() {
  const parts = [], tr = new THREE.CylinderGeometry(1.3, 2.4, 38, 6); tr.translate(0, 19, 0); parts.push(paint(tr, () => [.3, .18, .1]));
  [[0, 40, 0, 15], [-6, 47, 4, 11], [7, 50, -3, 10]].forEach(([x, y, z, r], i) => { const b = new THREE.IcosahedronGeometry(r, TD); b.scale(1, .42, 1); b.translate(x, y, z); jitter(b, r * .3, i * 9 + 1); parts.push(paint(b, (px, py) => { const tt = clamp01((py - (y - r * .4)) / (r * .8)); return [.07 + tt * .1, .18 + tt * .16, .07 + tt * .05]; })); });
  return mergeGeometries(parts);
}
function broadleaf() {
  const parts = [], tr = new THREE.CylinderGeometry(1.6, 2.8, 22, 7); tr.translate(0, 11, 0); parts.push(paint(tr, () => [.22, .16, .1]));
  [[5, 20, 2, 18], [-5, 22, -2, 18]].forEach(([x, y, z, l], i) => { const br = new THREE.CylinderGeometry(.9, 1.4, l, 5); br.rotateZ(i ? .6 : -.6); br.translate(x, y, z); parts.push(paint(br, () => [.21, .15, .09])); });
  const lobes = [[0, 34, 0, 15], [-14, 28, 5, 11.5], [14, 29, -4, 12], [4, 27, 14, 11], [-4, 29, -14, 11.5], [9, 40, 6, 9.5], [-9, 38, -5, 9.5], [0, 22, 0, 12]];
  lobes.forEach(([x, y, z, r], i) => { const b = new THREE.IcosahedronGeometry(r, TD); b.scale(1, .78, 1); b.translate(x, y, z); jitter(b, r * .34, i * 5); parts.push(paint(b, (px, py) => { const tt = clamp01((py - (y - r * .8)) / (1.6 * r)); const edge = hash(Math.round(px), Math.round(py)) * .04; return [.09 + tt * .16 + edge, .2 + tt * .22 + edge, .05 + tt * .06]; })); });
  return mergeGeometries(parts);
}
function birch() {
  const parts = [], tr = new THREE.CylinderGeometry(.9, 1.6, 28, 6); tr.translate(0, 14, 0); parts.push(paint(tr, (x, y) => (hash(Math.round(y * 2), 3) > .8 ? [.2, .2, .18] : [1.5, 1.45, 1.35])));
  [[0, 34, 0, 9], [-6, 28, 3, 7], [6, 30, -3, 7.5], [1, 42, 2, 6.5], [-3, 24, -5, 6]].forEach(([x, y, z, r], i) => { const b = new THREE.IcosahedronGeometry(r, TD); b.scale(1, 1.1, 1); b.translate(x, y, z); jitter(b, r * .3, i * 4 + 2); parts.push(paint(b, (px, py) => { const tt = clamp01((py - (y - r)) / (2 * r)); return [.2 + tt * .2, .36 + tt * .22, .1 + tt * .06]; })); });
  return mergeGeometries(parts);
}
function deadTree() {
  const parts = [], tr = new THREE.CylinderGeometry(1.3, 2.6, 34, 6); tr.translate(0, 17, 0); parts.push(paint(tr, () => [.26, .22, .18]));
  [[.9, 0], [-.8, 1.6], [.7, 3.2], [-.6, 4.7], [1.0, 5.6]].forEach(([r, a], i) => { const br = new THREE.CylinderGeometry(.5, 1.1, 15 - i, 5); br.translate(0, (15 - i) / 2, 0); br.rotateZ(r); br.rotateY(a); br.translate(0, 16 + i * 4.5, 0); parts.push(paint(br, () => [.24, .2, .16])); });
  return mergeGeometries(parts);
}
function willow() {
  const parts = [], tr = new THREE.CylinderGeometry(1.8, 3, 24, 7); tr.translate(0, 12, 0); parts.push(paint(tr, () => [.2, .16, .1]));
  [[0, 34, 0, 18], [-12, 30, 5, 12], [12, 31, -4, 12]].forEach(([x, y, z, r], i) => { const b = new THREE.IcosahedronGeometry(r, TD); b.scale(1, .55, 1); b.translate(x, y, z); jitter(b, r * .25, i * 3 + 1); parts.push(paint(b, (px, py) => [.14 + (py - y) * .01, .26 + (py - y) * .012, .08])); });
  for (let i = 0; i < 10; i++) { const a = i / 10 * 6.2832, c = new THREE.ConeGeometry(2.6, 24, 5); c.rotateX(Math.PI); c.translate(Math.cos(a) * 15, 20, Math.sin(a) * 15); parts.push(paint(c, (px, py) => [.16, .3 + (py - 8) * .004, .1])); }
  return mergeGeometries(parts);
}
function acacia() {
  const parts = [], tr = new THREE.CylinderGeometry(1.5, 2.6, 26, 6); tr.translate(0, 13, 0); parts.push(paint(tr, () => [.3, .22, .14]));
  [[7, 22, 3, .9], [-8, 20, -3, -.9]].forEach(([x, y, z, r]) => { const br = new THREE.CylinderGeometry(.9, 1.3, 16, 5); br.rotateZ(r); br.translate(x * .6, y, z * .6); parts.push(paint(br, () => [.28, .2, .12])); });
  [[0, 34, 0, 20], [-14, 31, 6, 13], [14, 32, -5, 14]].forEach(([x, y, z, r], i) => { const b = new THREE.IcosahedronGeometry(r, TD); b.scale(1, .3, 1); b.translate(x, y, z); jitter(b, r * .22, i * 3 + 7); parts.push(paint(b, (px, py) => { const tt = clamp01((py - (y - r * .3)) / (r * .6)); return [.2 + tt * .12, .3 + tt * .14, .09]; })); });
  return mergeGeometries(parts);
}
function cactus() {
  const parts = [], b = new THREE.CylinderGeometry(3.2, 3.8, 26, 9); b.translate(0, 13, 0); parts.push(paint(b, (x, y) => [.1 + y * .002, .3, .14]));
  [[1, 15, 11], [-1, 19, 9]].forEach(([sx, y, h]) => { const h1 = new THREE.CylinderGeometry(2.1, 2.1, 9, 7); h1.rotateZ(Math.PI / 2); h1.translate(sx * 6, y, 0); const v1 = new THREE.CylinderGeometry(2.1, 2.3, h, 7); v1.translate(sx * 10.5, y + h / 2, 0); parts.push(paint(h1, () => [.1, .3, .14]), paint(v1, () => [.12, .33, .15])); });
  return mergeGeometries(parts);
}
function palm() {
  const parts = [], tr = new THREE.CylinderGeometry(1.3, 2.4, 44, 7); tr.translate(0, 22, 0); parts.push(paint(tr, (x, y) => (Math.floor(y / 4) % 2 ? [.34, .24, .14] : [.28, .2, .12])));
  for (let i = 0; i < 8; i++) { const f = new THREE.ConeGeometry(2.6, 28, 4); f.translate(0, 14, 0); f.scale(1, 1, .35); f.rotateZ(1.25 + (i % 2) * .25); f.rotateY(i / 8 * 6.2832); f.translate(0, 43, 0); parts.push(paint(f, (x, y) => [.1 + (y - 40) * .004, .3 + (y - 40) * .004, .1])); }
  return mergeGeometries(parts);
}
function poplar() {
  const parts = [], tr = new THREE.CylinderGeometry(1.2, 2, 14, 6); tr.translate(0, 7, 0); parts.push(paint(tr, () => [.28, .2, .12]));
  [[0, 22, 0, 8, 1.7], [0, 38, 0, 7.5, 1.9], [0, 54, 0, 6, 1.8]].forEach(([x, y, z, r, sy], i) => { const b = new THREE.IcosahedronGeometry(r, TD); b.scale(.8, sy, .8); b.translate(x, y, z); jitter(b, r * .3, i * 6 + 4); parts.push(paint(b, (px, py) => { const tt = clamp01((py - (y - r * sy)) / (2 * r * sy)); return [.16 + tt * .2, .3 + tt * .22, .08 + tt * .05]; })); });
  return mergeGeometries(parts);
}
const treeMat = windify(new THREE.MeshStandardMaterial({ vertexColors: true, roughness: .92, side: THREE.DoubleSide }));
const TK = .86, CSZ = Math.min(W / 8, 2800), FARSTRIDE = RICH ? Math.max(3, Math.round(W / 3700)) : 1; const CHUNKS = []; const snowCol = new THREE.Color(2.3, 2.5, 2.8);
function mkChunked(geom, mat, arr, place, grid = 8, shadows = RICH, far = false) {
  const cs = grid === 8 ? CSZ : W / grid, buckets = new Map(); arr.forEach((a) => { const k = Math.floor(a[0] / cs) + ',' + Math.floor(a[2] / cs); (buckets.get(k) || buckets.set(k, []).get(k)).push(a); });
  buckets.forEach((list, key) => { const im = new THREE.InstancedMesh(geom, mat, list.length); im.userData.tree = grid === 8; im.userData.far = far; im.castShadow = shadows; im.receiveShadow = true; list.forEach((a, i) => place(im, a, i)); im.instanceMatrix.needsUpdate = true; if (im.instanceColor) im.instanceColor.needsUpdate = true; im.computeBoundingSphere(); scene.add(im); CHUNKS.push(im); });
}
const BCELL = 64, BN = Math.ceil(W / BCELL) + 1, BLK = new Uint8Array(BN * BN);
const stamp = (x, z, r, bit) => { const r2 = (r + BCELL * .55) ** 2; for (let gz = Math.max(0, Math.floor((z - r) / BCELL)); gz <= Math.min(BN - 1, Math.floor((z + r) / BCELL)); gz++) for (let gx = Math.max(0, Math.floor((x - r) / BCELL)); gx <= Math.min(BN - 1, Math.floor((x + r) / BCELL)); gx++) { const dx = (gx + .5) * BCELL - x, dz = (gz + .5) * BCELL - z; if (dx * dx + dz * dz <= r2) BLK[gz * BN + gx] |= bit; } };
const blockedAt = (x, z, mask) => (BLK[Math.min(BN - 1, Math.max(0, Math.floor(z / BCELL))) * BN + Math.min(BN - 1, Math.max(0, Math.floor(x / BCELL)))] & mask) !== 0;
sites.forEach((s) => { stamp(s.x, s.y, s.riv ? 210 : 210 * CF, 1); stamp(s.x, s.y, 175, 32); stamp(s.x, s.y, 130, 64); });
ROADS.forEach((r) => r.pts.forEach((q) => stamp(q.x, q.z, 56, 2)));
for (let k = 0; k < RVX.length; k++) { stamp(RVX[k], RVZ[k], Math.max(40, RVW[k] * 1.5), 4); stamp(RVX[k], RVZ[k], Math.max(60, RVW[k] * 4.6), 128); }
LAKES.forEach((l) => stamp(l.x, l.z, l.r * 1.3, 8));
FIELDS.forEach(([fx, fz, fw, fd]) => stamp(fx, fz, Math.hypot(fw, fd) * .55, 16));
const SP = { spruce: [], fir: [], pine: [], oak: [], birch: [], poplar: [], cactus: [], palm: [], acacia: [], dead: [], willow: [] }, STEP = LO ? (RICH ? 64 : 80) : (RICH ? 54 : 62);
for (let z = 20; z < W; z += STEP) for (let x = 20; x < W; x += STEP) {
  const px = x + (rnd() - .5) * STEP, pz = z + (rnd() - .5) * STEP; if (blockedAt(px, pz, 31)) continue; const h = H(px, pz); if (h < SEA + .018) continue;
  const el = (h - SEA) / (1 - SEA), m = Mo(px, pz); if (el > .62) continue;
  const [bd, bf, bm, bsw, bsn] = biome(px, pz);
  const [dr, kr] = blockedAt(px, pz, 128) ? rvq(px, pz) : [1e9, -1];
  if (bsw > .3) { if (rnd() < .3 + bsw * .15) SP[rnd() < .5 ? 'dead' : 'willow'].push([px, hAt(px, pz), pz, .7 + rnd() * .7, rnd()]); continue; }
  if (bd > .12 && bd <= .45 && rnd() < .05) { SP.acacia.push([px, hAt(px, pz), pz, .7 + rnd() * .8, rnd()]); continue; }
  if (bd > .45) { const oasis = kr >= 0 && dr < RVW[kr] * 4.5; if (rnd() < (oasis ? .5 : .045 * (bd - .4)) ) SP[oasis ? 'palm' : 'cactus'].push([px, hAt(px, pz), pz, .7 + rnd() * .7, rnd()]); continue; }
  if (m + bf * .3 < .38) continue;
  const cl = fbm(px / 400, pz / 400); if (rnd() > Math.min(1, (m + bf * .3 - .3) * 1.5) * (.35 + cl * 1.1) * (1 + bf * 1.3) * (1 - bm * .55)) continue;
  const r = rnd(), nearRiver = kr >= 0 && dr < RVW[kr] * 4; let sp;
  if (nearRiver && r < .55) sp = r < .3 ? 'birch' : 'poplar';
  else if (bm > .4) sp = r < .7 ? 'fir' : 'spruce';
  else if (el > .32) sp = r < .6 ? 'fir' : 'spruce';
  else if (m < .52) sp = r < .5 ? 'pine' : r < .8 ? 'spruce' : 'oak';
  else sp = r < .44 ? 'oak' : r < .6 ? 'birch' : r < .7 ? 'poplar' : r < .87 ? 'spruce' : 'fir';
  if (bsn > .4 && sp !== 'cactus' && sp !== 'palm') sp = r < .55 ? 'spruce' : r < .88 ? 'fir' : 'pine';
  SP[sp].push([px, hAt(px, pz), pz, .6 + rnd() * .9, rnd()]);
}
marks.push(['  trees placed', performance.now()]);
const farCone = (() => { const g = new THREE.ConeGeometry(11, 54, 6); g.translate(0, 27, 0); return paint(g, (x, y) => [.05 + y * .0012, .16 + y * .0018, .08]); })(), farBlob = (() => { const g = new THREE.IcosahedronGeometry(15, 0); g.scale(1, .85, 1); g.translate(0, 32, 0); return paint(g, (x, y) => [.12 + y * .002, .26 + y * .003, .08]); })(), farTrunk = null;
const FARCONE = new Set(['spruce', 'fir', 'pine']);
const mkFar = (geom, arr, tint) => { const d = new THREE.Object3D(), col = new THREE.Color(); mkChunked(geom, treeMat, arr.filter((_, i) => i % FARSTRIDE === 0), (im, a, i) => { const fk = RICH ? 1.5 * Math.sqrt(FARSTRIDE / 3) : 2.05; d.position.set(a[0], a[1] - 1, a[2]); d.rotation.y = a[4] * 6.28; d.scale.set(a[3] * fk * TK, a[3] * fk * TK * (.85 + a[4] * .5), a[3] * fk * TK); d.updateMatrix(); im.setMatrixAt(i, d.matrix); const k = (tint[2] ?? .34) + a[4] * .2; col.setRGB(k * (.9 + hash(i, 1) * .25), k * (.95 + hash(i, 5) * .1), k * (.75 + hash(i, 2) * .25)); const sn = biome(a[0], a[2])[4]; if (sn > .3) col.lerp(snowCol, Math.min(1, sn * .85)); im.setColorAt(i, col); }, 8, false, true); };
const mkTrees = (g, arr, tint) => { const d = new THREE.Object3D(), col = new THREE.Color(); mkChunked(g, treeMat, arr, (im, a, i) => { d.position.set(a[0], a[1] - 1.5, a[2]); d.rotation.y = a[4] * 6.28; d.scale.set(a[3] * TK, a[3] * TK * (.85 + a[4] * .5), a[3] * TK); d.updateMatrix(); im.setMatrixAt(i, d.matrix); const k = (tint[2] ?? .34) + a[4] * .22, au = tint[1] > 0 && hash(Math.round(a[0]), Math.round(a[2])) < .14 ? 1 : 0; col.setRGB(k * (.88 + hash(i, 1) * .3) * (1 + au * .9), k * (.95 + hash(i, 5) * .12) * (1 - au * .18), k * (.7 + hash(i, 2) * .3) * (1 - au * .55)); { const sn = biome(a[0], a[2])[4]; if (sn > .3) col.lerp(snowCol, Math.min(1, sn * .85)); } im.setColorAt(i, col); }); };
if (RICH) { mkTrees(spruce(), SP.spruce, [.5, 0]); for (const [k, arr] of Object.entries(SP)) mkFar(FARCONE.has(k) || k === 'poplar' ? farCone : farBlob, arr, [.5, 0, k === 'fir' ? .32 : k === 'pine' ? .36 : .36]); mkTrees(fir(), SP.fir, [.5, 0, .32]); mkTrees(pine(), SP.pine, [.5, 0, .36]); mkTrees(broadleaf(), SP.oak, [.5, 1]); mkTrees(birch(), SP.birch, [.5, 1, .5]); mkTrees(poplar(), SP.poplar, [.5, 1, .4]); mkTrees(acacia(), SP.acacia, [.5, 0, .5]); mkTrees(deadTree(), SP.dead, [.5, 0, .45]); mkTrees(willow(), SP.willow, [.5, 0, .45]); mkTrees(cactus(), SP.cactus, [.5, 0, .7]); mkTrees(palm(), SP.palm, [.5, 0, .55]); } else { for (const [k, arr] of Object.entries(SP)) if (!['cactus', 'dead', 'palm'].includes(k)) mkFar(FARCONE.has(k) || k === 'poplar' ? farCone : farBlob, arr, [.5, 0, k === 'fir' ? .32 : k === 'pine' ? .36 : .36]); }
marks.push(['  trees built', performance.now()]);
const rockG = jitter(new THREE.IcosahedronGeometry(1, 2), .5, 77); const rocks = [];
for (let i = 0; i < 5000; i++) { const px = rnd() * W, pz = rnd() * W, h = H(px, pz); if (h < SEA + .01) continue; const el = (h - SEA) / (1 - SEA); if ((el < .28 && biome(px, pz)[0] < .4) || sites.some((s) => Math.hypot(px - s.x, pz - s.y) < 180 * CF)) continue; if (!nearLake(px, pz, 1.25)) rocks.push([px, hAt(px, pz), pz, 5 + rnd() * rnd() * 34, rnd()]); }
const rockMesh = new THREE.InstancedMesh(rockG, new THREE.MeshStandardMaterial({ color: 0x8a8278, roughness: 1 }), rocks.length); rockMesh.castShadow = true; rockMesh.receiveShadow = true;
{ const d = new THREE.Object3D(), col = new THREE.Color(); rocks.forEach((a, i) => { d.position.set(a[0], a[1] + a[3] * .15, a[2]); d.rotation.set(a[4]*6, a[4]*9, a[4]*3); d.scale.set(a[3], a[3] * .62, a[3] * .85); d.updateMatrix(); rockMesh.setMatrixAt(i, d.matrix); { const bdr = biome(a[0], a[2])[0]; col.setHSL(.09 - bdr * .03, .08 + a[4] * .1 + bdr * .3, .42 + a[4] * .2); } rockMesh.setColorAt(i, col); }); scene.add(rockMesh); }
{
  const slabs = []; const slabG = jitter(new THREE.IcosahedronGeometry(1, 3), .55, 91);
  for (let i = 0; i < 9000 && slabs.length < 3500; i++) { const px = rnd() * W, pz = rnd() * W, h = H(px, pz); if (h < SEA + .03) continue; const el = (h - SEA) / (1 - SEA); if (el < .18) continue; if (sites.some((s) => Math.hypot(px - s.x, pz - s.y) < 260)) continue; const y = hAt(px, pz), gx = hAt(px + 10, pz) - y, gz = hAt(px, pz + 10) - y, sl = Math.hypot(gx, gz) / 10; if (sl < .3) continue; if (biome(px, pz)[4] > .5 && rnd() < .6) continue; slabs.push([px, y, pz, 10 + rnd() * rnd() * 38, rnd(), Math.atan2(gx, gz), sl]); }
  const sm = new THREE.InstancedMesh(slabG, new THREE.MeshStandardMaterial({ color: 0x8a8076, roughness: 1 }), slabs.length); sm.castShadow = true; sm.receiveShadow = true; const d = new THREE.Object3D(), col = new THREE.Color();
  slabs.forEach((a, i) => { d.position.set(a[0], a[1] - a[3] * .05, a[2]); d.rotation.set((a[4] - .5) * .5, a[5] + (a[4] - .5), (a[4] - .5) * .4); d.scale.set(a[3] * (.9 + a[4] * .6), a[3] * (.55 + a[4] * .35), a[3] * (.8 + a[4] * .5)); d.updateMatrix(); sm.setMatrixAt(i, d.matrix); const bb = biome(a[0], a[2]), bdr = bb[0]; col.setHSL(.09 - bdr * .03, .06 + a[4] * .08 + bdr * .3 - bb[4] * .05, .44 + a[4] * .16 + bb[4] * .28); sm.setColorAt(i, col); }); scene.add(sm);
  const sp = [], spG = jitter(new THREE.ConeGeometry(1, 1, 7, 4), .22, 55); for (let i = 0; i < 12000 && sp.length < 650; i++) { const px = rnd() * W, pz = rnd() * W, h = H(px, pz); if (h < SEA + .03) continue; const el = (h - SEA) / (1 - SEA); if (el < .36 || sites.some((s) => Math.hypot(px - s.x, pz - s.y) < 300)) continue; sp.push([px, hAt(px, pz), pz, 8 + rnd() * 14, rnd()]); }
  const spm = new THREE.InstancedMesh(spG, new THREE.MeshStandardMaterial({ color: 0x8c8378, roughness: 1 }), sp.length); spm.castShadow = true; spm.receiveShadow = true; const d2 = new THREE.Object3D(), c2 = new THREE.Color();
  sp.forEach((a, i) => { d2.position.set(a[0], a[1] - 6, a[2]); d2.rotation.set((a[4] - .5) * .3, a[4] * 6, (a[4] - .5) * .3); d2.scale.set(a[3], a[3] * (1.6 + a[4] * 1.8), a[3] * .85); d2.updateMatrix(); spm.setMatrixAt(i, d2.matrix); const sn = biome(a[0], a[2])[4]; c2.setHSL(.08, .07 + a[4] * .06, .42 + a[4] * .16 + sn * .3); spm.setColorAt(i, c2); }); scene.add(spm);
}

const mkTex = (draw, w = 512, h = 512) => { const c = document.createElement('canvas'); c.width = w; c.height = h; draw(c.getContext('2d'), w, h); const t = new THREE.CanvasTexture(c); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8; return t; };
const stoneTex = mkTex((g, w, h) => { g.fillStyle = '#5e564a'; g.fillRect(0, 0, w, h); const rows = 14, bh = h / rows; for (let r = 0; r < rows; r++) { const bw = w / (5 + (r % 3)); for (let c = -1; c < 9; c++) { const x = c * bw + (r % 2) * bw / 2 + (hash(r, 7) - .5) * 8, v = 128 + hash(r, c) * 86; g.fillStyle = `rgb(${v + 16},${v + 6},${v - 16})`; g.fillRect(x + 3.5, r * bh + 3.5, bw - 7, bh - 7); g.fillStyle = 'rgba(255,245,220,.16)'; g.fillRect(x + 3, r * bh + 3, bw - 6, 5); g.fillStyle = 'rgba(0,0,0,.2)'; g.fillRect(x + 3, r * bh + bh - 8, bw - 6, 5); } } for (let i = 0; i < 14000; i++) { const lt = hash(i, 1) > .5; g.fillStyle = lt ? 'rgba(255,240,205,.06)' : 'rgba(0,0,0,.08)'; g.fillRect(hash(i, 2) * w, hash(i, 3) * h, 2 + hash(i, 8) * 3, 2); } g.strokeStyle = 'rgba(35,26,16,.7)'; g.lineWidth = 3.5; for (let r = 0; r <= rows; r++) { g.beginPath(); g.moveTo(0, r * bh); g.lineTo(w, r * bh); g.stroke(); } for (let i = 0; i < 40; i++) { g.strokeStyle = 'rgba(30,22,14,.35)'; g.lineWidth = 1.5; g.beginPath(); const x = hash(i, 11) * w, y = hash(i, 12) * h; g.moveTo(x, y); g.lineTo(x + (hash(i, 13) - .5) * 30, y + 14 + hash(i, 14) * 24); g.stroke(); } }, 1024, 1024);
const roofTex = mkTex((g, w, h) => { g.fillStyle = '#fff'; g.fillRect(0, 0, w, h); const rows = 16, th = h / rows; for (let r = 0; r < rows; r++) for (let c = -1; c < 12; c++) { const tw = w / 10, x = c * tw + (r % 2) * tw / 2, v = 210 + hash(r, c) * 45; g.fillStyle = `rgb(${v},${v},${v})`; g.beginPath(); g.moveTo(x, r * th); g.lineTo(x + tw, r * th); g.lineTo(x + tw, r * th + th * .65); g.arc(x + tw / 2, r * th + th * .65, tw / 2, 0, Math.PI); g.closePath(); g.fill(); g.strokeStyle = 'rgba(30,20,10,.5)'; g.lineWidth = 1.5; g.stroke(); } });
const thatchTex = mkTex((g, w, h) => { g.fillStyle = '#a58a52'; g.fillRect(0, 0, w, h); for (let i = 0; i < 2600; i++) { const v = 110 + hash(i, 4) * 90; g.strokeStyle = `rgba(${v},${v * .85},${v * .5},.6)`; g.lineWidth = 1.5; const x = hash(i, 5) * w, y = hash(i, 6) * h; g.beginPath(); g.moveTo(x, y); g.lineTo(x + (hash(i, 7) - .5) * 6, y + 26); g.stroke(); } });
const woodTex = mkTex((g, w, h) => { g.fillStyle = '#46301c'; g.fillRect(0, 0, w, h); for (let i = 0; i < 40; i++) { g.fillStyle = `rgba(${hash(i, 1) > .5 ? 20 : 220},${hash(i, 1) > .5 ? 10 : 170},${hash(i, 1) > .5 ? 0 : 110},.18)`; g.fillRect(i * w / 40, 0, w / 40 - 2, h); } });
const mStones = [0xd8cba8, 0xb9b3a6, 0xc9a98a, 0xa9aab0].map((c) => new THREE.MeshStandardMaterial({ map: stoneTex, bumpMap: stoneTex, bumpScale: 3.4, roughness: .94, color: c, vertexColors: true }));
const grime = (g) => { const p = g.attributes.position, c = new Float32Array(p.count * 3); for (let i = 0; i < p.count; i++) { const y = p.getY(i), tt = Math.min(1, Math.max(0, y / 30)), k = .58 + .42 * tt, moss = Math.max(0, 1 - y / 14) * .3, n = .9 + hash(Math.round(p.getX(i) * .5), Math.round(p.getZ(i) * .5)) * .2; c[i*3] = k * n * (1 - moss * .5); c[i*3+1] = k * n * (1 + moss * .08); c[i*3+2] = k * n * (1 - moss * .6); } g.setAttribute('color', new THREE.BufferAttribute(c, 3)); return g; };
let mStone = mStones[0];
const mSand = new THREE.MeshStandardMaterial({ map: stoneTex, bumpMap: stoneTex, bumpScale: 3.4, roughness: .96, color: 0xe6c690, vertexColors: true });
const mWood = new THREE.MeshStandardMaterial({ map: woodTex, roughness: .9 });
const mDark = new THREE.MeshStandardMaterial({ color: 0x1b140c, roughness: 1 });
const mGlow = new THREE.MeshStandardMaterial({ color: 0xffa347, emissive: 0xff8a2a, emissiveIntensity: 3, roughness: .5 });
const mThatch = new THREE.MeshStandardMaterial({ map: thatchTex, roughness: 1 });
const scaleUV = (g, u, v) => { const a = g.attributes.uv; for (let i = 0; i < a.count; i++) a.setXY(i, a.getX(i) * u, a.getY(i) * v); return g; };
const place = (g, x, y, z, ry = 0, sx = 1, sy = 1, sz = 1) => { const m = new THREE.Matrix4().compose(new THREE.Vector3(x, y, z), new THREE.Quaternion().setFromEuler(new THREE.Euler(0, ry, 0)), new THREE.Vector3(sx, sy, sz)); g.applyMatrix4(m); return g; };

const houseWall = new THREE.BoxGeometry(1, 1, 1); houseWall.translate(0, .5, 0);
const houseRoof = (() => { const g = new THREE.ConeGeometry(.78, .7, 4, 1); g.rotateY(Math.PI / 4); g.scale(1.3, 1, 1.1); g.translate(0, 1.32, 0); return g; })();
const villW = [], villR = [];
function village(cx0, cz0, n, S) { for (let i = 0; i < n; i++) { const a = rnd() * 6.28, r = 160 * S + rnd() * 140 * S, x = cx0 + Math.cos(a) * r, z = cz0 + Math.sin(a) * r; if (H(x, z) < SEA + .02) continue; const s = 16 + rnd() * 10; villW.push([x, hAt(x, z), z, a, s, rnd()]); } }


{
  const parts = [], mk = (r, y, sc) => { const g = new THREE.IcosahedronGeometry(r, 1); g.scale(1, sc, 1); g.translate(0, y, 0); parts.push(paint(jitter(g, r * .25, 7), () => [.5, .47, .43])); };
  mk(11, 6, .7); mk(8, 15, .75); mk(5.5, 22, .8); const pole = new THREE.CylinderGeometry(.9, .9, 34, 5); pole.translate(0, 38, 0); parts.push(paint(pole, () => [.24, .17, .1])); const fl = new THREE.PlaneGeometry(13, 8); fl.translate(7.5, 51, 0); parts.push(paint(fl, () => [.65, .2, .15]));
  const g = mergeGeometries(parts), im = new THREE.InstancedMesh(g, new THREE.MeshStandardMaterial({ vertexColors: true, roughness: .95, side: THREE.DoubleSide }), PASS.length), d = new THREE.Object3D();
  PASS.forEach((p, i) => { d.position.set(p.x, hAt(p.x, p.z) - 1, p.z); d.rotation.y = hash(i, 4) * 6; d.scale.setScalar(.95); d.updateMatrix(); im.setMatrixAt(i, d.matrix); }); im.castShadow = true; im.receiveShadow = true; scene.add(im); scene.userData.pass = im;
}
const makeSign = () => {
  const parts = [], post = new THREE.CylinderGeometry(.7, .8, 16, 5); post.translate(0, 8, 0); parts.push(paint(post, () => [.3, .21, .12]));
  for (const [yy, rot] of [[13, .4], [9.5, -.5]]) { const arm = new THREE.BoxGeometry(11, 2.4, .8); arm.translate(5.5, 0, 0); arm.rotateY(rot); arm.translate(0, yy, 0); parts.push(paint(arm, () => [.62, .5, .3])); }
  const m = new THREE.Mesh(mergeGeometries(parts), new THREE.MeshStandardMaterial({ vertexColors: true, roughness: .95 })); m.castShadow = true; m.scale.setScalar(3.6);
  const g = new THREE.Group(); g.add(m); g.userData = { radius: 22, hgt: 36 }; return g;
};
const flags = [];
const mEarth = new THREE.MeshStandardMaterial({ color: 0xb08c5c, roughness: 1, map: thatchTex, bumpMap: thatchTex, bumpScale: 1 });
const mCobble = new THREE.MeshStandardMaterial({ map: stoneTex, bumpMap: stoneTex, bumpScale: 2.5, color: 0x7e776a, roughness: 1 });
const mSail = new THREE.MeshStandardMaterial({ color: 0xe8dcc0, side: THREE.DoubleSide, roughness: .9 });
const VARIANTS = ['keepBailey', 'roundShell', 'motte', 'towerHouse', 'concentric', 'citadel', 'starFort', 'polyKeep'];
function rectPlanes(hx, hz) { return [[0, 1, hz], [1, 0, hx], [0, -1, hz], [-1, 0, hx]]; }
function polyPlanes(n, ap) { return Array.from({ length: n }, (_, k) => { const a = Math.PI / 2 + k * 2 * Math.PI / n; return [Math.cos(a), Math.sin(a), ap]; }); }
function keepAsp(seed) { return hash(seed, 71) < .45 ? 1 : 1.25 + .5 * hash(seed, 72); }
function polySides(seed) { return hash(seed, 73) < .5 ? 6 : 8; }
function moatLocal(v, tier, seed, S) {
  if (tier < 2) return null;
  const wd = 17 * S;
  if (v === 'keepBailey') return { pl: rectPlanes(56 * S * keepAsp(seed) + 22 * S, 78 * S), wd };
  if (v === 'concentric') return { pl: rectPlanes(99 * S, 99 * S), wd };
  if (v === 'roundShell') return { r: (tier >= 3 ? 82 : 60) * S * 1.18, wd };
  if (v === 'polyKeep') { const n = polySides(seed); return { pl: polyPlanes(n, (tier >= 3 ? 84 : 66) * S * Math.cos(Math.PI / n) + 24 * S), wd }; }
  if (v === 'starFort') return { pl: polyPlanes(5, .906 * 74 * S + 20 * S), wd };
  return null;
}
function planeVerts(pl, grow) {
  const o = pl.map((p, i) => ({ a: Math.atan2(p[1], p[0]), p })).sort((x, y) => x.a - y.a).map((q) => q.p), out = [];
  for (let i = 0; i < o.length; i++) { const a = o[i], b = o[(i + 1) % o.length], d = a[0] * b[1] - a[1] * b[0], c1 = a[2] + grow, c2 = b[2] + grow; out.push([(c1 * b[1] - c2 * a[1]) / d, (a[0] * c2 - b[0] * c1) / d]); }
  return out;
}
function pickVariant(tier, terrain, seed) {
  const r = hash(seed, 41), rocky = terrain === 'mountain' || terrain === 'hills';
  if (tier === 1) return rocky && r < .5 ? 'citadel' : (terrain === 'forest' ? (r < .7 ? 'motte' : 'towerHouse') : (r < .4 ? 'motte' : 'towerHouse'));
  if (tier === 2) return rocky && r < .4 ? 'citadel' : (r < .28 ? 'keepBailey' : r < .46 ? 'roundShell' : r < .64 ? 'starFort' : r < .84 ? 'polyKeep' : 'keepBailey');
  return r < .3 ? 'concentric' : (rocky && r < .5 ? 'citadel' : (r < .62 ? 'polyKeep' : (r < .78 ? 'roundShell' : (r < .9 ? 'starFort' : 'keepBailey'))));
}
const flagTexCache = new Map();
function flagTex(c1, c2) {
  const key = c1 + c2; let t = flagTexCache.get(key); if (t) return t;
  const cv = document.createElement('canvas'); cv.width = 256; cv.height = 150; const x = cv.getContext('2d');
  x.fillStyle = c1; x.fillRect(0, 0, 256, 150); x.fillStyle = c2; x.fillRect(0, 0, 256, 26);
  x.save(); x.translate(128, 84); x.scale(1.5, 1.5); x.beginPath(); x.moveTo(-30, -34); x.lineTo(30, -34); x.lineTo(30, 4); x.quadraticCurveTo(30, 28, 0, 40); x.quadraticCurveTo(-30, 28, -30, 4); x.closePath();
  x.fillStyle = c2; x.fill(); x.lineWidth = 4; x.strokeStyle = '#1a1008'; x.stroke();
  x.fillStyle = c1; x.fillRect(-30, -14, 60, 10); x.beginPath(); x.arc(0, -4, 9, 0, 6.2832); x.fill(); x.lineWidth = 3; x.stroke(); x.restore();
  t = new THREE.CanvasTexture(cv); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 4; flagTexCache.set(key, t); return t;
}
function drapedRing(cx, cz, r0, r1) {
  const N = 96, pos = [], idx = [];
  for (let i = 0; i <= N; i++) { const a = i / N * 6.2832, co = Math.cos(a), si = Math.sin(a), x0 = cx + co * r0, z0 = cz + si * r0, x1 = cx + co * r1, z1 = cz + si * r1; pos.push(x0, hAt(x0, z0) + 2.2, z0, x1, hAt(x1, z1) + 2.2, z1); if (i < N) { const k = i * 2; idx.push(k, k + 1, k + 2, k + 1, k + 3, k + 2); } }
  const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); g.setIndex(idx); return g;
}
function makeCastle(tier, col, col2, seed, variant, desert, snowy, opts) {
  const S = (tier >= 3 ? 1.35 : tier === 2 ? 1.05 : .72) * 1.25;
  const stone = [], roof = [], wood = [], dark = [], glow = [], cloth = [], earth = [], thatch = [], cobble = [];
  const box = (w, h, d, x, y, z, arr = stone, ry = 0, u = 1) => { const g = new THREE.BoxGeometry(w, h, d); scaleUV(g, Math.max(1, w / 30) * u, Math.max(1, h / 30)); place(g, x, y + h / 2, z, ry); arr.push(g); return g; };
  const merlonsLine = (x0, z0, x1, z1, y, n, sz = 5) => { for (let i = 0; i < n; i++) { const tt = (i + .5) / n; box(sz * S, 6 * S, sz * S, x0 + (x1 - x0) * tt, y, z0 + (z1 - z0) * tt); } };
  const merlonsRing = (r, y, n, cx = 0, cz = 0, sz = 4) => { for (let i = 0; i < n; i++) { const a = i / n * 6.2832; box(sz * S, 5.5 * S, sz * S, cx + Math.cos(a) * r, y, cz + Math.sin(a) * r, stone, -a); } };
  const cone = (r, h, x, y, z, arr = roof, seg = 16, ry = 0, uu = 4) => { const g = new THREE.ConeGeometry(r, h, seg); if (seg === 4) g.rotateY(Math.PI / 4); scaleUV(g, uu, 2); place(g, x, y + h / 2, z, ry); arr.push(g); };
  const gable = (w, d, h, x, y, z, ry = 0, arr = roof) => { const sh = new THREE.Shape(); sh.moveTo(-w / 2, 0); sh.lineTo(w / 2, 0); sh.lineTo(0, h); sh.closePath(); const g = new THREE.ExtrudeGeometry(sh, { depth: d, bevelEnabled: false }); g.translate(0, 0, -d / 2); scaleUV(g, .06, .06); place(g, x, y, z, ry); arr.push(g); };
  const tower = (x, z, r, h, rf = true, y0 = 0) => {
    const c0 = new THREE.CylinderGeometry(r, r * 1.1, h, 16); scaleUV(c0, 6, Math.max(1, h / 30)); place(c0, x, y0 + h / 2, z); stone.push(c0);
    const c1 = new THREE.CylinderGeometry(r * 1.22, r * 1.05, 6 * S, 16); place(c1, x, y0 + h + 3 * S, z); stone.push(c1);
    for (let i = 0; i < 3; i++) { const a = i * 2.1 + seed; box(1.6, 7, 2.6, x + Math.cos(a) * r * 1.02, y0 + h * .55, z + Math.sin(a) * r * 1.02, dark, -a); }
    if (rf) { const pyr = hash(Math.round(x * 3) + seed, Math.round(z * 3)) > .72; if (pyr) cone(r * 1.75, r * 2.1, x, y0 + h + 6 * S, z, roof, 4, 0, 3); else cone(r * 1.4, r * 2.5, x, y0 + h + 6 * S, z); cone(1.4, 9, x, y0 + h + 6 * S + (pyr ? r * 2.1 : r * 2.5), z, dark, 6, 0, 1); const hd = new THREE.CylinderGeometry(r * 1.28, r * 1.28, 7, 16); scaleUV(hd, 6, 1); place(hd, x, y0 + h - 3, z); wood.push(hd); } else merlonsRing(r * 1.1, y0 + h + 6 * S, 10, x, z, 3.6);
    { const pl = new THREE.CylinderGeometry(r * 1.2, r * 1.28, 6, 16); scaleUV(pl, 6, 1); place(pl, x, y0 + 3, z); stone.push(pl); }
    return y0 + h + 6 * S + (rf ? r * 2.5 : 0);
  };
  const gatehouse = (x, z, gw, wh, rot = 0) => {
    const gh = 26 * S, c = Math.cos(rot), s = Math.sin(rot);
    box(gw + 22 * S, wh + 16 * S, 18 * S, x, 0, z, stone, rot);
    [-1, 1].forEach((sx) => { tower(x + c * sx * (gw / 2 + 11 * S), z - s * sx * (gw / 2 + 11 * S), 8 * S, wh + 28 * S); });
    const sh = new THREE.Shape(); sh.moveTo(-gw / 2, 0); sh.lineTo(-gw / 2, gh * .6); sh.absarc(0, gh * .6, gw / 2, Math.PI, 0, true); sh.lineTo(gw / 2, 0); const eg = new THREE.ExtrudeGeometry(sh, { depth: 4, bevelEnabled: false }); eg.translate(0, 0, 9 * S); place(eg, x, 0, z, rot); dark.push(eg);
    [-1, 1].forEach((sx) => { const bg = new THREE.PlaneGeometry(7 * S, 20 * S); place(bg, x + c * sx * (gw / 2 + 5 * S) + s * 10.2 * S, wh * .62 + 8 * S, z + c * 10.2 * S - s * sx * (gw / 2 + 5 * S), rot); cloth.push(bg); });
    [-1, 1].forEach((sx) => { const g = new THREE.SphereGeometry(1.8, 8, 6); place(g, x + c * sx * (gw / 2 + 3) + s * 12 * S, gh * .85, z + c * 12 * S - s * sx * (gw / 2 + 3)); glow.push(g); });
  };
  const wallDetail = (x0, z0, x1, z1, h, n, ox, oz, th) => { for (let i = 0; i < n; i++) { const tt = (i + .5) / n, x = x0 + (x1 - x0) * tt, z = z0 + (z1 - z0) * tt, ry = Math.atan2(ox, oz); box(1.8, 9, 1.6, x + ox * (th / 2 + .4), h * .5, z + oz * (th / 2 + .4), dark, ry); if (i % 3 === 1) box(5 * S, h * .92, 4 * S, x + ox * (th / 2 + 1.6 * S), 0, z + oz * (th / 2 + 1.6 * S), stone, ry); } };
  const windows = (cx, cz, w, d, h, floors) => { [[0, 1], [0, -1], [1, 0], [-1, 0]].forEach(([nx, nz]) => { const fw = nz ? w : d, half = nz ? d / 2 : w / 2; for (let f = 0; f < floors; f++) for (let c = -1; c <= 1; c++) { const lx = c * fw * .27, y = h * (.28 + f * .6 / floors); box(2.8 * S, 5.4 * S, 1.2, cx + nx * (half + .5) + (nz ? lx : 0), y, cz + nz * (half + .5) + (nx ? lx : 0), dark, Math.atan2(nx, nz)); box(3.8 * S, 1.2, 2, cx + nx * (half + .9) + (nz ? lx : 0), y - 1, cz + nz * (half + .9) + (nx ? lx : 0), stone, Math.atan2(nx, nz)); } }); };
  const floor = (w, d, cx, cz) => { const g = new THREE.BoxGeometry(w, 1.2, d); scaleUV(g, w / 30, d / 30); place(g, cx, .6, cz); cobble.push(g); };
  const bridge = (z0, z1) => { box(12 * S, 2.6, z1 - z0, 0, -.8, (z0 + z1) / 2, wood); [-1, 1].forEach((sx) => box(1.4, 6, z1 - z0, sx * 6 * S, 0, (z0 + z1) / 2, wood)); };
  const chapel = (x, z, ry = 0) => { const sn = Math.sin(ry), cs = Math.cos(ry); box(22 * S, 18 * S, 38 * S, x, 0, z, stone, ry); gable(22 * S * 1.06, 38 * S * 1.06, 11 * S, x, 18 * S, z, ry + Math.PI / 2, roof); const tx = x + sn * 24 * S, tz = z + cs * 24 * S; box(11 * S, 36 * S, 11 * S, tx, 0, tz, stone, ry); cone(6.4 * S, 30 * S, tx, 36 * S, tz, roof, 8, 0, 3); box(1.2, 8, 1.2, tx, 66 * S, tz, dark); box(5, 1.2, 1.2, tx, 69 * S, tz, dark); };
  const hall = (x, z, w, d, h, ry, mat = wood) => { box(w, h, d, x, 0, z, wood, ry); gable(d * 1.05, w * 1.08, h * .55, x, h, z, ry + Math.PI / 2, thatch); };
  let top = 0, rad = 70 * S;
  const v = variant;
  const ml = moatLocal(v, tier, seed, S), gateEnd = ml ? (ml.pl ? ml.pl[0][2] : ml.r) + ml.wd + 8 : 0;
  if (v === 'keepBailey') {
    const wh = 34 * S, hw = 56 * S, hx = hw * keepAsp(seed), nx = Math.round(14 * hx / hw), nd = Math.round(6 * hx / hw), th = 8 * S;
    [[0, -hw, 2 * hx, th], [0, hw, 2 * hx, th], [-hx, 0, th, 2 * hw], [hx, 0, th, 2 * hw]].forEach(([x, z, ww, dd]) => { box(ww, wh, dd, x, 0, z); box(ww, 3, dd + 3 * S, x, wh, z); });
    merlonsLine(-hx, -hw, hx, -hw, wh + 3, nx); merlonsLine(-hx, hw, hx, hw, wh + 3, nx); merlonsLine(-hx, -hw, -hx, hw, wh + 3, 14); merlonsLine(hx, -hw, hx, hw, wh + 3, 14);
    [[-1, -1], [1, -1], [-1, 1], [1, 1]].forEach(([a, b]) => tower(a * hx, b * hw, 13.5 * S, wh + 24 * S));
    gatehouse(0, hw + 3 * S, 24 * S, wh);
    wallDetail(-hx, -hw, hx, -hw, wh, nd, 0, -1, th); wallDetail(-hx, hw, hx, hw, wh, nd, 0, 1, th); wallDetail(-hx, -hw, -hx, hw, wh, 6, -1, 0, th); wallDetail(hx, -hw, hx, hw, wh, 6, 1, 0, th);
    floor(2 * hx - 2 * th, 2 * hw - 2 * th, 0, 0); bridge(hw + 13 * S, gateEnd);
    if (hash(seed, 60) > .5) [[0, -1], [-1, 0], [1, 0]].forEach(([a, b]) => tower(a * hx, b * hw, 9 * S, wh + 12 * S, false));
    if (hash(seed, 55) < .55) chapel(-hw * .5, hw * .35, 0.2);
    const kw = 40 * S + 6, kh = (tier >= 3 ? 96 : 66) * S; box(kw, kh, kw, 0, 0, -6 * S); windows(0, -6 * S, kw, kw, kh, tier >= 3 ? 4 : 3); box(kw + 6, 5, kw + 6, 0, kh, -6 * S); cone(kw * .85, kw * .95, 0, kh + 5, -6 * S, roof, 4, 0, 3);
    top = kh + 5 + kw * .95; rad = hx * 1.25;
    for (let i = 0; i < 3; i++) { const a = i / 3 * 6.28 + seed, x = Math.cos(a) * hw * .55, z = Math.sin(a) * hw * .55 - 12 * S; if (Math.abs(x) < kw * .7 && Math.abs(z + 6 * S) < kw * .7) continue; hall(x, z, (14 + hash(i, seed) * 6) * S, (11 + hash(seed, i) * 6) * S, (11 + hash(i, 9) * 4) * S, a); }
  } else if (v === 'passGate') {
    const w = 96 * S, wh = 30 * S, th = 9 * S;
    box(w, wh, th, 0, 0, 0); box(w, 3, th + 3 * S, 0, wh, 0); merlonsLine(-w / 2, 0, w / 2, 0, wh + 3, 12);
    [-1, 1].forEach((sx) => tower(sx * w / 2, 0, 12 * S, wh + 26 * S));
    gatehouse(0, 0, 20 * S, wh); floor(w, 30 * S, 0, 8 * S);
    top = wh + 26 * S + 12 * S * 2.5 + 6 * S; rad = w * .7;
  } else if (v === 'roundShell') {
    const R = (tier >= 3 ? 82 : 60) * S, wh = 32 * S, n = 22, seg = 2 * R * Math.sin(Math.PI / n) * 1.04;
    for (let i = 0; i < n; i++) { const a = i / n * 6.2832; if (Math.abs(a - 1.5708) < .2) continue; box(seg, wh, 8 * S, Math.cos(a) * R, 0, Math.sin(a) * R, stone, -a + Math.PI / 2); }
    merlonsRing(R + 1, wh, 32, 0, 0, 5);
    for (let i = 0; i < 6; i++) { const a = i / 6 * 6.2832 + .3; if (Math.abs(a - 1.5708) < .5) continue; tower(Math.cos(a) * R, Math.sin(a) * R, 11 * S, wh + 20 * S, i % 2 === 0); }
    gatehouse(0, R, 22 * S, wh);
    { const cg = new THREE.CylinderGeometry(R * .97, R * .97, 1.2, 32); scaleUV(cg, 8, 1); place(cg, 0, .6, 0); cobble.push(cg); }
    bridge(R + 12 * S, gateEnd);
    if (hash(seed, 56) < .5) chapel(-R * .42, R * .22, -0.3);
    const kr = (tier >= 3 ? 24 : 19) * S, kh = (tier >= 3 ? 104 : 80) * S; top = tower(0, -4 * S, kr, kh, true); rad = R * 1.25;
    [[-1, 1], [1, 1], [0, -1]].forEach(([a, b], i) => { if (tier >= 3) tower(Math.cos(i * 2.1) * kr * 1.7, -4 * S + Math.sin(i * 2.1) * kr * 1.7, 8 * S, kh * .6, true); });
    for (let i = 0; i < 4; i++) { const a = i / 4 * 6.28 + .7; hall(Math.cos(a) * R * .6, Math.sin(a) * R * .6, (12 + hash(i, seed) * 5) * S, 10 * S, 10 * S, a); }
  } else if (v === 'starFort') {
    const Rv = 74 * S, wh = 30 * S, nV = 5, vs = [], a0 = Math.PI / 2 - Math.PI / 5;
    for (let i = 0; i < nV; i++) { const a = a0 + i * 2 * Math.PI / nV; vs.push([Math.cos(a) * Rv, Math.sin(a) * Rv, a]); }
    for (let i = 0; i < nV; i++) { const A = vs[i], B = vs[(i + 1) % nV], dx = B[0] - A[0], dz = B[1] - A[1], L = Math.hypot(dx, dz), ry = -Math.atan2(dz, dx); box(L, wh, 8 * S, (A[0] + B[0]) / 2, 0, (A[1] + B[1]) / 2, stone, ry); box(L, 3, 11 * S, (A[0] + B[0]) / 2, wh, (A[1] + B[1]) / 2, stone, ry); merlonsLine(A[0], A[1], B[0], B[1], wh + 3, 10); const mx = (A[0] + B[0]) / 2, mz = (A[1] + B[1]) / 2, ln = Math.hypot(mx, mz), ox = mx / ln, oz = mz / ln; wallDetail(A[0], A[1], B[0], B[1], wh, 5, ox, oz, 8 * S); }
    vs.forEach(([x, z, a]) => { box(20 * S, wh * 1.2, 30 * S, x * 1.12, 0, z * 1.12, stone, Math.atan2(x, z)); box(22 * S, 3, 32 * S, x * 1.12, wh * 1.2, z * 1.12, stone, Math.atan2(x, z)); tower(x, z, 9.5 * S, wh + 20 * S, false); });
    gatehouse(0, Rv * Math.cos(Math.PI / 5) + 4 * S, 22 * S, wh);
    { const cg = new THREE.CylinderGeometry(Rv * .85, Rv * .85, 1.2, 5); scaleUV(cg, 8, 1); place(cg, 0, .6, 0); cobble.push(cg); }
    const hh = 26 * S; box(60 * S, hh, 22 * S, 0, 0, -6 * S); gable(22 * S * 1.06, 60 * S * 1.06, 14 * S, 0, hh, -6 * S, Math.PI / 2, roof); box(22 * S, hh, 56 * S, 0, 0, -6 * S); gable(22 * S * 1.06, 56 * S * 1.06, 14 * S, 0, hh, -6 * S, 0, roof);
    windows(0, -6 * S, 60 * S, 22 * S, hh, 2);
    top = tower(0, -6 * S, 12 * S, 66 * S, true); rad = Rv * 1.35;
    gatehouse(0, Rv * .809 + 2 * S, 22 * S, wh); bridge(Rv * .809 + 13 * S, gateEnd);
    if (hash(seed, 58) < .6) chapel(-Rv * .45, Rv * .4, .4);
  } else if (v === 'polyKeep') {
    const n = polySides(seed), R = (tier >= 3 ? 84 : 66) * S, wh = 32 * S, ap = R * Math.cos(Math.PI / n), th = 8 * S, vs = [];
    for (let k = 0; k < n; k++) { const a = Math.PI / 2 + (k + .5) * 2 * Math.PI / n; vs.push([Math.cos(a) * R, Math.sin(a) * R]); }
    { const cg = new THREE.CylinderGeometry(R * .96, R * .96, 1.2, n); cg.rotateY(Math.PI / n); scaleUV(cg, 8, 1); place(cg, 0, .6, 0); cobble.push(cg); }
    for (let k = 0; k < n; k++) { const A = vs[k], B = vs[(k + 1) % n], dx = B[0] - A[0], dz = B[1] - A[1], L = Math.hypot(dx, dz), ry = -Math.atan2(dz, dx), mx = (A[0] + B[0]) / 2, mz = (A[1] + B[1]) / 2, ln = Math.hypot(mx, mz); box(L, wh, th, mx, 0, mz, stone, ry); box(L, 3, th + 3 * S, mx, wh, mz, stone, ry); merlonsLine(A[0], A[1], B[0], B[1], wh + 3, Math.round(L / (8 * S))); wallDetail(A[0], A[1], B[0], B[1], wh, Math.max(3, Math.round(L / (24 * S))), mx / ln, mz / ln, th); }
    vs.forEach(([x, z], k) => tower(x, z, 13 * S, wh + 22 * S, k % 2 === 0));
    gatehouse(0, ap + 2 * S, 24 * S, wh); bridge(ap + 13 * S, gateEnd);
    const kw = (tier >= 3 ? 44 : 38) * S, kh = (tier >= 3 ? 98 : 68) * S; box(kw, kh, kw, 0, 0, -6 * S); windows(0, -6 * S, kw, kw, kh, tier >= 3 ? 4 : 3); box(kw + 6, 5, kw + 6, 0, kh, -6 * S); cone(kw * .85, kw * .95, 0, kh + 5, -6 * S, roof, 4, 0, 3);
    top = kh + 5 + kw * .95; rad = R * 1.25;
    for (let i = 0; i < n; i++) { const a = i / n * 6.2832 + .3; hall(Math.cos(a) * R * .62, Math.sin(a) * R * .62 - 8 * S, (13 + hash(i, seed) * 5) * S, 10 * S, 10 * S, a); }
    if (hash(seed, 56) < .5) chapel(-R * .45, R * .3, -0.3);
  } else if (v === 'riverTwins') {
    const KR = CK * 1.7, off = opts.off / KR, wardW = 64 * S, hw2 = wardW / 2, wh = 34 * S, th = 8 * S, depth = opts.depth / KR;
    const bankWard = (b) => { const cx0 = b * off, inner = -b;
      [-1, 1].forEach((sz) => { box(wardW, wh, th, cx0, 0, sz * hw2); box(wardW, 3, th + 3 * S, cx0, wh, sz * hw2); merlonsLine(cx0 - hw2, sz * hw2, cx0 + hw2, sz * hw2, wh + 3, 8); });
      box(th, wh, wardW, cx0 - inner * hw2, 0, 0); box(th + 3 * S, 3, wardW, cx0 - inner * hw2, wh, 0); merlonsLine(cx0 - inner * hw2, -hw2, cx0 - inner * hw2, hw2, wh + 3, 8);
      [-1, 1].forEach((sz) => box(th, wh, hw2 - 11 * S, cx0 + inner * hw2, 0, sz * (11 * S + (hw2 - 11 * S) / 2)));
      [[-1, -1], [1, -1], [-1, 1], [1, 1]].forEach(([ax, az]) => tower(cx0 + ax * hw2, az * hw2, 12.5 * S, wh + 24 * S, true));
      [-1, 1].forEach((sz) => tower(cx0 + inner * hw2, sz * 13 * S, 7 * S, wh + 30 * S, true));
      const kw = 34 * S, kx = cx0 - inner * 8 * S; box(kw, 62 * S, kw, kx, 0, 0); windows(kx, 0, kw, kw, 62 * S, 3); box(kw + 6, 5, kw + 6, kx, 62 * S, 0); cone(kw * .85, kw * .9, kx, 62 * S + 5, 0, roof, 4, 0, 3);
      floor(wardW - 2 * th, wardW - 2 * th, cx0, 0); };
    bankWard(-1); bankWard(1);
    const gx = off - hw2, bl = gx * 2 + 4 * th; box(bl, 8, 20 * S, 0, -4, 0, stone);
    [-1, 1].forEach((sz) => { box(bl, 5, 2.2, 0, 4, sz * 9.4 * S, stone); merlonsLine(-bl / 2, sz * 9.4 * S, bl / 2, sz * 9.4 * S, 9, Math.max(6, Math.round(bl / 14))); });
    const nP = Math.max(2, Math.round(bl / (46 * S))); for (let k = 0; k <= nP; k++) { const px = -bl / 2 + bl * k / nP; box(10 * S, depth - 4, 20 * S, px, -depth, 0, stone); }
    { const sh = new THREE.Shape(); sh.moveTo(-11 * S, 0); sh.lineTo(-11 * S, 17 * S); sh.absarc(0, 17 * S, 11 * S, Math.PI, 0, true); sh.lineTo(11 * S, 0); const eg = new THREE.ExtrudeGeometry(sh, { depth: 46 * S, bevelEnabled: false }); eg.translate(0, 0, -23 * S); eg.rotateY(Math.PI / 2); place(eg, 0, 4, 0); dark.push(eg); }
    box(40 * S, 54 * S, 26 * S, 0, 4, 0); windows(0, 0, 40 * S, 26 * S, 54 * S, 3); box(46 * S, 5, 32 * S, 0, 4 + 54 * S, 0); cone(26 * S, 34 * S, 0, 4 + 54 * S + 5, 0, roof, 4, 0, 3);
    [[-1, -1], [1, -1], [-1, 1], [1, 1]].forEach(([ax, az]) => tower(ax * 18 * S, az * 11 * S, 6.5 * S, 40 * S, true, 4));
    top = 4 + 54 * S + 34 * S; rad = off + hw2 + 20;
  } else if (v === 'motte') {
    const R = 62 * S, mh = 26 * S, e = new THREE.CylinderGeometry(R * .38, R * .72, mh, 14); scaleUV(e, 4, 1); place(e, 0, mh / 2, 0); earth.push(e);
    const kw = 34 * S, kh = 54 * S; box(kw, kh, kw, 0, mh, 0); box(kw + 10, 11, kw + 10, 0, mh + kh - 8, 0, wood); cone(kw * .82, kw * .85, 0, mh + kh, 0, roof, 4, 0, 3);
    top = mh + kh + kw * .85;
    for (let i = 0; i < 44; i++) { const a = i / 44 * 6.2832; if (Math.abs(a - 1.5708) < .16) continue; const hh = (17 + hash(i, seed) * 5) * S; box(2.6, hh, 2.6, Math.cos(a) * R, 0, Math.sin(a) * R, wood); cone(1.9, 6, Math.cos(a) * R, hh, Math.sin(a) * R, thatch, 4, 0, 1); }
    [-1, 1].forEach((sx) => { box(4, 30 * S, 4, sx * 9 * S, 0, R, wood); const gg = new THREE.SphereGeometry(1.8, 8, 6); place(gg, sx * 9 * S + 3, 22 * S, R + 3); glow.push(gg); });
    for (let i = 0; i < 4; i++) { const a = i / 4 * 6.28 + 1.2; hall(Math.cos(a) * R * .72, Math.sin(a) * R * .72 + 4, (13 + hash(i, 3) * 5) * S, 11 * S, 10 * S, a); }
    rad = R * 1.25;
    const rmp = new THREE.BoxGeometry(10 * S, 3, 54 * S); place(rmp, 0, mh * .5, R * .52, 0); const rg = rmp; rg.rotateX(0); wood.push(scaleUV(rg, 1, 3));
  } else if (v === 'towerHouse') {
    const tw = 34 * S, th = 78 * S; box(tw, th, tw, 0, 0, 0); box(tw + 8, 7, tw + 8, 0, th - 4, 0, stone); merlonsLine(-tw / 2 - 3, -tw / 2 - 3, tw / 2 + 3, -tw / 2 - 3, th + 3, 6); merlonsLine(-tw / 2 - 3, tw / 2 + 3, tw / 2 + 3, tw / 2 + 3, th + 3, 6); merlonsLine(-tw / 2 - 3, -tw / 2 - 3, -tw / 2 - 3, tw / 2 + 3, th + 3, 6); merlonsLine(tw / 2 + 3, -tw / 2 - 3, tw / 2 + 3, tw / 2 + 3, th + 3, 6);
    cone(tw * .42, tw * .7, 0, th + 3, 0, roof, 4, 0, 3);
    const hw2 = 56 * S, hd = 30 * S, hh = 30 * S; box(hw2, hh, hd, tw / 2 + hw2 / 2 - 4, 0, 6 * S); gable(hd * 1.05, hw2 * 1.04, hh * .6, tw / 2 + hw2 / 2 - 4, hh, 6 * S, Math.PI / 2, roof);
    box(110 * S, 14 * S, 6 * S, 10 * S, 0, 56 * S); merlonsLine(-45 * S, 56 * S, 65 * S, 56 * S, 14 * S, 12, 4);
    [-1, 1].forEach((sx) => { tower(10 * S + sx * 55 * S, 56 * S, 9 * S, 34 * S); });
    box(18 * S, 22 * S, 10 * S, 10 * S, 0, 56 * S, dark);
    top = th + 3 + tw * .7; rad = 78 * S;
    hall(-34 * S, 30 * S, 16 * S, 12 * S, 10 * S, .4);
  } else if (v === 'concentric') {
    const w1 = 150 * S, h1 = 30 * S, hw = w1 / 2, th = 8 * S;
    [[0, -hw, w1, th], [0, hw, w1, th], [-hw, 0, th, w1], [hw, 0, th, w1]].forEach(([x, z, ww, dd]) => { box(ww, h1, dd, x, 0, z); box(ww, 3, dd + 3 * S, x, h1, z); });
    merlonsLine(-hw, -hw, hw, -hw, h1 + 3, 18); merlonsLine(-hw, hw, hw, hw, h1 + 3, 18); merlonsLine(-hw, -hw, -hw, hw, h1 + 3, 18); merlonsLine(hw, -hw, hw, hw, h1 + 3, 18);
    [[-1, -1], [1, -1], [-1, 1], [1, 1]].forEach(([a, b]) => tower(a * hw, b * hw, 14 * S, h1 + 22 * S, false)); [[0, -1], [-1, 0], [1, 0]].forEach(([a, b]) => tower(a * hw, b * hw, 10 * S, h1 + 14 * S, false));
    gatehouse(0, hw, 26 * S, h1);
    wallDetail(-hw, -hw, hw, -hw, h1, 8, 0, -1, th); wallDetail(-hw, hw, hw, hw, h1, 8, 0, 1, th); wallDetail(-hw, -hw, -hw, hw, h1, 8, -1, 0, th); wallDetail(hw, -hw, hw, hw, h1, 8, 1, 0, th);
    floor(w1 - 2 * th, w1 - 2 * th, 0, 0); bridge(hw + 13 * S, gateEnd);
    if (hash(seed, 57) < .6) chapel(hw * .56, hw * .5, -0.5);
    const w2 = 74 * S, h2 = 48 * S, hw2 = w2 / 2;
    [[0, -hw2, w2, th], [0, hw2, w2, th], [-hw2, 0, th, w2], [hw2, 0, th, w2]].forEach(([x, z, ww, dd]) => { box(ww, h2, dd, x, 0, z); box(ww, 3, dd + 3 * S, x, h2, z); });
    merlonsLine(-hw2, -hw2, hw2, -hw2, h2 + 3, 12); merlonsLine(-hw2, hw2, hw2, hw2, h2 + 3, 12); merlonsLine(-hw2, -hw2, -hw2, hw2, h2 + 3, 12); merlonsLine(hw2, -hw2, hw2, hw2, h2 + 3, 12);
    [[-1, -1], [1, -1], [-1, 1], [1, 1]].forEach(([a, b]) => tower(a * hw2, b * hw2, 14 * S, h2 + 36 * S));
    const kw = 36 * S, kh = 92 * S; box(kw, kh, kw, 0, 0, -4 * S); windows(0, -4 * S, kw, kw, kh, 5); box(kw + 6, 5, kw + 6, 0, kh, -4 * S); cone(kw * .8, kw, 0, kh + 5, -4 * S, roof, 4, 0, 3);
    [[-1, -1], [1, -1], [-1, 1], [1, 1]].forEach(([a, b]) => tower(a * kw * .56, -4 * S + b * kw * .56, 6 * S, kh * .86));
    top = kh + 5 + kw; rad = hw * 1.2;
    for (let i = 0; i < 5; i++) { const a = i / 5 * 6.28 + .4, rr = (hw + hw2) / 2 - 4; hall(Math.cos(a) * rr * .96, Math.sin(a) * rr * .96, (12 + hash(i, seed) * 5) * S, 10 * S, 9 * S, a); }
  } else {
    const tiers = [[118, 78, 28, 36, 0], [90, 62, 28, 0, 28], [60, 46, 32, -26, 56]];
    tiers.forEach(([w, d, h, z, y], i) => { box(w * S, h * S, d * S, 0, y * S, z * S); merlonsLine(-w * S / 2, (z + d / 2) * S, w * S / 2, (z + d / 2) * S, (y + h) * S, Math.round(w / 8)); merlonsLine(-w * S / 2, (z - d / 2) * S, w * S / 2, (z - d / 2) * S, (y + h) * S, Math.round(w / 8)); [-1, 1].forEach((sx) => tower(sx * (w / 2) * S, (z + d / 2) * S, 11 * S, h * S + (i ? 8 : 14) * S, true, y * S)); });
    const kw = 34 * S, kh = 56 * S; box(kw, kh, kw, 0, 56 * S + 32 * S, -26 * S); cone(kw * .8, kw * .9, 0, 56 * S + 32 * S + kh, -26 * S, roof, 4, 0, 3);
    box(22 * S, 24 * S, 8 * S, 0, 0, 36 * S + 40 * S, dark); top = 56 * S + 32 * S + kh + kw * .9; rad = 80 * S;
    const st = new THREE.BoxGeometry(14 * S, 2.5, 66 * S); st.rotateX(-.32); place(st, 0, 16 * S, 66 * S); wood.push(scaleUV(st, 1, 4));
  }
  if (v !== 'motte' && v !== 'riverTwins') { const bg = new THREE.CylinderGeometry(rad * .86, rad * .98, 90, 28); scaleUV(bg, 10, 3); place(bg, 0, -44.5, 0); cobble.push(bg); }
  const g = new THREE.Group();
  const add = (arr, mat, sh = true) => { if (!arr.length) return; const m = new THREE.Mesh(mergeGeometries(arr), mat); m.castShadow = sh; m.receiveShadow = true; g.add(m); };
  const mRoof = new THREE.MeshStandardMaterial({ map: roofTex, color: new THREE.Color(col).lerp(snowy ? new THREE.Color(0xdfe6ec) : new THREE.Color(col), snowy ? .4 : 0).lerp(new THREE.Color(desert ? 0xb0643a : [0x8a4a32, 0x55595f, 0x6a4a36][Math.floor(hash(seed, 23) * 3)]), .7), roughness: .75 });
  const mCloth = new THREE.MeshStandardMaterial({ color: col, side: THREE.DoubleSide, roughness: .85 });
  stone.forEach(grime); add(stone, desert ? mSand : mStones[Math.floor(hash(seed, 17) * mStones.length)]); add(cobble, mCobble, true); add(roof, mRoof); add(wood, mWood); add(thatch, mThatch); add(earth, mEarth); add(dark, mDark, false); add(glow, mGlow, false); add(cloth, mCloth, false);
  const pole = new THREE.Mesh(new THREE.CylinderGeometry(1, 1, 36, 6), mWood); pole.position.set(0, top + 16, 0); pole.castShadow = true; g.add(pole);
  const fg = new THREE.PlaneGeometry(34, 20, 10, 1); const fl = new THREE.Mesh(fg, new THREE.MeshStandardMaterial({ map: flagTex(col, col2), side: THREE.DoubleSide, roughness: .8 })); fl.position.set(17, top + 26, 0); g.add(fl); flags.push({ fg, base: fg.attributes.position.array.slice() });
  const stripe = new THREE.Mesh(new THREE.PlaneGeometry(34, 5, 10, 1), new THREE.MeshStandardMaterial({ color: col2, side: THREE.DoubleSide })); stripe.position.set(17, top + 26.5, .3); g.add(stripe); flags.push({ fg: stripe.geometry, base: stripe.geometry.attributes.position.array.slice() }); g.userData.tint = { cloth: mCloth, flag: fl.material, stripe: stripe.material, fl, stripe3: stripe, top };
  { const KK = v === 'riverTwins' ? CK * 1.7 : CK * (tier >= 3 ? 1.7 : tier === 2 ? 2.1 : 2.7); g.scale.setScalar(KK); g.userData.hgt = (top + 40) * KK; g.userData.radius = rad * .78 * KK; } g.userData.S = S; g.userData.variant = v;
  return g;
}
function makeDock(s, ang) {
  const g = new THREE.Group(), dx = Math.sin(ang), dz = Math.cos(ang);
  const pier = new THREE.Mesh(new THREE.BoxGeometry(11, 3, 150), mWood); pier.position.set(0, 3, 75); pier.castShadow = true; pier.receiveShadow = true; g.add(pier);
  for (let i = 0; i < 6; i++) { [-1, 1].forEach((sx) => { const p = new THREE.Mesh(new THREE.CylinderGeometry(1.6, 1.6, 14, 6), mWood); p.position.set(sx * 5.5, -1, 12 + i * 26); g.add(p); }); }
  const hull = new THREE.Shape(); hull.moveTo(-34, 6); hull.lineTo(34, 6); hull.lineTo(26, -4); hull.lineTo(-24, -4); hull.closePath(); const hg2 = new THREE.ExtrudeGeometry(hull, { depth: 14, bevelEnabled: false }); hg2.translate(0, 0, -7);
  const boat = new THREE.Group(); const hm = new THREE.Mesh(hg2, mWood); hm.castShadow = true; boat.add(hm); const mast = new THREE.Mesh(new THREE.CylinderGeometry(.8, .8, 54, 5), mWood); mast.position.set(0, 32, 0); boat.add(mast); const sail = new THREE.Mesh(new THREE.PlaneGeometry(30, 34), mSail); sail.position.set(0, 36, 0); sail.rotation.y = Math.PI / 2; sail.castShadow = true; boat.add(sail);
  boat.position.set(30, 1.5, 120); boat.rotation.y = Math.PI / 2; g.add(boat);
  g.scale.setScalar(CK); g.position.set(s.x + dx * 55, 0, s.y + dz * 55); g.rotation.y = ang; return g;
}
const labels = $('labels');
const shield = (c, c2) => `<svg class="sh" viewBox="0 0 64 72"><path d="M4 4H60V38C60 56 46 66 32 70C18 66 4 56 4 38Z" fill="${c}" stroke="#1a1008" stroke-width="3"/><path d="M4 22H60V32H4Z" fill="${c2}" opacity=".9"/><circle cx="32" cy="27" r="8" fill="${c2}" stroke="#1a1008" stroke-width="2"/><path d="M4 4H60V38C60 56 46 66 32 70C18 66 4 56 4 38Z" fill="none" stroke="#f5dc94" stroke-width="2.4"/></svg>`;
const fillRb = (rb, name, n) => { rb.replaceChildren(); if (name) { const sp = document.createElement('span'); sp.textContent = name; rb.appendChild(sp); } const b = document.createElement('b'); b.textContent = String(n); rb.appendChild(b); };
const setLabel = (el, c1, c2, name, n) => { el.innerHTML = shield(c1, c2); const rb = document.createElement('div'); rb.className = 'rb'; fillRb(rb, name, n); el.appendChild(rb); };
marks.push(['  rocks+passes built', performance.now()]);
await stage('Raising castles');
const castles = [], DOCKS = [];
sites.forEach((s, i) => {
  if (s.junction) {
    const g = makeSign(); g.position.set(s.x, s.gy, s.y); g.rotation.y = hash(i, 9) * 6; scene.add(g);
    const el = document.createElement('div'); el.className = 'bn'; el.style.display = 'none'; labels.appendChild(el); s.cols = ['#8a8478', '#5a574f'];
    const hit = new THREE.Mesh(new THREE.SphereGeometry(4, 4, 4), new THREE.MeshBasicMaterial({ visible: false })); hit.position.set(s.x, s.gy + 20, s.y); hit.userData.i = i; scene.add(hit);
    castles.push({ s, g, el, hit, top: new THREE.Vector3(s.x, s.gy + 40, s.y), junction: true });
    return;
  }
  const c = s.owner == null ? ['#8a8478', '#5a574f'] : spec.colors(s.owner);
  const face = s.face;
  const g = makeCastle(s.tier || 1, c[0], c[1], i, s.riv ? 'riverTwins' : s.crossing_kind === 'pass' ? 'passGate' : pickVariant(s.tier || 1, s.terrain, i), biome(s.x, s.y)[0] > .4, biome(s.x, s.y)[4] > .4, s.riv); g.position.set(s.x, s.gy, s.y); g.rotation.y = s.riv ? -Math.atan2(s.riv.nz, s.riv.nx) : face; scene.add(g);
  let sea = -1; for (let k = 0; k < 16 && sea < 0; k++) { const a = k / 16 * 6.2832; for (let d = 160; d <= 520; d += 60) if (H(s.x + Math.sin(a) * d, s.y + Math.cos(a) * d) < SEA) { sea = a; break; } }
  if (sea >= 0 && !s.riv) { const dk = makeDock(s, sea); scene.add(dk); DOCKS.push(dk); }
  const el = document.createElement('div'); el.className = 'bn'; el.style.setProperty('--c', c[0]); setLabel(el, c[0], c[1], s.name, s.troops ?? '?'); labels.appendChild(el); s.cols = c;
  const hit = new THREE.Mesh(new THREE.SphereGeometry(g.userData.radius, 8, 8), new THREE.MeshBasicMaterial({ visible: false })); hit.position.set(s.x, s.gy + 50, s.y); hit.userData.i = i; scene.add(hit);
  const own = [[0, 1, .22], [1.02, 1.2, .85]].map(([r0, r1, op]) => { const m = new THREE.Mesh(drapedRing(s.x, s.y, s.pl * r0, s.pl * r1), new THREE.MeshBasicMaterial({ color: c[0], transparent: true, opacity: op, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2, side: THREE.DoubleSide })); m.renderOrder = 2; scene.add(m); return m; });
  castles.push({ s, g, el, hit, own, top: new THREE.Vector3(s.x, s.gy + g.userData.hgt + 14, s.y) }); el.style.pointerEvents = 'auto'; el.style.cursor = 'pointer'; el.onclick = () => select(i);
});
{
  const moatMat = new THREE.MeshStandardMaterial({ color: 0x1a5a74, roughness: .08, metalness: .1, transparent: true, opacity: .94, envMapIntensity: 1.6 });
  sites.forEach((s) => { if (!s.moat) return; const mo = s.moat; let geo; if (mo.pl) { const vo = planeVerts(mo.pl, mo.wd * .92), vi = planeVerts(mo.pl, mo.wd * .08), sh = new THREE.Shape(vo.map(([x, z]) => new THREE.Vector2(x, -z))); sh.holes.push(new THREE.Path(vi.map(([x, z]) => new THREE.Vector2(x, -z)))); geo = new THREE.ShapeGeometry(sh); } else geo = new THREE.RingGeometry(mo.r0 + mo.wd * .08, mo.r0 + mo.wd * .92, 64, 1); const m = new THREE.Mesh(geo, moatMat); m.rotation.x = -Math.PI / 2; m.position.set(s.x, s.gy - 1.4, s.y); m.receiveShadow = true; scene.add(m); });
  const posts = [], rails = [], hay = [];
  FIELDS.forEach(([fx0, fz0, fw, fd, ang, fenced]) => { const ca = Math.cos(ang), sa = Math.sin(ang), pt = (u, v) => [fx0 + u * ca - v * sa, fz0 + u * sa + v * ca]; const edges = [[-fw / 2, -fd / 2, fw / 2, -fd / 2], [fw / 2, -fd / 2, fw / 2, fd / 2], [fw / 2, fd / 2, -fw / 2, fd / 2], [-fw / 2, fd / 2, -fw / 2, -fd / 2]]; (fenced ? edges : []).forEach(([u0, v0, u1, v1], ei) => { const L = Math.hypot(u1 - u0, v1 - v0), n = Math.max(1, Math.round(L / 30)); for (let k = 0; k < n; k++) { const a0 = pt(u0 + (u1 - u0) * k / n, v0 + (v1 - v0) * k / n), a1 = pt(u0 + (u1 - u0) * (k + 1) / n, v0 + (v1 - v0) * (k + 1) / n), mx = (a0[0] + a1[0]) / 2, mz = (a0[1] + a1[1]) / 2, hh = hAt(mx, mz); if (hh < 3 || Math.hypot(mx - fx0, mz - fz0) < 0) continue; posts.push([a0[0], hAt(a0[0], a0[1]), a0[1]]); rails.push([mx, hh + 4.4, mz, Math.atan2(a1[1] - a0[1], a1[0] - a0[0]), Math.hypot(a1[0] - a0[0], a1[1] - a0[1])]); } }); for (let k = 0; k < (fenced ? 0 : 2); k++) { const p = pt((hash(k, 5) - .5) * fw * .7, (hash(k, 9) - .5) * fd * .7); hay.push([p[0], hAt(p[0], p[1]), p[1], hash(k, ang * 99)]); } });
  const pm = new THREE.InstancedMesh(new THREE.BoxGeometry(1.3, 6.5, 1.3), mWood, posts.length), rm = new THREE.InstancedMesh(new THREE.BoxGeometry(1, .8, .8), mWood, rails.length), d = new THREE.Object3D();
  posts.forEach((p, i) => { d.position.set(p[0], p[1] + 2.5, p[2]); d.rotation.set(0, 0, 0); d.scale.set(1, 1, 1); d.updateMatrix(); pm.setMatrixAt(i, d.matrix); });
  rails.forEach((p, i) => { d.position.set(p[0], p[1], p[2]); d.rotation.set(0, -p[3], 0); d.scale.set(p[4], 1, 1); d.updateMatrix(); rm.setMatrixAt(i, d.matrix); });
  
  [pm, rm].forEach((m) => { m.castShadow = true; m.receiveShadow = true; scene.add(m); });
}
{
  marks.push(['  castles+fields posts', performance.now()]);
  await stage('Sowing the meadows');
  const gc = document.createElement('canvas'); gc.width = 128; gc.height = 128; const g2 = gc.getContext('2d');
  for (let i = 0; i < 26; i++) { const x = 8 + hash(i, 1) * 112, h = 50 + hash(i, 2) * 70, lean = (hash(i, 3) - .5) * 40, w = 3 + hash(i, 4) * 4; const gr = g2.createLinearGradient(0, 128, 0, 128 - h); gr.addColorStop(0, '#3a5a22'); gr.addColorStop(.6, '#7aa23c'); gr.addColorStop(1, '#c4d27a'); g2.fillStyle = gr; g2.beginPath(); g2.moveTo(x - w, 128); g2.quadraticCurveTo(x + lean * .3, 128 - h * .6, x + lean, 128 - h); g2.quadraticCurveTo(x + lean * .3 + 2, 128 - h * .55, x + w, 128); g2.fill(); }
  const gtex = new THREE.CanvasTexture(gc); gtex.colorSpace = THREE.SRGBColorSpace;
  const gp = new THREE.PlaneGeometry(15, 12); gp.translate(0, 6, 0); const g90 = gp.clone(); g90.rotateY(Math.PI / 2); const g45 = gp.clone(); g45.rotateY(Math.PI / 4); const grassG = mergeGeometries([gp, g90, g45]);
  const gmat = windify(new THREE.MeshStandardMaterial({ map: gtex, alphaTest: .45, side: THREE.DoubleSide, roughness: 1 }));
  const pts = []; const GN = !RICH ? 0 : LO ? 12000 : Math.round(36000 * Math.min(2, Math.max(1, WS)));
  for (let i = 0; i < GN * 2 && pts.length < GN; i++) { const px = rnd() * W, pz = rnd() * W, h = H(px, pz); if (h < SEA + .02) continue; const el = (h - SEA) / (1 - SEA), m = Mo(px, pz); if (el > .45 || m < .22 || m > .78) continue; { const [gd, gf, , gsw, gsn] = biome(px, pz); if (gsn > .5 || gd > .6 || (gd > .3 && rnd() < .5) || (gf > .4 && rnd() < .55) || nearLake(px, pz, 1.3)) continue; } if (blockedAt(px, pz, 64)) continue; const [dr, kr] = rvq(px, pz); if (kr >= 0 && dr < RVW[kr] * 1.25) continue; const y = hAt(px, pz), sl = Math.abs(hAt(px + 8, pz) - y) + Math.abs(hAt(px, pz + 8) - y); if (sl > 7) continue; pts.push([px, y, pz, .7 + rnd() * .9, rnd()]); }
  marks.push(['    grass sampled', performance.now()]);
  const d = new THREE.Object3D(), col = new THREE.Color(); mkChunked(grassG, gmat, pts, (im, p, i) => { d.position.set(p[0], p[1] - .5, p[2]); d.rotation.y = p[4] * 6.28; d.scale.set(p[3], p[3] * (.7 + p[4] * .6), p[3]); d.updateMatrix(); im.setMatrixAt(i, d.matrix); { const gdd = biome(p[0], p[2])[0], k = .75 + p[4] * .3; col.setRGB(k * (1 + gdd * 1.1), k * (.95 + hash(i, 2) * .1) * (1 + gdd * .45), k * (.8 - gdd * .4)); im.setColorAt(i, col); } }, 10, false); const grassChunks = CHUNKS.slice(-100); scene.userData.grass = grassChunks;
  marks.push(['    grass meshed', performance.now()]);
  const cm = new THREE.Mesh(new THREE.PlaneGeometry(90000, 90000), new THREE.ShaderMaterial({ transparent: true, depthWrite: false, fog: false, side: THREE.DoubleSide, uniforms: { uTime }, vertexShader: 'varying vec2 vP; void main(){ vP = position.xy; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.); }', fragmentShader: `uniform float uTime; varying vec2 vP; ${NOISE_GLSL}
    void main(){ vec2 p = vP*.00022 + vec2(uTime*.0016, uTime*.0008); float n = fb2(p*1.7)*.62 + fb2(p*4.1+7.)*.38; float c = smoothstep(.5, .74, n); float edge = length(vP)/45000.; gl_FragColor = vec4(vec3(1.), c * .8 * (1. - smoothstep(.45, .98, edge))); }` }));
  cm.rotation.x = -Math.PI / 2; cm.position.set(W / 2, 4200, W / 2); cm.renderOrder = -1; scene.add(cm); scene.userData.clouds = cm;
  marks.push(['    clouds', performance.now()]);
  const ships = []; for (let i = 0; i < 5; i++) { const b = (() => { const boat = new THREE.Group(); const hull = new THREE.Shape(); hull.moveTo(-34, 6); hull.lineTo(34, 6); hull.lineTo(26, -4); hull.lineTo(-24, -4); hull.closePath(); const hg3 = new THREE.ExtrudeGeometry(hull, { depth: 14, bevelEnabled: false }); hg3.translate(0, 0, -7); const hm = new THREE.Mesh(hg3, mWood); hm.castShadow = true; boat.add(hm); const mast = new THREE.Mesh(new THREE.CylinderGeometry(.8, .8, 54, 5), mWood); mast.position.y = 32; boat.add(mast); const sail = new THREE.Mesh(new THREE.PlaneGeometry(32, 36), mSail); sail.position.set(0, 38, 0); sail.rotation.y = Math.PI / 2; sail.castShadow = true; boat.add(sail); boat.scale.setScalar(1.1); return boat; })(); let x, z, tries = 0; do { x = rnd() * W; z = rnd() * W; tries++; } while (H(x, z) > SEA * .6 && tries < 400); b.position.set(x, 1.2, z); scene.add(b); ships.push({ b, a: rnd() * 6.28, sp: .35 + rnd() * .3 }); }
  scene.userData.ships = ships;
}
{
  const em = []; castles.forEach((c, i) => { const g = c.g; em.push([c.s.x + (hash(i, 8) - .5) * 24, c.s.gy + 24, c.s.y + (hash(i, 9) - .5) * 24]); });
  const P = 10, base = new Float32Array(em.length * P * 3), ph = new Float32Array(em.length * P);
  em.forEach((e, k) => { for (let j = 0; j < P; j++) { const q = k * P + j; base[q*3] = e[0]; base[q*3+1] = e[1]; base[q*3+2] = e[2]; ph[q] = j / P + hash(k, j) * .05; } });
  const sg = new THREE.BufferGeometry(); sg.setAttribute('position', new THREE.BufferAttribute(base, 3)); sg.setAttribute('aPh', new THREE.BufferAttribute(ph, 1));
  const sc = document.createElement('canvas'); sc.width = sc.height = 64; const sx2 = sc.getContext('2d'), sgr = sx2.createRadialGradient(32, 32, 0, 32, 32, 32); sgr.addColorStop(0, 'rgba(255,255,255,.9)'); sgr.addColorStop(1, 'rgba(255,255,255,0)'); sx2.fillStyle = sgr; sx2.fillRect(0, 0, 64, 64);
  const smoke = new THREE.Points(sg, new THREE.ShaderMaterial({ transparent: true, depthWrite: false, uniforms: { uTime, map: { value: new THREE.CanvasTexture(sc) } }, vertexShader: `uniform float uTime; attribute float aPh; varying float vA; void main(){ float t = fract(uTime*.05 + aPh); vec3 p = position + vec3(sin(aPh*40.+uTime*.4)*10.*t + t*t*40., t*95., cos(aPh*31.)*7.*t); vec4 mv = modelViewMatrix * vec4(p,1.); gl_Position = projectionMatrix * mv; gl_PointSize = (10. + t*46.) * 520. / -mv.z; vA = (1.-t) * smoothstep(0.,.12,t) * .42; }`, fragmentShader: `uniform sampler2D map; varying float vA; void main(){ vec4 c = texture2D(map, gl_PointCoord); gl_FragColor = vec4(vec3(.78,.76,.72), c.a * vA); }` })); smoke.frustumCulled = false; scene.add(smoke); scene.userData.smoke = smoke;
  marks.push(['  grass built', performance.now()]);
  const shr = [], SG = new THREE.IcosahedronGeometry(1, 1); for (let i = 0, n = RICH ? 16000 : 4000; i < n; i++) { const px = rnd() * W, pz = rnd() * W, h = H(px, pz); if (h < SEA + .02) continue; const el = (h - SEA) / (1 - SEA); if (el > .5 || Mo(px, pz) < .25) continue; if (blockedAt(px, pz, 32)) continue; const [dr, kr] = rvq(px, pz); if ((kr >= 0 && dr < RVW[kr] * 1.4) || nearLake(px, pz, 1.25)) continue; shr.push([px, hAt(px, pz), pz, 4 + rnd() * 6, rnd()]); }
  const sm = new THREE.InstancedMesh(SG, windify(new THREE.MeshStandardMaterial({ roughness: 1 })), shr.length); sm.castShadow = false; sm.receiveShadow = true; const d = new THREE.Object3D(), col = new THREE.Color(); shr.forEach((a, i) => { d.position.set(a[0], a[1] + a[3] * .3, a[2]); d.rotation.y = a[4] * 6; d.scale.set(a[3], a[3] * .65, a[3] * (.8 + a[4] * .4)); d.updateMatrix(); sm.setMatrixAt(i, d.matrix); { const bdr = biome(a[0], a[2])[0]; col.setRGB(.07 + a[4] * .07 + bdr * .2, .13 + a[4] * .1 - (hash(i, 3) > .8 ? .04 : 0) + bdr * .05, .045 + a[4] * .04 + bdr * .02); } sm.setColorAt(i, col); }); scene.add(sm);
}
{
  const cells = []; for (let i = 0; i < BG * BG; i++) if (BIO[i * BS + 3] > .45) cells.push(i);
  if (cells.length) { const NM = Math.min(900, cells.length * 6), base = new Float32Array(NM * 3), ph = new Float32Array(NM); for (let k = 0; k < NM; k++) { const c = cells[Math.floor(rnd() * cells.length)], x = ((c % BG) + rnd()) / BG * W, z = (Math.floor(c / BG) + rnd()) / BG * W; base[k * 3] = x; base[k * 3 + 1] = 6; base[k * 3 + 2] = z; ph[k] = rnd(); }
    const mg2 = new THREE.BufferGeometry(); mg2.setAttribute('position', new THREE.BufferAttribute(base, 3)); mg2.setAttribute('aPh', new THREE.BufferAttribute(ph, 1));
    const mc = document.createElement('canvas'); mc.width = mc.height = 64; const mx = mc.getContext('2d'), mgr = mx.createRadialGradient(32, 32, 0, 32, 32, 32); mgr.addColorStop(0, 'rgba(255,255,255,.8)'); mgr.addColorStop(1, 'rgba(255,255,255,0)'); mx.fillStyle = mgr; mx.fillRect(0, 0, 64, 64);
    scene.add(Object.assign(new THREE.Points(mg2, new THREE.ShaderMaterial({ transparent: true, depthWrite: false, uniforms: { uTime, map: { value: new THREE.CanvasTexture(mc) } }, vertexShader: 'uniform float uTime; attribute float aPh; varying float vA; void main(){ float t = fract(uTime*.015 + aPh); vec3 p = position + vec3(sin(aPh*60.+uTime*.12)*40., t*34., cos(aPh*47.+uTime*.1)*40.); vec4 mv = modelViewMatrix * vec4(p,1.); gl_Position = projectionMatrix * mv; gl_PointSize = 360. * 520. / -mv.z; vA = (1.-abs(2.*t-1.)) * .16; }', fragmentShader: 'uniform sampler2D map; varying float vA; void main(){ vec4 c = texture2D(map, gl_PointCoord); gl_FragColor = vec4(vec3(.62,.7,.64), c.a * vA); }' })), { frustumCulled: false })); }
}
{
  const NF = 1800, base = new Float32Array(NF * 3), ph = new Float32Array(NF);
  for (let k = 0; k < NF; k++) { base[k * 3] = (rnd() - .5) * 3000; base[k * 3 + 1] = rnd() * 1000; base[k * 3 + 2] = (rnd() - .5) * 3000; ph[k] = rnd(); }
  const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.BufferAttribute(base, 3)); g.setAttribute('aPh', new THREE.BufferAttribute(ph, 1));
  const mat = new THREE.ShaderMaterial({ transparent: true, depthWrite: false, uniforms: { uTime, uC: { value: new THREE.Vector3() }, uA: { value: 0 } }, vertexShader: 'uniform float uTime; uniform vec3 uC; attribute float aPh; varying float vA; uniform float uA; void main(){ float y = mod(position.y - uTime * (60. + aPh * 40.), 1000.); vec3 p = uC + vec3(position.x + sin(uTime * .6 + aPh * 30.) * 24., y - 120., position.z + cos(uTime * .5 + aPh * 20.) * 24.); vec4 mv = modelViewMatrix * vec4(p, 1.); gl_Position = projectionMatrix * mv; gl_PointSize = clamp((3.2 + aPh * 3.) * 700. / -mv.z, 1.5, 7.); vA = uA * (.55 + aPh * .4); }', fragmentShader: 'varying float vA; void main(){ float d = length(gl_PointCoord - .5) * 2.; gl_FragColor = vec4(vec3(.96, .98, 1.), (1. - smoothstep(.4, 1., d)) * vA); }' });
  const pts = new THREE.Points(g, mat); pts.frustumCulled = false; pts.visible = false; scene.add(pts); scene.userData.snowfall = pts;
}
const ring = new THREE.Mesh(new THREE.TorusGeometry(1, .03, 6, 80), new THREE.MeshBasicMaterial({ color: 0xf5dc94, transparent: true, opacity: .95, depthWrite: false, fog: false })); ring.rotation.x = Math.PI / 2; ring.visible = false; scene.add(ring);
let sel = -1;
const TRAVEL_UPH = 10, RANGE = 840;
const dashTex = (() => { const c = document.createElement('canvas'); c.width = 64; c.height = 8; const g = c.getContext('2d'); g.fillStyle = '#fff'; g.fillRect(0, 0, 38, 8); const x = new THREE.CanvasTexture(c); x.wrapS = x.wrapT = THREE.RepeatWrapping; return x; })();
const overlays = []; let src = -1, etaPos = null;
const clearOverlays = () => { overlays.splice(0).forEach((m) => { scene.remove(m); m.geometry.dispose(); m.material.dispose(); }); etaPos = null; };
const ribbonLine = (pts, w, color, op = .95, solid = false) => { const pos = [], uvs = [], ind = []; let len = 0; pts.forEach((p, i) => { const a = pts[Math.max(0, i - 1)], b = pts[Math.min(pts.length - 1, i + 1)]; let tx = b.x - a.x, tz = b.z - a.z; const l = Math.hypot(tx, tz) || 1; tx /= l; tz /= l; if (i) len += Math.hypot(p.x - pts[i - 1].x, p.z - pts[i - 1].z); const y = hAt(p.x, p.z) + 3.5; pos.push(p.x - tz * w, y, p.z + tx * w, p.x + tz * w, y, p.z - tx * w); uvs.push(len / 70, 0, len / 70, 1); if (i < pts.length - 1) { const k = i * 2; ind.push(k, k + 2, k + 1, k + 1, k + 2, k + 3); } }); const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); g.setAttribute('uv', new THREE.Float32BufferAttribute(uvs, 2)); g.setIndex(ind); const m = new THREE.Mesh(g, new THREE.MeshBasicMaterial({ color, map: solid ? null : dashTex, transparent: true, opacity: op, depthWrite: false, fog: false, side: THREE.DoubleSide })); m.renderOrder = 6; m.frustumCulled = false; scene.add(m); overlays.push(m); return len; };
const circlePts = (x, z, r) => Array.from({ length: 161 }, (_, i) => ({ x: x + Math.cos(i / 160 * 6.2832) * r, z: z + Math.sin(i / 160 * 6.2832) * r }));
const selectRing = (i) => { sel = i; castles.forEach((c, k) => c.el.classList.toggle('sel', k === i)); const c = castles[i]; ring.visible = true; ring.position.set(c.s.x, c.s.gy + 4, c.s.y); };
function select(i) { selectRing(i); if (spec.onSelect) spec.onSelect(castles[i].s.id); }
const clearSel = () => { sel = -1; ring.visible = false; castles.forEach((c) => c.el.classList.remove('sel')); if (spec.onSelect) spec.onSelect(null); };

const armies = [];
function manFigure(body, skin, steel, dk, k, helm) {
  const m = new THREE.Group();
  const b = new THREE.Mesh(new THREE.CylinderGeometry(2.6, 3.2, 11, 8), body); b.position.y = 8; b.castShadow = true; m.add(b);
  const hd = new THREE.Mesh(new THREE.SphereGeometry(2.6, 8, 6), helm ? steel : skin); hd.position.y = 15.5; hd.castShadow = true; m.add(hd);
  const sp = new THREE.Mesh(new THREE.CylinderGeometry(.35, .35, 24, 4), dk); sp.position.set(3.5, 14, 0); m.add(sp);
  m.userData.phase = hash(k, 7) * 6.28; m.userData.spear = sp; return m;
}
function horseFigure(coat, cloth, skin, steel, dk, k) {
  const h = new THREE.Group(), cm = new THREE.MeshStandardMaterial({ color: coat, roughness: .85 });
  const bx = (w, hh, d, mat, x, y, z, rz = 0) => { const m = new THREE.Mesh(new THREE.BoxGeometry(w, hh, d), mat); m.position.set(x, y, z); m.rotation.z = rz; m.castShadow = true; h.add(m); return m; };
  bx(17, 8, 7, cm, 0, 12, 0); bx(7, 4, 7.4, cloth, -1, 14.2, 0); bx(5, 9, 4, cm, 9.5, 17, 0, -.5); bx(7, 4, 4, cm, 13.5, 20.5, 0, -.15); bx(1.4, 3, 1.4, cm, 11.5, 22.5, 1.4); bx(1.4, 3, 1.4, cm, 11.5, 22.5, -1.4); bx(2, 7, 1.4, cm, -9.5, 11, 0, .5);
  [[6, 2.6], [6, -2.6], [-6, 2.6], [-6, -2.6]].forEach(([x, z]) => bx(2.2, 8, 2.2, cm, x, 4, z));
  const r = manFigure(new THREE.MeshStandardMaterial({ color: cloth.color, roughness: .8 }), skin, steel, dk, k, true); r.position.set(-1, 8.5, 0); r.scale.setScalar(.85); r.rotation.y = 0; h.add(r);
  h.userData.phase = r.userData.phase; h.userData.spear = r.userData.spear; return h;
}
function ramFigure(dk, wood) {
  const g = new THREE.Group(), bx = (w, hh, d, mat, x, y, z, rz = 0) => { const m = new THREE.Mesh(new THREE.BoxGeometry(w, hh, d), mat); m.position.set(x, y, z); m.rotation.z = rz; m.castShadow = true; g.add(m); return m; };
  bx(34, 3, 14, wood, 0, 7, 0); [[-12, 6.5], [12, 6.5], [-12, -6.5], [12, -6.5]].forEach(([x, z]) => bx(2, 12, 2, dk, x, 14, z));
  bx(18, 1.6, 17, dk, 6, 21, 0, -.2); bx(18, 1.6, 17, dk, -6, 21, 0, .2);
  const log = new THREE.Mesh(new THREE.CylinderGeometry(2.4, 2.4, 40, 8), dk); log.rotation.z = Math.PI / 2; log.position.set(4, 13, 0); log.castShadow = true; g.add(log);
  const hd = new THREE.Mesh(new THREE.ConeGeometry(3.4, 6, 8), new THREE.MeshStandardMaterial({ color: 0x6a6f78, metalness: .6, roughness: .4 })); hd.rotation.z = -Math.PI / 2; hd.position.set(26, 13, 0); g.add(hd);
  [[-11, 8], [11, 8], [-11, -8], [11, -8]].forEach(([x, z]) => { const w = new THREE.Mesh(new THREE.CylinderGeometry(4.6, 4.6, 2, 10), dk); w.rotation.x = Math.PI / 2; w.position.set(x, 4.6, z); g.add(w); });
  return g;
}
function catapultFigure(dk, wood) {
  const g = new THREE.Group(), bx = (w, hh, d, mat, x, y, z, rz = 0) => { const m = new THREE.Mesh(new THREE.BoxGeometry(w, hh, d), mat); m.position.set(x, y, z); m.rotation.z = rz; m.castShadow = true; g.add(m); return m; };
  bx(30, 3, 12, wood, 0, 7, 0); bx(2.4, 18, 2.4, dk, -2, 17, 5); bx(2.4, 18, 2.4, dk, -2, 17, -5);
  const arm = bx(34, 2.2, 2.6, dk, 2, 21, 0, .55); arm.position.set(6, 24, 0);
  bx(7, 3, 6, wood, 20, 31, 0); bx(7, 6, 7, dk, -14, 16, 0);
  [[-9, 7.5], [9, 7.5], [-9, -7.5], [9, -7.5]].forEach(([x, z]) => { const w = new THREE.Mesh(new THREE.CylinderGeometry(4.6, 4.6, 2, 10), dk); w.rotation.x = Math.PI / 2; w.position.set(x, 4.6, z); g.add(w); });
  return g;
}
const COATS = [0x6b4423, 0x3c2a1c, 0x8a6a4a, 0xb8b0a0];
const armyGeoCache = new Map();
const armyMat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: .85 });
const bakeGroup = (grp) => { grp.updateMatrixWorld(true); const parts = []; grp.traverse((o) => { if (!o.isMesh) return; const g = o.geometry.clone(); g.applyMatrix4(o.matrixWorld); const c = o.material.color || new THREE.Color(0x888888); parts.push(paint(g, () => [c.r, c.g, c.b])); }); return mergeGeometries(parts); };
function armyGeos(col, col2) {
  const key = col + col2; let e = armyGeoCache.get(key); if (e) return e;
  const C = (hex) => { const c = new THREE.Color(hex); return [c.r, c.g, c.b]; };
  const cb = C(col), c2 = C(col2), skin = C(0xd4a17a), steel = C(0x9aa0a8), dkc = C(0x3a2a18), coat = C(0x6b4423);
  const col3 = (g, c) => paint(g, () => c);
  const manParts = (bodyC, dx = 0, dy = 0, sc = 1) => { const b = new THREE.CylinderGeometry(2.6, 3.2, 11, 8); b.translate(0, 8, 0); const hd = new THREE.SphereGeometry(2.6, 8, 6); hd.translate(0, 15.5, 0); const sp = new THREE.CylinderGeometry(.35, .35, 24, 4); sp.translate(3.5, 14, 0); return [b, hd, sp].map((g, k) => { col3(g, [bodyC, steel, dkc][k]); g.scale(sc, sc, sc); g.translate(dx, dy, 0); return g; }); };
  const man = mergeGeometries(manParts(cb));
  const bx = (w, h, d, c, x, y, z, rz = 0) => { const g = new THREE.BoxGeometry(w, h, d); g.rotateZ(rz); g.translate(x, y, z); return col3(g, c); };
  const horse = mergeGeometries([bx(17, 8, 7, coat, 0, 12, 0), bx(7, 4, 7.4, c2, -1, 14.2, 0), bx(5, 9, 4, coat, 9.5, 17, 0, -.5), bx(7, 4, 4, coat, 13.5, 20.5, 0, -.15), bx(1.4, 3, 1.4, coat, 11.5, 22.5, 1.4), bx(1.4, 3, 1.4, coat, 11.5, 22.5, -1.4), bx(2, 7, 1.4, coat, -9.5, 11, 0, .5), ...[[6, 2.6], [6, -2.6], [-6, 2.6], [-6, -2.6]].map(([x, z]) => bx(2.2, 8, 2.2, coat, x, 4, z)), ...manParts(c2, -1, 8.5, .85)]);
  if (!armyGeoCache.has('engines')) { const dk = new THREE.MeshStandardMaterial({ color: 0x3a2a18 }), wood = new THREE.MeshStandardMaterial({ color: 0x8a6a42 }); armyGeoCache.set('engines', { ram: bakeGroup(ramFigure(dk, wood)), cat: bakeGroup(catapultFigure(dk, wood)) }); }
  e = { man, horse, ...armyGeoCache.get('engines') }; armyGeoCache.set(key, e); return e;
}
const armyUnits = (n, tier) => (tier >= 2 ? { foot: 75, cav: 20, eng: 5 } : tier === 1 ? { foot: 40, cav: 10, eng: 0 } : { foot: typeof n === 'number' ? Math.max(1, Math.min(20, Math.round(n))) : 10, cav: 0, eng: 0 });
function makeArmy(col, col2, n, tier = 1, name = '') {
  const g = new THREE.Group(); const dk = new THREE.MeshStandardMaterial({ color: 0x3a2a18, roughness: .9 }); const flagRecs = [];
  const addFlag = (px, pz, hh) => { const p = new THREE.Mesh(new THREE.CylinderGeometry(1.6, 1.6, hh, 6), dk); p.position.set(px, hh / 2, pz); p.castShadow = true; g.add(p);
    const fg = new THREE.PlaneGeometry(36, 22, 10, 1), flagMat = new THREE.MeshStandardMaterial({ map: flagTex(col, col2), side: THREE.DoubleSide }), f = new THREE.Mesh(fg, flagMat); f.position.set(px + 18, hh - 12, pz); g.add(f); const fl = { fg, base: fg.attributes.position.array.slice() }; flags.push(fl); flagRecs.push(fl); return { fl, flagMat }; };
  const u = armyUnits(n, tier), geos = armyGeos(col, col2);
  const main = addFlag(0, 0, 74 + tier * 8);
  if (tier === 2) addFlag(-30, 14, 66);
  const cols = Math.max(2, Math.ceil(Math.sqrt(u.foot * 1.1))), rows = Math.ceil(u.foot / cols), half = (cols - 1) / 2 * 11, zMid = (rows - 1) / 2 * 12 - 10;
  const foot = new THREE.InstancedMesh(geos.man, armyMat, u.foot); foot.castShadow = true; foot.frustumCulled = false;
  const fpos = []; const tint = new THREE.Color();
  for (let k = 0; k < u.foot; k++) { fpos.push({ x: (k % cols - (cols - 1) / 2) * 11 + (hash(k, 1) - .5) * 4, z: Math.floor(k / cols) * 12 - 10, ph: hash(k, 7) * 6.28 }); const v = .85 + hash(k, 3) * .3; tint.setRGB(v, v, v); foot.setColorAt(k, tint); }
  g.add(foot);
  let cav = null; const cpos = [];
  if (u.cav) {
    cav = new THREE.InstancedMesh(geos.horse, armyMat, u.cav); cav.castShadow = true; cav.frustumCulled = false;
    for (let k = 0; k < u.cav; k++) { const side = k % 2 ? 1 : -1, idx = k >> 1, row = idx % 5, colN = Math.floor(idx / 5); cpos.push({ x: side * (half + 34 + colN * 22), z: (row - 2) * 17 + zMid, ph: hash(k, 17) * 6.28, side }); const v = .7 + hash(k, 5) * .6; tint.setRGB(v, v * (.92 + hash(k, 6) * .12), v * (.85 + hash(k, 9) * .2)); cav.setColorAt(k, tint); }
    g.add(cav);
  }
  for (let k = 0; k < u.eng; k++) { const m = new THREE.Mesh(k % 2 ? geos.cat : geos.ram, armyMat); m.castShadow = true; m.position.set((k - (u.eng - 1) / 2) * 50, 0, rows * 12 + 22); g.add(m); }
  if (tier >= 1) { const skin = new THREE.MeshStandardMaterial({ color: 0xd4a17a }), steel = new THREE.MeshStandardMaterial({ color: 0x9aa0a8, metalness: .6, roughness: .4 }); const ld = manFigure(new THREE.MeshStandardMaterial({ color: col2, roughness: .7 }), skin, steel, dk, 99, true); ld.scale.setScalar(1.3); ld.position.set(half + 24, 0, 0); const pl = new THREE.Mesh(new THREE.SphereGeometry(2.2, 6, 5), new THREE.MeshStandardMaterial({ color: col2 })); pl.position.set(0, 21, 0); ld.add(pl); g.add(ld); }
  scene.add(g); const el = document.createElement('div'); el.className = 'bn army'; el.style.setProperty('--c', col); setLabel(el, col, col2, name, n); labels.appendChild(el);
  g.scale.setScalar(.58); return { g, el, top: new THREE.Vector3(), fl: main.fl, flagMat: main.flagMat, cols: col + col2, n, name, tier, ukey: u.foot + '/' + u.cav + '/' + u.eng, foot, fpos, cav, cpos, flagRecs, lastAnim: -1 };
}
const _ad = new THREE.Object3D();
function animateArmy(ar, t) {
  const dx = cam.position.x - ar.g.position.x, dz = cam.position.z - ar.g.position.z;
  if (dx * dx + dz * dz > 4200 * 4200) return;
  if (ar.lastAnim >= 0 && t - ar.lastAnim < .033) return; ar.lastAnim = t;
  ar.fpos.forEach((p, i) => { _ad.position.set(p.x, Math.abs(Math.sin(t * 7 + p.ph)) * 1.8, p.z); _ad.rotation.set(0, 0, Math.sin(t * 3.5 + p.ph) * .05); _ad.updateMatrix(); ar.foot.setMatrixAt(i, _ad.matrix); });
  ar.foot.instanceMatrix.needsUpdate = true;
  if (ar.cav) { ar.cpos.forEach((p, i) => { _ad.position.set(p.x, Math.abs(Math.sin(t * 6 + p.ph)) * 1.4, p.z); _ad.rotation.set(0, 0, Math.sin(t * 3 + p.ph) * .03); _ad.updateMatrix(); ar.cav.setMatrixAt(i, _ad.matrix); }); ar.cav.instanceMatrix.needsUpdate = true; }
}
function killArmy(a) {
  scene.remove(a.g); a.el.remove(); armyList.splice(armyList.indexOf(a), 1);
  a.flagRecs.forEach((r) => { const k = flags.indexOf(r); if (k >= 0) flags.splice(k, 1); r.fg.dispose(); });
  a.foot.dispose(); if (a.cav) a.cav.dispose();
}

const mine = sites.filter((s) => s.mine);
const mapCenter = mine.length ? mine.reduce((a, s) => [a[0] + s.x / mine.length, a[1] + s.y / mine.length], [0, 0]) : [W / 2, W / 2];
const fogC = document.createElement('canvas'); fogC.width = fogC.height = 512; const fx = fogC.getContext('2d');
fx.fillStyle = 'rgba(4,6,12,.96)'; fx.fillRect(0, 0, 512, 512); fx.globalCompositeOperation = 'destination-out';
mine.forEach((s) => { const X = s.x / W * 512, Y = s.y / W * 512, r = 1500 / W * 512, gr = fx.createRadialGradient(X, Y, r * .55, X, Y, r); gr.addColorStop(0, 'rgba(0,0,0,1)'); gr.addColorStop(1, 'rgba(0,0,0,0)'); fx.fillStyle = gr; fx.fillRect(X - r, Y - r, r * 2, r * 2); });
const fogPlane = new THREE.Mesh(new THREE.PlaneGeometry(W, W), new THREE.MeshBasicMaterial({ map: new THREE.CanvasTexture(fogC), transparent: true, depthWrite: false, fog: false })); fogPlane.rotation.x = -Math.PI / 2; fogPlane.position.set(W / 2, HMAX + 120, W / 2); fogPlane.renderOrder = 10; fogPlane.visible = false; scene.add(fogPlane);

const controls = new OrbitControls(cam, renderer.domElement);
controls.mouseButtons = { LEFT: THREE.MOUSE.PAN, MIDDLE: THREE.MOUSE.DOLLY, RIGHT: THREE.MOUSE.ROTATE };
controls.touches = { ONE: THREE.TOUCH.PAN, TWO: THREE.TOUCH.DOLLY_ROTATE };
controls.screenSpacePanning = false; controls.enableDamping = true; controls.dampingFactor = .09; controls.minDistance = 230; controls.maxDistance = Math.max(22000, W * 2.2); controls.maxPolarAngle = 1.35; controls.panSpeed = 1.1;
controls.target.set(mapCenter[0], 80, mapCenter[1]);
const setView = (polar, dist) => { const t = controls.target, az = controls.getAzimuthalAngle(); cam.position.set(t.x + dist * Math.sin(polar) * Math.sin(az), t.y + dist * Math.cos(polar), t.z + dist * Math.sin(polar) * Math.cos(az)); };
setView(1.0, 2600); let tween = null;
const unlock = () => { controls.minPolarAngle = 0; controls.maxPolarAngle = 1.35; };
const goPolar = (p) => { unlock(); tween = { from: controls.getPolarAngle(), to: p, t: 0, d: cam.position.distanceTo(controls.target), lock: p < .01 }; };
$('bflat').onclick = (e) => { goPolar(0.0001); e.target.classList.add('on'); $('b3d').classList.remove('on'); };
$('b3d').onclick = (e) => { goPolar(1.0); e.target.classList.add('on'); $('bflat').classList.remove('on'); };
$('bshadow').onclick = (e) => { sun.castShadow = !sun.castShadow; e.target.classList.toggle('on', sun.castShadow); };
if ($('bao')) $('bao').onclick = (e) => { sao.enabled = !sao.enabled; e.target.classList.toggle('on', sao.enabled); };

const ray = new THREE.Raycaster(), mouse = new THREE.Vector2(); let down = null;
renderer.domElement.addEventListener('pointerdown', (e) => { down = [e.clientX, e.clientY]; });
renderer.domElement.addEventListener('pointerup', (e) => { if (!down || Math.hypot(e.clientX - down[0], e.clientY - down[1]) > 5) return; const rc = renderer.domElement.getBoundingClientRect(); mouse.set((e.clientX - rc.left) / rc.width * 2 - 1, -((e.clientY - rc.top) / rc.height) * 2 + 1); ray.setFromCamera(mouse, cam); const hit = ray.intersectObjects(castles.map((c) => c.hit))[0]; if (hit && !castles[hit.object.userData.i].junction) select(hit.object.userData.i); else clearSel(); });

const composer = new EffectComposer(renderer, new THREE.WebGLRenderTarget(host.clientWidth, host.clientHeight, { samples: LO ? 0 : 2, type: THREE.HalfFloatType }));
composer.addPass(new RenderPass(scene, cam));
const sao = RICH ? new X.SAO(scene, cam) : { params: {}, resolution: new THREE.Vector2(), enabled: false }; sao.params.saoBias = .45; sao.params.saoIntensity = .012; sao.params.saoScale = 700; sao.params.saoKernelRadius = 28; sao.params.saoBlurRadius = 6; sao.resolution.set(Math.round(host.clientWidth / 3), Math.round(host.clientHeight / 3)); sao.enabled = false;
if (RICH) { composer.addPass(sao); composer.addPass(new X.Bloom(new THREE.Vector2(host.clientWidth, host.clientHeight), .28, .7, .88)); }

composer.addPass(new ShaderPass({ uniforms: { tDiffuse: { value: null } }, vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.); }', fragmentShader: `uniform sampler2D tDiffuse; varying vec2 vUv;
  void main(){ vec4 c = texture2D(tDiffuse, vUv); vec2 d = vUv - .5; float v = smoothstep(.95, .25, length(d * vec2(1.15, 1.0)));
    c.rgb = mix(vec3(dot(c.rgb, vec3(.299,.587,.114))), c.rgb, .94); c.rgb *= vec3(1.04, 1.0, .94); c.rgb = (c.rgb - .5) * 1.06 + .5; c.rgb *= mix(.62, 1., v); gl_FragColor = c; }` }));
composer.addPass(new OutputPass());
const doResize = () => { const w = host.clientWidth, h = host.clientHeight; if (!w || !h) return; renderer.setSize(w, h); composer.setSize(w, h); cam.aspect = w / h; cam.updateProjectionMatrix(); sao.resolution.set(Math.round(w / 3), Math.round(h / 3)); };
const ro = new ResizeObserver(doResize); ro.observe(host);

const v = new THREE.Vector3(); const clock = new THREE.Clock(); const lastShadowT = new THREE.Vector3(1e9, 0, 0); let frameNo = 0;
function frame() {
  if (!running) return; requestAnimationFrame(frame); const dt = clock.getDelta(), t = clock.elapsedTime; uTime.value = t; lakeN.offset.set(t * .012, t * .008); if (!RICH) water.material.normalMap.offset.set(t * .006, t * .0035); flowTex.offset.y = -t * .35;
  if (tween) { tween.t = Math.min(1, tween.t + .035); const k = tween.t * tween.t * (3 - 2 * tween.t), p = tween.from + (tween.to - tween.from) * k; setView(Math.max(.0001, p), tween.d); if (tween.t >= 1) { if (tween.lock) { controls.minPolarAngle = controls.maxPolarAngle = .0001; } tween = null; } }
  controls.update();
  if (spec.onFrame) spec.onFrame(t, dt, cam, controls);
  (scene.userData.ships || []).forEach((s) => { const nx = s.b.position.x + Math.sin(s.a) * s.sp, nz = s.b.position.z + Math.cos(s.a) * s.sp; if (H(nx, nz) < SEA * .75) { s.b.position.x = nx; s.b.position.z = nz; } else s.a += 1.2 + Math.random(); s.b.rotation.y = s.a - Math.PI / 2; s.b.position.y = 1.2 + Math.sin(t * 1.6 + s.a * 5) * 1.1; s.b.rotation.z = Math.sin(t * 1.3 + s.a) * .04; });
  const tg = controls.target; { const mv = tg.distanceTo(lastShadowT); if (mv > 90 || frameNo < 3) { renderer.shadowMap.needsUpdate = true; lastShadowT.copy(tg); } frameNo++; }
  sun.position.set(tg.x + sunDir.x * 6000, tg.y + sunDir.y * 6000, tg.z + sunDir.z * 6000); sun.target.position.copy(tg);
  armyList.forEach((ar) => animateArmy(ar, t));
  updateFx(dt, t); updateSieges(dt, t); { const pl = .55 + .45 * Math.sin(t * 6); for (const c of castles) if (c.threat && c.own) { c.own[1].material.opacity = pl; c.own[0].material.opacity = .22 + .16 * pl; } }
  flags.forEach((f) => { const a = f.fg.attributes.position.array; for (let i = 0; i < a.length; i += 3) { const x = f.base[i] + 17; a[i + 2] = Math.sin(t * 4 + x * .22) * (x * .09); } f.fg.attributes.position.needsUpdate = true; });
  if (ring.visible) ring.scale.setScalar(castles[sel].g.userData.radius * (1.2 + Math.sin(t * 3) * .03));
  if (frameNo % 4 === 0) updateTiles(false);
  dashTex.offset.x -= dt * .5;
  { const dd2 = cam.position.distanceTo(controls.target), near = dd2 < 7800, ck = Math.max(1, Math.min(4.2, dd2 / 5600)); castles.forEach((c) => { if (c.junction) { c.g.visible = near; return; } c.g.visible = true; c.g.scale.setScalar(ck); c.top.y = c.s.gy + (c.g.userData.hgt + 14) * ck; }); DOCKS.forEach((d) => { d.visible = near; }); if (scene.userData.pass) scene.userData.pass.visible = dd2 < 7000; if (scene.userData.smoke) scene.userData.smoke.visible = near; }
  { const sf = scene.userData.snowfall; if (sf) { const sn = biome(controls.target.x, controls.target.z)[4], a = Math.min(1, Math.max(0, (sn - .2) * 1.6)) * (cam.position.distanceTo(controls.target) < 4200 ? .9 : 0); sf.material.uniforms.uA.value = a; sf.material.uniforms.uC.value.copy(controls.target); sf.visible = a > .02; } }
  { const dd1 = cam.position.distanceTo(controls.target), op = Math.min(.9, Math.max(0, (dd1 - 5000) / 3500)); stratMat.opacity = op; STRAT.forEach((m) => { m.visible = op > .01; }); }
  { const dd0 = cam.position.distanceTo(controls.target), gx = controls.target.x, gz = controls.target.z, cs = CSZ, lim = 3000 + dd0 * .5, nl = 1000 + dd0 * .3; CHUNKS.forEach((im) => { const c = im.boundingSphere && im.boundingSphere.center; if (!c) return; const d = Math.hypot(c.x - gx, c.z - gz); im.visible = RICH ? (im.userData.tree ? (im.userData.far ? (dd0 >= 8500 || (d > nl - cs * .6 && d < lim * 1.9 + cs)) : (dd0 < 8500 && d < nl + cs)) : d < 4200 + cs) : (im.userData.tree ? (dd0 >= 8500 || d < lim * 1.9 + cs) : d < 4200 + cs); }); }
  if (scene.userData.clouds) scene.userData.clouds.visible = cam.position.y < 3400;
  { const dd0 = cam.position.distanceTo(controls.target); scene.fog.density = .000068 * (spec.fogMul || 1) * (spec.fogMul ? 1 : Math.pow(Math.min(1, 3600 / dd0), 2.2)); }
  const flat = controls.getPolarAngle() < .35, dist = cam.position.distanceTo(controls.target), far = dist > 5200;
  const pl = (el, p) => { v.copy(p).project(cam); if (v.z > 1) { el.style.display = 'none'; return; } el.style.display = ''; el.style.transform = `translate(${(v.x * .5 + .5) * host.clientWidth}px,${(-v.y * .5 + .5) * host.clientHeight}px) translate(-10px,-100%)`; };
  { const boxes = [], hit = (b) => boxes.some((o) => b[0] < o[2] && b[2] > o[0] && b[1] < o[3] && b[3] > o[1]); const big = far || flat;
    castles.map((c, i) => { v.copy(flat ? new THREE.Vector3(c.s.x, c.s.gy + 40, c.s.y) : c.top).project(cam); return { c, i, ok: v.z < 1 && Math.abs(v.x) < 1.1 && Math.abs(v.y) < 1.1, x: (v.x * .5 + .5) * host.clientWidth, y: (-v.y * .5 + .5) * host.clientHeight, pri: (i === sel ? 1000 : 0) + (c.s.mine ? 100 : 0) + (c.s.tier || 1) * 5 }; }).sort((p, q) => q.pri - p.pri).forEach((o) => { const el = o.c.el; if (o.c.junction || !o.ok) { el.style.display = 'none'; return; } const sw = big ? 34 : 25, h = big ? 39 : 29, fw = sw + 8 + o.c.s.name.length * (big ? 8.2 : 7.2) + (big ? 58 : 50); const bf = [o.x - 10, o.y - h, o.x - 10 + fw, o.y], bs = [o.x - 10, o.y - h, o.x - 10 + sw, o.y]; el.classList.toggle('big', big); el.style.transform = `translate(${o.x}px,${o.y}px) translate(-10px,-100%)`; if (!hit(bf)) { el.style.display = ''; el.classList.remove('compact'); boxes.push(bf); } else if (!hit(bs)) { el.style.display = ''; el.classList.add('compact'); boxes.push(bs); } else el.style.display = 'none'; }); }
  armyList.forEach((a) => pl(a.el, a.top));
  if (ovSpec) { const b = ovBucketNow(); if (b !== ovBucket) { ovBucket = b; buildOverlays(ovSpec); } ovBadges.forEach((q) => pl(q.el, q.p)); }
  composer.render();
}

const fxs = [];
function fightSide(col, n, tier = 0) {
  const body = new THREE.MeshStandardMaterial({ color: col, roughness: .8 }), skin = new THREE.MeshStandardMaterial({ color: 0xd4a17a }), steel = new THREE.MeshStandardMaterial({ color: 0x9aa0a8, metalness: .6, roughness: .4 }), dk = new THREE.MeshStandardMaterial({ color: 0x3a2a18, roughness: .9 });
  const g = new THREE.Group(), men = [], per = Math.min(4, n);
  for (let k = 0; k < n; k++) { const m = manFigure(body, skin, steel, dk, k, k % 2); m.position.set(-Math.floor(k / per) * 10, 0, (k % per - (per - 1) / 2) * 12); g.add(m); men.push(m); }
  if (tier >= 1) { const cloth = new THREE.MeshStandardMaterial({ color: col, roughness: .8 }); for (let k = 0; k < tier * 2; k++) { const hz = horseFigure(COATS[k % 4], cloth, skin, steel, dk, 50 + k); hz.position.set(-30 - Math.floor(k / 2) * 18, 0, (k % 2 ? 1 : -1) * 34); g.add(hz); men.push(hz); } }
  if (tier >= 2) { const wood = new THREE.MeshStandardMaterial({ color: 0x8a6a42, roughness: .9 }), ct = catapultFigure(dk, wood); ct.position.set(-62, 0, 0); ct.scale.setScalar(.8); g.add(ct); }
  return { g, men };
}
function playBattle(d) {
  if (fxs.length >= 4) return;
  const g = new THREE.Group(); g.position.set(d.x, hAt(d.x, d.z), d.z); g.rotation.y = d.angle || 0; g.scale.setScalar(.7);
  const A = fightSide(d.colA[0], [3, 6, 10][d.tierA ?? 1], d.tierA ?? 1), B = fightSide(d.colB[0], [3, 6, 10][d.tierB ?? 1], d.tierB ?? 1);
  B.g.rotation.y = Math.PI; g.add(A.g, B.g);
  const sm = new THREE.MeshBasicMaterial({ color: 0xffe08a }), sparks = [];
  for (let i = 0; i < 18; i++) { const sMesh = new THREE.Mesh(new THREE.BoxGeometry(2.4, 2.4, 2.4), sm); sMesh.visible = false; g.add(sMesh); sparks.push({ m: sMesh, v: new THREE.Vector3(), life: 0 }); }
  const dust = [0, 1, 2, 3].map(() => { const m = new THREE.Mesh(new THREE.SphereGeometry(13, 10, 8), new THREE.MeshBasicMaterial({ color: 0xb59c78, transparent: true, opacity: 0, depthWrite: false })); m.position.set((Math.random() - .5) * 36, 9, (Math.random() - .5) * 36); g.add(m); return m; });
  const wc = d.winner === 0 ? d.colA[0] : d.colB[0], wg = new THREE.Group();
  const pole = new THREE.Mesh(new THREE.CylinderGeometry(1.3, 1.3, 78, 6), new THREE.MeshStandardMaterial({ color: 0x3a2a18 })); pole.position.y = 39; wg.add(pole);
  const fl = new THREE.Mesh(new THREE.PlaneGeometry(34, 21), new THREE.MeshStandardMaterial({ color: wc, side: THREE.DoubleSide })); fl.position.set(17, 64, 0); wg.add(fl); wg.scale.y = .001; g.add(wg);
  scene.add(g); fxs.push({ g, A, B, sparks, dust, wg, win: d.winner, t0: clock.elapsedTime, dur: 5 });
}
function updateFx(dt, t) {
  for (let i = fxs.length - 1; i >= 0; i--) {
    const f = fxs[i], a = t - f.t0;
    const adv = Math.min(1, a / 1.3), e = adv * adv * (3 - 2 * adv);
    f.A.g.position.x = -100 + 84 * e; f.B.g.position.x = 100 - 84 * e;
    [f.A, f.B].forEach((s, si) => s.men.forEach((m) => {
      const sp = m.userData.spear;
      if (a < 1.3) { m.position.y = Math.abs(Math.sin(a * 9 + m.userData.phase)) * 1.8; }
      else if (a < 3.2) { m.position.y = Math.abs(Math.sin(a * 14 + m.userData.phase)) * 2.4; m.rotation.z = Math.sin(a * 16 + m.userData.phase) * .16; sp.rotation.z = -1.15 + Math.sin(a * 13 + m.userData.phase) * .35; }
      else if (si !== f.win) { const k = Math.min(1, (a - 3.2) / .8); m.rotation.z = k * 1.45 * (m.userData.phase > 3.1 ? 1 : -1); m.position.y = -k * 4; sp.rotation.z = -1.15 + k * 1.1; }
      else { m.position.y *= .85; m.rotation.z *= .85; sp.rotation.z = -.05; }
    }));
    if (a > 1.25 && a < 3.2 && Math.random() < .6) { const sp = f.sparks.find((q) => q.life <= 0); if (sp) { sp.m.position.set((Math.random() - .5) * 10, 8 + Math.random() * 12, (Math.random() - .5) * 30); sp.v.set((Math.random() - .5) * 90, 40 + Math.random() * 70, (Math.random() - .5) * 90); sp.life = .45 + Math.random() * .3; sp.m.visible = true; } }
    f.sparks.forEach((sp) => { if (sp.life <= 0) return; sp.life -= dt; sp.m.position.addScaledVector(sp.v, dt); sp.v.y -= 140 * dt; sp.m.scale.setScalar(Math.max(.1, sp.life * 1.5)); if (sp.life <= 0) sp.m.visible = false; });
    const dOp = Math.max(0, Math.min(1, (a - 1.25) / .6)) * Math.max(0, 1 - Math.max(0, a - 3.2) / 1.5) * .42;
    f.dust.forEach((m, k) => { m.material.opacity = dOp; m.scale.setScalar(.7 + Math.max(0, a - 1.2) * (.45 + k * .08)); m.position.y = 9 + Math.max(0, a - 1.2) * 4; });
    if (a > 3.4) { const k = Math.min(1, (a - 3.4) / .7); f.wg.scale.y = Math.max(.001, k); }
    if (a > f.dur) { scene.remove(f.g); f.g.traverse((o) => { if (o.geometry) o.geometry.dispose(); if (o.material) o.material.dispose(); }); fxs.splice(i, 1); }
  }
}
const puffs = [], sieges = new Map();
const puffTex = (() => { const c = document.createElement('canvas'); c.width = c.height = 64; const x = c.getContext('2d'), g = x.createRadialGradient(32, 32, 2, 32, 32, 30); g.addColorStop(0, 'rgba(255,255,255,1)'); g.addColorStop(.5, 'rgba(255,255,255,.55)'); g.addColorStop(1, 'rgba(255,255,255,0)'); x.fillStyle = g; x.fillRect(0, 0, 64, 64); return new THREE.CanvasTexture(c); })();
const tentGeo = new THREE.ConeGeometry(14, 19, 4), boxGeo = new THREE.BoxGeometry(1, 1, 1), ballGeo = new THREE.SphereGeometry(4.2, 8, 6), flameGeo = new THREE.ConeGeometry(3.4, 9, 6), flashGeo = new THREE.SphereGeometry(1, 10, 8);
const stoneMat = new THREE.MeshStandardMaterial({ color: 0x4a4640, roughness: .9 });
function spawnPuff(x, y, z, o) {
  if (puffs.length > 140) return;
  const m = new THREE.Sprite(new THREE.SpriteMaterial({ map: puffTex, color: o.col ?? 0x58534c, transparent: true, opacity: o.op ?? .5, depthWrite: false }));
  m.position.set(x, y, z); m.scale.setScalar((o.size ?? 8) * 2); scene.add(m);
  puffs.push({ m, vy: o.rise ?? 14, vx: o.vx ?? 5, life: o.life ?? 4, age: 0, size: o.size ?? 8, grow: o.grow ?? 2, op: o.op ?? .5 });
}
function updatePuffs(dt) {
  for (let i = puffs.length - 1; i >= 0; i--) {
    const p = puffs[i]; p.age += dt; const k = p.age / p.life;
    if (k >= 1) { scene.remove(p.m); p.m.material.dispose(); puffs.splice(i, 1); continue; }
    p.m.position.y += p.vy * dt; p.m.position.x += p.vx * dt; p.m.scale.setScalar(p.size * 2 * (1 + k * p.grow)); p.m.material.opacity = p.op * (1 - k) * Math.min(1, p.age * 3);
  }
}
function trebuchet(dk, wood) {
  const g = new THREE.Group(), bx = (w, h, d, mat, x, y, z, parent = g) => { const m = new THREE.Mesh(boxGeo, mat); m.scale.set(w, h, d); m.position.set(x, y, z); m.castShadow = true; parent.add(m); return m; };
  bx(46, 4, 26, wood, 0, 2, 0); [-10, 10].forEach((z) => { bx(4, 40, 3.5, dk, -6, 22, z).rotation.z = .1; bx(4, 40, 3.5, dk, 6, 22, z).rotation.z = -.1; });
  const ax = new THREE.Mesh(new THREE.CylinderGeometry(1.6, 1.6, 30, 6), dk); ax.rotation.x = Math.PI / 2; ax.position.y = 40; g.add(ax);
  const pivot = new THREE.Group(); pivot.position.y = 40; g.add(pivot);
  bx(82, 3.4, 3.4, wood, -21, 0, 0, pivot); bx(13, 15, 13, dk, 19, -9, 0, pivot);
  const ball = new THREE.Mesh(ballGeo, stoneMat); ball.position.set(-60, -3, 0); pivot.add(ball);
  const rope = bx(2, 2, 2, dk, -60, -1, 0, pivot); rope.visible = false;
  g.scale.setScalar(1.15); return { g, pivot, ball };
}
function makeSiege(d) {
  const s = castles[siteIdx.get(d.id)].s, g = new THREE.Group(), mats = [], flagRecs = [];
  const col = new THREE.Color(d.cols[0]), col2 = new THREE.Color(d.cols[1]);
  const dk = new THREE.MeshStandardMaterial({ color: 0x3a2a18, roughness: .9 }), wood = new THREE.MeshStandardMaterial({ color: 0x8a6a42, roughness: .9 }), cloth = new THREE.MeshStandardMaterial({ color: col, roughness: .85 }), canvas = new THREE.MeshStandardMaterial({ color: 0xd8c9a0, roughness: .9 });
  mats.push(dk, wood, cloth, canvas);
  let nn = null, nd = 1e9; sites.forEach((q) => { if (q === s) return; const dd = Math.hypot(q.x - s.x, q.y - s.y); if (dd < nd) { nd = dd; nn = q; } });
  const CS = .68, a0 = nn ? Math.atan2(s.y - nn.y, s.x - nn.x) : hash(d.id, 11) * 6.283, R = s.pl + 75, cx = s.x + Math.cos(a0) * R, cz = s.y + Math.sin(a0) * R;
  const place = (o, x, z, dy = 0) => { o.position.set(x, hAt(x, z) + dy, z); g.add(o); return o; };
  const nt = [3, 5, 8][d.tier];
  for (let k = 0; k < nt; k++) { const ang = k / nt * 6.283 + hash(d.id, k) * .5, r = (34 + hash(d.id, k + 20) * 22) * CS, t = new THREE.Mesh(tentGeo, k % 2 ? canvas : cloth); t.rotation.y = .785 + ang; t.scale.setScalar(CS); t.castShadow = true; place(t, cx + Math.cos(ang) * r, cz + Math.sin(ang) * r, 9.5 * CS); }
  const fire = new THREE.Mesh(flameGeo, new THREE.MeshBasicMaterial({ color: 0xff9a3c })); mats.push(fire.material); place(fire, cx, cz, 6 * CS);
  for (let k = 0; k < 4; k++) { const lg = new THREE.Mesh(boxGeo, dk); lg.scale.set(9 * CS, 2 * CS, 2 * CS); lg.rotation.y = k * .785; place(lg, cx, cz, 1.5 * CS); }
  const skin = new THREE.MeshStandardMaterial({ color: 0xd4a17a }), steel = new THREE.MeshStandardMaterial({ color: 0x9aa0a8, metalness: .6, roughness: .4 }); mats.push(skin, steel);
  for (let k = 0; k < [2, 4, 6][d.tier]; k++) { const ang = k * 1.1 + 1, m = manFigure(cloth, skin, steel, dk, k + 70, k % 2); m.rotation.y = -ang + 1.5; m.scale.setScalar(CS); place(m, cx + Math.cos(ang) * 17 * CS, cz + Math.sin(ang) * 17 * CS); }
  { const px = cx + Math.cos(a0 + .5) * 52 * CS, pz = cz + Math.sin(a0 + .5) * 52 * CS, pole = new THREE.Mesh(new THREE.CylinderGeometry(1.5, 1.5, 78, 6), dk); pole.position.y = 39; const fg = new THREE.PlaneGeometry(40, 24, 10, 1), fm = new THREE.MeshStandardMaterial({ map: flagTex(d.cols[0], d.cols[1]), side: THREE.DoubleSide }), f = new THREE.Mesh(fg, fm); f.position.set(20, 64, 0); mats.push(fm); const bg = new THREE.Group(); bg.add(pole, f); bg.rotation.y = -a0; bg.scale.setScalar(CS); place(bg, px, pz); const rec = { fg, base: fg.attributes.position.array.slice() }; flags.push(rec); flagRecs.push(rec); }
  const trebs = [];
  for (let k = 0; k < [1, 1, 2][d.tier]; k++) {
    const ang = a0 + (k ? -1 : 1) * .3, tx = s.x + Math.cos(ang) * (s.pl + 45), tz = s.y + Math.sin(ang) * (s.pl + 45), tb = trebuchet(dk, wood); tb.g.scale.setScalar(.8);
    tb.g.rotation.y = Math.atan2(-(s.y - tz), s.x - tx); place(tb.g, tx, tz); trebs.push({ ...tb, off: k * 2.7 + hash(d.id, 5) * 3, fired: false, ang });
  }
  scene.add(g);
  return { g, mats, flagRecs, trebs, fire, cx, cz, s, tier: d.tier, cols: d.cols[0] + d.cols[1], level: d.level, acc: 0, cacc: 0, shots: [], fires: [] };
}
function removeSiege(sg) {
  droopFlag(sg, 0);
  for (let k = 0; k < 7; k++) spawnPuff(sg.cx + (Math.random() - .5) * 70, hAt(sg.cx, sg.cz) + 10 + Math.random() * 14, sg.cz + (Math.random() - .5) * 70, { size: 10, rise: 22 + Math.random() * 12, life: 3 + Math.random() * 1.5, col: k % 2 ? 0x8a857c : 0x3a3733, op: .6, grow: 2.4, vx: 8 });
  scene.remove(sg.g); sg.mats.forEach((m) => m.dispose()); sg.flagRecs.forEach((r) => { const i = flags.indexOf(r); if (i >= 0) flags.splice(i, 1); r.fg.dispose(); });
  sg.shots.forEach((q) => { scene.remove(q.m); q.m.material?.dispose?.(); }); sg.fires.forEach((q) => { scene.remove(q); q.material.dispose(); });
}
const _v = new THREE.Vector3();
function droopFlag(sg, a) {
  const tn = castles[siteIdx.get(sg.s.id)].g.userData.tint; if (!tn || !tn.fl) return;
  [[tn.fl, 26], [tn.stripe3, 26.5]].forEach(([m, dy]) => { m.rotation.z = -a; m.position.set(17 * Math.cos(a), tn.top + dy - 17 * Math.sin(a), m.position.z); });
  const el = castles[siteIdx.get(sg.s.id)].el; if (el) el.classList.toggle('starving', a > .3);
}
function updateSieges(dt, t) {
  updatePuffs(dt);
  sieges.forEach((sg) => {
    const s = sg.s, lv = sg.level; sg.droop = (sg.droop || 0) + (Math.max(0, lv - .25) * 1.5 - (sg.droop || 0)) * Math.min(1, dt * 2); droopFlag(sg, sg.droop); const dcam = Math.hypot(cam.position.x - s.x, cam.position.z - s.y), show = dcam < 9000;
    sg.g.visible = show; sg.fires.forEach((m) => { m.visible = show; });
    if (dcam > 5000) return;
    sg.fire.scale.set((.85 + Math.sin(t * 17 + sg.cx) * .18) * .55, (.9 + Math.sin(t * 23) * .25) * .55, (.85 + Math.sin(t * 19) * .18) * .55);
    sg.cacc += dt; if (sg.cacc > .7) { sg.cacc = 0; spawnPuff(sg.cx, hAt(sg.cx, sg.cz) + 14, sg.cz, { size: 7, rise: 20, life: 3.6, col: 0xa8a39a, op: .55, grow: 2.4, vx: 6 }); }
    sg.acc += dt; const gap = 1.1 - lv * .8; if (sg.acc > gap) { sg.acc = 0; const a = Math.random() * 6.283, r = s.pl * (.2 + Math.random() * .3), top = [0, 52, 72, 92][s.tier || 1] * CF; spawnPuff(s.x + Math.cos(a) * r, s.gy + top, s.y + Math.sin(a) * r, { size: 16 + lv * 12, rise: 24, life: 5.6, col: lv > .5 ? 0x24211e : 0x77726a, op: .6 + lv * .3, grow: 2, vx: 9 }); }
    const nf = Math.floor(lv * 3);
    while (sg.fires.length < nf) { const a = sg.fires.length * 2.1 + hash(s.id, 9) * 6, r = s.pl * .42, m = new THREE.Mesh(flameGeo, new THREE.MeshBasicMaterial({ color: 0xff7a22 })); m.scale.setScalar(2.2); m.position.set(s.x + Math.cos(a) * r, s.gy + [0, 46, 64, 84][s.tier || 1] * CF, s.y + Math.sin(a) * r); scene.add(m); sg.fires.push(m); }
    sg.fires.forEach((m, i) => { m.scale.set(2 + Math.sin(t * 15 + i * 2) * .4, 2.4 + Math.sin(t * 21 + i) * .6, 2 + Math.sin(t * 17 + i) * .4); });
    sg.trebs.forEach((tb) => {
      const u = (t + tb.off) % 6.4, rest = -1.35, cocked = .62; let th;
      if (u < 3.6) { const k = u / 3.6; th = rest + (cocked - rest) * (k * k * (3 - 2 * k)); tb.fired = false; tb.ball.visible = true; }
      else if (u < 4.1) th = cocked;
      else if (u < 4.65) { const k = (u - 4.1) / .55; th = cocked + (rest - cocked) * k * k; }
      else th = rest + Math.sin((u - 4.65) * 9) * .06 * Math.max(0, 1 - (u - 4.65) / 1.2);
      tb.pivot.rotation.z = th;
      if (u >= 4.1 && th < -.3 && !tb.fired) {
        tb.fired = true; tb.ball.visible = false; tb.ball.getWorldPosition(_v);
        const a = Math.atan2(s.y - tb.g.position.z, s.x - tb.g.position.x), side = (Math.random() - .5) * s.pl * .6, r = s.pl * .5;
        const tx = s.x + Math.cos(a + Math.PI) * r - Math.sin(a) * side, tz = s.y + Math.sin(a + Math.PI) * r + Math.cos(a) * side;
        const m = new THREE.Mesh(ballGeo, stoneMat); m.scale.setScalar(.75); m.position.copy(_v); scene.add(m);
        sg.shots.push({ m, from: _v.clone(), to: new THREE.Vector3(tx, s.gy + 30 + Math.random() * 30, tz), t: 0, dur: 1.25, h: 110 + s.pl * .4 });
      }
    });
    for (let i = sg.shots.length - 1; i >= 0; i--) {
      const q = sg.shots[i]; q.t += dt; const k = Math.min(1, q.t / q.dur);
      q.m.position.lerpVectors(q.from, q.to, k); q.m.position.y += 4 * q.h * k * (1 - k); q.m.rotation.x += dt * 6;
      if (k >= 1) {
        scene.remove(q.m); sg.shots.splice(i, 1);
        const fm = new THREE.Mesh(flashGeo, new THREE.MeshBasicMaterial({ color: 0xffc46a, transparent: true, opacity: .95, depthWrite: false })); fm.position.copy(q.to); scene.add(fm); fxFlash.push({ m: fm, t: 0 });
        for (let j = 0; j < 5; j++) spawnPuff(q.to.x + (Math.random() - .5) * 18, q.to.y + Math.random() * 8, q.to.z + (Math.random() - .5) * 18, { size: 7, rise: 16 + Math.random() * 14, life: 1.8 + Math.random(), col: 0xb59c78, op: .55, grow: 2.6, vx: (Math.random() - .5) * 30 });
        for (let j = 0; j < 6; j++) { const db = new THREE.Mesh(boxGeo, stoneMat); db.scale.setScalar(2 + Math.random() * 2); db.position.copy(q.to); scene.add(db); fxDebris.push({ m: db, v: new THREE.Vector3((Math.random() - .5) * 90, 50 + Math.random() * 70, (Math.random() - .5) * 90), life: 1.1 }); }
      }
    }
  });
  for (let i = fxFlash.length - 1; i >= 0; i--) { const f = fxFlash[i]; f.t += dt; f.m.scale.setScalar(6 + f.t * 55); f.m.material.opacity = Math.max(0, .95 - f.t * 3.2); if (f.t > .32) { scene.remove(f.m); f.m.material.dispose(); fxFlash.splice(i, 1); } }
  for (let i = fxDebris.length - 1; i >= 0; i--) { const f = fxDebris[i]; f.life -= dt; f.v.y -= 220 * dt; f.m.position.addScaledVector(f.v, dt); f.m.rotation.x += dt * 8; if (f.life <= 0) { scene.remove(f.m); fxDebris.splice(i, 1); } }
}
const fxFlash = [], fxDebris = [];
let focused = false;
const armyList = [], armyById = new Map(), siteIdx = new Map(sites.map((s, i) => [s.id, i]));
const recolor = (c, cols) => { const t = c.g.userData.tint; if (!t) return; t.cloth.color.set(cols[0]); t.flag.map = flagTex(cols[0], cols[1]); t.flag.needsUpdate = true; t.stripe.color.set(cols[1]); if (c.own) c.own.forEach((m, i) => m.material.color.set(c.threat && i === 1 ? '#ff3b2a' : cols[0])); };
let ovSpec = null, ovBucket = -1; const ovBadges = [];
const ovScale = () => Math.max(1, Math.min(9, cam.position.distanceTo(controls.target) / 2600));
const ovBucketNow = () => Math.round(Math.log2(ovScale()) * 2);
const buildOverlays = (o) => {
  clearOverlays(); ovBadges.splice(0).forEach((b) => b.el.remove());
  const k = ovScale(), P = (pts) => pts.map(([x, z]) => ({ x, z }));
  (o.vision || []).forEach((c) => ribbonLine(circlePts(c.x, c.z, c.r), 3 * k, 0xd4a94a, .35));
  (o.rings || []).forEach((id) => { const i = siteIdx.get(id); if (i !== undefined) ribbonLine(circlePts(castles[i].s.x, castles[i].s.y, 150), 5 * k, 0xf0cf7d, .9); });
  (o.circles || []).forEach((c) => ribbonLine(circlePts(c.x, c.z, c.r), (c.w || 7) * k, c.color || 0xf0cf7d, c.op ?? .95, !!c.solid));
  (o.routes || []).forEach((r) => { if (r.pts.length > 1) { ribbonLine(P(r.pts), 10 * k, 0x1a140c, .7, true); ribbonLine(P(r.pts), 6 * k, r.color || 0xf5dc94, .95); } });
  (o.lines || []).forEach((l) => { if (l.pts.length > 1) ribbonLine(P(l.pts), (l.w || 6) * k, l.color || 0xf5dc94, l.op ?? .9, !!l.solid); });
  (o.badges || []).forEach((b) => { const el = document.createElement('div'); el.className = 'ovb' + (b.wide ? ' wide' : ''); el.textContent = b.text; labels.appendChild(el); ovBadges.push({ el, p: new THREE.Vector3(b.x, hAt(b.x, b.z) + (b.up ?? 110), b.z) }); });
};
const api = {
  update(list) { if (!focused && list.some((x) => x.mine)) { focused = true; const ms2 = list.filter((x) => x.mine).map((x) => castles[siteIdx.get(x.id)].s), fx0 = ms2.reduce((a, q) => a + q.x, 0) / ms2.length, fz0 = ms2.reduce((a, q) => a + q.y, 0) / ms2.length, spread = Math.max(...ms2.map((q) => Math.hypot(q.x - fx0, q.y - fz0))), f0 = spread > 1500 ? ms2[0] : null; controls.target.set(f0 ? f0.x : fx0, 80, f0 ? f0.y : fz0); setView(1.0, Math.min(2600, Math.max(1500, W * .38))); } list.forEach(({ id, owner, troops, mine, threat, seen }) => { const i = siteIdx.get(id); if (i === undefined) return; const c = castles[i], s = c.s; if (c.junction) return; const cols = owner == null ? ['#8a8478', '#5a574f'] : spec.colors(owner); const changed = s.owner !== owner || s.troops !== troops || s.mine !== !!mine; s.owner = owner; s.troops = troops; s.mine = !!mine; c.el.classList.toggle('fog', seen === false); if (!!threat !== !!c.threat) { c.threat = !!threat; c.el.classList.toggle('threat', c.threat); if (c.own) c.own[1].material.color.set(c.threat ? '#ff3b2a' : cols[0]); } if (changed) { c.el.style.setProperty('--c', cols[0]); setLabel(c.el, cols[0], cols[1], s.name, s.troops ?? '?'); recolor(c, cols); } }); },
  playBattle,
  siegeEdge(id) { const sg = sieges.get(id); if (!sg) return null; const s = sg.s, a = Math.atan2(sg.cz - s.y, sg.cx - s.x), r = s.pl + 18; return { x: s.x + Math.cos(a) * r, z: s.y + Math.sin(a) * r, angle: -a }; },
  setSieges(list) {
    const keep = new Set(list.map((d) => d.id));
    sieges.forEach((sg, id) => { if (!keep.has(id)) { removeSiege(sg); sieges.delete(id); } });
    list.forEach((d) => { if (siteIdx.get(d.id) === undefined) return; let sg = sieges.get(d.id); if (sg && (sg.tier !== d.tier || sg.cols !== d.cols[0] + d.cols[1])) { removeSiege(sg); sg = null; } if (!sg) { sg = makeSiege(d); sieges.set(d.id, sg); } sg.level = d.level; });
  },
  setArmies(list) {
    const keep = new Set(list.map((a) => a.id));
    armyById.forEach((a, id) => { if (!keep.has(id)) { killArmy(a); armyById.delete(id); } });
    list.forEach((d) => { let a = armyById.get(d.id); const uk = (() => { const q = armyUnits(d.troops, d.tier ?? 1); return q.foot + '/' + q.cav + '/' + q.eng; })(); if (!a || a.cols !== d.cols[0] + d.cols[1] || a.ukey !== uk) { if (a) killArmy(a); a = makeArmy(d.cols[0], d.cols[1], d.troops, d.tier ?? 1, d.name || ''); armyById.set(d.id, a); armyList.push(a); }
      if (a.n !== d.troops) { a.n = d.troops; a.el.querySelector('b').textContent = d.troops; }
      if ((d.name || '') !== a.name) { a.name = d.name || ''; fillRb(a.el.querySelector('.rb'), a.name, a.n); } const y = hAt(d.x, d.z); a.g.position.set(d.x, y, d.z); a.g.rotation.y = d.heading; a.top.set(d.x, y + 46, d.z); });
  },
  setOverlays(o) { ovSpec = o; ovBucket = ovBucketNow(); buildOverlays(o); },
  select(id) { const i = id == null ? -1 : siteIdx.get(id); if (i === undefined || i < 0) { sel = -1; ring.visible = false; castles.forEach((c) => c.el.classList.remove('sel')); } else selectRing(i); },
  focus(id, dist = 900) { const i = siteIdx.get(id); if (i === undefined) return; const c = castles[i]; controls.target.set(c.s.x, c.s.gy + 50, c.s.y); setView(.9, dist); },
  resize: doResize,
  groundAt: (x, z) => hAt(x, z),
  capture(w, h, q) { composer.render(); const c = document.createElement('canvas'); c.width = w; c.height = h; c.getContext('2d').drawImage(renderer.domElement, 0, 0, w, h); return c.toDataURL('image/jpeg', q || 0.8); },
  scene,
  sites: () => sites.map((q) => ({ id: q.id, x: q.x, z: q.y, y: q.gy, tier: q.tier, name: q.name, v: q.v, moat: !!q.moat })),
  dispose() { running = false; ro.disconnect(); renderer.dispose(); try { renderer.forceContextLoss(); } catch {} host.innerHTML = ''; host.classList.remove('map3d'); },
};
scene.traverse((o) => { if (o.isInstancedMesh) o.layers.set(1); }); cam.layers.enable(1);
if (spec.debug) spec.debug({ THREE, scene, renderer, composer, cam, controls, sun, sao, water, marks });
updateTiles(true); marks.push(['done', performance.now()]); $('load').remove(); frame();
return api;
}
