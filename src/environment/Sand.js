import * as THREE from 'three';
import { PALETTE, WORLD, GROUPS, SURFACE } from '../config.js';
import { sharedUniforms } from '../shaders/common.glsl.js';
import { patchStylizedVertex, patchStylizedFragment } from '../shaders/StylizedMaterial.js';
import { heightFogUniforms } from '../lighting/ShaderPatches.js';
import { SAND_HEIGHT_GLSL, sandHeight } from './Terrain.js';
import { GerstnerWaves, OCEAN_LOD_CENTER } from './GerstnerWaves.js';

/**
 * Beach sand.
 *
 * Visual: a flat grid displaced in the vertex shader by `sandHeight()` (soft
 * dunes), with analytic normals, fine grain, wind-aligned ripples and
 * shimmering sun glints on individual grains, lit by the stylised PBR patch.
 *
 * Dampness is a continuous, multi-state field driven by the *live* Gerstner
 * swash (same wave function as the ocean and buoyancy):
 *   film      thin sheet of water just above the instantaneous waterline:
 *             darkest albedo, mirror-smooth (reflects the sky through IBL)
 *   wet       below the reach of recent waves (wave envelope): dark, glossy
 *   damp      upper intertidal band + noisy patches/puddles: slightly dark
 *   dry       light, rough, sparkly
 * Roughness is driven per pixel, so the wet sheen is physically based.
 *
 * Physics: a Rapier heightfield sampled from the same `sandHeight()` on the
 * same grid, so what you see is what you walk/drive on.
 */
export class Sand {
  /**
   * @param {import('../core/PhysicsWorld.js').PhysicsWorld} physics
   * @param {import('./GerstnerWaves.js').GerstnerWaves} waves
   */
  constructor(physics, waves = new GerstnerWaves()) {
    const B = WORLD.beach;
    this.waves = waves;
    this.width = B.xMax - B.xMin;
    this.depth = B.zMax - B.zMin;
    this.center = new THREE.Vector2((B.xMin + B.xMax) / 2, (B.zMin + B.zMax) / 2);
    this.cols = Math.round(this.width / B.cellSize); // cells along X
    this.rows = Math.round(this.depth / B.cellSize); // cells along Z

    this.mesh = this._createMesh();
    this.collider = this._createCollider(physics);
  }

