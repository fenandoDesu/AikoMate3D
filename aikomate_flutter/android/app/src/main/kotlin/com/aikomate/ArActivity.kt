package com.aikomate

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.net.Uri
import android.os.Bundle
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import android.widget.ImageButton
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
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
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import org.json.JSONObject
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

class ArActivity : AppCompatActivity() {

    companion object {
        private const val TAG = "ArActivity"
        private const val FRAGMENT_TAG = "AikoArFragment"
        private const val MODEL_PATH = "models/UltimateLoverH1.glb"
    }

    data class Phoneme(val phoneme: String, val start: Double, val duration: Double)

    private lateinit var arFragment: ArFragment
    private lateinit var hudTextView: TextView

    private var arSceneView: ArSceneView? = null
    private var sceneUpdateListenerAttached = false
    private var modelRenderable: ModelRenderable? = null
    private var modelLoading = false
    private var modelPlaced = false
    private var anchorNode: AnchorNode? = null
    private var cameraTextureBound = false
    private var speechRecognizer: SpeechRecognizer? = null
    private var ws: WebSocket? = null
    private var wsUrl: String? = null
    private var authToken: String? = null
    private var avatarName: String = "Haruna"
    private var userName: String = "Fernando"
    private val fishAudioId = "a2fcdd688eed4521baf39ffc05ca7d3f"
    private val intimacyLevel = 4

    private val wsClient = OkHttpClient.Builder()
        .pingInterval(20, TimeUnit.SECONDS)
        .build()
    private var audioTrack: AudioTrack? = null
    private var audioThread: Thread? = null
    private val audioQueue = LinkedBlockingQueue<ByteArray>()
    private val phonemeTimeline = mutableListOf<Phoneme>()
    private var phonemeAudioDurationSec = 0.0

