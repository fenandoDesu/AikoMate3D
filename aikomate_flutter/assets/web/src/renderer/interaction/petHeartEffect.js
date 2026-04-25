import { disposeObject } from "./gltfPropCache.js";

/**
 * @param {import("../../../libs/three.module.js").Object3D} heart
 * @param {number} randomFactor
 * @param {{ onComplete?: () => void }} ctx
 */
export function animateHeart(heart, randomFactor, ctx) {
  const { onComplete } = ctx;
  const startX = heart.position.x;
  const startY = heart.position.y;
  let life = 0;
  let xMovement = 0;
  let zRotation = 0;
  let xRotation = 0;

  function tick() {
    life += 0.01;
    xMovement += randomFactor / 2200;
    zRotation += randomFactor / 8000;
    xRotation += randomFactor / 10000;

    heart.position.y = startY + life * 0.1;
    heart.position.x = startX + xMovement;
    heart.rotation.y += 0.03;
    heart.rotation.z += zRotation;
    heart.rotation.x += xRotation;

    heart.traverse((obj) => {
      if (obj.isMesh && obj.material) {
        const mats = Array.isArray(obj.material) ? obj.material : [obj.material];
        for (const m of mats) {
          m.transparent = true;
          m.opacity = 1 - life;
        }
      }
    });

    if (life < 1) {
      requestAnimationFrame(tick);
    } else {
      heart.removeFromParent();
      disposeObject(heart);
      onComplete?.();
    }
  }

  tick();
}
