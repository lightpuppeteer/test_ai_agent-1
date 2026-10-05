import * as THREE from 'three';
import { PALETTE } from '../config.js';
import { createStylizedMaterial } from '../shaders/StylizedMaterial.js';
import { VerletCloth } from '../simulation/VerletCloth.js';
import { SpringBoneChain, createSpringTail } from '../simulation/SpringBoneChain.js';
import { BONE_INDEX as BI } from './CharacterMesh.js';
import { sampleSection } from './body/Loft.js';

const TAU = Math.PI * 2;
const sm = (a, b, x) => {
  const t = THREE.MathUtils.clamp((x - a) / (b - a), 0, 1);
  return t * t * (3 - 2 * t);
};

// -----------------------------------------------------------------------------
// Garment cut-out masks (GLSL), evaluated on the body-surface coordinates
// aBodyUV = (angle / 2π, t). Angle 0 = left side, π/2 = front, 3π/2 = back.
// The angle is interpolated as a direction (cos, sin) and recovered per
// fragment, so triangles straddling the 0/2π seam don't sweep through every
// angle (which would shred the mask along the side of the body).
// -----------------------------------------------------------------------------
const MASKS = {
  bikiniTop: /* glsl */ `
    float band = 1.0 - step(1.245, y);
    float da = min(abs(a - 1.15), abs(a - 1.99));
    float cup = step(da, 0.4) * step(y, 1.245 + 0.115 * (1.0 - da / 0.4));
    float strapF = (step(abs(a - 1.15), 0.035) + step(abs(a - 1.99), 0.035)) * step(1.3, y);
    float strapB = (step(abs(a - 4.36), 0.035) + step(abs(a - 5.06), 0.035)) * step(1.24, y);
    return max(max(band, cup), max(strapF, strapB));`,
  bikiniBottom: /* glsl */ `
    float frontTri = step(abs(a - 1.5708), 0.16 + (y - 0.8) * 3.2) * step(y, 0.985);
    float backTri = step(abs(a - 4.7124), 0.24 + (y - 0.8) * 4.2) * step(y, 0.985);
    float ties = step(0.945, y) * step(y, 0.972);
    float crotch = step(y, 0.845);
    return max(max(frontTri, backTri), max(ties, crotch));`,
  dressBodice: /* glsl */ `
    float front = smoothstep(0.05, 0.35, sin(a));
    float sweetheart = 1.3 + 0.035 * abs(sin(2.0 * (a - 1.5708)));
    float top = mix(1.25, sweetheart, front);
    float body = step(y, top);
    float straps = (step(abs(a - 1.02), 0.03) + step(abs(a - 2.12), 0.03)
                  + step(abs(a - 4.21), 0.03) + step(abs(a - 5.21), 0.03)) * step(1.2, y);
    return max(body, straps);`,
  hairShort: /* glsl */ `
    float front = smoothstep(0.2, 0.55, sin(a));
    float hairline = mix(1.665, 1.778, front);
    return step(hairline, y);`,
  hairLong: /* glsl */ `
    float front = smoothstep(0.15, 0.55, sin(a));
    // Side-swept fringe: hairline dips on one side of the forehead.
    float fringe = 0.03 * smoothstep(0.6, 1.0, sin(a)) * smoothstep(1.4, 1.9, a);
    float hairline = mix(1.605, 1.772, front) - fringe;
    return step(hairline, y);`,
};

/**
 * Wardrobe items. Kinds:
 *  shell  skinned, lofted over body segments (same weights + morph as the
 *         body) with an inflation offset; optional GLSL cut-out mask; may
 *         hide the body regions it fully covers (no z-fighting, no clipping)
 *  cloth  Verlet cloth pinned to a skinned body ring/arc; collides with the
 *         body capsules inflated per `layer` (outer layers stay outside)
 *  dress  skinned bell with GPU flow displacement + GPU capsule push-out
 *  spring spring-bone tail (hair, scarf)
 * Optional: `profiles` restricts an item to 'feminine' / 'masculine' bodies
 * (e.g. the bikini top), `windScale` tunes a cloth item's wind response and
 * `over` lists cloth items this one is layered on top of.
 */