    private var idleAnimator: VrmIdleAnimator? = null
    private var elapsedTimeSec = 0f
    private var lastFrameNanos = 0L
    private var vrmFactor = 1f

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_ar)

        authToken = intent.getStringExtra("token")
        wsUrl = intent.getStringExtra("wsUrl") ?: "wss://api.japaneseblossom.com/ws/chat"
        avatarName = intent.getStringExtra("avatarName") ?: avatarName
        userName = intent.getStringExtra("userName") ?: userName

        hudTextView = findViewById(R.id.hudText)
        findViewById<TextView>(R.id.backBtn).setOnClickListener { finish() }
        findViewById<ImageButton>(R.id.micBtn).setOnClickListener {
            startSpeechRecognition()
        }

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

    private fun ensureSpeechRecognizer(): SpeechRecognizer {
        return speechRecognizer ?: SpeechRecognizer.createSpeechRecognizer(this).also {
            speechRecognizer = it
        }
    }

    private fun startSpeechRecognition() {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            updateHud("Speech recognition unavailable")
            return
        }

        val permission = ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
        if (permission != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.RECORD_AUDIO), 42)
            return
        }

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
        }

        val recognizer = ensureSpeechRecognizer()
        recognizer.setRecognitionListener(object : SimpleRecognitionListener() {
            override fun onReadyForSpeech(params: Bundle?) {
                updateHud("Listening...")
                Log.d(TAG, "Speech ready")
            }

            override fun onResults(results: Bundle) {
                val text = results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
                if (!text.isNullOrBlank()) {
                    updateHud("Heard: $text")
                    Log.d(TAG, "Speech result: $text")
                    sendTranscriptToApi(text, "en-US")
                } else {
                    updateHud("Did not catch that")
                }
            }

            override fun onPartialResults(partialResults: Bundle) {
                val text = partialResults.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
                if (!text.isNullOrBlank()) {
                    updateHud("Heard: $text")
                    Log.d(TAG, "Speech partial: $text")
                }
            }

            override fun onError(error: Int) {
                updateHud("Speech error ($error)")
                Log.e(TAG, "Speech error: $error")
            }
        })

        recognizer.startListening(intent)
    }

    private fun sendTranscriptToApi(text: String, language: String) {
        val token = authToken
        val url = wsUrl
        if (token.isNullOrBlank() || url.isNullOrBlank()) {
            updateHud("Missing auth or server URL")
            Log.e(TAG, "Missing auth token or wsUrl")
            return
        }

        val socket = ensureWebSocket(url, token) ?: run {
            updateHud("Companion unavailable")
            return
        }

        val payload = JSONObject().apply {
            put("text", text)
            put("language", language)
            put("avatar_name", avatarName)
            put("user_name", userName)
            put("fish_audio_id", fishAudioId)
            put("intimacy", intimacyLevel)
        }.toString()

        Log.d(TAG, "Sending text to companion: $text")
        val sent = socket.send(payload)
        if (!sent) {
            updateHud("Companion send failed")
            Log.e(TAG, "Companion WS send failed")
        }
    }

    private fun ensureWebSocket(url: String, token: String): WebSocket? {
        if (ws != null) return ws
        val request = Request.Builder()
            .url(url)
            .addHeader("Authorization", "Bearer $token")
            .build()
        ws = wsClient.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                Log.d(TAG, "Companion WS connected")
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                handleJsonMessage(text)
            }

            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                handleAudio(bytes.toByteArray())
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.e(TAG, "Companion WS error: ${t.message}", t)
                ws = null
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                Log.d(TAG, "Companion WS closed: $code $reason")
                ws = null
            }
        })
        return ws
    }

    private fun handleJsonMessage(text: String) {
        runCatching {
            val json = JSONObject(text)
            val type = json.optString("type")
            when (type) {
                "stream_start" -> {
                    audioQueue.clear()
                    audioTrack?.pause()
                    audioTrack?.flush()
                    phonemeTimeline.clear()
                    phonemeAudioDurationSec = 0.0
                    Log.d(TAG, "Companion stream_start")
                }
                "sentence_chunk" -> {
                    handleSentenceChunk(json)
                }
                "sentence_audio_end" -> {
                    Log.d(TAG, "Companion sentence_audio_end")
                }
                "turn_end" -> {
                    Log.d(TAG, "Companion turn_end")
                }
                "error" -> {
                    Log.e(TAG, "Companion error: ${json.optString("message")}")
                }
            }
        }.onFailure {
            Log.e(TAG, "Failed to parse companion JSON: ${it.message}", it)
        }
    }

    private fun handleSentenceChunk(json: JSONObject) {
        val phonemes = json.optJSONArray("phonemes") ?: return
        var offset = 0.0
        if (phonemeTimeline.isNotEmpty()) {
            val last = phonemeTimeline.last()
            offset = last.start + last.duration
        }
        for (i in 0 until phonemes.length()) {
            val p = phonemes.optJSONObject(i) ?: continue
            val phoneme = p.optString("phoneme", "")
            val start = p.optDouble("start", Double.NaN)
            val duration = p.optDouble("duration", Double.NaN)
            if (phoneme.isBlank() || start.isNaN() || duration.isNaN()) continue
            phonemeTimeline.add(
                Phoneme(
                    phoneme = phoneme,
                    start = start + offset,
                    duration = duration
                )
            )
        }

        onPhonemesUpdated()
    }

    private fun onPhonemesUpdated() {
        // Foundation hook for future lip-sync on the native VRM.
        Log.d(TAG, "Phonemes updated: ${phonemeTimeline.size} entries, audioDuration=$phonemeAudioDurationSec")
    }

    private fun handleAudio(bytes: ByteArray) {
        if (bytes.isEmpty()) return
        ensureAudioTrack()
        phonemeAudioDurationSec += bytes.size / 2.0 / 44100.0
        audioQueue.offer(bytes)
        if (audioTrack?.playState != AudioTrack.PLAYSTATE_PLAYING) {
            audioTrack?.play()
        }
    }

    private fun ensureAudioTrack() {
        if (audioTrack != null) return
        val sampleRate = 44100
        val minBuffer = AudioTrack.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        audioTrack = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(sampleRate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .build()
            )
            .setTransferMode(AudioTrack.MODE_STREAM)
            .setBufferSizeInBytes(minBuffer * 4)
            .build()

        if (audioThread == null) {
            audioThread = Thread {
                try {
                    while (!Thread.currentThread().isInterrupted) {
                        val data = audioQueue.take()
                        audioTrack?.write(data, 0, data.size)
                    }
                } catch (_: InterruptedException) {
                    // Thread interrupted on teardown.
                }
            }.apply { start() }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 42 && grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            startSpeechRecognition()
        } else if (requestCode == 42) {
            updateHud("Microphone permission needed")
        }
    }

    override fun onDestroy() {
        idleAnimator = null
        runCatching { anchorNode?.anchor?.detach() }
        runCatching { anchorNode?.setParent(null) }
        anchorNode = null
        runCatching { speechRecognizer?.destroy() }
        speechRecognizer = null
        runCatching { ws?.close(1000, "Activity destroyed") }
        ws = null
        runCatching { audioThread?.interrupt() }
        audioThread = null
        audioQueue.clear()
        runCatching { audioTrack?.stop() }
        runCatching { audioTrack?.release() }
        audioTrack = null
        super.onDestroy()
    }
}
