/**
 * Central VRM expression control: setExpressions (with mouth buffer + tweens),
 * defineExpression presets, and per-frame tween updates.
 */

export const EYE_EXPRESSIONS = new Set([
  "lookUp",
  "lookDown",
  "lookLeft",
  "lookRight",
  "lookUpLeft",
  "lookUpRight",
  "lookDownLeft",
  "lookDownRight",
]);

export const BLINK_EXPRESSIONS = new Set(["blink", "blinkLeft", "blinkRight"]);

export const MOUTH_VISEMES = new Set(["aa", "ih", "ee", "oh", "ou"]);

/** Idle / scripted mouth targets (visemes); never written here during speech unless isLipSync. */
export const mouthPose = { aa: 0, ih: 0, ee: 0, oh: 0, ou: 0 };

/** @type {Record<string, { target: number, blended: number } | { startValue: number, targetValue: number, startTime: number, endTime: number }>} */
const expressionTweens = {};

let getIsSpeaking = () => false;

/**
 * @param {{ getIsSpeaking?: () => boolean }} opts
 */
export function configureExpressionRuntime(opts = {}) {
  if (typeof opts.getIsSpeaking === "function") {
    getIsSpeaking = opts.getIsSpeaking;
  }
}

/**
 * @param {any} manager VRM expressionManager
 * @param {Record<string, number>} expressions
 * @param {number} duration seconds
 * @param {boolean | { isLipSync?: boolean, allowEye?: boolean, allowBlink?: boolean, isSpeaking?: boolean }} options
 */
export function setExpressions(manager, expressions, duration = 0, options = {}) {
  if (!manager) return;

  const opts = typeof options === "boolean" ? { isLipSync: options } : options;
  const {
    isLipSync = false,
    allowEye = false,
    allowBlink = true,
    isSpeaking: isSpeakingOpt,
  } = opts;

  const speaking =
    isSpeakingOpt !== undefined ? isSpeakingOpt : getIsSpeaking();
  const now = performance.now();

  for (const [name, targetValue] of Object.entries(expressions)) {
    if (!allowEye && EYE_EXPRESSIONS.has(name)) continue;
    if (!allowBlink && BLINK_EXPRESSIONS.has(name)) continue;

    if (MOUTH_VISEMES.has(name)) {
      if (!speaking || isLipSync) {
        mouthPose[name] = targetValue;
      }
      continue;
    }

    const startValue = safeGetValue(manager, name) ?? 0;

    if (duration === 0) {
      safeSetValue(manager, name, targetValue);
      expressionTweens[name] = { target: targetValue, blended: targetValue };
    } else {
      expressionTweens[name] = {
        startValue,
        targetValue,
        startTime: now,
        endTime: now + duration * 1000,
      };
    }
  }
}

function safeGetValue(manager, name) {
  try {
    return manager.getValue(name);
  } catch (_) {
    return undefined;
  }
}

function safeSetValue(manager, name, value) {
  try {
    manager.setValue(name, value);
  } catch (_) {
    /* unknown expression */
  }
}

/**
 * Lerp active tweens and apply to manager.
 * @param {any} manager VRM expressionManager
 * @param {number} nowMs performance.now()
 */
export function updateExpressionTweens(manager, nowMs) {
  if (!manager) return;

  for (const name of Object.keys(expressionTweens)) {
    const tw = expressionTweens[name];
    if (!tw) continue;

    if ("startTime" in tw && "endTime" in tw) {
      const { startValue, targetValue, startTime, endTime } = tw;
      const span = endTime - startTime;
      const u = span <= 0 ? 1 : Math.min(1, Math.max(0, (nowMs - startTime) / span));
      const v = startValue + (targetValue - startValue) * u;
      safeSetValue(manager, name, v);
      if (u >= 1) delete expressionTweens[name];
    }
  }
}

/**
 * When not speaking, ease mouthPose into the VRM viseme channels.
 * @param {any} manager VRM expressionManager
 * @param {number} delta seconds
 */
export function applyIdleMouthFromPose(manager, delta) {
  const d = Math.min(delta, 0.05);
  for (const v of MOUTH_VISEMES) {
    const target = mouthPose[v] ?? 0;
    const current = safeGetValue(manager, v) ?? 0;
    const smooth = current + (target - current) * d * 12;
    safeSetValue(manager, v, smooth);
  }
}