export const WARDROBE_ITEMS = {
  tunic: {
    kind: 'shell',
    hides: ['belly', 'chest', 'shoulder', 'upperArm'],
    material: { color: PALETTE.tunic, roughness: 0.92, rim: 0.28, painterly: 0.12, painterlyScale: 1.2 },
    parts: [
      { segment: 'torso', t0: 0.97, t1: 1.49, rings: 30, inflate: (t) => 0.014 + 0.02 * (1 - sm(0.97, 1.05, t)) },
      { segment: 'armL', t0: -0.07, t1: 0.27, rings: 16, inflate: (t) => 0.011 + 0.012 * sm(0.18, 0.27, t) },
      { segment: 'armR', t0: -0.07, t1: 0.27, rings: 16, inflate: (t) => 0.011 + 0.012 * sm(0.18, 0.27, t) },
    ],
  },
  trousers: {
    kind: 'shell',
    hides: ['hips', 'thigh', 'shin'],
    material: { color: PALETTE.trousers, roughness: 0.9, rim: 0.22 },
    parts: [
      { segment: 'torso', t0: 0.8, t1: 1.05, rings: 14, inflate: 0.012, capStart: true },
      { segment: 'legL', t0: -0.04, t1: 0.86, rings: 34, inflate: (t) => 0.011 + 0.008 * sm(0.6, 0.86, t) },
      { segment: 'legR', t0: -0.04, t1: 0.86, rings: 34, inflate: (t) => 0.011 + 0.008 * sm(0.6, 0.86, t) },
    ],
  },
  boots: {
    kind: 'shell',
    hides: ['foot'],
    material: { color: 0x4a3426, roughness: 0.65, rim: 0.2 },
    parts: [
      { segment: 'footL', inflate: 0.01, capStart: true, capEnd: true },
      { segment: 'footR', inflate: 0.01, capStart: true, capEnd: true },
      { segment: 'legL', t0: 0.7, t1: 0.92, rings: 8, inflate: 0.02 },
      { segment: 'legR', t0: 0.7, t1: 0.92, rings: 8, inflate: 0.02 },
    ],
  },
  shirt: {
    kind: 'shell',
    hides: ['belly', 'chest', 'shoulder'],
    material: { color: 0xf1ece0, roughness: 0.95, rim: 0.3, painterly: 0.06 },
    parts: [
      { segment: 'torso', t0: 1.0, t1: 1.49, rings: 26, inflate: 0.012 },
      { segment: 'armL', t0: -0.07, t1: 0.13, rings: 10, inflate: (t) => 0.011 + 0.014 * sm(0.06, 0.13, t) },
      { segment: 'armR', t0: -0.07, t1: 0.13, rings: 10, inflate: (t) => 0.011 + 0.014 * sm(0.06, 0.13, t) },
    ],
  },
  shirtHem: {
    kind: 'cloth',
    layer: 2,
    // Pinned above and outside the skirt's waistband; `over` keeps the free
    // hem radially outside the skirt (cloth-over-cloth layering).
    ring: { segment: 'torso', t: 1.05, inflate: 0.022 },
    over: ['skirt'],
    cols: 28,
    rows: 5,
    length: 0.15,
    flare: 0.02,
    mass: 0.006,
    windScale: 0.5,
    colliders: ['hips', 'belly', 'thigh'],
    material: { color: 0xf1ece0, roughness: 0.95, rim: 0.3, painterly: 0.06 },
  },
  skirt: {
    kind: 'cloth',
    layer: 1,
    ring: { segment: 'torso', t: 1.02, inflate: 0.012 },
    cols: 30,
    rows: 10,
    length: 0.46,
    flare: 0.05,
    mass: 0.012,
    windScale: 0.3,
    colliders: ['hips', 'thigh', 'shin'],
    material: { color: 0x4f6f8f, roughness: 0.9, rim: 0.25, painterly: 0.1 },
  },
  cloak: {
    kind: 'cloth',
    layer: 2,
    arc: { segment: 'torso', t: 1.43, from: (3 * Math.PI) / 2 - 1.05, to: (3 * Math.PI) / 2 + 1.05, inflate: 0.03 },
    cols: 9,
    rows: 11,
    length: 0.86,
    flare: 0.035,
    mass: 0.03,
    colliders: ['shoulders', 'chest', 'belly', 'hips', 'thigh', 'shin'],
    material: { color: PALETTE.cloak, roughness: 0.9, rim: 0.35, painterly: 0.14, painterlyScale: 1.2 },
  },
  bikiniTop: {
    kind: 'shell',
    profiles: ['feminine'],
    mask: 'bikiniTop',
    material: { color: 0xd9564a, roughness: 0.42, rim: 0.3, painterly: 0.04, polygonOffset: true },
    parts: [{ segment: 'torso', t0: 1.2, t1: 1.47, rings: 22, inflate: 0.004 }],
  },
  bikiniBottom: {
    kind: 'shell',
    mask: 'bikiniBottom',
    material: { color: 0xd9564a, roughness: 0.42, rim: 0.3, painterly: 0.04, polygonOffset: true },
    parts: [{ segment: 'torso', t0: 0.8, t1: 1.0, rings: 16, inflate: 0.004, capStart: true }],
  },
  silverDressBodice: {
    kind: 'shell',
    mask: 'dressBodice',
    hides: ['belly'],
    material: 'silver',
    parts: [{ segment: 'torso', t0: 0.95, t1: 1.47, rings: 30, inflate: 0.008 }],
  },
  silverDressSkirt: { kind: 'dress', material: 'silver', top: 0.975, hem: 0.3, hemRadius: 0.33 },
  hairShort: {
    kind: 'shell',
    mask: 'hairShort',
    material: { color: PALETTE.hair, roughness: 0.7, rim: 0.4, painterly: 0.1, painterlyScale: 6 },
    parts: [{ segment: 'head', t0: 1.655, t1: 1.845, rings: 14, inflate: 0.011, capEnd: true }],
  },
  hairLong: {
    kind: 'shell',
    mask: 'hairLong',
    material: { color: PALETTE.hair, roughness: 0.62, rim: 0.4, painterly: 0.1, painterlyScale: 6 },
    parts: [{ segment: 'head', t0: 1.6, t1: 1.845, rings: 18, inflate: 0.014, capEnd: true }],
  },
  ponytail: {
    kind: 'spring',
    bone: 'head',
    offset: [0, 0.17, -0.1],
    rotation: [0.9, 0, 0],
    tail: { segments: 5, length: 0.42, radiusTop: 0.045, radiusBottom: 0.012 },
    spring: { stiffness: 0.9, drag: 0.32, gravityPower: 0.45, windInfluence: 0.09 },
    color: PALETTE.hair,
  },
  scarf: {
    kind: 'spring',
    bone: 'chest',
    offset: [0.06, 0.05, -0.1],
    rotation: [0.5, 0, 0.15],
    tail: { segments: 6, length: 0.55, radiusTop: 0.05, radiusBottom: 0.035, flatten: 0.25 },
    spring: { stiffness: 0.5, drag: 0.22, gravityPower: 0.3, windInfluence: 0.14 },
    color: PALETTE.scarf,
  },
};

