import * as THREE from "../../libs/three.module.js";
import { GLTFLoader } from "../../libs/GLTFLoader.js";
import { VRMLoaderPlugin, VRMUtils } from "../../libs/three-vrm.module.js";
import { setBonesToIdle, initPoseBuffer, applyPoseBuffer } from "./animations/animations.js"

// ─── Renderer ───────────────────────────────────────────────────────────────
const canvas = document.getElementById("c");
const renderer = new THREE.WebGLRenderer({
  canvas,
  antialias: true,
  preserveDrawingBuffer: true
});

renderer.setSize(window.innerWidth, window.innerHeight, false);
renderer.setPixelRatio(window.devicePixelRatio);
renderer.setClearColor(0xffffff, 1);

// ─── Scene ───────────────────────────────────────────────────────────────────
const scene = new THREE.Scene();
scene.background = new THREE.Color(0xffffff);

// ─── Camera ──────────────────────────────────────────────────────────────────
const camera = new THREE.PerspectiveCamera(
  28,
  window.innerWidth / window.innerHeight,
  0.1,
  10
);
camera.position.set(0, 1.45, 2.7);
camera.lookAt(0, 1.4, 0);

// ─── Lights ──────────────────────────────────────────────────────────────────
scene.add(new THREE.AmbientLight(0xffffff, 0.8));
const dir = new THREE.DirectionalLight(0xffffff, 0.8);
dir.position.set(1, 2, 2);
scene.add(dir);

// ─── Resize ──────────────────────────────────────────────────────────────────
window.addEventListener("resize", () => {
  renderer.setSize(window.innerWidth, window.innerHeight, false);
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
});

// ─── VRM State ───────────────────────────────────────────────────────────────
let currentVRM = null;
let vrmVersion = null;
let clock = new THREE.Clock();
let body = {}
let vrmFactor = 1;

// ─── VRM Version Detection ───────────────────────────────────────────────────
function detectVRMVersion(gltf) {
  const extensionsUsed = gltf.parser.json.extensionsUsed || [];
  if (extensionsUsed.includes("VRMC_vrm")) return "VRM1";
  if (extensionsUsed.includes("VRM")) return "VRM0";
  throw new Error("Not a VRM file");
}

// ─── Load VRM ────────────────────────────────────────────────────────────────
function createVRMLoader() {
  const loader = new GLTFLoader();
  loader.register((parser) => new VRMLoaderPlugin(parser));
  return loader;
}

function notifyFlutterLoaded() {
  const payload = JSON.stringify({ event: "vrmLoaded", version: vrmVersion });
  window.flutter_inappwebview.callHandler("FlutterBridge", payload);
  if (window.FlutterBridge) {
    window.FlutterBridge.postMessage(payload);
  }
}

function notifyFlutterError(error) {
  const payload = JSON.stringify({
    event: "vrmError",
    error: String(error)
  });
  window.flutter_inappwebview.callHandler("FlutterBridge", payload);
  if (window.FlutterBridge) {
    window.FlutterBridge.postMessage(payload);
  }
}

function loadVRMFromUrl(url) {
  if (currentVRM) {
    scene.remove(currentVRM.scene);
    VRMUtils.deepDispose(currentVRM.scene);
    currentVRM = null;
  }

  const loader = createVRMLoader();

  loader.load(
    url,
    (gltf) => {
      vrmVersion = detectVRMVersion(gltf);
      vrmFactor = vrmVersion === "VRM0" ? -1 : 1;
      const vrm = gltf.userData.vrm;
      currentVRM = vrm;
      initPoseBuffer(vrm.humanoid.rawHumanBones);
      setBones(vrm);
      initPoseBuffer(body);

      VRMUtils.removeUnnecessaryVertices(vrm.scene);
      VRMUtils.removeUnnecessaryJoints(vrm.scene);

      if (vrmVersion === "VRM0") {
        VRMUtils.rotateVRM0(vrm);
      }

      scene.add(vrm.scene);
      console.log(`VRM loaded: ${vrmVersion}`);
      notifyFlutterLoaded();
    },
    (progress) => {
      const percent = Math.round((progress.loaded / progress.total) * 100);
      console.log(`Loading: ${percent}%`);
    },
    (loadError) => {
      console.error("VRM load failed:", loadError);
      notifyFlutterError(loadError);
    }
  );
}

