package com.example.aikomate_flutter

import android.opengl.Matrix
import android.util.Log
import com.google.ar.sceneform.rendering.EngineInstance
import com.google.ar.sceneform.rendering.RenderableInstance
import kotlin.math.cos
import kotlin.math.sin

class VrmIdleAnimator(
    private val renderableInstance: RenderableInstance,
    private val vrmFactor: Float
) {

    private data class BoneBinding(
        val entity: Int,
        val baseTransform: FloatArray
    )

    private val tag = "VrmIdleAnimator"
    private val transformManager = EngineInstance.getEngine().filamentEngine.transformManager
    private val bindings = mutableMapOf<String, BoneBinding>()
    private val entityNames = linkedMapOf<Int, String>()

    init {
        cacheEntityNames()

        bind("head", "head", "j_bip_c_head", "mixamorighead")
        bind("neck", "neck", "j_bip_c_neck", "mixamorigneck")
        bind("spine", "spine", "spine1", "chest", "j_bip_c_spine", "mixamorigspine")
        bind("rightUpperArm", "rightupperarm", "upperarmr", "j_bip_r_upperarm", "mixamorigrightarm")
        bind("leftUpperArm", "leftupperarm", "upperarml", "j_bip_l_upperarm", "mixamorigleftarm")
        bind("rightLowerArm", "rightlowerarm", "forearmr", "j_bip_r_lowerarm", "mixamorigrightforearm")
        bind("leftLowerArm", "leftlowerarm", "forearml", "j_bip_l_lowerarm", "mixamorigleftforearm")
        bind("rightHand", "righthand", "handr", "j_bip_r_hand", "mixamorigrighthand")
        bind("leftHand", "lefthand", "handl", "j_bip_l_hand", "mixamoriglefthand")
    }

    fun update(t: Float) {
        val yaw = 0f
        val pitch = 0f

        setBone(
            "head",
            xDeg = (pitch * 65f + sin(t) * 5f) * vrmFactor,
            yDeg = (yaw * 55f - sin(t) * 2f),
            zDeg = (cos(t * 2f) * 5f)
        )
        setBone(
            "neck",
            xDeg = (pitch * 20f + sin(t) * 3f) * vrmFactor,
            yDeg = sin(t) * 1f,
            zDeg = cos(t * 2f) * 5f
        )
        setBone(
            "spine",
            xDeg = (pitch * 10f + cos(t * 1.1f) * 3f) * vrmFactor,
            yDeg = yaw * 60f,
            zDeg = (sin(t) * 3f) * vrmFactor
        )

        setBone(
            "rightUpperArm",
            xDeg = cos(t * 0.8f) * 2f,
            yDeg = 0f,
            zDeg = (75f + sin(t * 0.7f) * 2f) * vrmFactor
        )
        setBone(
            "leftUpperArm",
            xDeg = sin(t * 0.85f) * 2f,
            yDeg = 0f,
            zDeg = (-75f + cos(t * 0.78f) * 2f) * vrmFactor
        )
        setBone("rightLowerArm", xDeg = 0f, yDeg = 0f, zDeg = 5f * vrmFactor)
        setBone("leftLowerArm", xDeg = 0f, yDeg = 0f, zDeg = -5f * vrmFactor)
        setBone("rightHand", xDeg = 0f, yDeg = 0f, zDeg = 20f * vrmFactor)
        setBone("leftHand", xDeg = 0f, yDeg = 0f, zDeg = -20f * vrmFactor)

        // Manual bone transforms require explicit skinning update in Sceneform's render path.
        runCatching { renderableInstance.filamentAsset?.animator?.updateBoneMatrices() }
    }

    private fun cacheEntityNames() {
        val asset = renderableInstance.filamentAsset ?: return
        asset.entities.forEach { entity ->
            val name = asset.getName(entity) ?: ""
            if (name.isNotEmpty()) {
                entityNames[entity] = name
            }
        }
    }

    private fun bind(logicalName: String, vararg candidateNames: String) {
        val asset = renderableInstance.filamentAsset ?: return
        val entity = findEntityByCandidates(asset, candidateNames.toList()) ?: return

        val instance = transformManager.getInstance(entity)
        if (instance == 0) return

        val base = FloatArray(16)
        transformManager.getTransform(instance, base)
        bindings[logicalName] = BoneBinding(entity, base)
    }

    private fun setBone(logicalName: String, xDeg: Float, yDeg: Float, zDeg: Float) {
        val bone = bindings[logicalName] ?: return
        val instance = transformManager.getInstance(bone.entity)
        if (instance == 0) return

        val rotation = FloatArray(16)
        Matrix.setIdentityM(rotation, 0)
        Matrix.rotateM(rotation, 0, xDeg, 1f, 0f, 0f)
        Matrix.rotateM(rotation, 0, yDeg, 0f, 1f, 0f)
        Matrix.rotateM(rotation, 0, zDeg, 0f, 0f, 1f)

        val combined = FloatArray(16)
        Matrix.multiplyMM(combined, 0, bone.baseTransform, 0, rotation, 0)
        transformManager.setTransform(instance, combined)
    }

    private fun normalizeName(value: String): String {
        return value.lowercase().filter { it.isLetterOrDigit() }
    }

    private fun findEntityByCandidates(
        asset: com.google.android.filament.gltfio.FilamentAsset,
        candidates: List<String>
    ): Int? {
        // Fast exact lookup through Filament API first.
        candidates.forEach { candidate ->
            val direct = asset.getFirstEntityByName(candidate)
            if (direct != 0) return direct
        }

        // Fuzzy fallback by normalized contains.
        val normalizedCandidates = candidates.map(::normalizeName)
        var bestEntity: Int? = null
        var bestScore = -1

        entityNames.forEach { (entity, name) ->
            val normalized = normalizeName(name)
            var score = 0
            normalizedCandidates.forEach { candidate ->
                if (candidate.isNotEmpty() && normalized.contains(candidate)) {
                    score += candidate.length
                }
            }
            if (score > bestScore) {
                bestScore = score
                bestEntity = entity
            }
        }

        return if (bestScore > 0) bestEntity else null
    }

    fun hasAnyBoundBone(): Boolean {
        val hasBones = bindings.isNotEmpty()
        if (!hasBones) {
            Log.w(tag, "No known VRM bones found for idle animation.")
            if (entityNames.isNotEmpty()) {
                val sample = entityNames.values.take(25).joinToString(", ")
                Log.w(tag, "Available entity names sample: $sample")
            }
        }
        return hasBones
    }
}
