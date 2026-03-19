package com.example.aikomate_flutter

import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.google.ar.core.Anchor
import com.google.ar.core.Config
import com.google.ar.core.Plane
import com.google.ar.core.Session
import com.google.ar.core.TrackingFailureReason
import com.google.ar.core.TrackingState
import com.google.ar.sceneform.ArSceneView
import com.google.ar.sceneform.AnchorNode
import com.google.ar.sceneform.rendering.CameraStream
import com.google.ar.sceneform.rendering.ModelRenderable
import com.google.ar.sceneform.rendering.RenderableInstance
import com.google.ar.sceneform.ux.ArFragment
import com.google.ar.sceneform.ux.TransformableNode
import com.gorisse.thomas.sceneform.light.LightEstimationConfig
import com.gorisse.thomas.sceneform.lightEstimationConfig

class ArActivity : AppCompatActivity() {

    companion object {
        private const val TAG = "ArActivity"
        private const val FRAGMENT_TAG = "AikoArFragment"
        private const val MODEL_PATH = "models/UltimateLoverH1.glb"
    }

    private lateinit var arFragment: ArFragment
    private lateinit var hudTextView: TextView

    private var arSceneView: ArSceneView? = null
    private var sceneUpdateListenerAttached = false
    private var modelRenderable: ModelRenderable? = null
    private var modelLoading = false
    private var modelPlaced = false
    private var anchorNode: AnchorNode? = null
    private var cameraTextureBound = false

