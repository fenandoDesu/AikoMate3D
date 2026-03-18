import * as THREE from "../../libs/three.module.js";
import { GLTFLoader } from "../../libs/GLTFLoader.js";
import { VRMLoaderPlugin, VRMUtils } from "../../libs/three-vrm.module.js";
import { setBonesToIdle, initPoseBuffer, applyPoseBuffer } from "./animations/animations.js";

// ─── Mode Detection ──────────────────────────────────────────────────────────
const urlParams = new URLSearchParams(window.location.search);
const mode = urlParams.get('mode'); // 'normal', 'ar', 'ar-overlay'
const isAR = mode === 'ar' || mode === 'ar-overlay';
const isOverlay = mode === 'ar-overlay';

// ─── Renderer ────────────────────────────────────────────────────────────────
const canvas = document.getElementById("c");
const renderer = new THREE.WebGLRenderer({
  canvas,
  antialias: true,
  preserveDrawingBuffer: true,
  alpha: isAR,
});

renderer.setSize(window.innerWidth, window.innerHeight, false);
renderer.setPixelRatio(window.devicePixelRatio);
renderer.xr.enabled = isAR && !isOverlay; // WebXR only if NOT overlay mode

if (!isAR) {
  renderer.setClearColor(0xffffff, 1);
} else {
  renderer.setClearColor(0x000000, 0); // transparent for both ar modes
}

// ─── Transparent background for overlay mode ─────────────────────────────────
if (isOverlay) {
  document.body.style.background = 'transparent';
  document.documentElement.style.background = 'transparent';
}

// ─── Scene ───────────────────────────────────────────────────────────────────
const scene = new THREE.Scene();
if (!isAR) scene.background = new THREE.Color(0xffffff);

