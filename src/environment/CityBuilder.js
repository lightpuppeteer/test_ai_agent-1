import * as THREE from 'three';
import { PALETTE, WORLD, SURFACE, GROUPS } from '../config.js';
import { createStylizedMaterial } from '../shaders/StylizedMaterial.js';
import { MeshBatcher } from './MeshBatcher.js';
import { bakeVertexAO } from '../lighting/VertexAO.js';
import { enableHeightFog } from '../lighting/ShaderPatches.js';
import { Interactable, Anchor, INTERACTION_TYPE, staticRoot } from '../interaction/Interactable.js';

/*
 * Old-town quarter inspired by Guimarães (Largo da Oliveira & Rua de Santa
 * Maria): a gently slanted cobbled square, the arcaded town hall with pointed
 * arches and battlements, a gothic shrine (Padrão do Salado) beside an olive
 * tree, white-stucco and granite houses with clay roofs, narrow climbing
 * streets with an arch bridging one of them, granite benches and a tavern.
 *
 * Layout (metres, +Z = sea):
 *
 *   z = -40 ─────────── sea wall / balustrade ─────────────────────────
 *            promenade (y = 3.0)          road
 *   z = -52 ── waterfront ──┬──── PLAZA (slanted) ───┬── waterfront ──
 *               houses      │   shrine  olive  tavern│    houses
 *        west street ◄──────┤                        │
 *                           │  ARCADE (town hall)    │
 *   z = -108 ───────────────┴─────┐ north ┌──────────┘
 *                                 │street │  (arch bridge at z = -130)
 */

const PROM_Y = WORLD.promenade.height;
const PLAZA = { x0: -24, x1: 24, zSouth: -52, zNorth: -108, slope: 0.035, cross: 0.012 };
const PLAZA_LEN = PLAZA.zSouth - PLAZA.zNorth; // 56
const NORTH_STREET = { x0: 2, x1: 7, z0: -108, z1: -152, slope: 0.045 };
const WEST_STREET = { z0: -76, z1: -71, x0: -24, x1: -72, slope: 0.03 };

const clamp = THREE.MathUtils.clamp;

/** Slanted square: rises inland and tilts sideways as it climbs. */
export function plazaHeight(x, z) {
  const t = clamp(PLAZA.zSouth - z, 0, PLAZA_LEN);
  return PROM_Y + PLAZA.slope * t + PLAZA.cross * x * (t / PLAZA_LEN);
}
function northStreetHeight(x, z) {
  return plazaHeight(x, NORTH_STREET.z0) + NORTH_STREET.slope * Math.max(NORTH_STREET.z0 - z, 0);
}
function westStreetHeight(x, z) {
  return plazaHeight(WEST_STREET.x0, z) + WEST_STREET.slope * Math.max(WEST_STREET.x0 - x, 0);
}

/** Walkable city ground height (null outside the city). Used to place props. */
export function cityGroundHeight(x, z) {
  if (z >= WORLD.promenade.zLand && z <= WORLD.promenade.zSea) return PROM_Y;
  if (x >= PLAZA.x0 && x <= PLAZA.x1 && z <= PLAZA.zSouth && z >= PLAZA.zNorth) return plazaHeight(x, z);
  if (x >= NORTH_STREET.x0 && x <= NORTH_STREET.x1 && z <= NORTH_STREET.z0 && z >= NORTH_STREET.z1)
    return northStreetHeight(x, z);
  if (z >= WEST_STREET.z0 && z <= WEST_STREET.z1 && x <= WEST_STREET.x0 && x >= WEST_STREET.x1)
    return westStreetHeight(x, z);
  return null;
}

const FACES = {
  '+z': { n: new THREE.Vector3(0, 0, 1), yaw: 0 },
  '-z': { n: new THREE.Vector3(0, 0, -1), yaw: Math.PI },
  '+x': { n: new THREE.Vector3(1, 0, 0), yaw: Math.PI / 2 },
  '-x': { n: new THREE.Vector3(-1, 0, 0), yaw: -Math.PI / 2 },
};

const _q = new THREE.Quaternion();
const _p = new THREE.Vector3();
const _s = new THREE.Vector3();
const _right = new THREE.Vector3();
const UP = new THREE.Vector3(0, 1, 0);
const _fwd = new THREE.Vector3(0, 0, 1);

export class CityBuilder {
  /**
   * @param {import('../core/PhysicsWorld.js').PhysicsWorld} physics
   * @param {import('./TextureFactory.js').TextureFactory} textures
   */
  constructor(physics, textures) {
    this.physics = physics;
    this.textures = textures;
    this.group = new THREE.Group();
    this.group.name = 'City';
    this.batch = new MeshBatcher();
    this.interactables = [];
    this.groundPatches = [];
    /** Street-facing walls, for set dressing (ivy, rubble, banners…). */
    this.facades = [];
    this.bannerMounts = [];
    this.pennantMounts = [];
    this.rng = mulberry(7); // layout (footprints, floors, materials) — keep its call order stable
    this.drng = mulberry(19); // decoration only, so detail never reshuffles the layout

    this._createAssets();
    this.colliders = physics.createStaticGroup('city', { surface: SURFACE.STONE });
  }