export const OUTFITS = {
  explorer: ['tunic', 'trousers', 'boots', 'cloak', 'scarf'],
  skirtShirt: ['shirt', 'shirtHem', 'skirt', 'boots'],
  silverDress: ['silverDressBodice', 'silverDressSkirt'],
  bikini: ['bikiniTop', 'bikiniBottom'],
};

/** Hair style per profile (switches when the morph crosses 0.5). */
const HAIR = { masculine: ['hairShort'], feminine: ['hairLong', 'ponytail'] };

const _v = new THREE.Vector3();
const _w = new THREE.Vector3();
const _head = new THREE.Vector3();
const _inv = new THREE.Matrix4();
const _rot3 = new THREE.Matrix3();

/**
 * Wardrobe: equips data-driven garments on a CharacterMesh and keeps their
 * secondary motion running (cloth, springs, dress shader uniforms), plus
 * body-region masking for whatever is covered.
 */
export class Wardrobe {
  /**
   * @param {object} o
   * @param {import('./CharacterMesh.js').CharacterMesh} o.mesh
   * @param {import('../environment/WindSystem.js').WindSystem} o.wind
   * @param {THREE.Object3D} o.worldParent parent for world-space cloth meshes
   */
  constructor({ mesh, wind, worldParent }) {
    this.mesh = mesh;
    this.wind = wind;
    this.worldParent = worldParent;
    this.windAt = wind ? (p, out) => wind.sample(p, out, 0.6) : (p, out) => out.set(0, 0, 0);
    this.items = new Map();
    this.outfit = null;
    this.hairStyle = null;
    this._capsules = [];
    this._cloth = []; // cloth items, inner layers first
    this._axis = new THREE.Vector3(); // body axis point for cloth layering
    this._lastRoot = new THREE.Vector3();
    this._rootVel = new THREE.Vector3();
    this._materials = new Map();
  }

