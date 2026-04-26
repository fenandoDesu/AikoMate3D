import * as THREE from "../../libs/three.module.js";
import { GLTFLoader } from "../../libs/GLTFLoader.js";
import { VRMLoaderPlugin, VRMUtils } from "../../libs/three-vrm.module.js";
import { setBonesToIdle, initPoseBuffer, applyPoseBuffer } from "./animations/animations.js";
import {
  attachAvatarHitRegions,
  detachAvatarHitRegions,
  pickInteractiveBone,
  sampleHeadOrbitPerimeterWorld,
} from "./interaction/avatarHitRegions.js";
import {
  disposeObject,
  isPropCached,
  preloadProp,
  prepareGltfInstanceForDisplay,
  spawnProp,
} from "./interaction/gltfPropCache.js";
import { animateHeart } from "./interaction/petHeartEffect.js";
import { bodyToPoseBufferInput, buildVrmNormalizedBody } from "./vrmBones.js";
import {
  applyIdleMouthFromPose,
  clearExpressionTweens,
  configureExpressionRuntime,
  defineExpression,
  mouthPose,
  resetHeadPettingExpressionState,
  setExpressions,
  updateExpressionTweens,
  updateHeadPettingExpression,
} from "./expressions.js";

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
if ("outputColorSpace" in renderer) {
  renderer.outputColorSpace = THREE.SRGBColorSpace;
}
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
  38,
  window.innerWidth / window.innerHeight,
  0.1,
  100
);
const defaultCameraPosition = new THREE.Vector3(0, 1.45, 1.7);
camera.position.copy(defaultCameraPosition);
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
  refreshRasterBackgroundCover();
});

// ─── VRM State ───────────────────────────────────────────────────────────────
let currentVRM = null;
/** Cached normalized bone nodes from buildVrmNormalizedBody (see vrmBones.js). */
let avatarNormalizedBody = null;
let vrmFactor = 1;
const clock = new THREE.Clock();
let elapsedTime = 0;

// ─── Head petting + heart props (normal mode) ───────────────────────────────
const PET_ACTIVE_HOLD_MS = 500;
const PET_MOVEMENT_PER_HEART_PX = 20;
const PET_HEART_COOLDOWN_MS = 500;
const MAX_ACTIVE_HEARTS = 10;
const HEART_MIN_SPAWN_SEPARATION = 0.14;
const HEART_ORBIT_SAMPLE_ATTEMPTS = 8;
const PET_DEBUG = true;
/** Extra scale after `prepareGltfInstanceForDisplay` normalizes the GLB. */
const HEART_SCALE = 0.3;
/** Circle radius (world units) around the head bone; hearts spawn on this circle's perimeter. */
const HEAD_HEART_ORBIT_RADIUS = 0.2;
/** World-space nudge after orbit sample (Y up, Z depth); tune if hearts sit too low/high. */
const HEAD_HEART_SPAWN_OFFSET = new THREE.Vector3(0, 0, 0.2);
const HEART_ASSET_URL = new URL("../../3d_objects/heart.glb", import.meta.url).href;

const _heartOrbitPos = new THREE.Vector3();
const _heartCandidatePos = new THREE.Vector3();
const _lastHeartSpawnWorldPositions = [];

let lastHeartSpawnTs = 0;
let activePetHearts = 0;
const _petDebugTsByKey = new Map();
/** @type {Promise<void> | null} */
let heartPreloadPromise = null;
let petIntimacyLevel = 0;
let petProgress = 0;
const petInput = {
  isDown: false,
  nearHead: false,
  lastX: 0,
  lastY: 0,
  movementAccum: 0,
  rubActiveUntilMs: 0,
};

function petsRequired(level) {
  // Increasing effort curve per level (10, 20, 34, 52, ...).
  return 10 + level * 8 + level * level * 2;
}

function emitIntimacyUpdate() {
  try {
    window.flutter_inappwebview.callHandler(
      "FlutterBridge",
      JSON.stringify({ event: "intimacy_update", intimacy: petIntimacyLevel })
    );
  } catch (_) {
    /* no bridge available */
  }
}

