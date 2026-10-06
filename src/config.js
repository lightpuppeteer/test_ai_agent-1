/**
 * Global configuration: art palette, physics constants, collision groups,
 * input bindings and world layout. Everything that a designer may want to
 * tweak lives here so that systems stay data-driven.
 */

// ---------------------------------------------------------------------------
// Art direction — Guimarães architecture under a warm late-afternoon sky.
// Colours are authored in sRGB hex; THREE.Color converts them to linear.
// ---------------------------------------------------------------------------
export const PALETTE = {
  // Architecture
  granite: 0xa49b8c,
  graniteDark: 0x7b7368,
  graniteWarm: 0xb7a58c,
  stucco: 0xf2ebdf,
  stuccoShade: 0xe6d9c4,
  roofClay: 0xb4532f,
  roofClayDark: 0x8f3f24,
  wood: 0x7d5538,
  woodDark: 0x553826,
  ironwork: 0x2f2b28,
  shutterGreen: 0x4d6b5a,
  shutterBlue: 0x456a86,

  // Nature
  sand: 0xe6cb9b,
  sandWet: 0xb99c70,
  foliage: 0x6f8a4c,
  foliageDark: 0x4f6a3a,
  bark: 0x6b5442,

  // Water
  oceanDeep: 0x1b5568,
  oceanMid: 0x2e8a92,
  oceanShallow: 0x6cc9bd,
  foam: 0xf7f1e6,

  // Sky / atmosphere
  skyZenith: 0x5f93bf,
  skyHorizon: 0xf2d4ae,
  skyGround: 0xe0c7a4,
  sun: 0xffdcb0,
  hemiSky: 0xb7d2ea,
  hemiGround: 0xd8b48a,

  // Characters / props
  tunic: 0xc98e3f,
  trousers: 0x3e4a57,
  cloak: 0x2f6f73,
  scarf: 0xb8442e,
  skin: 0xe2b48f,
  hair: 0x3b2a20,
  carBody: 0x8fb6b0,
  carTrim: 0xe9e2d2,
  towels: [0xd9534f, 0x3f88c5, 0xf2b134, 0x4ea36d],
};

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------
export const RENDER = {
  maxPixelRatio: 1.75,
  antialias: 'smaa', // 'smaa' | 'none'
  exposure: 1.0,

  // --- Sun shadows ---------------------------------------------------------
  shadowMapSize: 4096,
  shadowFrustum: 40, // half-size (m) of the orthographic sun shadow camera
  shadow: {
    near: 1,
    far: 220,
    bias: -0.00025, // depth bias (acne)
    normalBias: 0.022, // world-space offset along normals (acne on slopes) without peter-panning
    radius: 3.0, // max penumbra scale in texels (contact-hardening patch scales it)
    taps: 12, // PCF taps per pixel
    lightAngle: 0.03, // apparent sun size (rad): penumbra growth with blocker distance
  },

  // --- Image-based lighting (procedural sky PMREM) -------------------------
  ibl: { exposure: 1.1, intensity: 1.0, groundBounce: 0.85, size: 128 },

  // --- Atmosphere ------------------------------------------------------------
  fogDensity: 0.0022, // distance FogExp2 (horizon)
  heightFog: { density: 0.0018, falloff: 0.12, base: 0.0 },

  // --- Post-processing -------------------------------------------------------
  ao: { enabled: true, radius: 0.85, intensity: 0.8, bias: 0.025, samples: 12, scale: 0.5 },
  bloom: { strength: 0.16, radius: 0.65, threshold: 0.86 },
  grading: {
    saturation: 1.04,
    contrast: 1.03,
    shadowTint: [0.97, 0.99, 1.02], // the creative split-tone lives in the LUT
    highlightTint: [1.02, 1.0, 0.97],
    vignette: 0.3,
    grain: 0.022,
  },
  lut: { enabled: true, intensity: 0.85, size: 32 },
};

// ---------------------------------------------------------------------------
// Physics
// ---------------------------------------------------------------------------
export const PHYSICS = {
  gravity: -9.81,
  fixedTimeStep: 1 / 60,
  maxSubSteps: 5, // avoids the "spiral of death" after tab switches
  waterDensity: 1025, // kg/m^3 (sea water)
};

/**
 * Collision layers (16-bit membership / filter masks, Rapier convention).
 * Two colliders interact when each one's membership intersects the other's filter.
 */