    private var idleAnimator: VrmIdleAnimator? = null
    private var elapsedTimeSec = 0f
    private var lastFrameNanos = 0L
    private var vrmFactor = 1f

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_ar)

        hudTextView = findViewById(R.id.hudText)
        findViewById<TextView>(R.id.backBtn).setOnClickListener { finish() }

        vrmFactor = detectVrmFactor(MODEL_PATH)

        arFragment = obtainArFragment()
        configureArFragment()
        loadModel()
    }

    private fun obtainArFragment(): ArFragment {
        (supportFragmentManager.findFragmentByTag(FRAGMENT_TAG) as? ArFragment)?.let { return it }

        val fragment = ArFragment.newInstance(true)
        supportFragmentManager
            .beginTransaction()
            .replace(R.id.arFragmentContainer, fragment, FRAGMENT_TAG)
            .commitNow()
        return fragment
    }

    private fun configureArFragment() {
        arFragment.setOnSessionConfigurationListener { session, config ->
            config.depthMode =
                if (session.isDepthModeSupported(Config.DepthMode.AUTOMATIC)) {
                    Config.DepthMode.AUTOMATIC
                } else {
                    Config.DepthMode.DISABLED
                }
            config.instantPlacementMode = Config.InstantPlacementMode.LOCAL_Y_UP
            config.lightEstimationMode = Config.LightEstimationMode.AMBIENT_INTENSITY
            config.focusMode = Config.FocusMode.AUTO
            config.updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
        }

        arFragment.setOnTapArPlaneListener { hitResult, _, _ ->
            if (modelRenderable == null) {
                updateHud("Loading avatar model...")
                return@setOnTapArPlaneListener
            }
            placeAvatar(hitResult.createAnchor(), "Avatar repositioned")
        }

        arFragment.setOnViewCreatedListener { sceneView ->
            arSceneView = sceneView
            sceneView.lightEstimationConfig = LightEstimationConfig.DISABLED
            sceneView.cameraStream.setDepthOcclusionMode(CameraStream.DepthOcclusionMode.DEPTH_OCCLUSION_DISABLED)
            bindSessionCameraTexture(sceneView)
            attachSceneUpdateListener(sceneView)
        }

        // If fragment view is already created (e.g. after commitNow), hook immediately.
        runCatching { arFragment.arSceneView }.getOrNull()?.let { sceneView ->
            arSceneView = sceneView
            sceneView.lightEstimationConfig = LightEstimationConfig.DISABLED
            sceneView.cameraStream.setDepthOcclusionMode(CameraStream.DepthOcclusionMode.DEPTH_OCCLUSION_DISABLED)
            bindSessionCameraTexture(sceneView)
            attachSceneUpdateListener(sceneView)
        }
    }

    private fun attachSceneUpdateListener(sceneView: ArSceneView) {
        if (sceneUpdateListenerAttached) return
        sceneUpdateListenerAttached = true
        lastFrameNanos = System.nanoTime()

        sceneView.scene.addOnUpdateListener {
            val now = System.nanoTime()
            val dt = ((now - lastFrameNanos).coerceAtLeast(0L) / 1_000_000_000.0).toFloat()
            lastFrameNanos = now
            elapsedTimeSec += dt
            idleAnimator?.update(elapsedTimeSec)

            if (!cameraTextureBound) {
                bindSessionCameraTexture(sceneView)
            }

            val frame = sceneView.arFrame ?: return@addOnUpdateListener

            if (!modelPlaced && modelRenderable != null) {
                frame.getUpdatedTrackables(Plane::class.java)
                    .firstOrNull {
                        it.type == Plane.Type.HORIZONTAL_UPWARD_FACING &&
                            it.trackingState == TrackingState.TRACKING
                    }
                    ?.let { plane ->
                        placeAvatar(plane.createAnchor(plane.centerPose), "Avatar placed - move around to view")
                    }
            }

            if (!modelPlaced) {
                val reason = if (frame.camera.trackingState == TrackingState.TRACKING) {
                    TrackingFailureReason.NONE
                } else {
                    frame.camera.trackingFailureReason
                }
                updateHud(
                    when (reason) {
                        TrackingFailureReason.NONE -> "Move camera slowly to detect surfaces"
                        TrackingFailureReason.INSUFFICIENT_LIGHT -> "Too dark - find better lighting"
                        TrackingFailureReason.EXCESSIVE_MOTION -> "Moving too fast - slow down"
                        TrackingFailureReason.INSUFFICIENT_FEATURES -> "Point at a textured surface"
                        else -> "Move camera slowly to detect surfaces"
                    }
                )
            }
        }
    }

    private fun bindSessionCameraTexture(sceneView: ArSceneView) {
        val session = sceneView.session ?: return
        val textureId = sceneView.cameraTextureId
        if (textureId == 0) return

        val bound = runCatching {
            val setTextureNames = Session::class.java.getMethod("setCameraTextureNames", IntArray::class.java)
            setTextureNames.invoke(session, intArrayOf(textureId))
            true
        }.getOrElse {
            runCatching {
                session.setCameraTextureName(textureId)
                true
            }.getOrDefault(false)
        }

        if (bound) {
            cameraTextureBound = true
            Log.d(TAG, "Camera texture bound to session: id=$textureId")
        }
    }

    private fun loadModel() {
        if (modelLoading || modelRenderable != null) return

        modelLoading = true
        updateHud("Loading avatar model...")

        ModelRenderable.builder()
            .setSource(this, Uri.parse(MODEL_PATH))
            .setIsFilamentGltf(true)
            .setRegistryId(MODEL_PATH)
            .build()
            .thenAccept { renderable ->
                modelRenderable = renderable
                modelLoading = false
                updateHud("Move camera slowly to detect surfaces")
                Log.d(TAG, "Model loaded: $MODEL_PATH")
            }
            .exceptionally { throwable ->
                modelLoading = false
                updateHud("Failed to load avatar model")
                Log.e(TAG, "Model load failed: ${throwable.message}", throwable)
                null
            }
    }

    private fun placeAvatar(anchor: Anchor, successHud: String) {
        val renderable = modelRenderable ?: return
        val sceneView = arSceneView ?: run {
            Log.w(TAG, "AR scene view is not ready yet.")
            return
        }

        idleAnimator = null
        anchorNode?.anchor?.detach()
        anchorNode?.setParent(null)

        val newAnchorNode = AnchorNode(anchor).apply {
            setParent(sceneView.scene)
        }

        TransformableNode(arFragment.transformationSystem).apply {
            setParent(newAnchorNode)
            this.renderable = renderable
            select()

            val instance: RenderableInstance? = renderableInstance
            if (instance != null) {
                val animator = VrmIdleAnimator(instance, vrmFactor)
                idleAnimator = if (animator.hasAnyBoundBone()) {
                    Log.d(TAG, "Started procedural idle animation in AR mode.")
                    animator
                } else {
                    if (instance.hasAnimations()) {
                        instance.animate(true).start()
                        Log.d(TAG, "Falling back to embedded GLB animation in AR mode.")
                    }
                    null
                }
            }
        }

        anchorNode = newAnchorNode
        modelPlaced = true
        updateHud(successHud)
    }

    private fun detectVrmFactor(assetPath: String): Float {
        return runCatching {
            assets.open(assetPath).use { input ->
                val header = ByteArray(12)
                if (input.read(header) != 12) return@runCatching 1f

                val chunkLenBytes = ByteArray(4)
                if (input.read(chunkLenBytes) != 4) return@runCatching 1f
                val chunkLen =
                    (chunkLenBytes[0].toInt() and 0xFF) or
                        ((chunkLenBytes[1].toInt() and 0xFF) shl 8) or
                        ((chunkLenBytes[2].toInt() and 0xFF) shl 16) or
                        ((chunkLenBytes[3].toInt() and 0xFF) shl 24)

                if (input.skip(4) != 4L) return@runCatching 1f // chunk type

                val jsonBytes = ByteArray(chunkLen)
                val read = input.read(jsonBytes)
                if (read <= 0) return@runCatching 1f

                val json = String(jsonBytes, Charsets.UTF_8)
                when {
                    json.contains("VRMC_vrm") -> 1f
                    json.contains("\"VRM\"") -> -1f
                    else -> 1f
                }
            }
        }.getOrElse {
            Log.w(TAG, "Could not detect VRM version, defaulting factor=1: ${it.message}")
            1f
        }
    }

    private fun updateHud(text: String) {
        runOnUiThread { hudTextView.text = text }
    }

    override fun onDestroy() {
        idleAnimator = null
        runCatching { anchorNode?.anchor?.detach() }
        runCatching { anchorNode?.setParent(null) }
        anchorNode = null
        super.onDestroy()
    }
}
