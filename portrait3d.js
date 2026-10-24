import * as THREE from 'three';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { mergeVertices } from 'three/addons/utils/BufferGeometryUtils.js';

const W = 360;
const H = 480;
const SKIN = ['#f3d3b6', '#e6b995', '#d29e72', '#b67c55', '#9a6542', '#74492f'];
const HAIR = ['#1a1410', '#3f2c20', '#6e4d33', '#ab753c', '#d0a85e', '#8f3d22', '#d8d3c6'];
const EYE = ['#4a2f1c', '#7a5a2c', '#4f6a3a', '#4a6a8a', '#707880'];
const STEEL = '#a4abb4';
const BRASS = '#dcb64c';
const HEAD = [0.98, 0.95, 0.96];

const EXPR = [
  { name: 'calm', inner: 0, mid: 0, outer: 0, up: 0.43, low: 0.68, smile: 0, down: 0, asym: 0, teeth: false },
  { name: 'warm', inner: 0.035, mid: 0.045, outer: 0.0, up: 0.46, low: 0.62, smile: 0.09, down: 0, asym: 0, teeth: true },
  { name: 'smirk', inner: 0, mid: 0.035, outer: 0.015, up: 0.45, low: 0.66, smile: 0.04, down: 0, asym: 0.085, teeth: false },
  { name: 'stern', inner: -0.085, mid: -0.045, outer: 0.02, up: 0.48, low: 0.68, smile: 0, down: 0.055, asym: 0, teeth: false },
  { name: 'weary', inner: 0.085, mid: 0.0, outer: -0.05, up: 0.53, low: 0.65, smile: 0, down: 0.035, asym: 0, teeth: false },
  { name: 'resolute', inner: -0.06, mid: -0.055, outer: -0.015, up: 0.47, low: 0.67, smile: 0, down: 0.025, asym: 0, teeth: false },
];

let R = null;
const cache = new Map();