  // ---------------------------------------------------------------------------
  // Shared geometry & materials
  // ---------------------------------------------------------------------------
  _createAssets() {
    const T = this.textures;
    const S = createStylizedMaterial;
    // Texture set { map, detail } — tolerant of the headless test stub.
    const tex = (name) => (T.set ? T.set(name) : { map: T.get?.(name) ?? null, detail: null });
    // Hip roof with flat faces (each face needs one consistent roof-plane frame).
    const roof = new THREE.ConeGeometry(Math.SQRT1_2, 1, 4, 1)
      .rotateY(Math.PI / 4)
      .translate(0, 0.5, 0)
      .toNonIndexed();
    roof.computeVertexNormals();
    this.geo = {
      box: new THREE.BoxGeometry(1, 1, 1),
      roof,
      cyl: new THREE.CylinderGeometry(0.5, 0.5, 1, 10),
      pipe: new THREE.CylinderGeometry(0.5, 0.5, 1, 8, 1, true),
      ridge: new THREE.CylinderGeometry(0.5, 0.5, 1, 7).rotateX(Math.PI / 2),
      trunk: new THREE.CylinderGeometry(0.16, 0.26, 1, 7).translate(0, 0.5, 0),
      clump: new THREE.IcosahedronGeometry(1, 1),
      flower: new THREE.IcosahedronGeometry(1, 0),
      sphere: new THREE.SphereGeometry(0.5, 10, 8),
      cone: new THREE.ConeGeometry(0.5, 1, 4, 1).rotateY(Math.PI / 4).translate(0, 0.5, 0),
    };
    const stucco = tex('stucco');
    const ashlar = tex('ashlar');
    const roofTiles = tex('roofTiles');
    const wood = tex('wood');
    const shutter = tex('shutter');
    const iron = tex('castIron');
    this.mat = {
      stucco: [PALETTE.stucco, PALETTE.stuccoShade, 0xeedcb4, 0xedd2c4].map((c, i) =>
        S({
          name: `Stucco${i}`,
          color: c,
          map: stucco.map,
          detailMap: stucco.detail,
          triplanarScale: 1 / 3,
          heightGradient: [0, 2.5, 0.12],
        }),
      ),
      granite: S({
        name: 'Granite',
        color: PALETTE.granite,
        map: ashlar.map,
        detailMap: ashlar.detail,
        triplanarScale: 0.5,
        painterly: 0.1,
      }),
      graniteDark: S({
        name: 'GraniteDark',
        color: PALETTE.graniteDark,
        map: ashlar.map,
        detailMap: ashlar.detail,
        triplanarScale: 0.5,
      }),
      graniteWall: S({
        name: 'GraniteWall',
        color: PALETTE.graniteWarm,
        map: ashlar.map,
        detailMap: ashlar.detail,
        triplanarScale: 0.45,
        heightGradient: [0, 3, 0.15],
      }),
      // Ground variants that read the baked per-vertex AO (see bakeGroundAO).
      cobblesAO: S({
        name: 'CobblesAO',
        color: PALETTE.granite,
        map: tex('cobbles').map,
        detailMap: tex('cobbles').detail,
        triplanarScale: 0.6,
        wrap: 0.6,
        roughness: 0.85,
        vertexAO: true,
      }),
      pavingAO: S({
        name: 'PavingAO',
        color: 0xc9bca6,
        map: tex('paving').map,
        detailMap: tex('paving').detail,
        triplanarScale: 0.33,
        wrap: 0.6,
        roughness: 0.85,
        vertexAO: true,
      }),
      roof: S({
        name: 'RoofClay',
        color: PALETTE.roofClay,
        map: roofTiles.map,
        detailMap: roofTiles.detail,
        triplanarScale: 0.5,
        roofMapping: true,
        painterly: 0.1,
      }),
      roofDark: S({
        name: 'RoofClayDark',
        color: PALETTE.roofClayDark,
        map: roofTiles.map,
        detailMap: roofTiles.detail,
        triplanarScale: 0.5,
        roofMapping: true,
      }),
      ridge: S({
        name: 'RoofRidge',
        color: PALETTE.roofClayDark,
        map: roofTiles.map,
        detailMap: roofTiles.detail,
        triplanarScale: 2,
      }),
      wood: S({ name: 'Wood', color: PALETTE.wood, map: wood.map, detailMap: wood.detail, triplanarScale: 0.7 }),
      woodDark: S({
        name: 'WoodDark',
        color: PALETTE.woodDark,
        map: wood.map,
        detailMap: wood.detail,
        triplanarScale: 0.7,
      }),
      door: [PALETTE.woodDark, 0x2f4f3a, 0x6b2f2a].map((c, i) =>
        S({ name: `Door${i}`, color: c, map: tex('door').map, detailMap: tex('door').detail, roughness: 0.8 }),
      ),
      iron: S({
        name: 'Iron',
        color: PALETTE.ironwork,
        map: iron.map,
        detailMap: iron.detail,
        triplanarScale: 1.5,
        metalness: 0.35,
        roughness: 0.62,
        rim: 0.1,
        painterly: 0.04,
      }),
      // Glazed windows: painted frames + glossy panes reflecting the sky IBL.
      windows: ['window', 'windowCurtains'].map((n, i) =>
        S({
          name: `Window${i}`,
          color: 0xffffff,
          map: tex(n).map,
          detailMap: tex(n).detail,
          roughness: 0.62,
          envMapIntensity: 1.25,
          rim: 0.12,
          painterly: 0.02,
          wrap: 0.3,
        }),
      ),
      glass: S({
        name: 'WindowPane',
        color: 0x2b3440,
        rim: 0.4,
        painterly: 0.03,
        wrap: 0.2,
        roughness: 0.08,
        envMapIntensity: 1.3,
      }),
      shutters: [PALETTE.shutterGreen, PALETTE.shutterBlue, PALETTE.woodDark].map((c, i) =>
        S({ name: `Shutter${i}`, color: c, map: shutter.map, detailMap: shutter.detail, roughness: 0.75 }),
      ),
      azulejo: S({
        name: 'Azulejo',
        color: 0xffffff,
        map: tex('azulejo').map,
        detailMap: tex('azulejo').detail,
        triplanarScale: 1 / 0.56,
        roughness: 0.6,
        painterly: 0.03,
        envMapIntensity: 1.2,
      }),
      terracotta: S({ name: 'Terracotta', color: 0xb8643f, painterly: 0.12, roughness: 0.92 }),
      flowers: [0xd8323e, 0xe85d9c, 0xf4f0e4, 0xe9a23b].map((c, i) =>
        S({
          name: `Flowers${i}`,
          color: c,
          painterly: 0.1,
          wrap: 0.7,
          rim: 0.3,
          windSway: 0.04,
          heightGradient: [-1, 1, 0.1],
        }),
      ),
      bark: S({
        name: 'Bark',
        color: PALETTE.bark,
        map: tex('bark').map,
        detailMap: tex('bark').detail,
        triplanarScale: 1.5,
        painterly: 0.15,
      }),
      foliage: S({
        name: 'Foliage',
        color: PALETTE.foliage,
        map: tex('leaves').map,
        detailMap: tex('leaves').detail,
        triplanarScale: 1.4,
        normalScale: 0.8,
        painterly: 0.25,
        painterlyScale: 0.9,
        wrap: 0.8,
        softness: 0.8,
        rim: 0.35,
        windSway: 0.18,
        heightGradient: [-1, 1, 0.3],
      }),
      lantern: enableHeightFog(
        new THREE.MeshBasicMaterial({ name: 'Lantern', color: new THREE.Color(2.6, 1.9, 1.1), fog: true }),
      ),
    };
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  build() {
    this._promenade();
    this._groundPatches();
    this._waterfrontRows();
    this._plazaRows();
    this._arcade(-17, 2, -106, -98);
    this._northStreet();
    this._westStreet();
    this._shrine(7, -83);
    this._oliveTree(12.5, -88);
    this._furniture();
    this._bounds();
    this.batch.build(this.group);
    return this;
  }

  /**
   * Bakes per-vertex AO into every walkable ground patch by ray casting the
   * finished collider set (houses, arcades, benches, lamp posts, kerbs, and
   * any set dressing added after build()). Call once the level is complete.
   */
  bakeGroundAO() {
    this.physics.updateQueries();
    for (const mesh of this.groundPatches) bakeVertexAO(mesh.geometry, this.physics, { samples: 14, radius: 2.8 });
  }

  // ---------------------------------------------------------------------------
  // Ground
  // ---------------------------------------------------------------------------
  _promenade() {
    const P = WORLD.promenade;
    const width = P.xMax - P.xMin + 20;
    const depth = P.zSea - P.zLand;
    const cz = (P.zSea + P.zLand) / 2;
    // Slab + sea wall in one box (the front face is the granite sea wall).
    const slab = new THREE.Mesh(this.geo.box, this.mat.graniteWall);
    slab.scale.set(width, 3.4, depth);
    slab.position.set(0, P.height - 1.7, cz);
    slab.receiveShadow = true;
    slab.updateMatrixWorld();
    this.group.add(slab);
    this.colliders.addBoxFromMesh(slab);

    // Walkable top surfaces as subdivided patches (visual only; the slab is
    // the collider) so they can carry baked AO from the balustrade, lamps,
    // benches and house fronts: cobbled road + paved footpath.
    const flat = () => P.height + 0.003;
    this._groundPatch(-width / 2, width / 2, P.zLand, -45.55, flat, this.mat.cobblesAO, { collide: false });
    this._groundPatch(-width / 2, width / 2, -45.25, P.zSea, flat, this.mat.pavingAO, { collide: false });
    // Granite kerb between road and footpath.
    this.batch.place(this.geo.box, this.mat.granite, _p.set(0, P.height + 0.06, -45.4), null, _s.set(width, 0.12, 0.3));

    // Balustrade along the sea wall, with openings onto the beach.
    const gaps = [
      [-49, -44],
      [-4.5, 4.5],
      [40, 45],
    ];
    let x = P.xMin;
    const segments = [];
    for (const [g0, g1] of gaps) {
      segments.push([x, g0]);
      x = g1;
    }
    segments.push([x, P.xMax]);
    for (const [a, b] of segments) {
      const len = b - a;
      const c = (a + b) / 2;
      _p.set(c, P.height + 0.3, P.zSea - 0.35);
      _s.set(len, 0.6, 0.45);
      this.batch.place(this.geo.box, this.mat.granite, _p, null, _s);
      this.colliders.addBox(_p, _s);
      // Capstone.
      this.batch.place(
        this.geo.box,
        this.mat.graniteDark,
        _p.set(c, P.height + 0.63, P.zSea - 0.35),
        null,
        _s.set(len, 0.08, 0.55),
      );
      // Iron lamp posts every ~18 m.
      for (let lx = a + 6; lx < b - 3; lx += 18) this._lampPost(lx, P.zSea - 0.9);
    }
  }

  _groundPatches() {
    // Plaza: subdivided, slanted & twisted → trimesh collider from the render mesh.
    this._groundPatch(PLAZA.x0, PLAZA.x1, PLAZA.zNorth, PLAZA.zSouth, plazaHeight, this.mat.cobblesAO);
    this._groundPatch(
      NORTH_STREET.x0 - 0.5,
      NORTH_STREET.x1 + 0.5,
      NORTH_STREET.z1,
      NORTH_STREET.z0 + 0.5,
      northStreetHeight,
      this.mat.cobblesAO,
    );
    this._groundPatch(
      WEST_STREET.x1,
      WEST_STREET.x0 + 0.5,
      WEST_STREET.z0 - 0.5,
      WEST_STREET.z1 + 0.5,
      westStreetHeight,
      this.mat.cobblesAO,
    );
  }

  /** Subdivided (~1 m) ground surface following `heightFn`; trimesh collider unless `collide: false`. */
  _groundPatch(x0, x1, z0, z1, heightFn, material, { collide = true, cell = 1.0 } = {}) {
    const segX = Math.max(1, Math.ceil((x1 - x0) / cell));
    const segZ = Math.max(1, Math.ceil((z1 - z0) / cell));
    const g = new THREE.PlaneGeometry(x1 - x0, z1 - z0, segX, segZ);
    g.rotateX(-Math.PI / 2);
    g.translate((x0 + x1) / 2, 0, (z0 + z1) / 2);
    const pos = g.attributes.position;
    for (let i = 0; i < pos.count; i++) pos.setY(i, heightFn(pos.getX(i), pos.getZ(i)));
    g.computeVertexNormals();
    g.computeBoundingSphere();
    const mesh = new THREE.Mesh(g, material);
    mesh.receiveShadow = true;
    mesh.matrixAutoUpdate = false;
    this.group.add(mesh);
    if (collide) this.colliders.addTrimesh(g);
    this.groundPatches.push(mesh);
    return mesh;
  }

  // ---------------------------------------------------------------------------
  // Buildings
  // ---------------------------------------------------------------------------
  _waterfrontRows() {
    for (const [a, b] of [
      [-110, -34],
      [34, 110],
    ]) {
      this._row(a, b, 'x', -62, -52, ['+z'], { minW: 7, maxW: 11, floors: [2, 4] });
    }
  }

  _plazaRows() {
    // West side (faces the square, +x). Corner house also faces the sea.
    this.building({ x0: -34, x1: -24, z0: -62, z1: -52, floors: 4, fronts: ['+x', '+z'] });
    this.building({ x0: -34, x1: -24, z0: -71, z1: -62, floors: 3, fronts: ['+x', '-z'] });
    // gap = west street (z -76..-71)
    this._row(-108, -76, 'z', -34, -24, ['+x'], { minW: 8, maxW: 11, floors: [3, 4] });
    // East side (faces the square, -x).
    this.building({ x0: 24, x1: 34, z0: -62, z1: -52, floors: 4, fronts: ['-x', '+z'] });
    this.building({ x0: 24, x1: 34, z0: -71, z1: -62, floors: 3, fronts: ['-x'], tavern: true });
    this._row(-116, -71, 'z', 24, 34, ['-x'], { minW: 8, maxW: 12, floors: [3, 4] });
    // North side: corner house, arcade (separate), houses behind the arcade, NE block.
    this.building({ x0: -24, x1: -17, z0: -116, z1: -98, floors: 4, fronts: ['+z'] });
    this.building({ x0: -17, x1: 2, z0: -116, z1: -106, floors: 3, fronts: [], roofOnly: true });
    this.building({ x0: 7, x1: 15, z0: -116, z1: -98, floors: 3, fronts: ['+z', '-x'] });
    this.building({ x0: 15, x1: 24, z0: -116, z1: -98, floors: 4, fronts: ['+z'] });
  }

  _northStreet() {
    const S = NORTH_STREET;
    this._row(S.z1, -116, 'z', -6, S.x0, ['+x'], { minW: 6, maxW: 9, floors: [3, 4] });
    this._row(S.z1, -116, 'z', S.x1, 15, ['-x'], { minW: 6, maxW: 9, floors: [3, 4] });
    this.building({ x0: -6, x1: 15, z0: S.z1 - 8, z1: S.z1, floors: 4, fronts: ['+z'] }); // closes the street
    this._streetArch(S.x0, S.x1, -131);
  }

  _westStreet() {
    const W = WEST_STREET;
    this._row(W.x1, -34, 'x', -86, W.z0, ['+z'], { minW: 7, maxW: 10, floors: [2, 4] });
    this._row(W.x1, -34, 'x', W.z1, -62, ['-z'], { minW: 7, maxW: 10, floors: [2, 3] });
    this.building({ x0: W.x1 - 8, x1: W.x1, z0: -86, z1: -62, floors: 3, fronts: ['+x'] }); // closes the street
  }

  /** A contiguous row of houses along `axis` from a to b (no gaps → no escapes). */
  _row(a, b, axis, c0, c1, fronts, { minW, maxW, floors }) {
    let s = a;
    while (s < b - 0.01) {
      let w = minW + this.rng() * (maxW - minW);
      if (b - (s + w) < minW) w = b - s;
      const fl = floors[0] + Math.floor(this.rng() * (floors[1] - floors[0] + 1));
      if (axis === 'x') this.building({ x0: s, x1: s + w, z0: c0, z1: c1, floors: fl, fronts });
      else this.building({ x0: c0, x1: c1, z0: s, z1: s + w, floors: fl, fronts });
      s += w;
    }
  }

  /** Ground height sampled along a footprint (min & max), falling back to the promenade. */
  _footprintGround(x0, x1, z0, z1) {
    let lo = Infinity;
    let hi = -Infinity;
    for (let i = 0; i <= 4; i++)
      for (let j = 0; j <= 4; j++) {
        const x = x0 + ((x1 - x0) * i) / 4;
        const z = z0 + ((z1 - z0) * j) / 4;
        // Probe just outside the footprint where the walkable ground is.
        const h =
          cityGroundHeight(x, z) ??
          cityGroundHeight(x + 0.6, z) ??
          cityGroundHeight(x - 0.6, z) ??
          cityGroundHeight(x, z + 0.6) ??
          cityGroundHeight(x, z - 0.6);
        if (h === null) continue;
        lo = Math.min(lo, h);
        hi = Math.max(hi, h);
      }
    if (lo === Infinity) lo = hi = PROM_Y + 1.5; // hidden back plots
    return { lo, hi };
  }

  /**
   * One house: granite plinth, stucco (or granite) walls, corner quoins,
   * cornice, hip roof, windows with frames & shutters, balconies and a door.
   */
  building({ x0, x1, z0, z1, floors = 3, fronts = [], tavern = false, roofOnly = false }) {
    const rng = this.rng;
    const w = x1 - x0;
    const d = z1 - z0;
    const cx = (x0 + x1) / 2;
    const cz = (z0 + z1) / 2;
    const { lo, hi } = this._footprintGround(x0, x1, z0, z1);
    const floorH = 3.1;
    const base = hi;
    const top = base + 0.9 + floors * floorH;
    const bottom = lo - 1.2;
    const graniteHouse = !roofOnly && rng() < 0.22;
    const wallMat = graniteHouse ? this.mat.graniteWall : this.mat.stucco[Math.floor(rng() * this.mat.stucco.length)];
    const B = this.batch;
    const box = this.geo.box;

    // Walls (one box) + collider.
    B.place(box, wallMat, _p.set(cx, (bottom + top) / 2, cz), null, _s.set(w, top - bottom, d));
    this.colliders.addBox(_p, _s);
    // Plinth.
    B.place(
      box,
      this.mat.graniteDark,
      _p.set(cx, (bottom + base + 0.9) / 2, cz),
      null,
      _s.set(w + 0.16, base + 0.9 - bottom, d + 0.16),
    );
    // Corner quoins: alternating long/short dressed stones.
    if (!graniteHouse) this._quoins(x0, x1, z0, z1, base, top);
    // Stepped cornice (three courses, each projecting further).
    for (const [y, h, ext] of [
      [top + 0.06, 0.12, 0.22],
      [top + 0.155, 0.07, 0.4],
      [top + 0.205, 0.05, 0.52],
    ])
      B.place(box, this.mat.granite, _p.set(cx, y, cz), null, _s.set(w + ext, h, d + ext));
    // Hip roof (pitch varies a little) + ridge caps along the four hips.
    const roofH = Math.min(w, d) * (0.26 + rng() * 0.1);
    const roofY = top + 0.22;
    B.place(
      this.geo.roof,
      rng() < 0.3 ? this.mat.roofDark : this.mat.roof,
      _p.set(cx, roofY, cz),
      null,
      _s.set(w + 1.0, roofH, d + 1.0),
    );
    const apex = new THREE.Vector3(cx, roofY + roofH, cz);
    for (const [sx, sz] of [
      [-1, -1],
      [1, -1],
      [1, 1],
      [-1, 1],
    ])
      this._beam(
        this.geo.ridge,
        this.mat.ridge,
        new THREE.Vector3(cx + (sx * (w + 1)) / 2, roofY, cz + (sz * (d + 1)) / 2),
        apex,
        0.14,
      );
    // Chimney with a capping slab and terracotta pots.
    if (rng() < 0.6) {
      const chx = cx + (rng() - 0.5) * w * 0.4;
      const chz = cz + (rng() - 0.5) * d * 0.4;
      const chTop = top + roofH * 1.15;
      B.place(box, wallMat, _p.set(chx, top + roofH * 0.6, chz), null, _s.set(0.6, roofH * 1.1, 0.6));
      B.place(box, this.mat.granite, _p.set(chx, chTop + 0.04, chz), null, _s.set(0.78, 0.08, 0.78));
      const pots = 1 + Math.floor(this.drng() * 2);
      for (let k = 0; k < pots; k++)
        B.place(
          this.geo.cyl,
          this.mat.terracotta,
          _p.set(chx + (pots > 1 ? (k - 0.5) * 0.28 : 0), chTop + 0.22, chz),
          null,
          _s.set(0.18, 0.3, 0.18),
        );
    }
    if (roofOnly) return;

    const shutterMat = this.mat.shutters[Math.floor(rng() * this.mat.shutters.length)];
    // Per-house style (decoration RNG only).
    const style = {
      tiled: !graniteHouse && this.drng() < 0.18, // azulejo-clad façade
      keystones: this.drng() < 0.5,
      flowers: this.drng() < 0.65,
      grilles: this.drng() < 0.5,
      door: this.mat.door[Math.floor(this.drng() * this.mat.door.length)],
      window: this.mat.windows[this.drng() < 0.45 ? 1 : 0],
      number: 1 + Math.floor(this.drng() * 120),
    };
    for (const f of fronts) {
      const F = FACES[f];
      const len = f === '+z' || f === '-z' ? w : d;
      const faceCenter = new THREE.Vector3(cx + (F.n.x * w) / 2, 0, cz + (F.n.z * d) / 2);
      const groundHere = cityGroundHeight(faceCenter.x + F.n.x, faceCenter.z + F.n.z) ?? hi;
      this.facades.push({
        center: faceCenter.clone().setY(groundHere),
        normal: F.n.clone(),
        yaw: F.yaw,
        length: len,
        ground: groundHere,
        top,
        tavern: tavern && f === '-x',
        stone: graniteHouse,
      });
      this._facade(faceCenter, F, len, groundHere, base, floors, floorH, shutterMat, tavern && f === '-x', style, top);
      this._rainwater(faceCenter, F, len, groundHere, top);
    }
  }

  /** Dressed corner stones, alternating long and short faces up each corner. */
  _quoins(x0, x1, z0, z1, base, top) {
    const B = this.batch;
    const course = 0.36;
    for (const [qx, qz] of [
      [x0, z0],
      [x1, z0],
      [x0, z1],
      [x1, z1],
    ]) {
      const dx = qx === x0 ? 1 : -1;
      const dz = qz === z0 ? 1 : -1;
      for (let k = 0, y = base; y + course <= top + 0.01; k++, y += course) {
        const long = k % 2 === 0;
        const sx = long ? 0.62 : 0.36;
        const sz = long ? 0.36 : 0.62;
        B.place(
          this.geo.box,
          this.mat.granite,
          _p.set(qx + dx * (sx / 2 - 0.05), y + course / 2, qz + dz * (sz / 2 - 0.05)),
          null,
          _s.set(sx, course - 0.025, sz),
        );
      }
    }
  }

  /** Places a cylinder-like `geometry` (unit, along +Z) between two points. */
  _beam(geometry, material, a, b, radius) {
    const dir = new THREE.Vector3().subVectors(b, a);
    const len = dir.length();
    _q.setFromUnitVectors(_fwd, dir.multiplyScalar(1 / len));
    this.batch.place(geometry, material, _p.addVectors(a, b).multiplyScalar(0.5), _q, _s.set(radius, radius, len));
  }

  /** Eave gutter along a façade + a downpipe with a shoe at one end. */
  _rainwater(center, F, len, ground, top) {
    const yaw = F.yaw;
    _right.set(Math.cos(yaw), 0, -Math.sin(yaw));
    const out = 0.5;
    const gy = top + 0.18;
    const a = center
      .clone()
      .addScaledVector(F.n, out)
      .addScaledVector(_right, -len / 2 - 0.45)
      .setY(gy);
    const b = center
      .clone()
      .addScaledVector(F.n, out)
      .addScaledVector(_right, len / 2 + 0.45)
      .setY(gy);
    this._beam(this.geo.ridge, this.mat.iron, a, b, 0.12);
    const side = this.drng() < 0.5 ? -1 : 1;
    const px = center.clone().addScaledVector(_right, side * (len / 2 - 0.35));
    const wallOff = 0.09;
    // Offset from the gutter back to the wall, then straight down.
    this._beam(
      this.geo.ridge,
      this.mat.iron,
      px
        .clone()
        .addScaledVector(F.n, out)
        .setY(gy - 0.05),
      px
        .clone()
        .addScaledVector(F.n, wallOff)
        .setY(gy - 0.45),
      0.09,
    );
    const pipeTop = gy - 0.45;
    const pipeBot = ground + 0.25;
    this.batch.place(
      this.geo.pipe,
      this.mat.iron,
      px
        .clone()
        .addScaledVector(F.n, wallOff)
        .setY((pipeTop + pipeBot) / 2),
      null,
      _s.set(0.09, pipeTop - pipeBot, 0.09),
    );
    this._beam(
      this.geo.ridge,
      this.mat.iron,
      px
        .clone()
        .addScaledVector(F.n, wallOff)
        .setY(pipeBot + 0.02),
      px
        .clone()
        .addScaledVector(F.n, wallOff + 0.22)
        .setY(ground + 0.05),
      0.1,
    );
    // Wall clips.
    for (let y = pipeBot + 0.6; y < pipeTop - 0.3; y += 1.6)
      this.batch.place(
        this.geo.box,
        this.mat.iron,
        px.clone().addScaledVector(F.n, 0.05).setY(y),
        _q.setFromAxisAngle(UP, yaw),
        _s.set(0.14, 0.04, 0.1),
      );
  }

  _facade(center, F, len, ground, base, floors, floorH, shutterMat, tavern, style, top) {
    const B = this.batch;
    const box = this.geo.box;
    const rnd = this.drng;
    const q = _q.setFromAxisAngle(UP, F.yaw).clone();
    _right.set(Math.cos(F.yaw), 0, -Math.sin(F.yaw));
    const right = _right.clone();
    const n = F.n;
    const count = Math.max(1, Math.floor(len / 2.9));
    const spacing = len / count;
    const doorSlot = Math.floor(count / 2);
    const at = (u, y, out = 0) =>
      new THREE.Vector3().copy(center).addScaledVector(right, u).addScaledVector(n, out).setY(y);

    // Azulejo cladding over the whole façade (windows and doors sit proud of it).
    if (style.tiled) {
      const y0 = base + 0.9;
      B.place(box, this.mat.azulejo, at(0, (y0 + top) / 2, 0.012), q, _s.set(len - 0.62, top - y0, 0.02));
    }

    for (let i = 0; i < count; i++) {
      const u = -len / 2 + (i + 0.5) * spacing;
      // Ground floor: door or window.
      if (i === doorSlot || tavern) {
        const wide = tavern && i !== doorSlot;
        const dw = wide ? 1.8 : 1.15;
        B.place(box, this.mat.granite, at(u, ground + 1.3, 0.04), q, _s.set(dw + 0.45, 2.75, 0.12));
        if (wide) {
          B.place(box, style.window, at(u, ground + 1.15, 0.09), q, _s.set(dw, 2.3, 0.08));
        } else {
          B.place(box, style.door, at(u, ground + 1.15, 0.09), q, _s.set(dw, 2.3, 0.08));
          // Fanlight, threshold, handle and a tiled house number.
          B.place(box, this.mat.glass, at(u, ground + 2.46, 0.09), q, _s.set(dw, 0.26, 0.06));
          B.place(box, this.mat.granite, at(u, ground + 2.33, 0.11), q, _s.set(dw + 0.05, 0.06, 0.1));
          B.place(box, this.mat.graniteDark, at(u, ground + 0.03, 0.2), q, _s.set(dw + 0.5, 0.06, 0.3));
          B.place(
            this.geo.sphere,
            this.mat.iron,
            at(u + dw * 0.36, ground + 1.05, 0.15),
            null,
            _s.set(0.07, 0.07, 0.07),
          );
          B.place(box, this.mat.azulejo, at(u + dw / 2 + 0.42, ground + 2.0, 0.03), q, _s.set(0.2, 0.2, 0.025));
        }
      } else {
        const wy = base + 1.55;
        B.place(box, this.mat.granite, at(u, wy, 0.04), q, _s.set(1.25, 1.75, 0.12));
        B.place(box, style.window, at(u, wy, 0.08), q, _s.set(0.95, 1.45, 0.08));
        B.place(box, this.mat.granite, at(u, wy - 0.86, 0.1), q, _s.set(1.4, 0.08, 0.24)); // sill
        if (style.grilles) {
          // Wrought-iron grille: rails + bars standing off the window.
          for (const gy of [wy - 0.62, wy + 0.62])
            B.place(box, this.mat.iron, at(u, gy, 0.17), q, _s.set(0.98, 0.035, 0.035));
          for (let k = 0; k < 6; k++)
            B.place(box, this.mat.iron, at(u - 0.42 + k * 0.168, wy, 0.17), q, _s.set(0.025, 1.32, 0.025));
        }
      }
      // Upper floors.
      for (let f = 1; f < floors; f++) {
        const y = base + 0.9 + f * floorH + 1.2;
        B.place(box, this.mat.granite, at(u, y, 0.04), q, _s.set(1.2, 1.9, 0.12));
        B.place(box, style.window, at(u, y, 0.08), q, _s.set(0.9, 1.6, 0.08));
        // Lintel (+ keystone) and projecting sill.
        B.place(box, this.mat.granite, at(u, y + 0.98, 0.09), q, _s.set(1.36, 0.16, 0.16));
        if (style.keystones) B.place(box, this.mat.granite, at(u, y + 0.99, 0.13), q, _s.set(0.2, 0.26, 0.14));
        B.place(box, this.mat.granite, at(u, y - 0.99, 0.12), q, _s.set(1.34, 0.08, 0.28));
        // Open shutters either side.
        B.place(box, shutterMat, at(u - 0.82, y, 0.12), q, _s.set(0.45, 1.6, 0.05));
        B.place(box, shutterMat, at(u + 0.82, y, 0.12), q, _s.set(0.45, 1.6, 0.05));
        // First-floor balconies on some windows (granite slab on corbels + iron railing).
        if (f === 1 && this.rng() < 0.45) {
          const by = y - 0.95;
          B.place(box, this.mat.granite, at(u, by, 0.35), q, _s.set(1.6, 0.12, 0.7));
          for (const s of [-0.6, 0.6])
            B.place(box, this.mat.granite, at(u + s, by - 0.16, 0.25), q, _s.set(0.14, 0.22, 0.46));
          for (const ry of [by + 0.9, by + 0.12])
            B.place(box, this.mat.iron, at(u, ry, 0.68), q, _s.set(1.6, 0.05, 0.05));
          for (const s of [-1, 1])
            B.place(box, this.mat.iron, at(u + s * 0.78, by + 0.9, 0.38), q, _s.set(0.05, 0.05, 0.62));
          for (let k = 0; k <= 6; k++)
            B.place(box, this.mat.iron, at(u - 0.78 + k * 0.26, by + 0.45, 0.68), q, _s.set(0.035, 0.85, 0.035));
        } else if (style.flowers && rnd() < 0.5) {
          this._flowerBox(at(u, y - 0.86, 0.2), q, right);
        }
      }
    }
    // String courses at every floor.
    for (let f = 1; f < floors; f++)
      B.place(
        box,
        this.mat.granite,
        at(0, base + 0.9 + f * floorH - 0.05, 0.05),
        q,
        _s.set(len, f === 1 ? 0.18 : 0.12, 0.14),
      );

    // A wall lantern by some doors.
    if (!tavern && rnd() < 0.35) {
      const lu = -len / 2 + (doorSlot + 0.5) * spacing - 1.1;
      B.place(box, this.mat.iron, at(lu, ground + 2.9, 0.25), q, _s.set(0.04, 0.04, 0.42));
      this._lantern(at(lu, ground + 2.62, 0.42), 0.7);
    }

    if (tavern) {
      // Hanging wooden sign on an iron bracket + a lantern.
      B.place(box, this.mat.iron, at(-len * 0.3, base + 3.7, 0.6), q, _s.set(0.06, 0.06, 1.2));
      B.place(box, this.mat.wood, at(-len * 0.3, base + 3.25, 1.0), q, _s.set(0.06, 0.7, 0.9));
      this._lantern(at(len * 0.3, base + 3.6, 0.35));
    }
  }

  /** Terracotta window box with leaves and geraniums. */
  _flowerBox(pos, q, right) {
    const B = this.batch;
    const rnd = this.drng;
    B.place(this.geo.box, this.mat.terracotta, pos.clone().setY(pos.y + 0.1), q, _s.set(0.84, 0.2, 0.22));
    const flowers = this.mat.flowers[Math.floor(rnd() * this.mat.flowers.length)];
    for (let k = 0; k < 6; k++) {
      const p = pos
        .clone()
        .addScaledVector(right, -0.34 + k * 0.136 + (rnd() - 0.5) * 0.05)
        .setY(pos.y + 0.26 + rnd() * 0.06);
      const r = 0.09 + rnd() * 0.04;
      B.place(this.geo.clump, this.mat.foliage, p, null, _s.set(r, r * 0.8, r));
      B.place(this.geo.flower, flowers, p.setY(p.y + r * 0.7), null, _s.set(0.045, 0.045, 0.045));
    }
  }

  _lampPost(x, z) {
    const y = PROM_Y;
    const B = this.batch;
    // Granite pedestal, fluted iron column, scrolled arm and a caged lantern.
    B.place(this.geo.box, this.mat.graniteDark, _p.set(x, y + 0.2, z), null, _s.set(0.42, 0.4, 0.42));
    B.place(this.geo.cyl, this.mat.iron, _p.set(x, y + 0.55, z), null, _s.set(0.26, 0.3, 0.26));
    B.place(this.geo.cyl, this.mat.iron, _p.set(x, y + 2.0, z), null, _s.set(0.11, 2.9, 0.11));
    B.place(this.geo.cyl, this.mat.iron, _p.set(x, y + 0.75, z), null, _s.set(0.18, 0.08, 0.18));
    B.place(this.geo.cyl, this.mat.iron, _p.set(x, y + 3.42, z), null, _s.set(0.16, 0.06, 0.16));
    this._beam(
      this.geo.ridge,
      this.mat.iron,
      new THREE.Vector3(x, y + 3.4, z),
      new THREE.Vector3(x, y + 3.5, z - 0.55),
      0.05,
    );
    this._beam(
      this.geo.ridge,
      this.mat.iron,
      new THREE.Vector3(x, y + 3.05, z),
      new THREE.Vector3(x, y + 3.45, z - 0.3),
      0.035,
    );
    B.place(this.geo.sphere, this.mat.iron, _p.set(x, y + 3.55, z), null, _s.set(0.09, 0.09, 0.09));
    this._lantern(new THREE.Vector3(x, y + 3.2, z - 0.5));
    this.colliders.addBox(_p.set(x, y + 1.75, z), _s.set(0.2, 3.5, 0.2));
  }

  /** Caged lantern: iron cap and base, glowing glass, corner bars, finial. */
  _lantern(pos, scale = 1) {
    const B = this.batch;
    const k = scale;
    B.place(
      this.geo.cone,
      this.mat.iron,
      pos.clone().setY(pos.y + 0.2 * k),
      null,
      _s.set(0.42 * k, 0.16 * k, 0.42 * k),
    );
    B.place(
      this.geo.box,
      this.mat.iron,
      pos.clone().setY(pos.y - 0.21 * k),
      null,
      _s.set(0.28 * k, 0.04 * k, 0.28 * k),
    );
    B.place(this.geo.box, this.mat.lantern, pos, null, _s.set(0.22 * k, 0.38 * k, 0.22 * k), { castShadow: false });
    for (const [sx, sz] of [
      [-1, -1],
      [1, -1],
      [1, 1],
      [-1, 1],
    ])
      B.place(
        this.geo.box,
        this.mat.iron,
        _p.set(pos.x + sx * 0.12 * k, pos.y, pos.z + sz * 0.12 * k),
        null,
        _s.set(0.025 * k, 0.4 * k, 0.025 * k),
      );
    B.place(
      this.geo.sphere,
      this.mat.iron,
      pos.clone().setY(pos.y + 0.39 * k),
      null,
      _s.set(0.06 * k, 0.06 * k, 0.06 * k),
    );
  }

  // ---------------------------------------------------------------------------
  // Landmarks
  // ---------------------------------------------------------------------------
  /** Pointed (equilateral) gothic arch panel geometry: piers + arches cut from a wall. */
  static archPanelGeometry({ arches = 1, span = 2.4, pier = 0.9, spring = 2.6, height = 5.2, depth = 0.8 }) {
    const width = arches * span + (arches + 1) * pier;
    const s = new THREE.Shape();
    s.moveTo(0, 0);
    let x = 0;
    for (let i = 0; i < arches; i++) {
      x += pier;
      s.lineTo(x, 0);
      s.lineTo(x, spring);
      // Left arc: centre at right springing point, from angle π → 2π/3.
      s.absarc(x + span, spring, span, Math.PI, (2 * Math.PI) / 3, true);
      // Right arc: centre at left springing point, from π/3 → 0.
      s.absarc(x, spring, span, Math.PI / 3, 0, true);
      s.lineTo(x + span, 0);
      x += span;
    }
    s.lineTo(width, 0);
    s.lineTo(width, height);
    s.lineTo(0, height);
    s.closePath();
    const g = new THREE.ExtrudeGeometry(s, { depth, bevelEnabled: false, curveSegments: 10 });
    g.translate(-width / 2, 0, -depth / 2);
    g.computeVertexNormals();
    return { geometry: g, width, apex: spring + span * Math.sin(Math.PI / 3) };
  }

  /** Town hall (Paços do Concelho): open pointed arcade, upper floor, battlements. */
  _arcade(x0, x1, z0, z1) {
    const len = x1 - x0;
    const cx = (x0 + x1) / 2;
    const cz = (z0 + z1) / 2;
    const depth = z1 - z0;
    const base = plazaHeight(cx, z1) - 0.1;
    const arches = 5;
    const pier = 1.0;
    const span = (len - (arches + 1) * pier) / arches;
    const H = 5.4;
    const panel = CityBuilder.archPanelGeometry({ arches, span, pier, spring: 2.7, height: H, depth: 0.9 });
    const endPanel = CityBuilder.archPanelGeometry({
      arches: 2,
      span: (depth - 3 * pier) / 2,
      pier,
      spring: 2.7,
      height: H,
      depth: 0.9,
    });
    const B = this.batch;

    // South (plaza) and north faces; east end open onto the north street; west end abuts a house.
    for (const z of [z1 - 0.45, z0 + 0.45]) B.place(panel.geometry, this.mat.granite, _p.set(cx, base, z), null, null);
    B.place(
      endPanel.geometry,
      this.mat.granite,
      _p.set(x1 - 0.45, base, cz),
      _q.setFromAxisAngle(UP, Math.PI / 2),
      null,
    );
    B.place(this.geo.box, this.mat.granite, _p.set(x0 + 0.45, base + H / 2, cz), null, _s.set(0.9, H, depth));

    // Colliders: piers + everything above the arches.
    for (const z of [z1 - 0.45, z0 + 0.45]) {
      for (let i = 0; i <= arches; i++) {
        const px = x0 + pier / 2 + i * (span + pier);
        this.colliders.addBox(_p.set(px, base + H / 2, z), _s.set(pier, H, 0.9));
      }
    }
    // End panel piers (panel is rotated 90°, so its local X runs along world Z).
    for (const zz of [cz - depth / 2 + pier / 2, cz, cz + depth / 2 - pier / 2])
      this.colliders.addBox(_p.set(x1 - 0.45, base + H / 2, zz), _s.set(0.9, H, pier));
    this.colliders.addBox(_p.set(x0 + 0.45, base + H / 2, cz), _s.set(0.9, H, depth));
    this.colliders.addBox(_p.set(cx, base + (panel.apex + H) / 2, cz), _s.set(len, H - panel.apex, depth));

    // Vaulted ceiling (flat, dark wood) and upper floor.
    B.place(this.geo.box, this.mat.woodDark, _p.set(cx, base + H - 0.15, cz), null, _s.set(len - 1, 0.3, depth - 1));
    const upperH = 4.4;
    B.place(this.geo.box, this.mat.stucco[0], _p.set(cx, base + H + upperH / 2, cz), null, _s.set(len, upperH, depth));
    this.colliders.addBox(_p, _s);
    B.place(this.geo.box, this.mat.granite, _p.set(cx, base + H + 0.1, cz), null, _s.set(len + 0.3, 0.25, depth + 0.3));
    // Tall gothic windows (granite frame + pane) on the plaza face.
    for (let i = 0; i < arches; i++) {
      const px = x0 + pier + span / 2 + i * (span + pier);
      B.place(this.geo.box, this.mat.granite, _p.set(px, base + H + 2.2, z1 + 0.05), null, _s.set(1.2, 2.6, 0.14));
      B.place(this.geo.box, this.mat.windows[1], _p.set(px, base + H + 2.2, z1 + 0.09), null, _s.set(0.85, 2.25, 0.1));
      B.place(this.geo.box, this.mat.granite, _p.set(px, base + H + 2.2, z1 + 0.12), null, _s.set(0.1, 2.25, 0.06)); // mullion
    }
    // Banner mounts between the windows: iron rods parallel to the wall;
    // CityDressing hangs wind-driven Verlet banners from them.
    for (let i = 0; i < arches - 1; i++) {
      const px = x0 + pier + span + pier / 2 + i * (span + pier);
      const top = new THREE.Vector3(px, base + H + 3.7, z1 + 0.42);
      B.place(this.geo.box, this.mat.iron, top, null, _s.set(0.95, 0.04, 0.04));
      B.place(this.geo.box, this.mat.iron, _p.set(px, top.y, z1 + 0.2), null, _s.set(0.04, 0.04, 0.44));
      this.bannerMounts.push({ top, width: 0.78, length: 2.1, wall: { normal: new THREE.Vector3(0, 0, 1), z: z1 } });
    }
    // Battlements.
    const topY = base + H + upperH;
    for (const px of [x0 + 0.5, x1 - 0.5])
      this.pennantMounts.push({ base: new THREE.Vector3(px, topY + 0.3, z1 - 0.5), height: 3.6 });
    B.place(this.geo.box, this.mat.granite, _p.set(cx, topY + 0.15, cz), null, _s.set(len + 0.4, 0.3, depth + 0.4));
    const merlon = (x, z) =>
      B.place(this.geo.box, this.mat.granite, _p.set(x, topY + 0.75, z), null, _s.set(0.7, 0.9, 0.7));
    for (let x = x0 + 0.35; x <= x1 - 0.35; x += 1.4) {
      merlon(x, z0 + 0.1);
      merlon(x, z1 - 0.1);
    }
    for (let z = z0 + 1.5; z <= z1 - 1.5; z += 1.4) {
      merlon(x0 + 0.1, z);
      merlon(x1 - 0.1, z);
    }
  }

  /** Padrão do Salado–style gothic canopy: four pointed arches under a stone pyramid. */
  _shrine(x, z) {
    const size = 3.4;
    const base = plazaHeight(x, z) - 0.05;
    const H = 4.8;
    const p = CityBuilder.archPanelGeometry({ arches: 1, span: 2.2, pier: 0.6, spring: 2.5, height: H, depth: 0.5 });
    const B = this.batch;
    const half = size / 2 - 0.25;
    for (const [ox, oz, yaw] of [
      [0, half, 0],
      [0, -half, 0],
      [half, 0, Math.PI / 2],
      [-half, 0, Math.PI / 2],
    ])
      B.place(p.geometry, this.mat.granite, _p.set(x + ox, base, z + oz), _q.setFromAxisAngle(UP, yaw), null);
    // Stepped plinth.
    B.place(this.geo.box, this.mat.graniteDark, _p.set(x, base - 0.1, z), null, _s.set(size + 1.2, 0.4, size + 1.2));
    this.colliders.addBox(_p, _s);
    // Pyramid roof + finial cross.
    B.place(this.geo.box, this.mat.granite, _p.set(x, base + H + 0.15, z), null, _s.set(size + 0.3, 0.3, size + 0.3));
    B.place(this.geo.roof, this.mat.granite, _p.set(x, base + H + 0.3, z), null, _s.set(size + 0.2, 3.2, size + 0.2));
    B.place(this.geo.box, this.mat.granite, _p.set(x, base + H + 3.8, z), null, _s.set(0.14, 0.9, 0.14));
    B.place(this.geo.box, this.mat.granite, _p.set(x, base + H + 3.95, z), null, _s.set(0.55, 0.12, 0.14));
    // Colliders: corner piers + roof mass.
    for (const [ox, oz] of [
      [-1, -1],
      [1, -1],
      [-1, 1],
      [1, 1],
    ])
      this.colliders.addBox(
        _p.set(x + ox * (size / 2 - 0.35), base + H / 2, z + oz * (size / 2 - 0.35)),
        _s.set(0.7, H, 0.7),
      );
    this.colliders.addBox(_p.set(x, base + H + 1.2, z), _s.set(size, 2.4, size));
  }

  _oliveTree(x, z) {
    const g = plazaHeight(x, z);
    const B = this.batch;
    // Low granite planter.
    B.place(this.geo.cyl, this.mat.granite, _p.set(x, g + 0.25, z), null, _s.set(3.2, 0.5, 3.2));
    this.colliders.addCylinder(_p.set(x, g + 0.25, z), 0.25, 1.6);
    // Gnarled trunk: three leaning segments.
    const segs = [
      [0, 0, 0, 1.4, 0.18, 0.1],
      [0.15, 1.3, 0.05, 1.3, -0.3, 0.25],
      [-0.1, 1.2, 0.1, 1.2, 0.35, -0.2],
    ];
    for (const [ox, oy, oz, len, rz, rx] of segs) {
      _q.setFromEuler(new THREE.Euler(rx, 0, rz));
      B.place(this.geo.trunk, this.mat.bark, _p.set(x + ox, g + 0.5 + oy, z + oz), _q, _s.set(1, len, 1));
    }
    this.colliders.addCylinder(_p.set(x, g + 1.5, z), 1.0, 0.3);
    // Foliage clumps (silvery olive green, wind-swayed in the shader).
    const clumps = [
      [0, 3.4, 0, 1.6],
      [1.1, 3.0, 0.4, 1.2],
      [-1.0, 3.1, -0.3, 1.3],
      [0.3, 3.0, -1.1, 1.1],
      [-0.4, 3.9, 0.8, 1.0],
      [0.9, 3.8, -0.6, 0.9],
    ];
    for (const [ox, oy, oz, r] of clumps)
      B.place(
        this.geo.clump,
        this.mat.foliage,
        _p.set(x + ox, g + oy, z + oz),
        null,
        _s.set(r * 1.2, r * 0.85, r * 1.2),
      );
  }

  _streetArch(x0, x1, z) {
    const span = x1 - x0;
    const g = northStreetHeight((x0 + x1) / 2, z);
    const panel = CityBuilder.archPanelGeometry({
      arches: 1,
      span: span - 0.4,
      pier: 0.2,
      spring: 3.4,
      height: 7.6,
      depth: 2.6,
    });
    this.batch.place(panel.geometry, this.mat.graniteWall, _p.set((x0 + x1) / 2, g - 0.3, z), _q.identity(), null);
    this.batch.place(
      this.geo.roof,
      this.mat.roof,
      _p.set((x0 + x1) / 2, g + 7.3, z),
      null,
      _s.set(span + 0.8, 1.4, 3.4),
    );
    this.colliders.addBox(
      _p.set((x0 + x1) / 2, g - 0.3 + (panel.apex + 7.6) / 2, z),
      _s.set(span, 7.6 - panel.apex, 2.6),
    );
  }

  // ---------------------------------------------------------------------------
  // Furniture (interactive)
  // ---------------------------------------------------------------------------
  _furniture() {
    // Granite benches around the square and along the promenade (facing the sea).
    const benches = [
      [-19, -64, Math.PI / 2],
      [-19, -88, Math.PI / 2],
      [-6, -94, 0],
      [3, -70, Math.PI],
      [-22, -42.1, 0],
      [-12, -42.1, 0],
      [14, -42.1, 0],
      [24, -42.1, 0],
      [-64, -42.1, 0],
      [62, -42.1, 0],
    ];
    for (const [x, z, yaw] of benches) this.bench(x, z, yaw);
    // Tavern terrace in front of the tavern (east side of the square).
    this.tavernTable(19.5, -63.5, Math.PI / 2);
    this.tavernTable(19.5, -68.5, Math.PI / 2);
  }

  /** Granite bench: slab on two blocks. Two seat anchors. Faces +Z (rotated by yaw). */
  bench(x, z, yaw = 0) {
    const g = cityGroundHeight(x, z) ?? PROM_Y;
    const root = staticRoot(new THREE.Vector3(x, g, z), yaw);
    const q = root.quaternion;
    const seatH = 0.46;
    const put = (geo, mat, lx, ly, lz, sx, sy, sz, collide = true) => {
      _p.set(lx, ly, lz).applyQuaternion(q).add(root.position);
      this.batch.place(geo, mat, _p, q, _s.set(sx, sy, sz));
      if (collide) this.colliders.addBox(_p, _s, q);
    };
    put(this.geo.box, this.mat.granite, 0, seatH - 0.06, 0, 1.9, 0.12, 0.52);
    put(this.geo.box, this.mat.graniteDark, -0.65, (seatH - 0.12) / 2 - 0.05, 0, 0.28, seatH - 0.02, 0.44);
    put(this.geo.box, this.mat.graniteDark, 0.65, (seatH - 0.12) / 2 - 0.05, 0, 0.28, seatH - 0.02, 0.44);
    const anchors = [-0.45, 0.45].map(
      (lx, i) =>
        new Anchor({
          id: `seat${i}`,
          position: new THREE.Vector3(lx, seatH, -0.02),
          meta: { seatHeight: seatH, standOffset: new THREE.Vector3(0, -seatH, 0.62) },
        }),
    );
    this.interactables.push(
      new Interactable({
        type: INTERACTION_TYPE.SEAT,
        label: 'Sit',
        object: root,
        anchors,
        radius: 1.8,
        center: new THREE.Vector3(0, 0.5, 0.3),
      }),
    );
  }

  /** Tavern table with a wooden bench on each long side (one interactable per bench). */
  tavernTable(x, z, yaw = 0) {
    const g = cityGroundHeight(x, z) ?? PROM_Y;
    const root = staticRoot(new THREE.Vector3(x, g, z), yaw);
    const q = root.quaternion;
    const put = (mat, lx, ly, lz, sx, sy, sz, collide = true) => {
      _p.set(lx, ly, lz).applyQuaternion(q).add(root.position);
      this.batch.place(this.geo.box, mat, _p, q, _s.set(sx, sy, sz));
      if (collide) this.colliders.addBox(_p, _s, q, { surface: SURFACE.WOOD });
    };
    // Table top + trestle legs.
    put(this.mat.wood, 0, 0.76, 0, 1.8, 0.07, 0.85);
    put(this.mat.woodDark, -0.7, 0.37, 0, 0.1, 0.74, 0.6, false);
    put(this.mat.woodDark, 0.7, 0.37, 0, 0.1, 0.74, 0.6, false);
    this.colliders.addBox(_p.set(0, 0.37, 0).applyQuaternion(q).add(root.position), _s.set(1.5, 0.74, 0.6), q, {
      surface: SURFACE.WOOD,
    });
    // Benches on both sides; anchors face the table.
    const seatH = 0.45;
    for (const side of [-1, 1]) {
      const bz = side * 0.78;
      put(this.mat.wood, 0, seatH - 0.03, bz, 1.7, 0.06, 0.32);
      put(this.mat.woodDark, -0.65, (seatH - 0.06) / 2, bz, 0.08, seatH - 0.06, 0.28, false);
      put(this.mat.woodDark, 0.65, (seatH - 0.06) / 2, bz, 0.08, seatH - 0.06, 0.28, false);
      // Facing the table: the anchor's +Z points to -side.
      const faceQ = new THREE.Quaternion().setFromAxisAngle(UP, side > 0 ? Math.PI : 0);
      const anchors = [-0.42, 0.42].map(
        (lx, i) =>
          new Anchor({
            id: `tavern${side}-${i}`,
            position: new THREE.Vector3(lx, seatH, bz + side * 0.02),
            quaternion: faceQ,
            meta: { seatHeight: seatH, standOffset: new THREE.Vector3(0, -seatH, -0.55), pose: 'sitTable' },
          }),
      );
      this.interactables.push(
        new Interactable({
          type: INTERACTION_TYPE.SEAT,
          label: 'Sit at the table',
          object: root,
          anchors,
          radius: 1.5,
          center: new THREE.Vector3(0, 0.5, side * 1.15),
        }),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // World bounds (only stop characters & vehicles)
  // ---------------------------------------------------------------------------
  _bounds() {
    const P = WORLD.promenade;
    const B = WORLD.beach;
    const opts = { groups: GROUPS.BOUNDS };
    for (const x of [P.xMax + 0.5, P.xMin - 0.5])
      this.colliders.addBox(_p.set(x, 5, (P.zSea + P.zLand) / 2), _s.set(1, 10, P.zSea - P.zLand + 2), null, opts);
    for (const x of [B.xMax - 1, B.xMin + 1])
      this.colliders.addBox(_p.set(x, 0, (B.zMin + B.zMax) / 2), _s.set(1, 20, B.zMax - B.zMin), null, opts);
    this.colliders.addBox(_p.set(0, 0, WORLD.wadeLimitZ), _s.set(B.xMax - B.xMin, 20, 1), null, opts);
  }
}

function mulberry(seed) {
  return () => {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