function registerPetHeart() {
  petProgress += 1;
  const req = petsRequired(petIntimacyLevel);
  if (petProgress >= req) {
    petIntimacyLevel += 1;
    petProgress = 0;
    emitIntimacyUpdate();
  }
}

function setPetIntimacyLevel(level) {
  const next = Number.isFinite(level) ? Math.max(0, Math.round(level)) : 0;
  petIntimacyLevel = next;
  petProgress = 0;
}

function ensureHeartCached() {
  if (isPropCached("heart")) return true;
  if (!heartPreloadPromise) {
    heartPreloadPromise = preloadProp("heart", HEART_ASSET_URL)
      .catch((err) => {
        console.warn("heart.glb preload failed", err);
      })
      .finally(() => {
        heartPreloadPromise = null;
      });
  }
  return false;
}

function minDistanceToRecentHearts(worldPos) {
  if (_lastHeartSpawnWorldPositions.length === 0) return Infinity;
  let minDist = Infinity;
  for (const p of _lastHeartSpawnWorldPositions) {
    const d = worldPos.distanceTo(p);
    if (d < minDist) minDist = d;
  }
  return minDist;
}

function rememberHeartSpawnWorld(worldPos) {
  _lastHeartSpawnWorldPositions.push(worldPos.clone());
  if (_lastHeartSpawnWorldPositions.length > 2) {
    _lastHeartSpawnWorldPositions.shift();
  }
}

function isPointOnHead(clientX, clientY) {
  const hit = pickInteractiveBone(
    clientX,
    clientY,
    avatarNormalizedBody,
    camera,
    canvas
  );
  return hit?.name === "head";
}

function resetPetInputState() {
  petInput.isDown = false;
  petInput.nearHead = false;
  petInput.movementAccum = 0;
  petInput.rubActiveUntilMs = 0;
}

function onPetInputStart(clientX, clientY) {
  petInput.isDown = true;
  petInput.lastX = clientX;
  petInput.lastY = clientY;
  petInput.nearHead = isPointOnHead(clientX, clientY);
  petInput.movementAccum = 0;
  if (!petInput.nearHead) {
    petInput.rubActiveUntilMs = 0;
  }
}

function onPetInputMove(clientX, clientY) {
  if (!petInput.isDown) return;
  const now = performance.now();
  const nearHead = isPointOnHead(clientX, clientY);
  const dx = clientX - petInput.lastX;
  const dy = clientY - petInput.lastY;
  petInput.lastX = clientX;
  petInput.lastY = clientY;
  petInput.nearHead = nearHead;

  if (!nearHead) {
    petInput.movementAccum = 0;
    petInput.rubActiveUntilMs = 0;
    return;
  }

  const move = Math.hypot(dx, dy);
  if (move >= 0.5) {
    petInput.movementAccum += move;
  }

  if (petInput.movementAccum >= PET_MOVEMENT_PER_HEART_PX) {
    petInput.rubActiveUntilMs = now + PET_ACTIVE_HOLD_MS;
    while (petInput.movementAccum >= PET_MOVEMENT_PER_HEART_PX) {
      petInput.movementAccum -= PET_MOVEMENT_PER_HEART_PX;
      emitPetRubHaptic();
      trySpawnPetHeart(clientX, clientY);
      if (now - lastHeartSpawnTs < PET_HEART_COOLDOWN_MS) break;
    }
  }
}

function onPetInputEnd() {
  resetPetInputState();
}

function petDebug(message, data, throttleKey = "", throttleMs = 0) {
  if (!PET_DEBUG) return;
  const now = performance.now();
  if (throttleKey) {
    const prev = _petDebugTsByKey.get(throttleKey) ?? 0;
    if (now - prev < throttleMs) return;
    _petDebugTsByKey.set(throttleKey, now);
  }
  if (data !== undefined) {
    try {
      console.log(`[pet] ${message} ${JSON.stringify(data)}`);
    } catch (_) {
      console.log(`[pet] ${message}`, data);
    }
  } else {
    console.log(`[pet] ${message}`);
  }
}

function emitPetRubHaptic() {
  try {
    window.flutter_inappwebview.callHandler(
      "FlutterBridge",
      JSON.stringify({ event: "petRub" })
    );
  } catch (_) {
    /* no bridge available */
  }
}

