package com.example.coalition_app_v2.editor

import android.content.Context
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.ViewTreeObserver
import android.widget.FrameLayout
import android.widget.TextView
import androidx.media3.common.Player
import androidx.media3.ui.PlayerView
import io.flutter.plugin.platform.PlatformView

class PreviewView(
    context: Context,
    private val viewId: Int,
    private val onDispose: (() -> Unit)? = null,
) : PlatformView {

    data class TextOverlay(
        val text: String,
        val x: Float,
        val y: Float,
        val scale: Float,
        val rotationDeg: Float,
        val color: Int,
        val startMs: Long,
        val endMs: Long,
    )

    private val container: FrameLayout = FrameLayout(context)
    private val playerView: PlayerView = PlayerView(context).apply {
        useController = false
    }
    private val overlayLayer: FrameLayout = FrameLayout(context).apply {
        isClickable = false
        isFocusable = false
    }
    private var boundPlayer: Player? = null
    private var overlays: List<TextOverlay> = emptyList()
    private var visibilityUpdater: Runnable? = null
    private val handler = Handler(Looper.getMainLooper())

    init {
        val matchParent = FrameLayout.LayoutParams.MATCH_PARENT
        container.addView(
            playerView,
            FrameLayout.LayoutParams(matchParent, matchParent),
        )
        container.addView(
            overlayLayer,
            FrameLayout.LayoutParams(matchParent, matchParent),
        )
    }

    val id: Int
        get() = viewId

    fun bindPlayer(player: Player?) {
        if (boundPlayer === player) {
            return
        }
        boundPlayer?.clearVideoSurface()
        playerView.player = player
        boundPlayer = player
    }

    fun setTextOverlays(newOverlays: List<TextOverlay>) {
        overlays = newOverlays
        rebuildOverlayViews()
    }

    private fun rebuildOverlayViews() {
        overlayLayer.removeAllViews()
        if (overlays.isEmpty()) {
            stopVisibilityLoop()
            return
        }
        postLayout {
            val width = overlayLayer.width.coerceAtLeast(1).toFloat()
            val height = overlayLayer.height.coerceAtLeast(1).toFloat()
            for (overlay in overlays) {
                val textView = TextView(container.context).apply {
                    text = overlay.text
                    setTextColor(overlay.color)
                    setShadowLayer(4f, 0f, 0f, Color.BLACK)
                    textSize = 18f
                    gravity = Gravity.CENTER
                    scaleX = overlay.scale
                    scaleY = overlay.scale
                    rotation = overlay.rotationDeg
                    isClickable = false
                }
                val params = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                )
                overlayLayer.addView(textView, params)
                textView.tag = overlay
                textView.viewTreeObserver.addOnGlobalLayoutListener(
                    object : ViewTreeObserver.OnGlobalLayoutListener {
                        override fun onGlobalLayout() {
                            textView.viewTreeObserver.removeOnGlobalLayoutListener(this)
                            val tx = overlay.x * width - textView.width / 2f
                            val ty = overlay.y * height - textView.height / 2f
                            textView.translationX = tx
                            textView.translationY = ty
                        }
                    },
                )
            }
        }
        startVisibilityLoop()
    }

    private fun startVisibilityLoop() {
        if (overlays.isEmpty()) {
            stopVisibilityLoop()
            return
        }
        stopVisibilityLoop()
        val updater = object : Runnable {
            override fun run() {
                val position = boundPlayer?.currentPosition ?: 0L
                for (index in 0 until overlayLayer.childCount) {
                    val view = overlayLayer.getChildAt(index)
                    val overlay = view.tag as? TextOverlay
                    val visible = overlay?.let { position >= it.startMs && position <= it.endMs } ?: true
                    view.visibility = if (visible) View.VISIBLE else View.GONE
                }
                handler.postDelayed(this, 200L)
            }
        }
        visibilityUpdater = updater
        handler.post(updater)
    }

    private fun stopVisibilityLoop() {
        visibilityUpdater?.let { handler.removeCallbacks(it) }
        visibilityUpdater = null
    }

    private inline fun postLayout(crossinline block: () -> Unit) {
        if (overlayLayer.width > 0 && overlayLayer.height > 0) {
            block()
            return
        }
        overlayLayer.viewTreeObserver.addOnGlobalLayoutListener(
            object : ViewTreeObserver.OnGlobalLayoutListener {
                override fun onGlobalLayout() {
                    overlayLayer.viewTreeObserver.removeOnGlobalLayoutListener(this)
                    block()
                }
            },
        )
    }

    override fun getView(): View = container

    override fun dispose() {
        stopVisibilityLoop()
        handler.removeCallbacksAndMessages(null)
        overlayLayer.removeAllViews()
        playerView.player = null
        boundPlayer = null
        onDispose?.invoke()
    }
}
