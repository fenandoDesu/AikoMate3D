import * as THREE from "../../../libs/three.module.js";

/** @type {THREE.Mesh[]} */
const hitRegionMeshes = [];

/** @type {{ region: string, bone: string, size: [number, number, number], offset?: [number, number, number] }[]} */
const REGION_CONFIG = [
  /*
   * Literal 3D head box in bone-local space.
   * This mesh is both the debug visualization and the exact pick volume.
   */
  { region: "head", bone: "head", size: [0.36, 0.34, 0.34], offset: [0, 0.07, 0] },
];

const _raycaster = new THREE.Raycaster();
const _ndc = new THREE.Vector2();

const _headCenter = new THREE.Vector3();
const _toCam = new THREE.Vector3();
const _orbitRight = new THREE.Vector3();
const _orbitUp = new THREE.Vector3();
const _worldUp = new THREE.Vector3(0, 1, 0);

/**
 * @param {Record<string, THREE.Object3D | null> | null} body from buildVrmNormalizedBody
 * @returns {THREE.Object3D | null}
 */
export function getHeadBoneFromBody(body) {
  return body?.head ?? null;
}

/**
 * Picks a random world position on the perimeter of a circle centered on the
 * head bone. The circle lies in the plane facing the camera (screen-aligned),
 * so hearts orbit around the head silhouette from the viewer's perspective.
 *
 * @param {Record<string, THREE.Object3D | null> | null} body normalized bone body (see vrmBones.js)
 * @param {THREE.Camera} camera
 * @param {number} radius world-units radius of the orbit (e.g. 0.24 for typical VRM scale)
 * @param {THREE.Vector3} target written world position
 * @returns {boolean} false if head bone or camera direction is degenerate
 */
export function sampleHeadOrbitPerimeterWorld(body, camera, radius, target) {
  const bone = getHeadBoneFromBody(body);
  if (!bone || !camera || !target) return false;

  bone.getWorldPosition(_headCenter);
  _toCam.subVectors(camera.position, _headCenter);
  if (_toCam.lengthSq() < 1e-10) return false;
  _toCam.normalize();

  _orbitRight.crossVectors(_worldUp, _toCam);
  if (_orbitRight.lengthSq() < 1e-8) {
    _orbitRight.set(1, 0, 0);
  } else {
    _orbitRight.normalize();
  }
  _orbitUp.crossVectors(_toCam, _orbitRight).normalize();

  const theta = Math.random() * Math.PI * 2;
  const c = Math.cos(theta) * radius;
  const s = Math.sin(theta) * radius;

  target.copy(_headCenter);
  target.addScaledVector(_orbitRight, c);
  target.addScaledVector(_orbitUp, s);
  return true;
}

/**
 * @param {Record<string, THREE.Object3D | null> | null} body from buildVrmNormalizedBody
 */
export function attachAvatarHitRegions(body) {
  detachAvatarHitRegions();
  if (!body) return;

  for (const cfg of REGION_CONFIG) {
    const bone = body[cfg.bone];
    if (!bone) continue;
    const [sx, sy, sz] = cfg.size;
    const geo = new THREE.BoxGeometry(sx, sy, sz);
    const mat = new THREE.MeshBasicMaterial({
      color: 0x00d4ff,
      transparent: true,
      opacity: 0,
      wireframe: false,
      depthWrite: false,
      depthTest: true,
    });
    const mesh = new THREE.Mesh(geo, mat);
    mesh.userData.hitRegion = cfg.region;
    mesh.userData.boneRef = bone;
    mesh.name = `HitRegion_${cfg.region}`;
    if (cfg.offset) {
      mesh.position.set(cfg.offset[0], cfg.offset[1], cfg.offset[2]);
    }
    bone.add(mesh);
    hitRegionMeshes.push(mesh);
  }
}

export function detachAvatarHitRegions() {
  for (const mesh of hitRegionMeshes) {
    mesh.removeFromParent();
    mesh.geometry?.dispose();
    mesh.material?.dispose();
  }
  hitRegionMeshes.length = 0;
}

/** Toggle debug visibility for hit region boxes. */
export function setHitRegionDebugVisible(visible) {
  for (const mesh of hitRegionMeshes) {
    const m = mesh.material;
    if (!m) continue;
    m.opacity = visible ? 0.18 : 0;
    if ("wireframe" in m) m.wireframe = !!visible;
    m.needsUpdate = true;
  }
}

/**
 * @param {number} clientX
 * @param {number} clientY
 * @param {THREE.Camera} camera
 * @param {HTMLCanvasElement} canvas
 * @returns {{ region: string, distance: number, point: THREE.Vector3 } | null}
 */
export function raycastAvatarRegions(clientX, clientY, camera, canvas) {
  if (hitRegionMeshes.length === 0 || !camera || !canvas) return null;
  const rect = canvas.getBoundingClientRect();
  const w = rect.width || 1;
  const h = rect.height || 1;
  _ndc.x = ((clientX - rect.left) / w) * 2 - 1;
  _ndc.y = -((clientY - rect.top) / h) * 2 + 1;
  _raycaster.setFromCamera(_ndc, camera);
  const hits = _raycaster.intersectObjects(hitRegionMeshes, false);
  if (hits.length === 0) return null;
  const h0 = hits[0];
  const region = h0.object.userData.hitRegion;
  if (!region) return null;
  return { region, distance: h0.distance, point: h0.point.clone() };
}

/**
 * Picks a bone by raycasting against the same literal box meshes used for debug.
 * @param {number} clientX
 * @param {number} clientY
 * @param {Record<string, THREE.Object3D | null> | null} _body
 * @param {THREE.Camera} camera
 * @param {HTMLCanvasElement} canvas
 * @returns {{ name: string, bone: THREE.Object3D } | null}
 */
export function pickInteractiveBone(clientX, clientY, _body, camera, canvas) {
  if (!camera || !canvas) return null;
  if (hitRegionMeshes.length === 0) return null;
  const rect = canvas.getBoundingClientRect();
  const w = rect.width || 1;
  const h = rect.height || 1;
  _ndc.x = ((clientX - rect.left) / w) * 2 - 1;
  _ndc.y = -((clientY - rect.top) / h) * 2 + 1;
  _raycaster.setFromCamera(_ndc, camera);
  const hits = _raycaster.intersectObjects(hitRegionMeshes, false);
  if (hits.length === 0) return null;
  const h0 = hits[0].object;
  const name = h0.userData.hitRegion;
  const bone = h0.userData.boneRef;
  if (!name || !bone) return null;
  return { name, bone };
}