function trySpawnPetHeart(clientX, clientY) {
  if (isAR || renderer.xr?.isPresenting || !currentVRM) {
    petDebug("spawn blocked: ar/xr/no vrm", { isAR, xrPresenting: !!renderer.xr?.isPresenting, hasVRM: !!currentVRM }, "spawn-block-ar", 600);
    return;
  }
  const now = performance.now();
  if (now - lastHeartSpawnTs < PET_HEART_COOLDOWN_MS) return;
  if (activePetHearts >= MAX_ACTIVE_HEARTS) {
    petDebug("spawn blocked: max active hearts", { activePetHearts, max: MAX_ACTIVE_HEARTS }, "spawn-block-max", 350);
    return;
  }
  if (!ensureHeartCached()) {
    petDebug("spawn blocked: heart not cached", undefined, "spawn-block-cache", 600);
    return;
  }
  const heart = spawnProp("heart");
  if (!heart) {
    petDebug("spawn blocked: spawnProp returned null", undefined, "spawn-block-null", 600);
    return;
  }

  lastHeartSpawnTs = now;
  activePetHearts += 1;
  registerPetHeart();
  petDebug("heart spawned", { activePetHearts });

  const randomFactor = 0.8 + Math.random() * 0.4;
  prepareGltfInstanceForDisplay(heart, { targetMaxDimension: 0.28 });
  heart.scale.multiplyScalar(HEART_SCALE);
  let bestMinDist = -1;
  let hasSample = false;
  for (let i = 0; i < HEART_ORBIT_SAMPLE_ATTEMPTS; i += 1) {
    if (
      !sampleHeadOrbitPerimeterWorld(
        avatarNormalizedBody,
        camera,
        HEAD_HEART_ORBIT_RADIUS,
        _heartCandidatePos
      )
    ) {
      break;
    }
    hasSample = true;
    const minDist = minDistanceToRecentHearts(_heartCandidatePos);
    if (minDist > bestMinDist) {
      bestMinDist = minDist;
      _heartOrbitPos.copy(_heartCandidatePos);
    }
    if (minDist >= HEART_MIN_SPAWN_SEPARATION) {
      break;
    }
  }

  if (!hasSample) {
    _heartOrbitPos.set(0, 0, 0);
    avatarNormalizedBody?.head?.getWorldPosition(_heartOrbitPos);
  }
  heart.position.copy(_heartOrbitPos).add(HEAD_HEART_SPAWN_OFFSET);
  rememberHeartSpawnWorld(heart.position);

  const headBone = avatarNormalizedBody?.head;
  if (!headBone) {
    petDebug("spawn aborted: no head bone on avatarNormalizedBody");
    disposeObject(heart);
    activePetHearts = Math.max(0, activePetHearts - 1);
    return;
  }
  headBone.updateMatrixWorld(true);
  headBone.worldToLocal(heart.position);
  headBone.add(heart);

  animateHeart(heart, randomFactor, {
    onComplete: () => {
      activePetHearts = Math.max(0, activePetHearts - 1);
      petDebug("heart completed", { activePetHearts }, "heart-complete", 200);
    },
  });
}


function focusCameraOnAvatar() {
  const target = new THREE.Vector3(0, 1.4, 0);
  if (currentVRM && currentVRM.scene) {
    currentVRM.scene.getWorldPosition(target);
    target.y += 1.4;
  }
  camera.lookAt(target);
}

function resetCamera() {
  camera.position.copy(defaultCameraPosition);
  focusCameraOnAvatar();
}

// --- Lip sync (phonemes) ---
let currentSpeech = null;
let isSpeaking = false;
let speechStartTime = 0;
let phonemeLastTime = 0;
const speechMouth = { aa: 0, ih: 0, ee: 0, oh: 0, ou: 0 };

configureExpressionRuntime({
  getIsSpeaking: () => isSpeaking,
});

