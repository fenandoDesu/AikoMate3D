import * as THREE from "../../../libs/three.module.js";

const deg = THREE.MathUtils.degToRad;
let poseBuffer = {};

export function initPoseBuffer(body) {
  poseBuffer = {};

  for (const [name, bone] of Object.entries(body)) {
    if (!bone || !bone.quaternion) continue;

    poseBuffer[name] = {
      bone,
      base: bone.quaternion.clone(),
      target: bone.quaternion.clone(),
      weight: 0,
      priority: 0,
      animationId: null,
    };
  }
}

function writePose(bone, quaternion, {
  weight = 1,
  priority = 0,
  animationId = null
}) {
  const slot = poseBuffer[bone];
  if (!slot) {

    return;
  }

  if (
    slot.animationId === null ||
    priority >= slot.priority
  ) {
    slot.target.copy(quaternion);
    slot.weight = weight;
    slot.priority = priority;
    slot.animationId = animationId;
  }
}



function getPoseBaseQuat(bone) {
  const slot = poseBuffer[bone];
  return slot?.base ? slot.base.clone() : new THREE.Quaternion();
}

export function setBonesToIdle(t, vrmFactor, dt = 1 / 60) {
  let yawLimit = 0.6, pitchLimit = 0.4;
  // hipSwing(vrm, t, body)
  // const yaw = THREE.MathUtils.clamp(mouse.x * yawLimit, -yawLimit, yawLimit);
  // const pitch = THREE.MathUtils.clamp(-mouse.y * pitchLimit, -pitchLimit, pitchLimit);

  const yaw = 0;
  const pitch = 0;

  // hipSwing(vrm, t, body, 1, 0.24, true, dt);

  writePose("head", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(pitch * 65 + Math.sin(t) * 5) * vrmFactor, deg(0 + yaw * 55 - Math.sin(t) * 2), deg(0 + Math.cos(t * 2) * 5))), { weight: 1, priority: 1, animationId: 0 });
  writePose("neck", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(pitch * 20 + Math.sin(t) * 3) * vrmFactor, deg(0 + Math.sin(t) * 1), deg(0 + Math.cos(t * 2) * 5))), { weight: 1, priority: 1, animationId: 0 });
  writePose("hips", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(0))), { weight: 1, priority: 1, animationId: 0 });
  writePose("spine", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0 + pitch * 10 + Math.cos(t * 1.1) * 3) * vrmFactor, deg(yaw * 60), deg(0 + Math.sin(t) * 3) * vrmFactor)), { weight: 1, priority: 1, animationId: 0 });

  writePose("leftShoulder", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(0))), { weight: 1, priority: 90, animationId: 0 });
  writePose("rightShoulder", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(0))), { weight: 1, priority: 90, animationId: 0 });

  writePose("rightUpperArm", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0 + Math.cos(t * 0.8) * 2), deg(0), deg(75 + Math.sin(t * 0.7) * 2) * vrmFactor)), { weight: 1, priority: 1, animationId: 0 });
  writePose("rightLowerArm", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(5) * vrmFactor)), { weight: 2, priority: 1, animationId: 0 });
  writePose("leftUpperArm", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0 + Math.sin(t * 0.85) * 2), deg(0), deg(-75 + Math.cos(t * 0.78) * 2) * vrmFactor)), { weight: 1, priority: 1, animationId: 0 });
  writePose("leftLowerArm", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(-5) * vrmFactor)), { weight: 1, priority: 1, animationId: 0 });

  writePose("rightHand", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(20 * vrmFactor))), { weight: 1, priority: 1, animationId: 0 });
  writePose("leftHand", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(-20 * vrmFactor))), { weight: 1, priority: 1, animationId: 0 });

  writePose("leftUpperLeg", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(0))), { weight: 1, priority: 1, animationId: 0 });
  writePose("rightUpperLeg", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(0))), { weight: 1, priority: 1, animationId: 0 });
  writePose("rightLowerLeg", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(0))), { weight: 1, priority: 1, animationId: 0 });
  writePose("leftLowerLeg", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(0))), { weight: 1, priority: 1, animationId: 0 });

  writePose("leftFoot", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(0))), { weight: 1, priority: 1, animationId: 0 });
  writePose("rightFoot", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(0))), { weight: 1, priority: 1, animationId: 0 });

  //fingers idle
  setFingerToIdle(t, 1, 1, 0, vrmFactor);
}