  _createMesh() {
    const geometry = new THREE.PlaneGeometry(this.width, this.depth, this.cols, this.rows);
    geometry.rotateX(-Math.PI / 2);
    geometry.translate(this.center.x, 0, this.center.y);
    // The vertex shader moves vertices vertically by up to ~3 m; make sure
    // frustum culling knows about it.
    geometry.boundingBox = new THREE.Box3(
      new THREE.Vector3(-this.width / 2 + this.center.x, -8, -this.depth / 2 + this.center.y),
      new THREE.Vector3(this.width / 2 + this.center.x, 6, this.depth / 2 + this.center.y),
    );
    geometry.boundingSphere = geometry.boundingBox.getBoundingSphere(new THREE.Sphere());

    const material = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.95, metalness: 0, name: 'Sand' });
    material.defines = { STY_HEIGHT_FOG: '' };
    const w = this.waves;
    // Highest crest the attenuated swell can reach on the beach (wave envelope).
    const envelope = w.waves.reduce((s, wave) => s + wave.steepness / wave.k, 0) * 0.35;
    const local = {
      uStyWrap: { value: 0.5 },
      uStySoftness: { value: 0.6 },
      uStyRim: { value: 0.08 },
      uStyPainterly: { value: 0.07 },
      uStyPainterlyScale: { value: 0.12 },
      uStyHeightGrad: { value: new THREE.Vector3(0, 1, 0) },
      uStyTriScale: { value: 0 },
      uStyWindSway: { value: 0 },
      uStyAOIntensity: { value: 1 },
      uSandDry: { value: new THREE.Color(PALETTE.sand) },
      uSandWet: { value: new THREE.Color(PALETTE.sandWet) },
      uWaves: { value: w.uniformWaves },
      uWavePhases: { value: w.uniformPhases },
      uWaterLevel: { value: WORLD.waterLevel },
      uLodCenter: { value: OCEAN_LOD_CENTER },
      uSwashEnvelope: { value: envelope },
    };
    material.userData.uniforms = local;
    material.onBeforeCompile = (shader) => {
      Object.assign(shader.uniforms, sharedUniforms, heightFogUniforms, local);
      patchSandVertex(shader);
      patchSandFragment(shader, w);
      patchStylizedVertex(shader);
      patchStylizedFragment(shader);
    };
    material.customProgramCacheKey = () => 'sand-pbr-v2';

    const mesh = new THREE.Mesh(geometry, material);
    mesh.name = 'Sand';
    mesh.receiveShadow = true;
    mesh.matrixAutoUpdate = false;
    return mesh;
  }

  _createCollider(physics) {
    const { RAPIER } = physics;
    const nrows = this.rows;
    const ncols = this.cols;
    // Rapier heightfield layout: rows run along Z, columns along X,
    // column-major storage: index = col * (nrows + 1) + row.
    const heights = new Float32Array((nrows + 1) * (ncols + 1));
    for (let c = 0; c <= ncols; c++) {
      const x = this.center.x - this.width / 2 + (this.width * c) / ncols;
      for (let r = 0; r <= nrows; r++) {
        const z = this.center.y - this.depth / 2 + (this.depth * r) / nrows;
        heights[c * (nrows + 1) + r] = sandHeight(x, z);
      }
    }
    const desc = RAPIER.ColliderDesc.heightfield(nrows, ncols, heights, {
      x: this.width,
      y: 1,
      z: this.depth,
    })
      .setTranslation(this.center.x, 0, this.center.y)
      .setFriction(SURFACE.SAND.friction)
      .setCollisionGroups(GROUPS.STATIC);
    return physics.createCollider(desc, undefined, { surface: SURFACE.SAND, owner: 'sand' });
  }
}

function patchSandVertex(shader) {
  shader.vertexShader = shader.vertexShader
    .replace('#include <common>', `#include <common>\n${SAND_HEIGHT_GLSL}`)
    .replace(
      '#include <beginnormal_vertex>',
      /* glsl */ `#include <beginnormal_vertex>
      vec2 sandP = (modelMatrix * vec4(position, 1.0)).xz;
      float sandH = sandHeight(sandP);
      {
        const float e = 0.35;
        float hx = sandHeight(sandP + vec2(e, 0.0)) - sandHeight(sandP - vec2(e, 0.0));
        float hz = sandHeight(sandP + vec2(0.0, e)) - sandHeight(sandP - vec2(0.0, e));
        objectNormal = normalize(vec3(-hx, 2.0 * e, -hz));
      }`,
    )
    .replace('#include <begin_vertex>', `#include <begin_vertex>\ntransformed.y += sandH;`);
}

