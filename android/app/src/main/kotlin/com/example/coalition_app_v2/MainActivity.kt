package com.example.coalition_app_v2

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var videoProxyChannel: VideoProxyChannel? = null
    private var tusUploadChannel: TusUploadChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        videoProxyChannel = VideoProxyChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        tusUploadChannel = TusUploadChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onDestroy() {
        super.onDestroy()
        videoProxyChannel = null
        tusUploadChannel?.dispose()
        tusUploadChannel = null
    }
}