export const LAYER = {
  STATIC: 1 << 0,
  CHARACTER: 1 << 1,
  VEHICLE: 1 << 2,
  DYNAMIC: 1 << 3,
  BOUNDS: 1 << 4,
  ALL: 0xffff,
};

/** Packs membership + filter into Rapier's 32-bit InteractionGroups. */
export function collisionGroups(membership, filter) {
  return (((membership & 0xffff) << 16) | (filter & 0xffff)) >>> 0;
}

export const GROUPS = {
  STATIC: collisionGroups(LAYER.STATIC, LAYER.ALL),
  CHARACTER: collisionGroups(LAYER.CHARACTER, LAYER.STATIC | LAYER.VEHICLE | LAYER.DYNAMIC | LAYER.BOUNDS),
  VEHICLE: collisionGroups(
    LAYER.VEHICLE,
    LAYER.STATIC | LAYER.CHARACTER | LAYER.VEHICLE | LAYER.DYNAMIC | LAYER.BOUNDS,
  ),
  DYNAMIC: collisionGroups(LAYER.DYNAMIC, LAYER.STATIC | LAYER.CHARACTER | LAYER.VEHICLE | LAYER.DYNAMIC),
  BOUNDS: collisionGroups(LAYER.BOUNDS, LAYER.CHARACTER | LAYER.VEHICLE),

  // Query filters (scene queries test against collider groups the same way).
  QUERY_CHARACTER: collisionGroups(LAYER.CHARACTER, LAYER.STATIC | LAYER.VEHICLE | LAYER.DYNAMIC | LAYER.BOUNDS),
  QUERY_CAMERA: collisionGroups(LAYER.ALL, LAYER.STATIC),
  QUERY_WHEELS: collisionGroups(LAYER.VEHICLE, LAYER.STATIC | LAYER.DYNAMIC),
  QUERY_SPAWN: collisionGroups(LAYER.CHARACTER, LAYER.STATIC | LAYER.VEHICLE | LAYER.DYNAMIC),
};

/** Surface materials drive tyre grip, footstep feel, etc. Stored in collider user data. */
export const SURFACE = {
  STONE: { name: 'stone', grip: 1.0, friction: 0.9 },
  SAND: { name: 'sand', grip: 0.72, friction: 0.75 },
  WOOD: { name: 'wood', grip: 0.95, friction: 0.8 },
};

// ---------------------------------------------------------------------------
// Input (KeyboardEvent.code values)
// ---------------------------------------------------------------------------
export const INPUT_BINDINGS = {
  forward: ['KeyW', 'ArrowUp'],
  backward: ['KeyS', 'ArrowDown'],
  left: ['KeyA', 'ArrowLeft'],
  right: ['KeyD', 'ArrowRight'],
  run: ['ShiftLeft', 'ShiftRight'],
  jump: ['Space'],
  interact: ['KeyE'],
  handbrake: ['Space'],
  debugPhysics: ['KeyP'],
  toggleHelp: ['KeyH'],
  cycleOutfit: ['KeyO'],
  toggleProfile: ['KeyG'],
};

// ---------------------------------------------------------------------------
// Player character
// ---------------------------------------------------------------------------
export const CHARACTER = {
  // Authored character (Blender → glTF, see art/blender). Set to null to use the
  // procedural, morphable body below.
  asset: `${import.meta.env?.BASE_URL ?? '/'}assets/characters/heroine.glb`,
  femininity: 1, // procedural body: 0 = masculine profile … 1 = feminine profile (morphable at runtime)
  outfit: 'explorer', // explorer | skirtShirt | silverDress | bikini (authored character: explorer)
};

// ---------------------------------------------------------------------------
// World layout (metres). +Z points out to sea, -Z inland towards the old town.
// ---------------------------------------------------------------------------
export const WORLD = {
  waterLevel: 0,
  promenade: { zSea: -40, zLand: -52, height: 3.0, xMin: -110, xMax: 110 },
  beach: { xMin: -120, xMax: 120, zMin: -40, zMax: 120, cellSize: 1.0 },
  // Where the beach meets the water, the character is stopped by an invisible
  // wall (no swimming in this boilerplate).
  wadeLimitZ: 36,
  spawn: { x: 2, z: -44.2, yaw: 0 }, // on the promenade, facing the sea
  // Azimuth measured from +Z (the sea) towards +X. A low sun over the Atlantic
  // back-lights the waves and paints the sea-facing façades warm.
  sun: { azimuthDeg: -28, elevationDeg: 24 },
};
