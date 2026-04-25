/**
 * Resolves VRM humanoid normalized bone nodes once per load (same idea as setBones).
 * Callers keep the returned object instead of repeating getNormalizedBoneNode everywhere.
 *
 * @param {object} vrm
 * @returns {Record<string, import("../../libs/three.module.js").Object3D | null> | null}
 */
export function buildVrmNormalizedBody(vrm) {
  const h = vrm?.humanoid;
  if (!h?.getNormalizedBoneNode) return null;

  const n = (name) => h.getNormalizedBoneNode(name) ?? null;

  const hips = n("hips");
  const spine = n("spine");
  const neck = n("neck");
  const head = n("head");

  const chest = n("chest");
  const upperChest = n("upperChest");

  const leftShoulder = n("leftShoulder");
  const rightShoulder = n("rightShoulder");

  const leftUpperArm = n("leftUpperArm");
  const rightUpperArm = n("rightUpperArm");
  const rightLowerArm = n("rightLowerArm");
  const leftLowerArm = n("leftLowerArm");

  const leftUpperLeg = n("leftUpperLeg");
  const rightUpperLeg = n("rightUpperLeg");
  const leftLowerLeg = n("leftLowerLeg");
  const rightLowerLeg = n("rightLowerLeg");

  const leftFoot = n("leftFoot");
  const rightFoot = n("rightFoot");

  const leftHand = n("leftHand");
  const rightHand = n("rightHand");

  const rightThumbProximal = n("rightThumbProximal");
  const rightThumbIntermediate = n("rightThumbIntermediate");
  const rightThumbDistal = n("rightThumbDistal");
  const rightThumbTip = n("rightThumbTip");

  const rightIndexProximal = n("rightIndexProximal");
  const rightIndexIntermediate = n("rightIndexIntermediate");
  const rightIndexDistal = n("rightIndexDistal");
  const rightIndexTip = n("rightIndexTip");

  const rightMiddleProximal = n("rightMiddleProximal");
  const rightMiddleIntermediate = n("rightMiddleIntermediate");
  const rightMiddleDistal = n("rightMiddleDistal");
  const rightMiddleTip = n("rightMiddleTip");

  const rightRingProximal = n("rightRingProximal");
  const rightRingIntermediate = n("rightRingIntermediate");
  const rightRingDistal = n("rightRingDistal");
  const rightRingTip = n("rightRingTip");

  const rightLittleProximal = n("rightLittleProximal");
  const rightLittleIntermediate = n("rightLittleIntermediate");
  const rightLittleDistal = n("rightLittleDistal");
  const rightLittleTip = n("rightLittleTip");

  const leftThumbProximal = n("leftThumbProximal");
  const leftThumbIntermediate = n("leftThumbIntermediate");
  const leftThumbDistal = n("leftThumbDistal");
  const leftThumbTip = n("leftThumbTip");

  const leftIndexProximal = n("leftIndexProximal");
  const leftIndexIntermediate = n("leftIndexIntermediate");
  const leftIndexDistal = n("leftIndexDistal");
  const leftIndexTip = n("leftIndexTip");

  const leftMiddleProximal = n("leftMiddleProximal");
  const leftMiddleIntermediate = n("leftMiddleIntermediate");
  const leftMiddleDistal = n("leftMiddleDistal");
  const leftMiddleTip = n("leftMiddleTip");

  const leftRingProximal = n("leftRingProximal");
  const leftRingIntermediate = n("leftRingIntermediate");
  const leftRingDistal = n("leftRingDistal");
  const leftRingTip = n("leftRingTip");

  const leftLittleProximal = n("leftLittleProximal");
  const leftLittleIntermediate = n("leftLittleIntermediate");
  const leftLittleDistal = n("leftLittleDistal");
  const leftLittleTip = n("leftLittleTip");

  return {
    head,
    neck,
    spine,
    hips,

    chest,
    upperChest,

    leftShoulder,
    rightShoulder,

    leftUpperArm,
    rightUpperArm,
    leftLowerArm,
    rightLowerArm,

    leftUpperLeg,
    rightUpperLeg,
    leftLowerLeg,
    rightLowerLeg,
    leftFoot,
    rightFoot,

    leftHand,
    rightHand,

    leftThumbProximal,
    leftThumbIntermediate,
    leftThumbDistal,
    leftThumbTip,

    leftIndexProximal,
    leftIndexIntermediate,
    leftIndexDistal,
    leftIndexTip,

    leftMiddleProximal,
    leftMiddleIntermediate,
    leftMiddleDistal,
    leftMiddleTip,

    leftRingProximal,
    leftRingIntermediate,
    leftRingDistal,
    leftRingTip,

    leftLittleProximal,
    leftLittleIntermediate,
    leftLittleDistal,
    leftLittleTip,

    rightThumbProximal,
    rightThumbIntermediate,
    rightThumbDistal,
    rightThumbTip,

    rightIndexProximal,
    rightIndexIntermediate,
    rightIndexDistal,
    rightIndexTip,

    rightMiddleProximal,
    rightMiddleIntermediate,
    rightMiddleDistal,
    rightMiddleTip,

    rightRingProximal,
    rightRingIntermediate,
    rightRingDistal,
    rightRingTip,

    rightLittleProximal,
    rightLittleIntermediate,
    rightLittleDistal,
    rightLittleTip,
  };
}

/**
 * Strip null entries for initPoseBuffer / similar.
 * @param {Record<string, import("../../libs/three.module.js").Object3D | null> | null} body
 */
export function bodyToPoseBufferInput(body) {
  if (!body) return {};
  /** @type {Record<string, import("../../libs/three.module.js").Object3D>} */
  const out = {};
  for (const [k, node] of Object.entries(body)) {
    if (node) out[k] = node;
  }
  return out;
}
