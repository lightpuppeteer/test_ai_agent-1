import * as THREE from 'three';
import { sharedUniforms, SHARED_UNIFORMS_GLSL, NOISE_GLSL, SKY_GLSL } from '../shaders/common.glsl.js';

/**
 * Gradient sky dome with a soft painted sun and slow, wind-driven brush-stroke
 * clouds. The horizon colour is exactly the fog colour, so FogExp2 dissolves
 * distant geometry seamlessly into the sky.
 */
export class Sky {
  constructor({ radius = 900 } = {}) {
    const geometry = new THREE.SphereGeometry(radius, 48, 24);
    const material = new THREE.ShaderMaterial({
      name: 'SkyDome',
      side: THREE.BackSide,
      depthWrite: false,
      fog: false,
      uniforms: { ...sharedUniforms, uCloudCover: { value: 0.42 } },
      vertexShader: /* glsl */ `
        varying vec3 vDir;
        void main() {
          vec4 wp = modelMatrix * vec4(position, 1.0);
          vDir = wp.xyz - cameraPosition;
          gl_Position = projectionMatrix * viewMatrix * wp;
          gl_Position.z = gl_Position.w; // pin to the far plane
        }
      `,
      fragmentShader: /* glsl */ `
        ${SHARED_UNIFORMS_GLSL}
        ${NOISE_GLSL}
        ${SKY_GLSL}
        uniform float uCloudCover;
        varying vec3 vDir;

        void main() {
          vec3 dir = normalize(vDir);
          vec3 col = stySkyColor(dir, true);

          // Painterly cloud layer projected on a flat ceiling.
          if (dir.y > 0.0) {
            vec2 uv = dir.xz / (dir.y + 0.12) * 0.55 + uWindOffset.xz * 0.0025;
            float n = styFbm2(uv * 1.1);
            float n2 = styFbm2(uv * 2.7 + 7.3);
            float cover = smoothstep(1.0 - uCloudCover, 1.0 - uCloudCover + 0.22, n * 0.8 + n2 * 0.25);
            cover *= smoothstep(0.02, 0.22, dir.y);
            // Self-shadow: sample slightly towards the sun.
            float toward = styFbm2((uv + uSunDir.xz * 0.08) * 1.1);
            float lit = clamp(0.55 + (n - toward) * 2.5, 0.0, 1.0);
            float sd = max(dot(dir, uSunDir), 0.0);
            vec3 cloudShadow = mix(uSkyZenith, uSkyHorizon, 0.55) * 0.92;
            vec3 cloudLit = mix(vec3(1.0, 0.97, 0.93), uSunColor, 0.35) * 1.05 + uSunColor * pow(sd, 6.0) * 0.6;
            vec3 cloudCol = mix(cloudShadow, cloudLit, lit);
            col = mix(col, cloudCol, cover * 0.85);
          }

          gl_FragColor = vec4(col, 1.0);
          #include <tonemapping_fragment>
          #include <colorspace_fragment>
        }
      `,
    });
    this.mesh = new THREE.Mesh(geometry, material);
    this.mesh.name = 'Sky';
    this.mesh.frustumCulled = false;
    this.mesh.renderOrder = -1000;
    this.mesh.matrixAutoUpdate = false;
  }

  /** Keep the dome centred on the camera (it is "infinitely" far away). */
  update(camera) {
    this.mesh.position.copy(camera.position);
    this.mesh.updateMatrix();
  }
}