function patchSandFragment(shader, waves) {
  shader.fragmentShader = shader.fragmentShader
    .replace(
      '#include <common>',
      /* glsl */ `#include <common>
      ${SAND_HEIGHT_GLSL}
      ${waves.glsl}
      uniform vec3 uSandDry;
      uniform vec3 uSandWet;
      uniform float uSwashEnvelope;
      float sandWetness = 0.0;  // 0 dry → 1 saturated
      float sandFilm = 0.0;     // water sheet on top of the sand`,
    )
    .replace(
      '#include <color_fragment>',
      /* glsl */ `#include <color_fragment>
      {
        vec2 p = vStyWorldPos.xz;
        float y = vStyWorldPos.y;
        // Instantaneous swash height at this point (vertical Gerstner term;
        // horizontal displacement is negligible in the attenuated shallows).
        vec3 tg = vec3(1.0, 0.0, 0.0), bn = vec3(0.0, 0.0, 1.0); float jac;
        float swash = uWaterLevel + gerstner(p, uTime, tg, bn, jac).y;
        float n1 = styNoise2(p * 0.25);
        float n2 = styFbm2(p * 0.08 + 3.7);
        // States (each a smooth 0..1 band):
        float film = 1.0 - smoothstep(swash + 0.02, swash + 0.14 + 0.06 * n1, y);
        float wet = 1.0 - smoothstep(uWaterLevel + uSwashEnvelope * 0.6, uWaterLevel + uSwashEnvelope + 0.25 + 0.3 * n1, y);
        float damp = 1.0 - smoothstep(uWaterLevel + 0.9, uWaterLevel + 1.6 + 0.6 * n2, y);
        // Patches of damp sand / shallow puddles in the lower beach.
        float patches = smoothstep(0.62, 0.72, n2) * (1.0 - smoothstep(uWaterLevel + 1.0, uWaterLevel + 1.8, y));
        sandFilm = max(film, patches * 0.6);
        sandWetness = clamp(max(max(film, wet * 0.82), max(damp * 0.38, patches * 0.7)), 0.0, 1.0);

        vec3 sandCol = mix(uSandDry, uSandWet, smoothstep(0.0, 0.85, sandWetness));
        sandCol *= mix(1.0, 0.82, sandFilm); // water darkens further
        float grain = styNoise2(p * 31.0) * 0.6 + styNoise2(p * 83.0) * 0.4;
        sandCol *= 0.93 + 0.13 * grain * (1.0 - sandWetness * 0.6);
        diffuseColor.rgb *= sandCol;
      }`,
    )
    .replace(
      '#include <roughnessmap_fragment>',
      /* glsl */ `#include <roughnessmap_fragment>
      // Physically based wet sheen: water fills the micro-relief.
      roughnessFactor = mix(roughnessFactor, 0.4, smoothstep(0.3, 0.85, sandWetness));
      roughnessFactor = mix(roughnessFactor, 0.16, sandFilm);`,
    )
    .replace(
      '#include <normal_fragment_maps>',
      /* glsl */ `#include <normal_fragment_maps>
      {
        // Wind ripples: crests perpendicular to the wind, warped by noise,
        // only on dry sand and faded with distance (avoids aliasing).
        vec2 p = vStyWorldPos.xz;
        vec2 wd = normalize(uWindDir.xz + vec2(1e-4));
        float dry = 1.0 - smoothstep(0.1, 0.4, sandWetness);
        float dist = length(cameraPosition - vStyWorldPos);
        float ph = dot(p, wd) * 5.2 + styNoise2(p * 0.35) * 6.0;
        float slope = cos(ph + 0.45 * sin(ph)); // asymmetric ripple profile
        vec2 g = wd * slope * 0.16 * dry * (1.0 - smoothstep(8.0, 35.0, dist));
        // Swash film: tiny moving ripples on the water sheet.
        float fp = dot(p, vec2(0.7, -0.7)) * 9.0 - uTime * 2.0;
        g += vec2(0.7, -0.7) * cos(fp) * 0.04 * sandFilm * (1.0 - smoothstep(6.0, 25.0, dist));
        normal = normalize(normal + (viewMatrix * vec4(-g.x, 0.0, -g.y, 0.0)).xyz);
      }`,
    )
    .replace(
      '#include <lights_fragment_end>',
      /* glsl */ `#include <lights_fragment_end>
      {
        vec3 V = normalize(cameraPosition - vStyWorldPos);
        vec3 N = normalize(vStyWorldNormal);
        // Grain glints: a few cells get a randomly tilted micro-normal and
        // flash when it mirrors the sun — the classic "shimmering sand".
        vec2 cell = floor(vStyWorldPos.xz * 26.0);
        float h = styHash12(cell);
        vec3 j = vec3(styHash12(cell + 3.1), styHash12(cell + 7.7), styHash12(cell + 11.3)) - 0.5;
        vec3 gn = normalize(N + j * 1.6);
        float glint = pow(max(dot(reflect(-V, gn), uSunDir), 0.0), 70.0) * step(0.82, h);
        float dist = length(cameraPosition - vStyWorldPos);
        glint *= (1.0 - smoothstep(5.0, 24.0, dist)) * (1.0 - sandWetness);
        reflectedLight.directDiffuse += styDirect * glint * 3.0;
      }`,
    );
}