  get outfitNames() {
    return Object.keys(OUTFITS);
  }

  // ---------------------------------------------------------------------------
  // Materials
  // ---------------------------------------------------------------------------
  _material(def, item) {
    const spec = def.material;
    const mask = def.mask;
    const dress = def.kind === 'dress';
    const key = `${typeof spec === 'string' ? spec : JSON.stringify(spec)}|${mask ?? ''}|${dress}`;
    if (!dress && this._materials.has(key)) return this._materials.get(key);
    const silver = spec === 'silver';
    const base = silver
      ? // Silver satin: high metalness, fairly high roughness → soft, broad
        // reflections instead of a mirror chrome look; the reflection banding
        // patch below keeps it reading as metal under the soft sky IBL.
        { color: 0xbcc1ca, metalness: 0.92, roughness: 0.42, rim: 0.1, painterly: 0.03, wrap: 0.2 }
      : spec;
    const uniforms = {};
    const defines = {};
    const patches = [];
    let cacheKey = '';
    if (silver) {
      defines.STY_SILVER = '';
      cacheKey += 'silver;';
      patches.push(patchSilver);
    }
    if (mask) {
      cacheKey += `mask:${mask};`;
      patches.push((shader) => {
        shader.vertexShader = shader.vertexShader
          .replace('#include <common>', '#include <common>\nattribute vec2 aBodyUV;\nvarying vec3 vBodyDir;')
          .replace(
            '#include <begin_vertex>',
            '#include <begin_vertex>\nfloat bodyA = aBodyUV.x * 6.2831853;\nvBodyDir = vec3(cos(bodyA), sin(bodyA), aBodyUV.y);',
          );
        shader.fragmentShader = shader.fragmentShader
          .replace(
            '#include <common>',
            `#include <common>\nvarying vec3 vBodyDir;\nfloat garmentMask(float a, float y) { ${MASKS[mask]} }`,
          )
          .replace(
            '#include <clipping_planes_fragment>',
            `#include <clipping_planes_fragment>
            float bodyAngle = mod(atan(vBodyDir.y, vBodyDir.x), 6.2831853);
            if (garmentMask(bodyAngle, vBodyDir.z) < 0.5) discard;`,
          );
      });
    }
    if (dress) {
      Object.assign(uniforms, {
        uDressVel: { value: new THREE.Vector3() },
        uDressWind: { value: new THREE.Vector3() },
        uDressCenter: { value: new THREE.Vector3() },
        uCapA: { value: [0, 1, 2, 3].map(() => new THREE.Vector3()) },
        uCapB: { value: [0, 1, 2, 3].map(() => new THREE.Vector3()) },
        uCapR: { value: [0.1, 0.1, 0.1, 0.1] },
      });
      cacheKey += 'dress;';
      patches.push(patchDress);
      item.uniforms = uniforms;
    }
    const material = createStylizedMaterial({
      name: `Garment:${item?.name ?? ''}`,
      side: THREE.DoubleSide,
      wrap: 0.55,
      ...base,
      uniforms,
      defines,
      patch: patches.length ? (shader) => patches.forEach((p) => p(shader)) : null,
      cacheKey,
    });
    if (!dress) this._materials.set(key, material);
    return material;
  }

