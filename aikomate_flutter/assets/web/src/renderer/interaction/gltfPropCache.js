import * as THREE from "../../../libs/three.module.js";
import { GLTFLoader } from "../../../libs/GLTFLoader.js";

/** @type {Map<string, THREE.Object3D>} */
const templates = new Map();
/** @type {Map<string, Promise<void>>} */
const loading = new Map();

/**
 * @param {THREE.Object3D} root
 */
function deepCloneForSpawn(root) {
  const c = root.clone(true);
  c.traverse((obj) => {
    if (obj.isMesh) {
      if (obj.geometry) obj.geometry = obj.geometry.clone();
      if (obj.material) {
        obj.material = Array.isArray(obj.material)
          ? obj.material.map((m) => m.clone())
          : obj.material.clone();
      }
    }
  });
  return c;
}

/**
 * @param {string} key
 * @param {string} url
 * @returns {Promise<void>}
 */
export function preloadProp(key, url) {
  if (templates.has(key)) return Promise.resolve();
  if (loading.has(key)) return loading.get(key);
  const loader = new GLTFLoader();
  loader.setCrossOrigin("anonymous");
  const p = new Promise((resolve, reject) => {
    loader.load(
      url,
      (gltf) => {
        templates.set(key, gltf.scene);
        resolve();
      },
      undefined,
      reject
    );
  });
  const tracked = p.finally(() => {
    loading.delete(key);
  });
  loading.set(key, tracked);
  return tracked;
}

/**
 * @param {string} key
 * @returns {THREE.Object3D | null}
 */
export function spawnProp(key) {
  const t = templates.get(key);
  if (!t) return null;
  return deepCloneForSpawn(t);
}

/**
 * @param {THREE.Scene} scene
 * @param {THREE.Object3D | null} object
 */
export function removePropFromScene(scene, object) {
  if (!object || !scene) return;
  scene.remove(object);
}

/**
 * @param {string} key
 */
export function disposePropCache(key) {
  const t = templates.get(key);
  if (!t) return;
  templates.delete(key);
  disposeObject(t);
}

/**
 * @param {THREE.Object3D | null | undefined} root
 */
export function disposeObject(root) {
  if (!root) return;
  root.traverse((obj) => {
    if (obj.geometry) obj.geometry.dispose();
    if (obj.material) {
      const mats = Array.isArray(obj.material) ? obj.material : [obj.material];
      for (const m of mats) {
        if (!m) continue;
        const keys = Object.keys(m);
        for (const k of keys) {
          const v = m[k];
          if (v && v.isTexture) v.dispose();
        }
        if (typeof m.dispose === "function") m.dispose();
      }
    }
  });
}

export function isPropCached(key) {
  return templates.has(key);
}

/**
 * Makes spawned GLB props readable in the scene: no shadow maps, double-sided,
 * sRGB textures, optional auto-scale to a target max dimension (meters).
 * @param {THREE.Object3D} root
 * @param {{ targetMaxDimension?: number }} [opts]
 */
export function prepareGltfInstanceForDisplay(root, opts = {}) {
  const targetMax = opts.targetMaxDimension ?? 0.28;

  root.updateMatrixWorld(true);
  const box = new THREE.Box3().setFromObject(root);
  const size = new THREE.Vector3();
  box.getSize(size);
  const maxDim = Math.max(size.x, size.y, size.z);
  if (maxDim > 1e-6 && maxDim < 10) {
    const s = targetMax / maxDim;
    root.scale.multiplyScalar(s);
  }

  root.traverse((obj) => {
    if (!obj.isMesh) return;
    obj.castShadow = false;
    obj.receiveShadow = false;
    obj.frustumCulled = true;

    const pos = obj.geometry?.getAttribute?.("position");
    const vCount = pos ? pos.count : 0;
    const mats = Array.isArray(obj.material) ? obj.material : [obj.material];

    const mb = new THREE.Box3().setFromObject(obj);
    const ms = new THREE.Vector3();
    mb.getSize(ms);
    const meshMax = Math.max(ms.x, ms.y, ms.z);

    const useFallback =
      vCount > 0 &&
      vCount <= 32 &&
      meshMax < 0.12 &&
      mats.every((m) => m && !m.map && (m.isMeshBasicMaterial || m.isMeshLambertMaterial));

    if (useFallback) {
      const rep = new THREE.MeshStandardMaterial({
        color: 0xff3355,
        emissive: 0x551022,
        emissiveIntensity: 0.6,
        roughness: 0.35,
        metalness: 0.08,
        side: THREE.DoubleSide,
        transparent: true,
        opacity: 1,
      });
      for (const m of mats) m?.dispose?.();
      obj.material = rep;
      return;
    }

    for (const mat of mats) {
      if (!mat) continue;
      mat.side = THREE.DoubleSide;
      mat.depthWrite = true;
      mat.depthTest = true;
      mat.needsUpdate = true;
      if (mat.map && "colorSpace" in mat.map) {
        mat.map.colorSpace = THREE.SRGBColorSpace;
      }
    }
  });
}