const deg = THREE.MathUtils.degToRad;

function loadVRMFromBuffer(arrayBuffer, fileName) {
  if (currentVRM) {
    scene.remove(currentVRM.scene);
    VRMUtils.deepDispose(currentVRM.scene);
    currentVRM = null;
  }

  const loader = createVRMLoader();
  const basePath = fileName ? fileName.replace(/[^/]*$/, "") : "";
  loader.parse(
    arrayBuffer,
    basePath,
    (gltf) => {
      vrmVersion = detectVRMVersion(gltf);
      vrmFactor = vrmVersion === "VRM0" ? -1 : 1;
      const vrm = gltf.userData.vrm;
      currentVRM = vrm;
      initPoseBuffer(vrm.humanoid.rawHumanBones);
      setBones(vrm);
      initPoseBuffer(body);

      VRMUtils.removeUnnecessaryVertices(vrm.scene);
      VRMUtils.removeUnnecessaryJoints(vrm.scene);

      if (vrmVersion === "VRM0") {
        VRMUtils.rotateVRM0(vrm);
      }

      scene.add(vrm.scene);
      console.log(`VRM loaded: ${vrmVersion}`);
      
      notifyFlutterLoaded();
    },
    (parseError) => {
      console.error("VRM parse failed:", parseError);
      notifyFlutterError(parseError);
    }
  );
}

function base64ToArrayBuffer(base64) {
  const binaryString = atob(base64);
  const len = binaryString.length;
  const bytes = new Uint8Array(len);
  for (let i = 0; i < len; i += 1) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  return bytes.buffer;
}