  // ---------------------------------------------------------------------------
  // Equip / unequip
  // ---------------------------------------------------------------------------
  /**
   * Equips an outfit preset. Items shared with the current outfit (boots,
   * hair) stay on untouched; only the difference is rebuilt.
   */
  equipOutfit(name) {
    if (!OUTFITS[name]) throw new Error(`Unknown outfit "${name}"`);
    this.outfit = name;
    this._sync();
  }

  /**
   * Re-evaluates profile-dependent items (hairstyle, profile-only garments).
   * Cheap when nothing changed — call it after morphing the body.
   */
  syncProfile() {
    if (this._style() !== this.hairStyle) this._sync();
  }

  _style() {
    return this.mesh.femininity >= 0.5 ? 'feminine' : 'masculine';
  }

  /** Brings the equipped set in line with (outfit, profile style). */
  _sync() {
    const style = this._style();
    const wanted = new Set(HAIR[style]);
    for (const n of OUTFITS[this.outfit] ?? []) {
      const profiles = WARDROBE_ITEMS[n].profiles;
      if (!profiles || profiles.includes(style)) wanted.add(n);
    }
    for (const n of [...this.items.keys()]) if (!wanted.has(n)) this.unequip(n);
    for (const n of wanted) this.equip(n);
    this.hairStyle = style;
  }

  equip(name) {
    if (this.items.has(name)) return this.items.get(name);
    const def = WARDROBE_ITEMS[name];
    if (!def) throw new Error(`Unknown wardrobe item "${name}"`);
    const item = { name, def, meshes: [] };
    if (def.kind === 'shell') this._buildShell(item);
    else if (def.kind === 'dress') this._buildDress(item);
    else if (def.kind === 'cloth') this._buildCloth(item);
    else if (def.kind === 'spring') this._buildSpring(item);
    this.items.set(name, item);
    this._refreshMasking();
    this._linkLayers();
    return item;
  }

  unequip(name) {
    const item = this.items.get(name);
    if (!item) return;
    for (const m of item.meshes) {
      if (m.isSkinnedMesh && this.mesh.morphables.includes(m)) this.mesh.detachGarment(m);
      else {
        m.removeFromParent();
        m.geometry?.dispose();
      }
    }
    item.holder?.removeFromParent();
    this.items.delete(name);
    this._refreshMasking();
    this._linkLayers();
  }

  /** Orders cloth inner → outer and wires each item's `over` layers. */
  _linkLayers() {
    this._cloth = [...this.items.values()].filter((it) => it.cloth).sort((a, b) => a.def.layer - b.def.layer);
    for (const it of this._cloth) {
      it.cloth.innerLayers = (it.def.over ?? [])
        .map((n) => this.items.get(n)?.cloth)
        .filter(Boolean)
        .map((cloth) => ({ cloth, center: this._axis, gap: 0.006, maxRow: 4 }));
    }
  }

  _refreshMasking() {
    const hidden = [];
    for (const it of this.items.values()) hidden.push(...(it.def.hides ?? []));
    this.mesh.setHiddenRegions(hidden);
  }

