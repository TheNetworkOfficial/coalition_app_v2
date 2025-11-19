package com.example.coalition_app_v2.editor

import android.content.Context
import android.view.View
import androidx.media3.common.Player
import androidx.media3.ui.PlayerView
import io.flutter.plugin.platform.PlatformView

class PreviewView(
    context: Context,
    private val viewId: Int,
    private val onDispose: (() -> Unit)? = null,
) : PlatformView {

    private val playerView: PlayerView = PlayerView(context).apply {
        useController = false
    }
    private var boundPlayer: Player? = null

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

    override fun getView(): View = playerView

    override fun dispose() {
        playerView.player = null
        boundPlayer = null
        onDispose?.invoke()
    }
}