function setBones(vrm) {
  const hips = vrm.humanoid.getNormalizedBoneNode('hips');
  const spine = vrm.humanoid.getNormalizedBoneNode('spine');
  const neck = vrm.humanoid.getNormalizedBoneNode('neck');
  const head = vrm.humanoid.getNormalizedBoneNode('head');

  const chest = vrm.humanoid.getNormalizedBoneNode("chest");
  const upperChest = vrm.humanoid.getNormalizedBoneNode("upperChest");

  const leftShoulder = vrm.humanoid.getNormalizedBoneNode('leftShoulder');
  const rightShoulder = vrm.humanoid.getNormalizedBoneNode('rightShoulder');

  const leftUpperArm = vrm.humanoid.getNormalizedBoneNode('leftUpperArm');
  const rightUpperArm = vrm.humanoid.getNormalizedBoneNode('rightUpperArm');
  const rightLowerArm = vrm.humanoid.getNormalizedBoneNode('rightLowerArm');
  const leftLowerArm = vrm.humanoid.getNormalizedBoneNode('leftLowerArm');

  const leftUpperLeg = vrm.humanoid.getNormalizedBoneNode('leftUpperLeg');
  const rightUpperLeg = vrm.humanoid.getNormalizedBoneNode('rightUpperLeg');
  const leftLowerLeg = vrm.humanoid.getNormalizedBoneNode('leftLowerLeg');
  const rightLowerLeg = vrm.humanoid.getNormalizedBoneNode('rightLowerLeg');

  const leftFoot = vrm.humanoid.getNormalizedBoneNode('leftFoot');
  const rightFoot = vrm.humanoid.getNormalizedBoneNode('rightFoot');

  const leftHand = vrm.humanoid.getNormalizedBoneNode('leftHand');
  const rightHand = vrm.humanoid.getNormalizedBoneNode('rightHand');

  // Right hand fingers
  const rightThumbProximal = vrm.humanoid.getNormalizedBoneNode("rightThumbProximal");
  const rightThumbIntermediate = vrm.humanoid.getNormalizedBoneNode("rightThumbIntermediate");
  const rightThumbDistal = vrm.humanoid.getNormalizedBoneNode("rightThumbDistal");
  const rightThumbTip = vrm.humanoid.getNormalizedBoneNode("rightThumbTip");

  const rightIndexProximal = vrm.humanoid.getNormalizedBoneNode("rightIndexProximal");
  const rightIndexIntermediate = vrm.humanoid.getNormalizedBoneNode("rightIndexIntermediate");
  const rightIndexDistal = vrm.humanoid.getNormalizedBoneNode("rightIndexDistal");
  const rightIndexTip = vrm.humanoid.getNormalizedBoneNode("rightIndexTip");

  const rightMiddleProximal = vrm.humanoid.getNormalizedBoneNode("rightMiddleProximal");
  const rightMiddleIntermediate = vrm.humanoid.getNormalizedBoneNode("rightMiddleIntermediate");
  const rightMiddleDistal = vrm.humanoid.getNormalizedBoneNode("rightMiddleDistal");
  const rightMiddleTip = vrm.humanoid.getNormalizedBoneNode("rightMiddleTip");

  const rightRingProximal = vrm.humanoid.getNormalizedBoneNode("rightRingProximal");
  const rightRingIntermediate = vrm.humanoid.getNormalizedBoneNode("rightRingIntermediate");
  const rightRingDistal = vrm.humanoid.getNormalizedBoneNode("rightRingDistal");
  const rightRingTip = vrm.humanoid.getNormalizedBoneNode("rightRingTip");

  const rightLittleProximal = vrm.humanoid.getNormalizedBoneNode("rightLittleProximal");
  const rightLittleIntermediate = vrm.humanoid.getNormalizedBoneNode("rightLittleIntermediate");
  const rightLittleDistal = vrm.humanoid.getNormalizedBoneNode("rightLittleDistal");
  const rightLittleTip = vrm.humanoid.getNormalizedBoneNode("rightLittleTip");

  // Left hand fingers
  const leftThumbProximal = vrm.humanoid.getNormalizedBoneNode("leftThumbProximal");
  const leftThumbIntermediate = vrm.humanoid.getNormalizedBoneNode("leftThumbIntermediate");
  const leftThumbDistal = vrm.humanoid.getNormalizedBoneNode("leftThumbDistal");
  const leftThumbTip = vrm.humanoid.getNormalizedBoneNode("leftThumbTip");

  const leftIndexProximal = vrm.humanoid.getNormalizedBoneNode("leftIndexProximal");
  const leftIndexIntermediate = vrm.humanoid.getNormalizedBoneNode("leftIndexIntermediate");
  const leftIndexDistal = vrm.humanoid.getNormalizedBoneNode("leftIndexDistal");
  const leftIndexTip = vrm.humanoid.getNormalizedBoneNode("leftIndexTip");

  const leftMiddleProximal = vrm.humanoid.getNormalizedBoneNode("leftMiddleProximal");
  const leftMiddleIntermediate = vrm.humanoid.getNormalizedBoneNode("leftMiddleIntermediate");
  const leftMiddleDistal = vrm.humanoid.getNormalizedBoneNode("leftMiddleDistal");
  const leftMiddleTip = vrm.humanoid.getNormalizedBoneNode("leftMiddleTip");

  const leftRingProximal = vrm.humanoid.getNormalizedBoneNode("leftRingProximal");
  const leftRingIntermediate = vrm.humanoid.getNormalizedBoneNode("leftRingIntermediate");
  const leftRingDistal = vrm.humanoid.getNormalizedBoneNode("leftRingDistal");
  const leftRingTip = vrm.humanoid.getNormalizedBoneNode("leftRingTip");

  const leftLittleProximal = vrm.humanoid.getNormalizedBoneNode("leftLittleProximal");
  const leftLittleIntermediate = vrm.humanoid.getNormalizedBoneNode("leftLittleIntermediate");
  const leftLittleDistal = vrm.humanoid.getNormalizedBoneNode("leftLittleDistal");
  const leftLittleTip = vrm.humanoid.getNormalizedBoneNode("leftLittleTip");

  body = {
    head: head,
    neck: neck,
    spine: spine,
    hips: hips,

    chest: chest,
    upperChest: upperChest,

    leftShoulder: leftShoulder,
    rightShoulder: rightShoulder,

    // Arms
    leftUpperArm: leftUpperArm,
    rightUpperArm: rightUpperArm,
    leftLowerArm: leftLowerArm,
    rightLowerArm: rightLowerArm,

    // Legs
    leftUpperLeg: leftUpperLeg,
    rightUpperLeg: rightUpperLeg,
    leftLowerLeg: leftLowerLeg,
    rightLowerLeg: rightLowerLeg,
    leftFoot: leftFoot,
    rightFoot: rightFoot,

    // Hands
    leftHand: leftHand,
    rightHand: rightHand,

    // Left fingers
    leftThumbProximal: leftThumbProximal,
    leftThumbIntermediate: leftThumbIntermediate,
    leftThumbDistal: leftThumbDistal,
    leftThumbTip: leftThumbTip,

    leftIndexProximal: leftIndexProximal,
    leftIndexIntermediate: leftIndexIntermediate,
    leftIndexDistal: leftIndexDistal,
    leftIndexTip: leftIndexTip,

    leftMiddleProximal: leftMiddleProximal,
    leftMiddleIntermediate: leftMiddleIntermediate,
    leftMiddleDistal: leftMiddleDistal,
    leftMiddleTip: leftMiddleTip,

    leftRingProximal: leftRingProximal,
    leftRingIntermediate: leftRingIntermediate,
    leftRingDistal: leftRingDistal,
    leftRingTip: leftRingTip,

    leftLittleProximal: leftLittleProximal,
    leftLittleIntermediate: leftLittleIntermediate,
    leftLittleDistal: leftLittleDistal,
    leftLittleTip: leftLittleTip,

    // Right fingers
    rightThumbProximal: rightThumbProximal,
    rightThumbIntermediate: rightThumbIntermediate,
    rightThumbDistal: rightThumbDistal,
    rightThumbTip: rightThumbTip,

    rightIndexProximal: rightIndexProximal,
    rightIndexIntermediate: rightIndexIntermediate,
    rightIndexDistal: rightIndexDistal,
    rightIndexTip: rightIndexTip,

    rightMiddleProximal: rightMiddleProximal,
    rightMiddleIntermediate: rightMiddleIntermediate,
    rightMiddleDistal: rightMiddleDistal,
    rightMiddleTip: rightMiddleTip,

    rightRingProximal: rightRingProximal,
    rightRingIntermediate: rightRingIntermediate,
    rightRingDistal: rightRingDistal,
    rightRingTip: rightRingTip,

    rightLittleProximal: rightLittleProximal,
    rightLittleIntermediate: rightLittleIntermediate,
    rightLittleDistal: rightLittleDistal,
    rightLittleTip: rightLittleTip,
  };
}

// ─── Animation Loop ──────────────────────────────────────────────────────────
let elapsedTime = 0;

function animate() {
  const delta = clock.getDelta();
  elapsedTime += delta;

  if (currentVRM) {
    currentVRM.update(delta);
  }

  if (currentVRM) {
    setBonesToIdle(elapsedTime, vrmFactor);
    applyPoseBuffer();
  }

  renderer.render(scene, camera);
  requestAnimationFrame(animate);
}

// ─── Flutter Bridge ──────────────────────────────────────────────────────────
requestAnimationFrame(animate);

// Receives messages from Dart
window.flutter_inappwebview.callHandler('FlutterBridge', JSON.stringify({ event: 'ready' }));

window.onFlutterMessage = (message) => {
  let payload;
  try {
    payload = typeof message === "string" ? JSON.parse(message) : message;
  } catch (err) {
    console.error("Invalid message from Flutter:", err);
    return;
  }

  if (payload?.command === "loadVRM") {
    if (payload.data) {
      const buffer = base64ToArrayBuffer(payload.data);
      loadVRMFromBuffer(buffer, payload.fileName);
      return;
    }
    if (payload.url) {
      loadVRMFromUrl(payload.url);
    }
  }
};
