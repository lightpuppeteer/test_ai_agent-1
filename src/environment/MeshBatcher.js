import * as THREE from 'three';

/**
 * Collects many (geometry, material, matrix) placements during level building
 * and emits one InstancedMesh per unique (geometry, material) pair.
 *
 * A whole medieval quarter — walls, quoins, windows, shutters, merlons,
 * benches — collapses into a couple dozen draw calls. All stylised materials
 * texture in world space, so instance scaling never stretches textures.
 */
export class MeshBatcher {
  constructor() {
    this.batches = new Map();
  }

  /**
   * @param {THREE.BufferGeometry} geometry
   * @param {THREE.Material} material
   * @param {THREE.Matrix4} matrix world matrix of this instance
   */
  add(geometry, material, matrix, { castShadow = true, receiveShadow = true } = {}) {
    const key = `${geometry.uuid}|${material.uuid}`;
    let b = this.batches.get(key);
    if (!b) {
      b = { geometry, material, matrices: [], castShadow, receiveShadow };
      this.batches.set(key, b);
    }
    b.matrices.push(matrix.clone());
  }

  /** Convenience: position / quaternion / scale. */
  place(geometry, material, position, quaternion, scale, opts) {
    _m.compose(position, quaternion ?? _qi, scale ?? _one);
    this.add(geometry, material, _m, opts);
  }

  /** Builds the instanced meshes into `parent` and clears the batcher. */
  build(parent) {
    const meshes = [];
    for (const b of this.batches.values()) {
      const mesh = new THREE.InstancedMesh(b.geometry, b.material, b.matrices.length);
      b.matrices.forEach((m, i) => mesh.setMatrixAt(i, m));
      mesh.instanceMatrix.needsUpdate = true;
      mesh.castShadow = b.castShadow;
      mesh.receiveShadow = b.receiveShadow;
      mesh.computeBoundingSphere();
      mesh.computeBoundingBox();
      mesh.matrixAutoUpdate = false;
      mesh.name = `${b.material.name || 'batch'}×${b.matrices.length}`;
      parent.add(mesh);
      meshes.push(mesh);
    }
    this.batches.clear();
    return meshes;
  }
}

const _m = new THREE.Matrix4();
const _qi = new THREE.Quaternion();
const _one = new THREE.Vector3(1, 1, 1);
