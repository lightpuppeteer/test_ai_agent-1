import * as THREE from 'three';
import { PALETTE } from '../config.js';

/**
 * Uniforms shared *by reference* across every custom/patched material.
 * Updating `.value` once per frame (Environment / WindSystem) updates the
 * whole scene: sun, sky gradient, wind and time stay coherent everywhere.
 */
export const sharedUniforms = {
  uTime: { value: 0 },
  uSunDir: { value: new THREE.Vector3(0, 1, 0) }, // world-space, towards the sun
  uSunColor: { value: new THREE.Color(PALETTE.sun) },
  uSkyZenith: { value: new THREE.Color(PALETTE.skyZenith) },
  uSkyHorizon: { value: new THREE.Color(PALETTE.skyHorizon) },
  uSkyGround: { value: new THREE.Color(PALETTE.skyGround) },
  uWindDir: { value: new THREE.Vector3(1, 0, 0) }, // normalised, horizontal
  uWindStrength: { value: 0.5 }, // 0..1 (gusts included)
  uWindPhase: { value: 0 }, // ∫ strength dt — coherent scrolling for sway/ripples
  uWindOffset: { value: new THREE.Vector3() }, // ∫ wind velocity dt (m) — particles
};

export const SHARED_UNIFORMS_GLSL = /* glsl */ `
  uniform float uTime;
  uniform vec3 uSunDir;
  uniform vec3 uSunColor;
  uniform vec3 uSkyZenith;
  uniform vec3 uSkyHorizon;
  uniform vec3 uSkyGround;
  uniform vec3 uWindDir;
  uniform float uWindStrength;
  uniform float uWindPhase;
  uniform vec3 uWindOffset;
`;

/** Hash / value-noise / fBm helpers (no sin() hashes → stable on all GPUs). */
export const NOISE_GLSL = /* glsl */ `
  float styHash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
  }
  float styHash13(vec3 p3) {
    p3 = fract(p3 * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
  }
  float styNoise2(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = styHash12(i);
    float b = styHash12(i + vec2(1.0, 0.0));
    float c = styHash12(i + vec2(0.0, 1.0));
    float d = styHash12(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
  }
  float styNoise3(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    vec3 u = f * f * (3.0 - 2.0 * f);
    float n000 = styHash13(i);
    float n100 = styHash13(i + vec3(1, 0, 0));
    float n010 = styHash13(i + vec3(0, 1, 0));
    float n110 = styHash13(i + vec3(1, 1, 0));
    float n001 = styHash13(i + vec3(0, 0, 1));
    float n101 = styHash13(i + vec3(1, 0, 1));
    float n011 = styHash13(i + vec3(0, 1, 1));
    float n111 = styHash13(i + vec3(1, 1, 1));
    return mix(
      mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
      mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y),
      u.z);
  }
  float styFbm2(vec2 p) {
    float s = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { s += a * styNoise2(p); p = p * 2.03 + 17.1; a *= 0.5; }
    return s / 0.9375;
  }
  float styFbm3(vec3 p) {
    float s = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { s += a * styNoise3(p); p = p * 2.01 + 11.7; a *= 0.5; }
    return s / 0.9375;
  }
  // Domain-warped noise that reads like broad brush strokes.
  float styPainterly(vec3 p) {
    vec3 w = vec3(styNoise3(p * 0.7), styNoise3(p * 0.7 + 5.2), styNoise3(p * 0.7 + 9.7));
    return styFbm3(p + w * 1.7);
  }
`;

/**
 * Stylised sky gradient shared by the skybox, the ocean reflections and the
 * fog colour logic. `dir` must be normalised. Requires SHARED_UNIFORMS_GLSL.
 */
export const SKY_GLSL = /* glsl */ `
  vec3 stySkyColor(vec3 dir, bool withSun) {
    float y = dir.y;
    // Horizon → zenith: a long, soft, slightly warm-biased gradient.
    float up = pow(clamp(y, 0.0, 1.0), 0.45);
    vec3 col = mix(uSkyHorizon, uSkyZenith, smoothstep(0.0, 1.0, up));
    // Below the horizon: haze settling into the ground colour.
    col = mix(col, uSkyGround, smoothstep(0.0, -0.25, y));

    // Warm glow around the sun spreading along the horizon.
    float sd = max(dot(dir, uSunDir), 0.0);
    float horizonBand = exp(-abs(y) * 6.0);
    col += uSunColor * (pow(sd, 6.0) * 0.35 + pow(sd, 2.0) * 0.12 * horizonBand);
    if (withSun) {
      // Soft painted disc (no hard edge) + bloom-friendly core.
      col += uSunColor * (smoothstep(0.9975, 0.9992, sd) * 6.0 + pow(sd, 400.0) * 1.5);
    }
    return col;
  }
`;
