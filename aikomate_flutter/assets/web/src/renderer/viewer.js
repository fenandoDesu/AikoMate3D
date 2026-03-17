import * as THREE from "../../libs/three.module.js";
import { GLTFLoader } from "../../libs/GLTFLoader.js";
import { VRMLoaderPlugin, VRMUtils } from "../../libs/three-vrm.module.js";

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
camera.position.set(0, 1.45, 1.7);
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
      const vrm = gltf.userData.vrm;
      currentVRM = vrm;

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
      const vrm = gltf.userData.vrm;
      currentVRM = vrm;

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

// ─── Animation Loop ──────────────────────────────────────────────────────────
function animate() {
  requestAnimationFrame(animate);
  const delta = clock.getDelta();
  if (currentVRM) {
    currentVRM.update(delta);
  }
  renderer.render(scene, camera);
}

animate();

// ─── Flutter Bridge ──────────────────────────────────────────────────────────
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