  // ---------------------------------------------------------------------------
  // Builders
  // ---------------------------------------------------------------------------
  _buildShell(item) {
    const geometry = this.mesh.buildGarmentGeometry(item.def.parts);
    item.meshes.push(this.mesh.attachGarment(geometry, this._material(item.def, item), item.name));
  }

  /**
   * Silver dress skirt: a lofted bell from the waist to mid-calf, skinned to
   * the pelvis and progressively to each thigh by side (it swings with the
   * stride). Flow and anti-clipping happen in the vertex shader.
   */
  _buildDress(item) {
    const def = item.def;
    const custom = (segs) => {
      const top = sampleSection(segs.torso.keys, def.top, {});
      const keys = [
        { t: 0, w: top.w + 0.012, f: top.f + 0.012, b: top.b + 0.014, n: 2.3, dz: top.dz },
        { t: 0.25, w: top.w + 0.05, f: top.f + 0.045, b: top.b + 0.055, n: 2.2, dz: top.dz },
        { t: 1, w: def.hemRadius, f: def.hemRadius * 0.92, b: def.hemRadius, n: 2.0, dz: 0 },
      ];
      return {
        rings: 26,
        radial: 40,
        t0: 0,
        t1: 1,
        keys,
        frame: (t, o, u, v) => (o.set(0, def.top - (def.top - def.hem) * t, 0), u.set(1, 0, 0), v.set(0, 0, 1)),
        weights: (t, a) => {
          const legs = 0.7 * sm(0.05, 1, t);
          const left = sm(-0.35, 0.35, Math.cos(a));
          return [
            [BI.pelvis, 1 - legs],
            [BI.thighL, legs * left],
            [BI.thighR, legs * (1 - left)],
          ];
        },
      };
    };
    const geometry = this.mesh.buildGarmentGeometry([{ custom, rings: 26, radial: 40 }]);
    item.meshes.push(this.mesh.attachGarment(geometry, this._material(def, item), item.name));
  }

  _buildCloth(item) {
    const def = item.def;
    const M = this.mesh;
    M.root.updateMatrixWorld(true);
    // Pin samples on the body surface (ring = full tube, arc = sheet).
    const cols = def.cols;
    const samples = [];
    for (let i = 0; i < cols; i++) {
      if (def.ring) samples.push(M.sampleSurface(def.ring.segment, def.ring.t, (i / cols) * TAU, def.ring.inflate));
      else {
        const a = def.arc.from + ((def.arc.to - def.arc.from) * i) / (cols - 1);
        samples.push(M.sampleSurface(def.arc.segment, def.arc.t, a, def.arc.inflate));
      }
    }
    item.samples = samples;
    const pins = samples.map((s) => M.skinPoint(s, new THREE.Vector3()));
    item.centre = M.bones.pelvis.getWorldPosition(new THREE.Vector3());
    const dy = def.length / (def.rows - 1);
    const initial = (i, j, out) => {
      const p = pins[i];
      _v.set(p.x - item.centre.x, 0, p.z - item.centre.z).normalize();
      return out
        .copy(p)
        .addScaledVector(_v, def.flare * j)
        .add(_w.set(0, -dy * j, 0));
    };
    // Per-garment wind response (a tight skirt shouldn't sail like a flag).
    const windScale = def.windScale ?? 1;
    item.windAt = windScale === 1 ? this.windAt : (p, out) => this.windAt(p, out).multiplyScalar(windScale);
    const cloth = new VerletCloth({
      cols,
      rows: def.rows,
      initial,
      isPinned: (_i, j) => j === 0,
      material: this._material(def, item),
      mass: def.mass,
      iterations: 7,
      drag: 0.5,
      wrapU: !!def.ring,
      collisionMargin: 0.012 + 0.014 * def.layer, // layer offset keeps outer cloth outside inner cloth
    });
    // getCapsules() refreshes the same objects in place every frame, so the
    // per-item collider subset can be resolved once here.
    cloth.capsules = M.getCapsules(this._capsules, 0).filter((c) => def.colliders.includes(c.name));
    cloth.mesh.name = item.name;
    this.worldParent.add(cloth.mesh);
    item.cloth = cloth;
    item.meshes.push(cloth.mesh);
    item.initial = initial;
    item.pins = pins;
  }

