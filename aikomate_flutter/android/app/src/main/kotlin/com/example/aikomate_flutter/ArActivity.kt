package com.example.aikomate_flutter

import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.ar.core.Config
import com.google.ar.core.Frame
import com.google.ar.core.Plane
import com.google.ar.core.Session
import com.google.ar.core.TrackingFailureReason
import io.github.sceneview.ar.ARScene
import io.github.sceneview.ar.arcore.createAnchorOrNull
import io.github.sceneview.ar.arcore.getUpdatedPlanes
import io.github.sceneview.ar.arcore.isValid
import io.github.sceneview.ar.camera.ARCameraStream
import io.github.sceneview.ar.node.AnchorNode
import io.github.sceneview.ar.rememberARCameraNode
import io.github.sceneview.ar.rememberARCameraStream
import io.github.sceneview.math.Position
import io.github.sceneview.node.ModelNode
import io.github.sceneview.rememberEngine
import io.github.sceneview.rememberMaterialLoader
import io.github.sceneview.rememberModelLoader
import io.github.sceneview.rememberNodes
import io.github.sceneview.rememberOnGestureListener
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.launch

class ArActivity : ComponentActivity() {

    companion object {
        private const val TAG = "ArActivity"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        setContent {
            var hudText by remember { mutableStateOf("Move camera slowly to detect surfaces") }
            var modelPlaced by remember { mutableStateOf(false) }
            var cameraTexturesBound by remember { mutableStateOf(false) }
            val latestFrame = remember { AtomicReference<Frame?>(null) }
            val scope = rememberCoroutineScope()

            val engine = rememberEngine()
            val modelLoader = rememberModelLoader(engine)
            val materialLoader = rememberMaterialLoader(engine)
            val cameraNode = rememberARCameraNode(engine)
            val cameraStream = rememberARCameraStream(materialLoader)
            val childNodes = rememberNodes()

            Box(modifier = Modifier.fillMaxSize()) {
                ARScene(
                    modifier = Modifier.fillMaxSize(),
                    engine = engine,
                    modelLoader = modelLoader,
                    materialLoader = materialLoader,
                    childNodes = childNodes,
                    cameraNode = cameraNode,
                    cameraStream = cameraStream,
                    planeRenderer = true,
                    isOpaque = true,
                    activity = this@ArActivity,
                    lifecycle = lifecycle,
                    sessionConfiguration = { session: Session, config: Config ->
                        config.depthMode = if (
                            session.isDepthModeSupported(Config.DepthMode.AUTOMATIC)
                        ) {
                            Config.DepthMode.AUTOMATIC
                        } else {
                            Config.DepthMode.DISABLED
                        }
                        config.instantPlacementMode = Config.InstantPlacementMode.LOCAL_Y_UP
                        config.lightEstimationMode = Config.LightEstimationMode.ENVIRONMENTAL_HDR
                        config.focusMode = Config.FocusMode.AUTO
                    },
                    onSessionCreated = { session ->
                        bindCameraTextures(session, cameraStream)
                    },
                    onSessionResumed = { session ->
                        bindCameraTextures(session, cameraStream)
                    },
                    onSessionUpdated = { session: Session, updatedFrame: Frame ->
                        val textureNameMatched = cameraStream.cameraTextureIds
                            .contains(updatedFrame.cameraTextureName)

                        if (!cameraTexturesBound || !textureNameMatched) {
                            cameraTexturesBound = bindCameraTextures(
                                session = session,
                                cameraStream = cameraStream
                            )
                            if (!textureNameMatched) {
                                Log.w(
                                    TAG,
                                    "Frame texture ${updatedFrame.cameraTextureName} not in " +
                                        "bound IDs ${cameraStream.cameraTextureIds.joinToString()}"
                                )
                            }
                        }
                        latestFrame.set(updatedFrame)
                        if (modelPlaced) return@ARScene

                        updatedFrame.getUpdatedPlanes()
                            .firstOrNull { it.type == Plane.Type.HORIZONTAL_UPWARD_FACING }
                            ?.let { plane ->
                                modelPlaced = true
                                val anchor = plane.createAnchor(plane.centerPose)
                                val anchorNode = AnchorNode(engine, anchor)
                                childNodes.add(anchorNode)

                                scope.launch {
                                    try {
                                        val instance = modelLoader.createModelInstance(
                                            assetFileLocation = "models/UltimateLoverH1.glb"
                                        )
                                        val modelNode = ModelNode(
                                            modelInstance = instance,
                                            scaleToUnits = 1.0f,
                                            centerOrigin = Position(y = -1.0f)
                                        )
                                        anchorNode.addChildNode(modelNode)
                                        modelNode.playAnimation(0)
                                        hudText = "Avatar placed - move around to view"
                                        Log.d(TAG, "Model placed")
                                    } catch (e: Exception) {
                                        modelPlaced = false
                                        Log.e(TAG, "Model load failed: ${e.message}", e)
                                    }
                                }
                            }
                    },
                    onTrackingFailureChanged = { reason: TrackingFailureReason? ->
                        if (modelPlaced) return@ARScene
                        hudText = when (reason) {
                            null, TrackingFailureReason.NONE ->
                                "Move camera slowly to detect surfaces"
                            TrackingFailureReason.INSUFFICIENT_LIGHT ->
                                "Too dark - find better lighting"
                            TrackingFailureReason.EXCESSIVE_MOTION ->
                                "Moving too fast - slow down"
                            TrackingFailureReason.INSUFFICIENT_FEATURES ->
                                "Point at a textured surface"
                            else -> "Move camera slowly to detect surfaces"
                        }
                    },
                    onGestureListener = rememberOnGestureListener(
                        onSingleTapConfirmed = { motionEvent, _ ->
                            if (!modelPlaced) return@rememberOnGestureListener

                            val hitResult = latestFrame.get()
                                ?.hitTest(motionEvent)
                                ?.firstOrNull { hit ->
                                    hit.isValid(depthPoint = false, point = false)
                                }
                                ?: return@rememberOnGestureListener

                            val newAnchor = hitResult.createAnchorOrNull()
                                ?: return@rememberOnGestureListener

                            childNodes.filterIsInstance<AnchorNode>()
                                .firstOrNull()
                                ?.let { it.anchor = newAnchor }

                            hudText = "Avatar repositioned"
                            Log.d(TAG, "Avatar repositioned")
                        }
                    )
                )

                Surface(
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .padding(bottom = 100.dp)
                        .wrapContentSize(),
                    color = Color(0x88000000),
                    shape = RoundedCornerShape(20.dp)
                ) {
                    Text(
                        text = hudText,
                        color = Color.White,
                        fontSize = 15.sp,
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 10.dp)
                    )
                }

                Surface(
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(top = 60.dp, end = 16.dp)
                        .wrapContentSize(),
                    color = Color.White,
                    shape = RoundedCornerShape(8.dp),
                    onClick = { finish() }
                ) {
                    Text(
                        text = "X",
                        color = Color.Black,
                        fontSize = 18.sp,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                    )
                }
            }
        }
    }

    private fun bindCameraTextures(session: Session, cameraStream: ARCameraStream): Boolean {
        val textureIds = cameraStream.cameraTextureIds
        if (textureIds.any { it == 0 }) {
            Log.w(TAG, "Camera texture IDs not ready yet: ${textureIds.joinToString()}")
            return false
        }
        return try {
            session.setCameraTextureNames(textureIds)
            Log.d(TAG, "Bound camera textures: ${textureIds.joinToString()}")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to bind camera textures: ${e.message}", e)
            false
        }
    }
}
