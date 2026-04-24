package com.aikomate

import android.content.Intent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    companion object {
        const val CHANNEL = "com.aikomate/ar"
        var flutterEngineRef: FlutterEngine? = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngineRef = flutterEngine

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openAR" -> {
                        val args = call.arguments as? Map<*, *>
                        val intent = Intent(this, ArActivity::class.java)
                        if (args != null) {
                            (args["token"] as? String)?.let { intent.putExtra("token", it) }
                            (args["wsUrl"] as? String)?.let { intent.putExtra("wsUrl", it) }
                            (args["avatarName"] as? String)?.let { intent.putExtra("avatarName", it) }
                            (args["userName"] as? String)?.let { intent.putExtra("userName", it) }
                        }
                        startActivity(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
