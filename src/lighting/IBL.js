import * as THREE from 'three';
import { sharedUniforms, SHARED_UNIFORMS_GLSL, SKY_GLSL } from '../shaders/common.glsl.js';

/**
 * Procedural image-based lighting.
 *
 * Renders a deliberately *low-frequency, over-exposed* HDR version of the sky
 * (no clouds, no sun disc — just the gradient, a broad sun lobe and a warm
 * ground bounce) into a PMREM. As `scene.environment` it replaces the old
 * hemisphere light: every MeshStandardMaterial now receives sky-coloured
 * irradiance from above, sand/stone-coloured bounce from below and soft,
 * roughness-correct specular reflections — the "path-traced bounce" feel.
 *
 * Regenerate whenever the sun or sky colours change (time of day).
 */
export class SkyIBL {
  constructor(renderer, { size = 128, exposure = 1.6, groundBounce = 0.85, blur = 0.02 } = {}) {
    this.renderer = renderer;
    this.size = size;
    this.blur = blur;
    this.pmrem = new THREE.PMREMGenerator(renderer);
    this.target = null;

    this.uniforms = {
      ...sharedUniforms,
      uExposure: { value: exposure },
      uGroundBounce: { value: groundBounce },
    };
    const material = new THREE.ShaderMaterial({
      name: 'IBLSky',
      side: THREE.BackSide,
      depthWrite: false,
      uniforms: this.uniforms,
      vertexShader: /* glsl */ `
        varying vec3 vDir;
        void main() {
          vDir = normalize(position);
          gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
        }
      `,
      fragmentShader: /* glsl */ `
        ${SHARED_UNIFORMS_GLSL}
        ${SKY_GLSL}
        uniform float uExposure;
        uniform float uGroundBounce;
        varying vec3 vDir;
        void main() {
          vec3 d = normalize(vDir);
          vec3 sky = stySkyColor(normalize(vec3(d.x, max(d.y, 0.02), d.z)), false);
          // Ground bounce: sunlit sand/stone, brighter on the sun side.
          float sunSide = 0.6 + 0.4 * max(dot(normalize(vec3(d.x, 0.0, d.z) + 1e-4), normalize(vec3(uSunDir.x, 0.0, uSunDir.z))), 0.0);
          vec3 ground = uSkyGround * uGroundBounce * sunSide * (0.55 + 0.45 * max(uSunDir.y, 0.0) * 2.0);
          vec3 col = mix(sky, ground, smoothstep(0.02, -0.18, d.y));
          gl_FragColor = vec4(col * uExposure, 1.0);
        }
      `,
    });
    this.scene = new THREE.Scene();
    this.scene.add(new THREE.Mesh(new THREE.SphereGeometry(10, 48, 24), material));
  }

  /** (Re)builds the PMREM and returns the environment texture. */
  update() {
    const old = this.target;
    this.target = this.pmrem.fromScene(this.scene, this.blur, 0.1, 100, { size: this.size });
    old?.dispose();
    return this.target.texture;
  }

  dispose() {
    this.target?.dispose();
    this.pmrem.dispose();
  }
}