  _buildSpring(item) {
    const def = item.def;
    this.mesh.root.updateMatrixWorld(true);
    const holder = new THREE.Group();
    holder.position.set(...def.offset);
    holder.rotation.set(...def.rotation);
    this.mesh.bones[def.bone].add(holder);
    const material = createStylizedMaterial({ name: item.name, color: def.color, roughness: 0.7, rim: 0.35 });
    const tail = createSpringTail({ holder, material, ...def.tail });
    item.spring = new SpringBoneChain(tail.bones, {
      ...def.spring,
      tipOffset: new THREE.Vector3(0, -def.tail.length / def.tail.segments, 0),
    });
    item.spring.colliders = [
      { center: new THREE.Vector3(), radius: 0.12 }, // head
      { center: new THREE.Vector3(), radius: 0.14 }, // upper back / chest
    ];
    item.holder = holder;
    item.meshes.push(tail.mesh);
  }

  // ---------------------------------------------------------------------------
  // Simulation
  // ---------------------------------------------------------------------------
  /** Re-seeds cloth/springs from the current pose (after teleports). */
  reset() {
    this.mesh.root.updateMatrixWorld(true);
    for (const it of this.items.values()) {
      if (it.cloth) {
        it.samples.forEach((s, i) => this.mesh.skinPoint(s, it.pins[i]));
        this.mesh.bones.pelvis.getWorldPosition(it.centre);
        it.cloth.resetToPins(it.initial);
      }
      it.spring?.reset();
    }
  }

  update(dt, groundY) {
    const M = this.mesh;
    M.root.updateMatrixWorld(true);
    // Root velocity (for dress inertia) and teleport detection.
    M.root.getWorldPosition(_v);
    const jump = _v.distanceToSquared(this._lastRoot) > 1.5 * 1.5;
    if (dt > 0) this._rootVel.lerp(_w.subVectors(_v, this._lastRoot).divideScalar(dt), Math.min(1, dt * 8));
    if (jump) this._rootVel.set(0, 0, 0);
    this._lastRoot.copy(_v);
    if (jump) this.reset();

    // One capsule refresh per frame, shared by every item (no allocations).
    const caps = M.getCapsules(this._capsules, 0);
    const chest = caps.find((c) => c.name === 'chest');
    const head = M.bones.head.getWorldPosition(_head).add(_w.set(0, 0.1, 0));
    M.bones.pelvis.getWorldPosition(this._axis);
    // Cloth inner → outer, so outer layers collide with this frame's inner ones.
    for (const it of this._cloth) {
      for (let i = 0; i < it.samples.length; i++) it.cloth.setPinTarget(i, 0, M.skinPoint(it.samples[i], it.pins[i]));
      it.cloth.groundY = groundY;
      it.cloth.update(dt, it.windAt);
    }
    for (const it of this.items.values()) {
      if (it.spring) {
        const [h, t] = it.spring.colliders;
        h.center.copy(head);
        t.center.lerpVectors(chest.a, chest.b, 0.6);
        t.radius = chest.r + 0.02;
        it.spring.update(dt, this.windAt);
      } else if (it.uniforms) {
        this._updateDressUniforms(it);
      }
    }
  }

