package com.example.coalition_app_v2

import com.example.coalition_app_v2.editor.EditorChannel
import com.example.coalition_app_v2.editor.PreviewViewFactory
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var videoProxyChannel: VideoProxyChannel? = null
    private var tusUploadChannel: TusUploadChannel? = null
    private var editorChannel: EditorChannel? = null
    private var previewFactory: PreviewViewFactory? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        videoProxyChannel = VideoProxyChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        tusUploadChannel = TusUploadChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        val factory = PreviewViewFactory(applicationContext)
        previewFactory = factory
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "EditorPreviewView",
            factory,
        )
        editorChannel = EditorChannel(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
            previewFactory!!,
        )
    }

    override fun onDestroy() {
        super.onDestroy()
        videoProxyChannel = null
        tusUploadChannel?.dispose()
        tusUploadChannel = null
        editorChannel?.release()
        editorChannel = null
    }
}
