package com.example.coalition_app_v2.editor

import android.content.Context
import android.util.SparseArray
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class PreviewViewFactory(
    private val appContext: Context,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    private val views = SparseArray<PreviewView>()

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val preview = PreviewView(
            appContext,
            viewId,
            onDispose = { views.remove(viewId) },
        )
        views.put(viewId, preview)
        return preview
    }

    fun findView(id: Int): PreviewView? = views.get(id)
}