/**
 * Preset expression bundles. Extend with new `case "foo" === expression` branches.
 * @param {any} manager VRM expressionManager
 * @param {string} expression
 * @param {number | null} t time in seconds for oscillating presets (e.g. idle relaxed)
 */
export function defineExpression(manager, expression, t = null) {
  if (!manager) return;

  const speaking = getIsSpeaking();
  const allowMouth = !speaking;
  const applyExpression = (face, mouth, duration = 0.3) => {
    const expressions = allowMouth ? { ...face, ...mouth } : face;
    setExpressions(manager, expressions, duration, { isSpeaking: speaking });
  };

  const happyStrength = speaking ? 0.5 : 1.0;

  switch (true) {
    case expression === "normal": {
      const tUse = typeof t === "number" ? t : 0;
      applyExpression(
        {
          happy: 0.0,
          angry: 0.0,
          sad: 0.0,
          relaxed: Math.sin(tUse),
          surprised: 0.0,
          blinkLeft: 0.0,
          blinkRight: 0.0,
        },
        { aa: 0.0, ih: 0.0, ee: 0.0, oh: 0.0, ou: 0.0 },
        0.6
      );
      break;
    }
    case expression === "petting":
      setExpressions(
        manager,
        { 
          blinkLeft: 1.0,
          blinkRight: 1.0,
          happy: 1.0,
        },
        0.6,
        { isSpeaking: speaking }
      );
      break;
    case expression === "happy":
      applyExpression(
        { 
          happy: happyStrength, 
          angry: 0, 
          sad: 0, 
          relaxed: 0, 
          surprised: 0,
          blinkLeft: 0,
          blinkRight: 0,
        },
        { aa: 0, ih: 0, ee: 0, oh: 0, ou: 0 },
        0.25
      );
      break;
    default:
      break;
  }
}

/** Clear tween state (e.g. on VRM unload). */
export function clearExpressionTweens() {
  for (const k of Object.keys(expressionTweens)) delete expressionTweens[k];
  resetHeadPettingExpressionState();
}

// ─── Head petting: expression only while pointer on head; 3s after leaving → neutral ─

const HEAD_PETTING_COOLDOWN_MS = 3000;

let headPetHadSession = false;
let headPetOffHeadSince = null;
/** True while the `defineExpression("petting", …)` preset is active (avoids re-triggering tweens every frame). */
let headPettingExpressionApplied = false;

export function resetHeadPettingExpressionState() {
  headPetHadSession = false;
  headPetOffHeadSince = null;
  headPettingExpressionApplied = false;
}

/**
 * Drives the petting face preset while `pettingActive` (press on head, rub inside hitbox, hold).
 * After 3s with no petting since last session, applies `normal`.
 * @param {any} manager
 * @param {number} elapsedTime viewer elapsed seconds (for `defineExpression("normal", t)`)
 * @param {{ isSpeaking: boolean, pettingActive: boolean }} ctx
 */
export function updateHeadPettingExpression(manager, elapsedTime, ctx) {
  if (!manager || ctx.isSpeaking) return;

  const { pettingActive } = ctx;
  const now = performance.now();

  if (pettingActive) {
    headPetHadSession = true;
    headPetOffHeadSince = null;
    if (!headPettingExpressionApplied) {
      defineExpression(manager, "petting", elapsedTime);
      headPettingExpressionApplied = true;
    }
    return;
  }

  if (headPettingExpressionApplied) {
    setExpressions(
      manager,
      { happy: 0, blinkLeft: 0, blinkRight: 0 },
      0.25,
      { isSpeaking: false }
    );
    headPettingExpressionApplied = false;
  }

  if (!headPetHadSession) return;

  if (headPetOffHeadSince === null) {
    headPetOffHeadSince = now;
  }

  if (now - headPetOffHeadSince >= HEAD_PETTING_COOLDOWN_MS) {
    defineExpression(manager, "normal", elapsedTime);
    headPetHadSession = false;
    headPetOffHeadSince = null;
  }
}