  /** Mesh-local leg capsules, velocity and wind for the dress vertex shader. */
  _updateDressUniforms(item) {
    const M = this.mesh;
    const U = item.uniforms;
    const mesh = item.meshes[0];
    _inv.copy(mesh.matrixWorld).invert();
    // Leg capsules (already refreshed this frame by update()), inflated by the
    // fabric's clearance.
    let k = 0;
    for (const c of this._capsules) {
      if (c.name !== 'thigh' && c.name !== 'shin') continue;
      U.uCapA.value[k].copy(c.a).applyMatrix4(_inv);
      U.uCapB.value[k].copy(c.b).applyMatrix4(_inv);
      U.uCapR.value[k++] = c.r + 0.022;
    }
    U.uDressCenter.value.copy(M.bones.pelvis.getWorldPosition(_v)).applyMatrix4(_inv);
    const rot = _rot3.setFromMatrix4(_inv);
    U.uDressVel.value.copy(this._rootVel).applyMatrix3(rot);
    if (this.wind) U.uDressWind.value.copy(this.wind.direction).multiplyScalar(this.wind.strength).applyMatrix3(rot);
  }
}

/**
 * Dress vertex patch (runs after skinning, in mesh-local space):
 *  1. flowing waves travelling around and down the skirt, stronger at the hem
 *  2. inertia (hem trails behind motion) + downwind lean
 *  3. anti-clipping: push vertices out of the thigh/shin capsules — a GPU
 *     distance constraint, so legs never poke through, whatever the pose
 */
function patchDress(shader) {
  shader.vertexShader = shader.vertexShader
    .replace(
      '#include <common>',
      /* glsl */ `#include <common>
      attribute vec2 aBodyUV;
      uniform vec3 uDressVel;
      uniform vec3 uDressWind;
      uniform vec3 uDressCenter;
      uniform vec3 uCapA[4];
      uniform vec3 uCapB[4];
      uniform float uCapR[4];`,
    )
    .replace(
      '#include <skinning_vertex>',
      /* glsl */ `#include <skinning_vertex>
      {
        float v = aBodyUV.y;              // 0 at the waist → 1 at the hem
        float a = aBodyUV.x * 6.2831853;
        float k = v * v;
        vec3 radial = transformed - uDressCenter;
        radial.y = 0.0;
        radial = normalize(radial + vec3(1e-5));
        float wave = sin(a * 3.0 + uTime * 2.2 + v * 5.0) * 0.6 + sin(a * 5.0 - uTime * 3.1 + v * 3.0) * 0.4;
        transformed += radial * wave * k * (0.01 + 0.025 * uWindStrength);
        vec3 drift = -uDressVel * 0.055 + uDressWind * 0.03;
        drift.y = 0.0;
        transformed += drift * k;
        for (int i = 0; i < 4; i++) {
          vec3 ab = uCapB[i] - uCapA[i];
          float h = clamp(dot(transformed - uCapA[i], ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
          vec3 cp = uCapA[i] + ab * h;
          vec3 d = transformed - cp;
          float dist = length(d);
          if (dist < uCapR[i]) transformed = cp + d / max(dist, 1e-4) * uCapR[i];
        }
      }`,
    );
}

/**
 * Silver fabric reflection patch (fragment, after the IBL lookup).
 *
 * A soft, low-frequency sky IBL makes any metal look like flat white satin.
 * This re-shapes the indirect specular with a stylised "studio" gradient
 * keyed on the world-space reflection vector: dark ground reflection, a
 * bright horizon band and a slightly dimmer zenith. Band width grows with
 * roughness, so folds read as broad, soft silver gradients — never chrome.
 */
function patchSilver(shader) {
  shader.fragmentShader = shader.fragmentShader.replace(
    '#include <lights_fragment_maps>',
    /* glsl */ `#include <lights_fragment_maps>
    #if defined( STY_SILVER ) && defined( USE_ENVMAP )
    {
      vec3 rw = inverseTransformDirection(reflect(-geometryViewDir, geometryNormal), viewMatrix);
      float w = 0.1 + 0.3 * material.roughness;
      float ground = smoothstep(-0.5, 0.05, rw.y);
      float horizon = exp(-pow((rw.y - 0.1) / w, 2.0));
      float zenith = smoothstep(0.35, 0.95, rw.y);
      radiance *= (0.28 + 0.72 * ground) * (1.0 - 0.3 * zenith) + 0.6 * horizon;
    }
    #endif`,
  );
}