const clamp = (x, a = 0, b = 1) => Math.max(a, Math.min(b, x));
const ss = (a, b, x) => { const t = clamp((x - a) / (b - a)); return t * t * (3 - 2 * t); };
const G = (x, y, cx, cy, rx, ry) => Math.exp(-(((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2));
const mix = (a, b, t) => new THREE.Color(a).lerp(new THREE.Color(b), t);
const hash = (x, y, z) => { const s = Math.sin(x * 127.1 + y * 311.7 + z * 74.7) * 43758.5453; return s - Math.floor(s); };

function canvasTex(size, draw, repeat = [1, 1], srgb = false) {
  const c = document.createElement('canvas');
  c.width = size[0];
  c.height = size[1];
  draw(c.getContext('2d'), size[0], size[1]);
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.repeat.set(repeat[0], repeat[1]);
  t.anisotropy = 4;
  if (srgb) t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

function makeTextures() {
  const noise = (x, w, h, amp, base = 128) => {
    const img = x.createImageData(w, h);
    for (let i = 0; i < img.data.length; i += 4) {
      const v = base + (Math.random() - 0.5) * amp;
      img.data[i] = img.data[i + 1] = img.data[i + 2] = v;
      img.data[i + 3] = 255;
    }
    x.putImageData(img, 0, 0);
  };
  return {
    skin: canvasTex([128, 128], (x, w, h) => { noise(x, w, h, 46); x.filter = 'blur(1px)'; x.drawImage(x.canvas, 0, 0); }, [4, 4]),
    quilt: canvasTex([128, 128], (x, w, h) => {
      x.fillStyle = '#e4e4e4'; x.fillRect(0, 0, w, h);
      x.strokeStyle = '#8a8a8a'; x.lineWidth = 3;
      for (let i = -h; i < w + h; i += 32) { x.beginPath(); x.moveTo(i, 0); x.lineTo(i + h, h); x.stroke(); x.beginPath(); x.moveTo(i, h); x.lineTo(i + h, 0); x.stroke(); }
      x.filter = 'blur(1.4px)'; x.drawImage(x.canvas, 0, 0);
    }, [3, 2], true),
    mail: canvasTex([128, 128], (x, w, h) => {
      x.fillStyle = '#9a9a9a'; x.fillRect(0, 0, w, h);
      x.strokeStyle = '#3a3a3a'; x.lineWidth = 2.2;
      for (let yy = 0; yy < h + 8; yy += 8) for (let xx = (yy / 8) % 2 ? 4 : 0; xx < w + 8; xx += 8) { x.beginPath(); x.arc(xx, yy, 3.6, 0, Math.PI * 2); x.stroke(); }
    }, [5, 3], true),
    weave: canvasTex([128, 128], (x, w, h) => {
      x.fillStyle = '#ececec'; x.fillRect(0, 0, w, h);
      x.strokeStyle = '#c4c4c4'; x.lineWidth = 1.2;
      for (let i = 0; i < w; i += 4) { x.beginPath(); x.moveTo(i, 0); x.lineTo(i, h); x.stroke(); }
      for (let i = 0; i < h; i += 4) { x.beginPath(); x.moveTo(0, i); x.lineTo(w, i); x.stroke(); }
    }, [14, 10], true),
    leather: canvasTex([128, 128], (x, w, h) => {
      noise(x, w, h, 70, 190);
      x.filter = 'blur(1.6px)'; x.drawImage(x.canvas, 0, 0);
      x.filter = 'none'; x.strokeStyle = 'rgba(40,24,10,0.35)'; x.lineWidth = 1;
      for (let i = 0; i < 40; i++) { x.beginPath(); x.moveTo(Math.random() * w, Math.random() * h); x.lineTo(Math.random() * w, Math.random() * h); x.stroke(); }
    }, [3, 3], true),
    strands: canvasTex([512, 16], (x, w, h) => {
      for (let i = 0; i < w; i += 2) {
        const v = 150 + Math.random() * 105;
        x.fillStyle = `rgb(${v},${v},${v})`;
        x.fillRect(i, 0, 2 + (Math.random() < 0.3 ? 2 : 0), h);
      }
    }, [1, 1], true),
  };
}

function irisTexture(color) {
  const c = document.createElement('canvas');
  c.width = c.height = 128;
  const x = c.getContext('2d');
  const col = new THREE.Color(color);
  const css = `#${col.getHexString()}`;
  const dark = `#${col.clone().multiplyScalar(0.35).getHexString()}`;
  const light = `#${col.clone().lerp(new THREE.Color('#ffffff'), 0.35).getHexString()}`;
  const g = x.createRadialGradient(64, 64, 6, 64, 64, 62);
  g.addColorStop(0, '#050403');
  g.addColorStop(0.34, '#050403');
  g.addColorStop(0.36, light);
  g.addColorStop(0.6, css);
  g.addColorStop(0.92, dark);
  g.addColorStop(1, '#0a0806');
  x.fillStyle = g;
  x.beginPath();
  x.arc(64, 64, 62, 0, Math.PI * 2);
  x.fill();
  x.strokeStyle = 'rgba(255,255,255,0.14)';
  x.lineWidth = 1;
  for (let i = 0; i < 32; i++) {
    const a = (i / 32) * Math.PI * 2;
    x.beginPath();
    x.moveTo(64 + Math.cos(a) * 24, 64 + Math.sin(a) * 24);
    x.lineTo(64 + Math.cos(a) * 52, 64 + Math.sin(a) * 52);
    x.stroke();
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

function setup() {
  const canvas = document.createElement('canvas');
  canvas.width = W;
  canvas.height = H;
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, preserveDrawingBuffer: true });
  renderer.setClearColor(0x000000, 0);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.05;
  const scene = new THREE.Scene();
  const pm = new THREE.PMREMGenerator(renderer);
  scene.environment = pm.fromScene(new RoomEnvironment(), 0.04).texture;
  scene.environmentIntensity = 0.34;
  const cam = new THREE.PerspectiveCamera(28, W / H, 0.1, 60);
  cam.position.set(0, -0.15, 7.4);
  cam.lookAt(0, -0.25, 0);
  const key = new THREE.DirectionalLight(0xfff0dc, 3.3);
  key.position.set(-4.2, 3.8, 4.6);
  const rim = new THREE.DirectionalLight(0xa8c8ff, 2.4);
  rim.position.set(4.5, 2.2, -3.5);
  const fill = new THREE.HemisphereLight(0xcfd6e4, 0x5a4636, 0.55);
  scene.add(key, rim, fill);
  return { canvas, renderer, scene, cam, tex: makeTextures() };
}

function rng(seed) {
  let s = (Math.imul(seed + 7, 2654435761) >>> 0) || 1;
  return () => { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; };
}

function field(ux, uy, uz, o) {
  const f = ss(0.02, 0.4, uz);
  const ax = Math.abs(ux);
  const side = ux < 0 ? -1 : 1;
  const age = o.age;
  const ex = o.ex;
  const fem = o.fem;
  let d = 0; let lip = 0; let blush = 0; let shade = 0; let nose = 0;
  d += (fem ? 0.018 : 0.034) * G(ax, uy, 0.38, 0.3, 0.26, 0.07);
  d += (fem ? 0.015 : 0.028) * G(ux, uy, 0, 0.27, 0.12, 0.09);
  const sock = G(ax, uy, 0.4, 0.06, 0.2, 0.14); d -= 0.05 * sock; shade += sock * 1.2;
  const crease = G(ax, uy, 0.4, 0.2, 0.22, 0.045); d -= 0.018 * crease; shade += crease * 0.7;
  if (ex.up >= 0.5 || age >= 50) shade += G(ax, uy, 0.4, -0.06, 0.16, 0.05) * 0.8;
  d += 0.04 * G(ax, uy, 0.55, -0.1, 0.2, 0.13);
  const cheek = G(ax, uy, 0.46, -0.28, 0.26, 0.22);
  d += (o.face === 2 ? 0.04 : o.face === 3 ? 0.1 : 0.075) * cheek * (1 + (ex.smile > 0 ? 0.35 : 0)) * (side > 0 ? 1 + o.asym * 0.5 : 1); blush += cheek * 1.3;
  d += 0.03 * G(ux, uy, 0, -0.02, 0.07, 0.14);
  const tip = G(ux, uy, o.nx, -0.2, 0.11, 0.095); d += (fem ? 0.105 : 0.125) * tip; nose += tip;
  d += 0.045 * G(ax - o.nx * (side > 0 ? 1 : -1) * 0, uy, 0.13, -0.22, 0.07, 0.06);
  const nost = G(ax, uy, 0.075, -0.285, 0.04, 0.03); d -= 0.05 * nost; shade += nost * 2.2;
  d -= 0.02 * G(ux, uy, 0, -0.32, 0.03, 0.06);
  const upl = G(ux, uy, 0, -0.415, 0.17, 0.045);
  const lol = G(ux, uy, 0, -0.505, 0.15, 0.055);
  d += (fem ? 0.055 : 0.048) * upl + (fem ? 0.075 : 0.065) * lol; lip += upl + lol;
  const mline = G(ux, uy, 0, -0.455, 0.18, 0.02);
  d -= (ex.teeth ? 0.07 : 0.05) * mline; shade += mline * (ex.teeth ? 3.2 : 2.8);
  const cornerUp = ex.smile + (side > 0 ? ex.asym : 0);
  d -= 0.025 * G(ax, uy, 0.17, -0.45, 0.04, 0.04);
  if (cornerUp > 0) { d += cornerUp * 0.9 * G(ax, uy, 0.2, -0.43, 0.06, 0.05); blush += G(ax, uy, 0.36, -0.28, 0.12, 0.1) * 0.5; }
  if (ex.down > 0) { d -= ex.down * 0.8 * G(ax, uy, 0.2, -0.5, 0.06, 0.05); shade += G(ax, uy, 0.2, -0.5, 0.06, 0.05) * 0.8; }
  d += (fem ? 0.04 : 0.05) * G(ux, uy, o.cx, -0.72, 0.2, 0.13);
  const groove = G(ux, uy, 0, -0.6, 0.1, 0.03); d -= 0.025 * groove; shade += groove * 0.7;
  d += 0.03 * G(ux, uy, 0, 0.55, 0.4, 0.2);
  d -= 0.04 * G(ax, uy, 0.72, 0.3, 0.12, 0.2);
  const nl = G(ax, uy, 0.2, -0.3, 0.035, 0.12);
  d -= (age >= 40 ? 0.02 : 0.008) * nl; shade += nl * (age >= 40 ? 0.7 : 0.2);
  if (age >= 42) { const fur = G(ux, uy, 0, 0.5, 0.3, 0.03); d -= 0.014 * fur; shade += fur * 0.5; }
  if (age >= 52) { const fur2 = G(ux, uy, 0, 0.6, 0.26, 0.028); d -= 0.012 * fur2; shade += fur2 * 0.4; }
  if (age >= 46) { const cf = G(ax, uy, 0.62, 0.02, 0.05, 0.1); d -= 0.012 * cf; shade += cf * 0.5; }
  return { d: d * f, lip: Math.min(1, lip) * f, blush: blush * f, shade: shade * f, nose: nose * f };
}

function headPoint(ux, uy, uz, o, out) {
  const fl = field(ux, uy, uz, o);
  const r = 1 + fl.d;
  let x = ux * r * HEAD[0];
  let y = uy * r * HEAD[1];
  let z = uz * r * HEAD[2];
  const narrow = [0.84, 0.98, 0.76, 0.92][o.face] * (o.fem ? 0.95 : 1);
  const j = ss(0, 1, clamp(-y * 1.05));
  x *= 1 - j * (1 - narrow);
  z *= 1 - j * (1 - narrow) * 0.5;
  if (o.face === 2) y *= 1.1;
  if (o.face === 3) { y *= 0.95; x *= 1.05; }
  if (out) out.set(x, y, z);
  return fl;
}

function buildHead(skin, lipTone, stubble, o) {
  let g = new THREE.SphereGeometry(1, 176, 128);
  g.deleteAttribute('uv');
  g.deleteAttribute('normal');
  g = mergeVertices(g, 1e-4);
  const p = g.attributes.position;
  const n = p.count;
  const col = new Float32Array(n * 3);
  const v = new THREE.Vector3();
  const shadow = mix(skin, '#3a1a12', 0.55);
  const blushC = mix(skin, '#cf6a62', 0.5);
  const noseC = mix(skin, '#cf6a62', 0.3);
  const freckle = mix(skin, '#8a5a3a', 0.5);
  const c = new THREE.Color();
  for (let i = 0; i < n; i++) {
    const ux = p.getX(i); const uy = p.getY(i); const uz = p.getZ(i);
    const fl = headPoint(ux, uy, uz, o, v);
    p.setXYZ(i, v.x, v.y, v.z);
    c.copy(skin);
    c.lerp(blushC, clamp(fl.blush) * 0.5);
    c.lerp(noseC, clamp(fl.nose) * 0.35);
    c.lerp(lipTone, clamp(fl.lip));
    c.lerp(shadow, clamp(fl.shade) * 0.75);
    if (o.freckles && uz > 0.2) {
      const fz = hash(Math.round(ux * 38), Math.round(uy * 38), 3.1);
      c.lerp(freckle, ss(0.8, 0.95, fz) * G(Math.abs(ux), uy, 0.3, -0.05, 0.4, 0.22) * 0.6);
    }
    if (uy < -0.78) c.multiplyScalar(0.8 + 0.2 * ss(-1, -0.78, uy));
    if (stubble) c.lerp(stubble, 0.5 * ss(-0.4, -0.55, uy) * ss(0, 0.3, uz + 0.3) * (1 - clamp(fl.lip) * 0.9));
    col[i * 3] = c.r; col[i * 3 + 1] = c.g; col[i * 3 + 2] = c.b;
  }
  g.setAttribute('color', new THREE.BufferAttribute(col, 3));
  g.computeVertexNormals();
  return g;
}

function torso(points, seg = 56, fold = 1) {
  const g = new THREE.LatheGeometry(points.map(([r, y]) => new THREE.Vector2(r, y)), seg);
  const p = g.attributes.position;
  for (let i = 0; i < p.count; i++) {
    const x = p.getX(i); const y = p.getY(i); const z = p.getZ(i);
    const r = Math.hypot(x, z);
    if (r < 0.05) continue;
    const a = Math.atan2(z, x);
    const off = fold * (0.028 * Math.sin(a * 7 + y * 2.2) + 0.018 * Math.sin(a * 13 - y * 4));
    p.setXYZ(i, x * (1 + off / r), y, z * (1 + off / r));
  }
  g.computeVertexNormals();
  return g;
}

function build(spec) {
  const look = spec.look || {};
  const rnd = rng(spec.id || 1);
  const group = new THREE.Group();
  const fem = spec.sex === 'f';
  const skin = new THREE.Color(SKIN[look.skin || 0]);
  const skinDark = skin.clone().multiplyScalar(0.7);
  const age = spec.age || 30;
  let hair = new THREE.Color(HAIR[look.hairc || 0]);
  if (age >= 46) hair = hair.lerp(new THREE.Color('#cbc7bd'), Math.min(1, (age - 44) / 16));
  const c1 = new THREE.Color(spec.c1 || '#6a3fa0');
  const c2 = new THREE.Color(spec.c2 || '#e0a526');
  const school = spec.school;
  const ex = { ...EXPR[(Math.imul(spec.id || 1, 7) + (look.brow || 0) * 3 + (look.mouth || 0)) % EXPR.length] };
  const o = {
    age, ex, fem, face: look.face || 0,
    nx: (rnd() - 0.5) * 0.03, cx: (rnd() - 0.5) * 0.05, asym: (rnd() - 0.5) * 0.04 + (ex.asym ? 0.05 : 0),
    freckles: (look.skin || 0) <= 2 && look.scar !== 1 && rnd() < 0.35,
  };
  const metal = { m: 0.75, r: 0.32 };
  const T = R.tex;

  const mat = (color, op = {}) => {
    const m = new THREE.MeshPhysicalMaterial({
      color, roughness: op.r === undefined ? 0.6 : op.r, metalness: op.m || 0, side: op.side || THREE.FrontSide,
      vertexColors: !!op.vc, sheen: op.sheen || 0, sheenColor: op.sheenColor || new THREE.Color('#ffffff'), sheenRoughness: 0.5,
      clearcoat: op.cc || 0, clearcoatRoughness: 0.08,
    });
    const bump = op.bump !== undefined ? op.bump : (op.m ? null : T.skin);
    if (bump) { m.bumpMap = bump; m.bumpScale = op.bs === undefined ? 0.35 : op.bs; }
    if (op.map) m.map = op.map;
    return m;
  };
  const add = (geo, color, op = {}) => {
    const m = new THREE.Mesh(geo, mat(color, op));
    if (op.pos) m.position.set(...op.pos);
    if (op.rot) m.rotation.set(...op.rot);
    if (op.scale) m.scale.set(...op.scale);
    (op.parent || group).add(m);
    return m;
  };
  const S = (r, w = 28, h = 20) => new THREE.SphereGeometry(r, w, h);
  const C = (r, len) => new THREE.CapsuleGeometry(r, len, 6, 16);
  const tube = (pts, r, seg = 24) => new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts.map((q) => new THREE.Vector3(...q))), seg, r, 8, false);
  const head = new THREE.Group();
  group.add(head);
  const A = (geo, color, op = {}) => add(geo, color, { ...op, parent: head });

  add(new THREE.CylinderGeometry(0.46, 0.6, 0.9, 32), skin.clone().multiplyScalar(0.6), { pos: [0, -1.05, -0.05] });

  const torsoPts = [[0.01, -3.3], [1.1, -3.3], [1.45, -2.9], [1.58, -2.3], [1.52, -1.8], [1.22, -1.5], [0.78, -1.3], [0.6, -1.15]];
  const body = (color, tex, rep) => {
    const m = add(torso(torsoPts), color, { map: tex, bump: tex, bs: 0.3, side: THREE.DoubleSide, r: 0.75, scale: [1, 1, 0.62] });
    if (rep) { m.material.map = tex.clone(); m.material.map.repeat.set(...rep); m.material.map.needsUpdate = true; m.material.bumpMap = m.material.map; }
    return m;
  };
  const rivet = (x, y, z, r = 0.04, color = BRASS) => add(S(r, 8, 6), color, { pos: [x, y, z], ...metal });
  const matOf = (m) => m.material;
  void matOf;

  if (school === 'battleschool') {
    body(mix('#8a7352', c1, 0.18), T.quilt, [3, 2]);
    add(new THREE.CylinderGeometry(0.66, 0.8, 0.5, 48, 1, true), '#b0b6bf', { pos: [0, -1.22, 0.01], map: T.mail, bump: T.mail, bs: 0.8, ...metal, side: THREE.DoubleSide });
    const sc = add(C(0.34, 1.2), c1, { pos: [0, -2.35, 0.7], scale: [1, 1, 0.34], map: T.weave, bump: T.weave, bs: 0.4 });
    void sc;
    add(C(0.05, 1.35), c2, { pos: [0, -2.35, 0.84], scale: [1, 1, 0.5] });
    add(new THREE.CircleGeometry(0.2, 28), c2, { pos: [0, -2.0, 0.862], r: 0.4 });
    add(new THREE.CircleGeometry(0.11, 24), c1, { pos: [0, -2.0, 0.866] });
    for (const s of [-1, 1]) {
      add(S(0.7, 40, 28), STEEL, { pos: [s * 1.43, -1.57, 0], scale: [1, 0.76, 0.96], ...metal });
      add(new THREE.TorusGeometry(0.67, 0.07, 10, 36), c2, { pos: [s * 1.43, -1.75, 0], rot: [Math.PI / 2, 0, 0] });
      for (let i = 0; i < 6; i++) { const a = (i / 6) * Math.PI * 2; rivet(s * 1.43 + Math.cos(a) * 0.5, -1.4 + Math.sin(a) * 0.04, Math.sin(a) * 0.5, 0.035, '#d9d9d9'); }
    }
    add(C(0.05, 0.5), '#4a3a28', { pos: [1.02, -0.45, -0.5], rot: [0, 0, -0.55] });
    add(C(0.05, 0.42), STEEL, { pos: [1.18, -0.05, -0.5], rot: [0, 0, Math.PI / 2 - 0.55], ...metal });
    add(S(0.1, 12, 10), BRASS, { pos: [0.9, -0.82, -0.5], ...metal });
  } else if (school === 'university') {
    body(mix(c1, '#1a1a22', 0.3), T.weave, [4, 3]);
    add(new THREE.TorusGeometry(0.66, 0.17, 14, 40), '#e8e0cc', { pos: [0, -1.25, 0.04], rot: [Math.PI / 2 - 0.22, 0, 0], map: T.weave, bump: T.weave, bs: 0.3 });
    add(new THREE.TorusGeometry(0.7, 0.1, 12, 40), c2, { pos: [0, -1.33, 0.03], rot: [Math.PI / 2 - 0.22, 0, 0] });
    for (const s of [-1, 1]) add(new THREE.BoxGeometry(0.2, 1.5, 0.05), c2, { pos: [s * 0.4, -2.4, 0.9], rot: [0, 0, s * -0.04], map: T.weave, bump: T.weave, bs: 0.15 });
    for (let i = 0; i < 9; i++) {
      const a = -1.0 + (i / 8) * 2.0;
      add(new THREE.TorusGeometry(0.055, 0.018, 6, 12), BRASS, { pos: [Math.sin(a) * 0.62, -1.6 - (1 - Math.cos(a)) * 0.55, 0.84 + (1 - Math.abs(a)) * 0.06], rot: [i % 2 ? Math.PI / 2 : 0, 0.3, 0], ...metal });
    }
    add(S(0.12, 16, 12), BRASS, { pos: [0, -2.1, 0.92], scale: [1, 1, 0.45], ...metal });
    add(new THREE.CircleGeometry(0.06, 16), c2, { pos: [0, -2.1, 0.96] });
  } else {
    body('#5a4430', T.leather, [3, 3]);
    add(new THREE.SphereGeometry(1.85, 44, 22, 0, Math.PI * 2, 0, Math.PI * 0.5), mix('#40502f', c1, 0.2), { pos: [0, -1.78, -0.05], scale: [1, 0.62, 0.7], side: THREE.DoubleSide, map: T.weave, bump: T.weave, bs: 0.2 });
    add(tube([[1.0, -1.35, 0.4], [0.3, -1.9, 0.92], [-0.5, -2.7, 0.88]], 0.11), '#3a2a1a', { bump: T.leather, map: T.leather });
    add(tube([[-1.0, -1.4, 0.4], [-0.2, -2.0, 0.95], [0.7, -2.8, 0.85]], 0.018), '#e8dcc0');
    add(new THREE.CylinderGeometry(0.15, 0.15, 0.06, 24), BRASS, { pos: [0, -1.5, 0.86], rot: [Math.PI / 2, 0, 0], ...metal });
    add(S(0.07, 12, 10), c2, { pos: [0, -1.5, 0.9], ...metal });
    for (const [ax, az] of [[0.94, -0.35], [1.04, -0.5], [0.84, -0.55]]) {
      add(new THREE.CylinderGeometry(0.018, 0.018, 0.9, 6), '#6a4a2a', { pos: [ax, -0.55, az], rot: [0, 0, -0.18] });
      add(new THREE.BoxGeometry(0.1, 0.22, 0.02), '#e8e0d0', { pos: [ax + 0.06, -0.12, az], rot: [0, 0.3, -0.18] });
    }
    add(new THREE.TorusGeometry(1.5, 0.05, 8, 40, Math.PI * 0.6), '#4a3220', { pos: [-1.1, -0.8, -0.55], rot: [0, 0, 1.0] });
  }

  const lipTone = mix(skin, '#9c3b38', fem ? 0.78 : 0.66);
  const hg = buildHead(skin, lipTone, look.beard === 1 ? mix(skin, hair, 0.7) : null, o);
  A(hg, '#ffffff', { vc: true, r: 0.55, sheen: 0.5, sheenColor: mix(skin, '#ffb090', 0.5) });
  const hp = (ux, uy) => { const q = new THREE.Vector3(); headPoint(ux, uy, Math.sqrt(Math.max(0, 1 - ux * ux - uy * uy)), o, q); return q; };

  for (const s of [-1, 1]) {
    A(S(0.16, 20, 14), skin.clone().multiplyScalar(0.94), { pos: [s * 0.9, -0.03, -0.02], scale: [0.45, 1, 0.75], r: 0.6 });
    A(S(0.08, 12, 10), skinDark.clone().multiplyScalar(0.85), { pos: [s * 0.92, -0.03, 0.02], scale: [0.4, 1, 0.7] });
  }

  const eyeCol = new THREE.Color(EYE[look.eyes || 0]);
  const irisTex = irisTexture(eyeCol);
  const brow = look.brow || 0;
  const lidCol = skin.clone().multiplyScalar(0.97);
  for (const s of [-1, 1]) {
    const e = hp(s * 0.4, 0.06);
    const ec = new THREE.Vector3(e.x * 0.97, e.y, e.z - 0.1);
    const sizeAdj = 1 + (s > 0 ? o.asym : -o.asym) * 0.6;
    A(S(0.165 * sizeAdj, 40, 30), '#f2ede3', { pos: ec.toArray(), r: 0.2, cc: 1 });
    const iris = A(new THREE.CircleGeometry(0.1 * sizeAdj, 40), '#ffffff', { pos: [ec.x + s * 0.004, ec.y - 0.005, ec.z + 0.158 * sizeAdj], r: 0.25, cc: 1 });
    iris.material.map = irisTex;
    A(S(0.024, 10, 8), '#ffffff', { pos: [ec.x - 0.04 + s * 0.004, ec.y + 0.045, ec.z + 0.163] }).material = new THREE.MeshBasicMaterial({ color: '#ffffff' });
    A(S(0.012, 8, 6), '#ffffff', { pos: [ec.x + 0.035 + s * 0.004, ec.y - 0.04, ec.z + 0.163] }).material = new THREE.MeshBasicMaterial({ color: '#ffffff' });
    const up = ex.up + (s > 0 ? o.asym * 0.15 : 0);
    A(new THREE.SphereGeometry(0.176, 40, 22, 0, Math.PI * 2, 0, Math.PI * up), lidCol, { pos: ec.toArray(), rot: [0.0, 0, s * -0.08], r: 0.6, side: THREE.DoubleSide });
    A(new THREE.SphereGeometry(0.174, 40, 22, 0, Math.PI * 2, Math.PI * ex.low, Math.PI * (1 - ex.low)), lidCol.clone().multiplyScalar(0.93), { pos: ec.toArray(), r: 0.6, side: THREE.DoubleSide });
    if (fem) {
      const lash = [-1, -0.5, 0, 0.5, 1].map((t) => [ec.x + t * 0.16, ec.y + 0.04 + Math.cos(t * 1.1) * 0.1 + (t === -s ? 0 : 0), ec.z + 0.1 + Math.cos(t * 1.1) * 0.1]);
      A(tube(lash, 0.014, 12), '#17110e', { r: 0.5 });
    }

    const thick = (brow === 3 ? 0.06 : brow === 0 ? 0.048 : 0.04) * (fem ? 0.78 : 1);
    const lift = s > 0 ? o.asym : 0;
    const by = [0.3 + ex.inner, 0.34 + ex.mid, 0.335 + ex.mid * 0.6, 0.28 + ex.outer];
    const pts = [[0.2, by[0] + lift], [0.36, by[1] + lift], [0.52, by[2] + lift], [0.66, by[3] + lift]].map(([bx, by2]) => {
      const q = hp(s * bx, by2);
      return q.add(q.clone().normalize().multiplyScalar(0.03));
    });
    const bm = A(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts), 24, thick, 8, false), hair.clone().multiplyScalar(0.8), { r: 0.5 });
    bm.scale.z = 0.8;
  }
  const off = (q, d) => q.add(q.clone().normalize().multiplyScalar(d));
  const lipCol = mix(skin, '#9c3b38', fem ? 0.8 : 0.68);
  A(S(0.1, 28, 18), lipCol, { pos: off(hp(0, -0.425), 0.006).toArray(), scale: [1.5 + (fem ? 0.15 : 0), 0.36, 0.6], r: 0.35, cc: 0.5 });
  A(S(0.11, 28, 18), lipCol.clone().multiplyScalar(1.06), { pos: off(hp(0, -0.505), 0.008).toArray(), scale: [1.4 + (fem ? 0.15 : 0), 0.42, 0.62], r: 0.3, cc: 0.7 });
  const cu = (ex.smile + ex.asym * 0.5) * 0.9 - ex.down * 0.9;
  const ml = [-0.19, -0.1, 0, 0.1, 0.19].map((mx) => {
    const q = hp(mx, -0.455 + cu * (Math.abs(mx) / 0.19) ** 2 * 0.5 + (mx > 0 ? ex.asym * 0.25 * (mx / 0.19) ** 2 : 0));
    return off(q, 0.008);
  });
  A(tube(ml.map((q) => q.toArray()), 0.011, 16), '#2a0f0c', { r: 0.6 });
  for (const s of [-1, 1]) A(S(0.03, 10, 8), skinDark.clone().multiplyScalar(0.35), { pos: off(hp(s * 0.075, -0.287), 0.004).toArray(), scale: [1, 0.6, 0.8], r: 0.7 });
  if (ex.teeth) {
    const tp = hp(0, -0.455);
    A(new THREE.CapsuleGeometry(0.02, 0.2, 4, 10), '#efe9dc', { pos: [tp.x, tp.y, tp.z - 0.022], rot: [0, 0, Math.PI / 2], r: 0.3 });
  }

  const hasHood = school === 'rangers';
  const hasHelm = school === 'battleschool' && spec.role !== 'king';
  const covered = hasHood || hasHelm;
  const hs = look.hair || 0;
  const hm = { r: 0.5, sheen: 0.7, sheenColor: hair.clone().lerp(new THREE.Color('#ffffff'), 0.4), map: T.strands, bump: T.strands, bs: 0.35 };
  const hairCap = (scale, len, rotX = 0) => {
    const m = A(new THREE.SphereGeometry(1, 48, 28, 0, Math.PI * 2, 0, len), hair, { scale: [HEAD[0] * scale, HEAD[1] * scale, HEAD[2] * scale], side: THREE.DoubleSide, ...hm });
    m.rotation.x = rotX;
    return m;
  };
  const X = 1.08;
  if (hs === 1) hairCap(1.05, Math.PI * 0.46, -0.25);
  if (hs === 2) {
    hairCap(1.05, Math.PI * 0.48, -0.25);
    A(C(0.13, 0.6), hair, { pos: [0.3, 0.78, 0.6], rot: [0.9, 0, 1.2], ...hm });
  }
  if (hs === 3) {
    hairCap(1.04, Math.PI * 0.4, -0.2);
    for (let i = 0; i < 20; i++) {
      const a = rnd() * Math.PI * 2; const t = 0.2 + rnd() * 0.8;
      A(S(0.2 + rnd() * 0.08, 14, 10), hair, { pos: [Math.cos(a) * Math.sin(t * 1.15) * 1.0 * X, Math.cos(t * 1.15) * 0.95 + 0.05, Math.sin(a) * Math.sin(t * 1.15) * 0.94 - 0.1], ...hm });
    }
  }
  if (hs === 4) {
    hairCap(1.06, Math.PI * 0.5, -0.3);
    A(C(0.55, 1.3), hair, { pos: [0, -0.5, -0.62], scale: [1.4, 1, 0.55], ...hm });
    for (const s of [-1, 1]) A(C(0.15, 1.3), hair, { pos: [s * 0.98, -0.25, 0.0], ...hm });
  }
  if (hs === 5) {
    hairCap(1.05, Math.PI * 0.47, -0.3);
    A(C(0.2, 0.8), hair, { pos: [0, -0.3, -1.05], rot: [0.3, 0, 0], ...hm });
    A(S(0.2, 14, 10), c2, { pos: [0, 0.2, -1.0] });
  }
  if (hs === 6) {
    hairCap(1.05, Math.PI * 0.47, -0.3);
    for (let i = 0; i < 5; i++) A(S(0.19 - i * 0.012, 14, 10), hair, { pos: [0.92 + i * 0.03, -0.1 - i * 0.3, 0.1 - i * 0.04], scale: [1, 1.2, 1], ...hm });
  }
  if (hs === 7) {
    hairCap(1.04, Math.PI * 0.36, -0.55);
    for (const s of [-1, 1]) A(C(0.12, 0.45), hair, { pos: [s * 0.93, 0.12, -0.12], ...hm });
  }
  if (hs === 8) {
    hairCap(1.06, Math.PI * 0.48, -0.5);
    A(C(0.4, 0.55), hair, { pos: [0, 0.35, -0.92], rot: [-0.5, 0, 0], scale: [1.35, 1, 0.8], ...hm });
  }
  if (hs === 0 && !covered) for (const s of [-1, 1]) A(C(0.07, 0.3), hair, { pos: [s * 0.9, 0.1, -0.3], ...hm });

  const beard = look.beard || 0;
  if (beard >= 2) {
    const bc = hair.clone().multiplyScalar(0.97);
    const big = beard === 3 ? 1.2 : 1;
    for (const s of [-1, 1]) {
      A(S(0.38 * big, 24, 16), bc, { pos: [s * 0.54, -0.5, 0.42], scale: [1, 1.15, 0.9], ...hm });
      A(C(0.1, 0.5), bc, { pos: [s * 0.88, -0.18, 0.2], rot: [0, 0, s * 0.08], ...hm });
      A(C(0.085, 0.3), bc, { pos: [s * 0.16, -0.32, 0.93], rot: [0, 0, Math.PI / 2 + s * 0.35], ...hm });
    }
    A(S(0.44 * big, 24, 16), bc, { pos: [0, -0.78, 0.6], scale: [1.15, 1.1, 0.95], ...hm });
    A(S(0.3 * big, 20, 14), bc, { pos: [0, -0.58, 0.8], scale: [1.4, 0.8, 0.7], ...hm });
    if (beard === 3) A(S(0.55, 24, 16), bc, { pos: [0, -1.0, 0.38], scale: [1.05, 1.15, 0.8], ...hm });
    if (beard === 4) for (const s of [-1, 1]) A(C(0.16, 0.5), bc, { pos: [s * 0.2, -1.1, 0.5], rot: [0, 0, s * 0.18], ...hm });
    if (beard === 5) for (let i = 0; i < 4; i++) A(S(0.17 - i * 0.015, 14, 10), bc, { pos: [0, -0.98 - i * 0.2, 0.62], scale: [1, 1.15, 1], ...hm });
  }

  const scar = look.scar || 0;
  const scarCol = mix(skin, '#e8b8a8', 0.6);
  const sp = (ux, uy) => { const q = hp(ux, uy); return q.add(q.clone().normalize().multiplyScalar(0.012)); };
  const scarLine = (a, b) => A(new THREE.TubeGeometry(new THREE.LineCurve3(sp(...a), sp(...b)), 8, 0.014, 6, false), scarCol, { r: 0.5 });
  if (scar === 1) scarLine([-0.55, 0.0], [-0.42, -0.35]);
  if (scar === 2) scarLine([0.3, 0.42], [0.36, 0.1]);
  if (scar === 3) scarLine([0.1, -0.6], [0.3, -0.78]);

  if (hasHood) {
    const hoodCol = mix('#40502f', c1, 0.25);
    const hmat = { map: T.weave, bump: T.weave, bs: 0.2 };
    A(new THREE.SphereGeometry(1, 40, 24, Math.PI * 0.86, Math.PI * 1.28, 0, Math.PI * 0.7), hoodCol, { scale: [HEAD[0] * 1.2, HEAD[1] * 1.14, HEAD[2] * 1.2], pos: [0, 0.05, -0.12], side: THREE.DoubleSide, ...hmat });
    A(new THREE.TorusGeometry(0.98, 0.21, 16, 40), hoodCol, { pos: [0, 0.08, 0.28], scale: [0.9, 1.1, 1], ...hmat });
    A(new THREE.SphereGeometry(1, 36, 16, 0, Math.PI * 2, 0, Math.PI * 0.33), hoodCol, { pos: [0, 0.18, 0.04], scale: [HEAD[0] * 1.14, HEAD[1] * 1.16, HEAD[2] * 1.14], side: THREE.DoubleSide, ...hmat });
    A(C(0.03, 0.4), c2, { pos: [0.55, 0.95, 0.35], rot: [0, 0, -0.5] });
    A(new THREE.BoxGeometry(0.1, 0.34, 0.02), '#e8e0d0', { pos: [0.58, 1.0, 0.36], rot: [0, 0.3, -0.5] });
  } else if (hasHelm) {
    A(new THREE.SphereGeometry(1, 48, 24, 0, Math.PI * 2, 0, Math.PI * 0.42), STEEL, { scale: [HEAD[0] * 1.1, HEAD[1] * 1.08, HEAD[2] * 1.1], ...metal });
    A(new THREE.TorusGeometry(0.97, 0.075, 10, 48), '#7a828c', { pos: [0, 0.27, 0], rot: [Math.PI / 2, 0, 0], scale: [0.94, 1.02, 1], ...metal });
    A(C(0.05, 0.55), STEEL, { pos: [0, -0.02, 1.02], ...metal });
    A(S(0.1, 12, 10), c2, { pos: [0, 1.14, -0.05] });
    for (let i = 0; i < 9; i++) { const a = (i / 8) * Math.PI * 1.3 + Math.PI * 0.18; A(S(0.032, 8, 6), '#d9d9d9', { pos: [Math.cos(a) * 0.94, 0.3, Math.sin(a) * 0.96], ...metal }); }
    for (const s of [-1, 1]) A(S(0.2, 16, 12), '#8a9099', { pos: [s * 1.0, -0.2, 0.3], scale: [0.4, 1.1, 0.8], ...metal });
  } else if (school === 'university') {
    A(new THREE.SphereGeometry(1, 40, 16, 0, Math.PI * 2, 0, Math.PI * 0.5), mix(c1, '#1a1a22', 0.3), { pos: [0.05, 0.64, 0], scale: [1.02, 0.5, 1.0], rot: [0, 0, 0.12], side: THREE.DoubleSide, map: T.weave, bump: T.weave, bs: 0.4 });
    A(new THREE.TorusGeometry(0.93, 0.08, 10, 40), c2, { pos: [0.02, 0.62, 0], rot: [Math.PI / 2, 0, 0.1], scale: [1, 0.98, 1] });
    A(S(0.09, 10, 8), c2, { pos: [0.08, 0.95, 0.05] });
    A(S(0.1, 14, 10), '#f4efe2', { pos: [0.55, 1.05, 0.2], scale: [0.28, 1.5, 0.14], rot: [0, 0, -0.7], r: 0.4 });
    A(tube([[0.38, 0.8, 0.2], [0.5, 1.0, 0.2], [0.62, 1.2, 0.2]], 0.012, 8), '#d8d0be');
  }

  if (spec.role === 'king') {
    A(new THREE.TorusGeometry(0.97, 0.065, 10, 48), BRASS, { pos: [0, 0.5, 0], rot: [Math.PI / 2, 0, 0], scale: [0.95, 1, 1], ...metal });
    for (let i = 0; i < 5; i++) {
      const a = Math.PI * (0.2 + i * 0.15);
      A(new THREE.ConeGeometry(0.09, 0.3, 12), BRASS, { pos: [Math.cos(a) * 0.9 * 0.95, 0.72, Math.sin(a) * 0.93], ...metal });
      A(S(0.035, 8, 6), c2, { pos: [Math.cos(a) * 0.93, 0.52, Math.sin(a) * 0.95 + 0.0], ...metal });
    }
  }

  head.rotation.y = (spec.id % 2 ? 1 : -1) * (0.2 + rnd() * 0.12);
  head.rotation.x = 0.04 + (ex.name === 'weary' ? 0.05 : 0) - (ex.name === 'resolute' ? 0.03 : 0);
  head.rotation.z = (rnd() - 0.5) * 0.06;
  group.rotation.y = head.rotation.y * 0.45;
  return group;
}

const keyOf = (spec) => JSON.stringify([spec.id, spec.school, spec.role, spec.age, spec.sex, spec.look, spec.c1, spec.c2]);

export const portraitPeek = (spec) => cache.get(keyOf(spec)) || null;

export function portraitDataUrl(spec) {
  const key = keyOf(spec);
  if (cache.has(key)) return cache.get(key);
  if (!R) R = setup();
  const group = build(spec);
  R.scene.add(group);
  R.renderer.render(R.scene, R.cam);
  const url = R.canvas.toDataURL('image/webp', 0.92);
  R.scene.remove(group);
  group.traverse((obj) => {
    if (obj.geometry) obj.geometry.dispose();
    if (obj.material) {
      const m = obj.material;
      if (m.map && !Object.values(R.tex).includes(m.map) && m.map.dispose) m.map.dispose();
      m.dispose();
    }
  });
  cache.set(key, url);
  return url;
}