// ─── Camera ──────────────────────────────────────────────────────────────────
const camera = new THREE.PerspectiveCamera(
  28,
  window.innerWidth / window.innerHeight,
  0.1,
  100
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
let vrmFactor = 1;
const clock = new THREE.Clock();
let elapsedTime = 0;

// ─── AR State (WebXR path — unused in overlay mode) ──────────────────────────
let xrSession = null;
let xrHitTestSource = null;
let xrRefSpace = null;
let avatarPlaced = false;

const reticle = new THREE.Mesh(
  new THREE.RingGeometry(0.1, 0.11, 32).rotateX(-Math.PI / 2),
  new THREE.MeshBasicMaterial({ color: 0xffffff })
);
reticle.visible = false;
reticle.matrixAutoUpdate = false;
scene.add(reticle);

// ─── VRM Version Detection ───────────────────────────────────────────────────
function detectVRMVersion(gltf) {
  const extensionsUsed = gltf.parser.json.extensionsUsed || [];
  if (extensionsUsed.includes("VRMC_vrm")) return "VRM1";
  if (extensionsUsed.includes("VRM")) return "VRM0";
  throw new Error("Not a VRM file");
}

// ─── Load VRM ────────────────────────────────────────────────────────────────
function loadVRM(url) {
  if (currentVRM) {
    scene.remove(currentVRM.scene);
    VRMUtils.deepDispose(currentVRM.scene);
    currentVRM = null;
  }

  const loader = new GLTFLoader();
  loader.register((parser) => new VRMLoaderPlugin(parser));

  loader.load(
    url,
    (gltf) => {
      const vrm = gltf.userData.vrm;
      currentVRM = vrm;
      const vrmVersion = detectVRMVersion(gltf);
      vrmFactor = vrmVersion === "VRM0" ? -1 : 1;

      VRMUtils.removeUnnecessaryVertices(vrm.scene);
      VRMUtils.removeUnnecessaryJoints(vrm.scene);

      if (vrmVersion === "VRM0") VRMUtils.rotateVRM0(vrm);

      // In AR/overlay mode: hide until placed
      if (isAR) vrm.scene.visible = false;

      scene.add(vrm.scene);

      const bones = {};
      for (const [name, bone] of Object.entries(vrm.humanoid.rawHumanBones)) {
        bones[name] = bone?.node;
      }
      initPoseBuffer(bones);

      console.log(`VRM loaded: ${vrmVersion}`);
      window.flutter_inappwebview.callHandler('FlutterBridge', JSON.stringify({
        event: 'vrmLoaded', vrmVersion
      }));
    },
    (progress) => {
      const percent = Math.round((progress.loaded / progress.total) * 100);
      console.log(`Loading: ${percent}%`);
    },
    (loadError) => {
      console.error("VRM load failed:", loadError);
      window.flutter_inappwebview.callHandler('FlutterBridge', JSON.stringify({
        event: 'vrmError', error: String(loadError)
      }));
    }
  );
}

// ─── Flutter Bridge ──────────────────────────────────────────────────────────
window.onFlutterMessage = (jsonString) => {
  const data = JSON.parse(jsonString);

  if (data.command === 'loadVRM') {
    loadVRM(data.url);
  }

  // ARCore overlay: Flutter tells us where to place the model
  if (data.command === 'placeAR') {
    if (currentVRM) {
      currentVRM.scene.position.set(data.x, data.y, data.z);
      currentVRM.scene.visible = true;
      avatarPlaced = true;
    }
  }
};

// ─── WebXR AR (only used in 'ar' mode, not 'ar-overlay') ─────────────────────
async function startAR() {
  if (isOverlay) {
    console.log("startAR skipped — using ARCore overlay mode");
    return;
  }

  console.log("startAR called");
  console.log("navigator.xr:", !!navigator.xr);

  if (!navigator.xr) {
    console.error("WebXR not available");
    return;
  }

  const supported = await navigator.xr.isSessionSupported('immersive-ar');
  if (!supported) {
    console.error("Immersive AR not supported on this device");
    return;
  }

  xrSession = await navigator.xr.requestSession('immersive-ar', {
    requiredFeatures: ['hit-test', 'dom-overlay'],
    domOverlay: { root: document.body }
  });

  await renderer.xr.setSession(xrSession);
  xrRefSpace = await xrSession.requestReferenceSpace('local');
  const viewerSpace = await xrSession.requestReferenceSpace('viewer');
  xrHitTestSource = await xrSession.requestHitTestSource({ space: viewerSpace });

  document.getElementById('tap-hint').style.display = 'block';

  document.addEventListener('touchstart', () => {
    if (reticle.visible && currentVRM) {
      currentVRM.scene.position.setFromMatrixPosition(reticle.matrix);
      currentVRM.scene.quaternion.setFromRotationMatrix(reticle.matrix);
      currentVRM.scene.visible = true;
      avatarPlaced = true;
      reticle.visible = false;
      document.getElementById('tap-hint').style.display = 'none';
    }
  });

  xrSession.addEventListener('end', () => {
    xrHitTestSource = null;
    xrSession = null;
    avatarPlaced = false;
    renderer.xr.enabled = false;
  });

  window.flutter_inappwebview.callHandler('FlutterBridge', JSON.stringify({
    event: 'arStarted'
  }));
}

// ─── Animation Loop ──────────────────────────────────────────────────────────
renderer.setAnimationLoop((timestamp, frame) => {
  const delta = clock.getDelta();
  elapsedTime += delta;

  if (currentVRM) {
    currentVRM.update(delta);
    setBonesToIdle(elapsedTime, vrmFactor);
    applyPoseBuffer();
  }

  // WebXR hit test (only active in 'ar' mode with a live session)
  if (frame && xrHitTestSource && xrRefSpace) {
    const hits = frame.getHitTestResults(xrHitTestSource);
    if (hits.length > 0 && !avatarPlaced) {
      const pose = hits[0].getPose(xrRefSpace);
      reticle.visible = true;
      reticle.matrix.fromArray(pose.transform.matrix);
    } else {
      reticle.visible = false;
    }
  }

  renderer.render(scene, camera);
});

// Exposed for HTML overlay button
window.startARSession = startAR;

// Signal Flutter that JS is ready
window.addEventListener('load', () => {
  window.flutter_inappwebview.callHandler('FlutterBridge', JSON.stringify({
    event: 'ready'
  }));
});