function applySpeechPauses(phonemes, audioDuration = 0) {
  if (!Array.isArray(phonemes)) return [];
  const pauseMap = new Map([
    [".", 500],
    ["?", 500],
    ["...", 500],
    ["[pause]", 500],
    [",", 300],
    ["-", 300],
    ["[long pause]", 700],
  ]);

  let delay = 0;
  let out = [];

  for (const p of phonemes) {
    const key = (p?.phoneme || "").trim().toLowerCase();
    const pause = pauseMap.get(key);
    if (pause) {
      delay += pause / 1000;
      continue;
    }
    if (p && typeof p.start === "number" && typeof p.duration === "number") {
      out.push({
        ...p,
        start: p.start + delay,
        duration: p.duration,
      });
    }
  }

  const endTime = out.length
    ? out[out.length - 1].start + out[out.length - 1].duration
    : 0;

  if (audioDuration > 0 && endTime > 0) {
    const scale = audioDuration / endTime;
    out = out.map((p) => ({
      ...p,
      start: p.start * scale,
      duration: p.duration * scale,
    }));
  }

  return out;
}

function startSpeech(phonemes, audioDuration = 0) {
  if (!currentVRM || !currentVRM.expressionManager) return;
  resetHeadPettingExpressionState();
  setExpressions(currentVRM.expressionManager, { petting: 0 }, 0, {
    isSpeaking: true,
  });
  currentSpeech = applySpeechPauses(phonemes, audioDuration);
  isSpeaking = true;
  speechStartTime = performance.now() / 1000;
  phonemeLastTime = speechStartTime;
  requestAnimationFrame(stepPhonemes);
}

function updatePhonemes(phonemes, audioDuration = 0) {
  if (!currentSpeech) return;
  currentSpeech = applySpeechPauses(phonemes, audioDuration);
}

function endSpeech() {
  isSpeaking = false;
  currentSpeech = null;
  resetHeadPettingExpressionState();
  if (currentVRM?.expressionManager) {
    defineExpression(currentVRM.expressionManager, "normal", elapsedTime);
  }
}

function stepPhonemes(nowMs) {
  if (!currentVRM || !currentVRM.expressionManager || !isSpeaking) return;
  const now = nowMs / 1000;
  const delta = Math.min(now - phonemeLastTime, 0.033);
  phonemeLastTime = now;
  const elapsed = now - speechStartTime;

  speechMouth.aa = 0;
  speechMouth.ih = 0;
  speechMouth.ee = 0;
  speechMouth.oh = 0;
  speechMouth.ou = 0;

  if (currentSpeech) {
    for (const p of currentSpeech) {
      if (elapsed >= p.start && elapsed < p.start + p.duration) {
        const strength = 1.0 - (elapsed - p.start) / p.duration;
        const phoneme = (p.phoneme || "").toUpperCase();
        let vrmViseme = "aa";

        switch (phoneme) {
          case "A": vrmViseme = "aa"; break;
          case "E": vrmViseme = "ee"; break;
          case "I": vrmViseme = "ih"; break;
          case "O": vrmViseme = "oh"; break;
          case "U": vrmViseme = "ou"; break;
          case "B":
          case "P":
          case "M": vrmViseme = "ou"; break;
          case "S": vrmViseme = "ih"; break;
          case "T": vrmViseme = "ee"; break;
          case "K": vrmViseme = "oh"; break;
          case "L": vrmViseme = "ee"; break;
          case "R": vrmViseme = "ou"; break;
          default: vrmViseme = "aa";
        }

        const maxStrength = 0.7;
        const target = Math.min(strength * 0.9, maxStrength);
        speechMouth[vrmViseme] = Math.max(speechMouth[vrmViseme], target);
      }
    }
  }

  for (const v of ["aa", "ih", "ee", "oh", "ou"]) {
    const target = isSpeaking ? speechMouth[v] : mouthPose[v];
    const current = currentVRM.expressionManager.getValue(v) ?? 0;
    const smooth = current + (target - current) * delta * 12;
    currentVRM.expressionManager.setValue(v, smooth);
  }

  currentVRM.expressionManager.update();
  if (isSpeaking) requestAnimationFrame(stepPhonemes);
}

// --- Backgrounds (normal mode only) ---
let roomModel = null;
let bgVideo = null;
let bgVideoTexture = null;

