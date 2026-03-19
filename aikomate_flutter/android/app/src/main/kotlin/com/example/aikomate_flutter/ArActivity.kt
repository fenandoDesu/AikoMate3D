package com.example.aikomate_flutter

import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.google.ar.core.Anchor
import com.google.ar.core.Config
import com.google.ar.core.Plane
import com.google.ar.core.TrackingFailureReason
import com.google.ar.core.TrackingState
import com.google.ar.sceneform.ArSceneView
import com.google.ar.sceneform.AnchorNode
import com.google.ar.sceneform.rendering.ModelRenderable
import com.google.ar.sceneform.rendering.RenderableInstance
import com.google.ar.sceneform.ux.ArFragment
import com.google.ar.sceneform.ux.TransformableNode

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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_ar)

        hudTextView = findViewById(R.id.hudText)
        findViewById<TextView>(R.id.backBtn).setOnClickListener { finish() }

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
            attachSceneUpdateListener(sceneView)
        }

        // If fragment view is already created (e.g. after commitNow), hook immediately.
        runCatching { arFragment.arSceneView }.getOrNull()?.let { sceneView ->
            arSceneView = sceneView
            attachSceneUpdateListener(sceneView)
        }
    }

    private fun attachSceneUpdateListener(sceneView: ArSceneView) {
        if (sceneUpdateListenerAttached) return
        sceneUpdateListenerAttached = true

        sceneView.scene.addOnUpdateListener {
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

        anchorNode?.anchor?.detach()
        anchorNode?.setParent(null)

        val newAnchorNode = AnchorNode(anchor).apply {
            setParent(sceneView.scene)
        }

        TransformableNode(arFragment.transformationSystem).apply {
            setParent(newAnchorNode)
            this.renderable = renderable
            select()

            val renderableInstance: RenderableInstance? = renderableInstance
            if (renderableInstance != null && renderableInstance.hasAnimations()) {
                renderableInstance.animate(true).start()
            }
        }

        anchorNode = newAnchorNode
        modelPlaced = true
        updateHud(successHud)
    }

    private fun updateHud(text: String) {
        runOnUiThread { hudTextView.text = text }
    }

    override fun onDestroy() {
        runCatching { anchorNode?.anchor?.detach() }
        runCatching { anchorNode?.setParent(null) }
        anchorNode = null
        super.onDestroy()
    }
}