function setFingerToIdle(t, weight, priority, animationId, vrmFactor) {
  writePose("rightIndexDistal", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(25 * vrmFactor))), { weight: weight, priority: priority, animationId: animationId });
  writePose("rightIndexIntermediate", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(25 * vrmFactor))), { weight: weight, priority: priority, animationId: animationId });
  writePose("rightIndexProximal", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(-5 * vrmFactor))), { weight: weight, priority: priority, animationId: animationId });
  writePose("rightMiddleDistal", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(25 * vrmFactor))), { weight: weight, priority: priority, animationId: animationId });
  writePose("rightMiddleIntermediate", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(25 * vrmFactor))), { weight: weight, priority: priority, animationId: animationId });
  writePose("rightMiddleProximal", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(-5 * vrmFactor))), { weight: weight, priority: priority, animationId: animationId });
  writePose("rightRingDistal", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(25 * vrmFactor))), { weight: weight, priority: priority, animationId: animationId });
  writePose("rightRingIntermediate", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(25 * vrmFactor))), { weight: weight, priority: priority, animationId: animationId });
  writePose("rightRingProximal", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(-5 * vrmFactor))), { weight: weight, priority: priority, animationId: animationId });
  writePose("rightLittleDistal", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(25 * vrmFactor))), { weight: weight, priority: priority, animationId: animationId });
  writePose("rightLittleIntermediate", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(25 * vrmFactor))), { weight: weight, priority: priority, animationId: animationId });
  writePose("rightLittleProximal", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(-5 * vrmFactor))), { weight: weight, priority: priority, animationId: animationId });
  writePose("rightThumbDistal", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(0))), { weight: weight, priority: priority, animationId: animationId });
  writePose("rightThumbProximal", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(0))), { weight: weight, priority: priority, animationId: animationId });

  writePose("leftIndexDistal", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(-25 * vrmFactor))), { weight: weight, priority: priority, animationId: animationId });
  writePose("leftIndexIntermediate", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(-25 * vrmFactor))), { weight: weight, priority: priority, animationId: animationId });
  writePose("leftIndexProximal", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(5 * vrmFactor))), { weight: weight, priority: priority, animationId: animationId });
  writePose("leftMiddleDistal", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(-25 * vrmFactor))), { weight: weight, priority: priority, animationId: animationId });
  writePose("leftMiddleIntermediate", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(-25 * vrmFactor))), { weight: weight, priority: priority, animationId: animationId });
  writePose("leftMiddleProximal", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(5 * vrmFactor))), { weight: weight, priority: priority, animationId: animationId });
  writePose("leftRingDistal", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(-25 * vrmFactor))), { weight: weight, priority: priority, animationId: animationId });
  writePose("leftRingIntermediate", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(-25 * vrmFactor))), { weight: weight, priority: priority, animationId: animationId });
  writePose("leftRingProximal", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(5 * vrmFactor))), { weight: weight, priority: priority, animationId: animationId });
  writePose("leftLittleDistal", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(-25 * vrmFactor))), { weight: weight, priority: priority, animationId: animationId });
  writePose("leftLittleIntermediate", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(-25 * vrmFactor))), { weight: weight, priority: priority, animationId: animationId });
  writePose("leftLittleProximal", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(5 * vrmFactor))), { weight: weight, priority: priority, animationId: animationId });
  writePose("leftThumbDistal", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(0))), { weight: weight, priority: priority, animationId: animationId });
  writePose("leftThumbProximal", new THREE.Quaternion().setFromEuler(new THREE.Euler(deg(0), deg(0), deg(0))), { weight: weight, priority: priority, animationId: animationId });

}

export function applyPoseBuffer() {
  for (const slot of Object.values(poseBuffer)) {
    if (!slot?.bone) continue;
    slot.bone.quaternion.copy(slot.target);
  }
}