function clearRoom() {
  if (!roomModel) return;
  scene.remove(roomModel);
  roomModel.traverse((child) => {
    if (child.geometry) child.geometry.dispose();
    if (child.material) {
      const mats = Array.isArray(child.material) ? child.material : [child.material];
      mats.forEach((m) => m.dispose && m.dispose());
    }
  });
  roomModel = null;
}

function clearVideoBackground() {
  if (bgVideo) {
    bgVideo.pause();
    bgVideo.src = "";
    bgVideo.load();
  }
  bgVideo = null;
  if (bgVideoTexture) bgVideoTexture.dispose();
  bgVideoTexture = null;
}

/** Active image/video background for aspect-cover + pan/zoom (not 3D room). */
let rasterBackgroundState = null;

function applyRasterCoverToTexture(texture, viewAspect, focusX, focusY, zoom) {
  const img = texture.image;
  if (!img) return;
  const iw = img.naturalWidth || img.width || img.videoWidth || 0;
  const ih = img.naturalHeight || img.height || img.videoHeight || 0;
  if (!iw || !ih) return;

  const ia = iw / ih;
  const z = Math.max(0.5, Math.min(Number(zoom) || 1, 4));
  const fx = Math.max(0, Math.min(Number(focusX) ?? 0.5, 1));
  const fy = Math.max(0, Math.min(Number(focusY) ?? 0.5, 1));

  let repeatX = 1;
  let repeatY = 1;
  if (ia > viewAspect) {
    repeatX = (viewAspect / ia) / z;
    repeatY = 1 / z;
  } else {
    repeatX = 1 / z;
    repeatY = (ia / viewAspect) / z;
  }

  const offsetX = fx * (1 - repeatX);
  const offsetY = fy * (1 - repeatY);

  texture.wrapS = THREE.ClampToEdgeWrapping;
  texture.wrapT = THREE.ClampToEdgeWrapping;
  texture.repeat.set(repeatX, repeatY);
  texture.offset.set(offsetX, offsetY);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.minFilter = THREE.LinearMipmapLinearFilter;
  texture.magFilter = THREE.LinearFilter;
  texture.anisotropy = renderer.capabilities.getMaxAnisotropy();
  texture.generateMipmaps = true;
  // scene.background expects the same vertical convention for TextureLoader and VideoTexture;
  // VideoTexture defaults to flipY false, which appears upside-down as the env background.
  texture.flipY = true;
  texture.needsUpdate = true;
}

function refreshRasterBackgroundCover() {
  if (!rasterBackgroundState) return;
  const { texture, focusX, focusY, zoom } = rasterBackgroundState;
  if (!texture || !texture.image) return;
  applyRasterCoverToTexture(
    texture,
    window.innerWidth / window.innerHeight,
    focusX,
    focusY,
    zoom
  );
}

function setBackground(config) {
  if (isAR) return;
  const type = config?.type || "none";
  const url = config?.url || "";
  const focusX = typeof config.focusX === "number" ? config.focusX : 0.5;
  const focusY = typeof config.focusY === "number" ? config.focusY : 0.5;
  const zoom = typeof config.zoom === "number" ? config.zoom : 1;

  if (
    (type === "image" || type === "video") &&
    url &&
    rasterBackgroundState &&
    rasterBackgroundState.url === url &&
    rasterBackgroundState.type === type
  ) {
    rasterBackgroundState.focusX = focusX;
    rasterBackgroundState.focusY = focusY;
    rasterBackgroundState.zoom = zoom;
    refreshRasterBackgroundCover();
    return;
  }

  clearRoom();
  clearVideoBackground();
  rasterBackgroundState = null;

  if (type === "none") {
    scene.background = new THREE.Color(0xffffff);
    return;
  }

  if (type === "image" && url) {
    const loader = new THREE.TextureLoader();
    loader.setCrossOrigin("anonymous");
    loader.load(
      url,
      (texture) => {
        const viewAspect = window.innerWidth / window.innerHeight;
        applyRasterCoverToTexture(texture, viewAspect, focusX, focusY, zoom);
        scene.background = texture;
        rasterBackgroundState = {
          texture,
          focusX,
          focusY,
          zoom,
          url,
          type: "image",
        };
      },
      undefined,
      () => {
        console.warn("Failed to load background image");
      }
    );
    return;
  }

  if (type === "video" && url) {
    bgVideo = document.createElement("video");
    bgVideo.crossOrigin = "anonymous";
    bgVideo.src = url;
    bgVideo.loop = true;
    bgVideo.muted = true;
    bgVideo.playsInline = true;
    bgVideo.play().catch(() => {});
    bgVideoTexture = new THREE.VideoTexture(bgVideo);
    bgVideoTexture.colorSpace = THREE.SRGBColorSpace;
    const applyVideoCover = () => {
      applyRasterCoverToTexture(
        bgVideoTexture,
        window.innerWidth / window.innerHeight,
        focusX,
        focusY,
        zoom
      );
      rasterBackgroundState = {
        texture: bgVideoTexture,
        focusX,
        focusY,
        zoom,
        url,
        type: "video",
      };
    };
    bgVideo.addEventListener("loadedmetadata", applyVideoCover, { once: true });
    scene.background = bgVideoTexture;
    rasterBackgroundState = {
      texture: bgVideoTexture,
      focusX,
      focusY,
      zoom,
      url,
      type: "video",
    };
    return;
  }

  if (type === "room" && url) {
    const loader = new GLTFLoader();
    loader.setCrossOrigin("anonymous");
    loader.load(
      url,
      (gltf) => {
        roomModel = gltf.scene;
        roomModel.position.set(0, 0, 0);
        roomModel.scale.set(1, 1, 1);
        scene.add(roomModel);
        resetCamera();
      },
      undefined,
      () => {
        console.warn("Failed to load room");
      }
    );
  }
}

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
  detachAvatarHitRegions();
  clearExpressionTweens();
  avatarNormalizedBody = null;
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
      resetCamera();

      avatarNormalizedBody = buildVrmNormalizedBody(vrm);
      initPoseBuffer(bodyToPoseBufferInput(avatarNormalizedBody));

      if (vrm.expressionManager) {
        defineExpression(vrm.expressionManager, "normal", 0);
      }

      if (!isAR) {
        attachAvatarHitRegions(avatarNormalizedBody);
        ensureHeartCached();
      }

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

  if (data.command === 'setBackground') {
    setBackground({
      type: data.type,
      url: data.url,
      focusX: data.focusX,
      focusY: data.focusY,
      zoom: data.zoom,
    });
  }

  // ARCore overlay: Flutter tells us where to place the model
  if (data.command === 'placeAR') {
    if (currentVRM) {
      currentVRM.scene.position.set(data.x, data.y, data.z);
      currentVRM.scene.visible = true;
      avatarPlaced = true;
    }
  }

  if (data.command === 'petInputStart') {
    onPetInputStart(Number(data.x) || 0, Number(data.y) || 0);
  }

  if (data.command === 'petInputMove') {
    onPetInputMove(Number(data.x) || 0, Number(data.y) || 0);
  }

  if (data.command === 'petInputEnd') {
    onPetInputEnd();
  }

  if (data.command === 'setIntimacy') {
    setPetIntimacyLevel(Number(data.value));
  }

  if (data.event === 'start_speech') {
    startSpeech(data.phonemes || [], data.audioDuration || 0);
  }

  if (data.event === 'update_phonemes') {
    updatePhonemes(data.phonemes || [], data.audioDuration || 0);
  }

  if (data.event === 'end_speech') {
    endSpeech();
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
    const em = currentVRM.expressionManager;
    if (em) {
      updateExpressionTweens(em, performance.now());

      let overHead = false;
      if (petInput.isDown && !isAR) {
        overHead = petInput.nearHead;
      }
      const pettingActive =
        petInput.isDown &&
        overHead &&
        performance.now() < petInput.rubActiveUntilMs;
      /* Petting morph must not be gated on global speech; that flag skipped all petting updates. */
      updateHeadPettingExpression(em, elapsedTime, {
        isSpeaking: false,
        pettingActive,
      });

      if (!isSpeaking) {
        applyIdleMouthFromPose(em, delta);
      }
      em.update();
    }
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
