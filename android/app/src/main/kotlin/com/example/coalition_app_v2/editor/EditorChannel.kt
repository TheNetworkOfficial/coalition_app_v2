package com.example.coalition_app_v2.editor

import android.content.Context
import android.graphics.Color
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.media3.common.AudioAttributes
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.json.JSONObject

@UnstableApi
class EditorChannel(
    private val context: Context,
    messenger: BinaryMessenger,
    private val previewFactory: PreviewViewFactory,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler, Player.Listener {

    companion object {
        private const val TAG = "EditorChannel"
        private const val METHOD_CHANNEL = "EditorChannel"
        private const val EVENT_CHANNEL = "EditorChannelEvents"
    }

    private val appContext = context.applicationContext
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val effectBuilder = EffectBuilder()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var eventSink: EventChannel.EventSink? = null
    private var player: ExoPlayer? = null
    private var currentViewId: Int? = null
    private var currentMediaPath: String? = null
    private var currentTimelineJson: String? = null

    private fun releasePlayer() {
        player?.removeListener(this)
        player?.release()
        player = null
    }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepareTimeline" -> handlePrepare(call, result)
            "updateTimeline" -> handleUpdate(call, result)
            "seekPreview" -> handleSeek(call, result)
            "setPlaybackState" -> handleSetPlayback(call, result)
            "generatePosterFrame" -> handlePosterFrame(call, result)
            "release" -> {
                release()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun handlePrepare(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: run {
            result.error("invalid_args", "Arguments missing", null)
            return
        }
        val sourcePath = args["sourcePath"]?.toString()
        val proxyPath = args["proxyPath"]?.toString()
        val timelineJson = args["timelineJson"]?.toString()
        val surfaceId = (args["surfaceId"] as? Number)?.toInt()
        if (sourcePath.isNullOrEmpty() || surfaceId == null) {
            result.error("invalid_args", "sourcePath/surfaceId required", null)
            return
        }
        val mediaPath = if (!proxyPath.isNullOrEmpty()) proxyPath else sourcePath
        currentMediaPath = mediaPath
        currentTimelineJson = timelineJson
        currentViewId = surfaceId
        scope.launch {
            prepareTimeline(mediaPath, surfaceId, timelineJson)
            result.success(null)
        }
    }

    private fun handleUpdate(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: run {
            result.error("invalid_args", "Arguments missing", null)
            return
        }
        currentTimelineJson = args["timelineJson"]?.toString()
        scope.launch {
            val mediaPath = currentMediaPath
            val viewId = currentViewId
            if (mediaPath != null && viewId != null) {
                updateTimeline(mediaPath, viewId, currentTimelineJson)
            }
            result.success(null)
        }
    }

    private fun handleSeek(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        val positionMs = (args?.get("positionMs") as? Number)?.toLong()
        if (positionMs == null) {
            result.error("invalid_args", "positionMs missing", null)
            return
        }
        player?.seekTo(positionMs)
        result.success(null)
    }

    private fun handleSetPlayback(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        val playing = args?.get("playing") as? Boolean ?: true
        val speed = (args?.get("speed") as? Number)?.toFloat()
        player?.playWhenReady = playing
        if (speed != null && speed > 0) {
            player?.playbackParameters = PlaybackParameters(speed)
        }
        result.success(null)
    }

    private fun handlePosterFrame(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        val positionMs = (args?.get("positionMs") as? Number)?.toLong()
        val mediaPath = currentMediaPath
        if (positionMs == null || mediaPath.isNullOrEmpty()) {
            result.error("invalid_args", "positionMs/media missing", null)
            return
        }
        scope.launch(Dispatchers.IO) {
            try {
                val retriever = MediaMetadataRetriever()
                retriever.setDataSource(context, Uri.fromFile(File(mediaPath)))
                val bitmap = retriever.getFrameAtTime(positionMs * 1000)
                retriever.release()
                if (bitmap == null) {
                    result.error("unavailable", "Frame unavailable", null)
                    return@launch
                }
                val output = File(context.cacheDir, "poster_${System.currentTimeMillis()}.png")
                output.outputStream().use { stream ->
                    bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, stream)
                }
                mainHandler.post { result.success(output.absolutePath) }
            } catch (error: Throwable) {
                Log.e(TAG, "generatePosterFrame failed", error)
                mainHandler.post {
                    result.error("error", error.message, null)
                }
            }
        }
    }

    private suspend fun prepareTimeline(path: String, surfaceId: Int, timelineJson: String?) {
        releasePlayer()
        val preview = previewFactory.findView(surfaceId)
        if (preview == null) {
            Log.w(TAG, "Preview view not found for $surfaceId")
            return
        }
        val timeline = effectBuilder.parseTimeline(timelineJson)
        val overlays = parseTextOverlaysFromManifest(timelineJson)
        val mediaItem = buildMediaItem(path, timeline)
        val p = ExoPlayer.Builder(appContext).build().also {
            it.setAudioAttributes(AudioAttributes.DEFAULT, true)
            it.repeatMode = ExoPlayer.REPEAT_MODE_ALL
            it.addListener(this)
        }
        player = p
        p.setPlaybackParameters(PlaybackParameters(timeline.speed))
        p.setMediaItem(mediaItem)
        p.prepare()
        p.playWhenReady = true
        preview.bindPlayer(p)
        preview.setTextOverlays(overlays)
        preview.getView().rotation = timeline.rotationDegrees
        emitEvent(mapOf("type" to "prepared"))
    }

    private suspend fun updateTimeline(path: String, surfaceId: Int, timelineJson: String?) {
        val preview = previewFactory.findView(surfaceId)
        if (preview == null) {
            Log.w(TAG, "Preview view not found for $surfaceId")
            return
        }
        val timeline = effectBuilder.parseTimeline(timelineJson)
        val overlays = parseTextOverlaysFromManifest(timelineJson)
        val existingPlayer = player
        if (existingPlayer == null) {
            prepareTimeline(path, surfaceId, timelineJson)
            return
        }
        val mediaItem = buildMediaItem(path, timeline)
        existingPlayer.setPlaybackParameters(PlaybackParameters(timeline.speed))
        existingPlayer.setMediaItem(mediaItem)
        existingPlayer.prepare()
        existingPlayer.playWhenReady = true
        preview.bindPlayer(existingPlayer)
        preview.setTextOverlays(overlays)
        preview.getView().rotation = timeline.rotationDegrees
        emitEvent(mapOf("type" to "prepared"))
    }

    private fun buildMediaItem(path: String, timeline: TimelineConfig): MediaItem {
        val uri = Uri.fromFile(File(path))
        val itemBuilder = MediaItem.Builder().setUri(uri)
        val clippingBuilder = MediaItem.ClippingConfiguration.Builder()
        timeline.trimStartMs?.let { clippingBuilder.setStartPositionMs(it) }
        timeline.trimEndMs?.let { clippingBuilder.setEndPositionMs(it) }
        itemBuilder.setClippingConfiguration(clippingBuilder.build())
        return itemBuilder.build()
    }

    private fun parseTextOverlaysFromManifest(json: String?): List<PreviewView.TextOverlay> {
        if (json.isNullOrEmpty()) {
            return emptyList()
        }
        return try {
            val root = JSONObject(json)
            val ops = root.optJSONArray("ops") ?: return emptyList()
            val overlays = mutableListOf<PreviewView.TextOverlay>()
            for (i in 0 until ops.length()) {
                val entry = ops.optJSONObject(i) ?: continue
                if (entry.optString("type") != "overlay_text") {
                    continue
                }
                val text = entry.optString("text")
                if (text.isEmpty()) {
                    continue
                }
                val x = entry.optDouble("x", 0.5).toFloat().coerceIn(0f, 1f)
                val y = entry.optDouble("y", 0.5).toFloat().coerceIn(0f, 1f)
                val scale = entry.optDouble("scale", 1.0).toFloat().coerceAtLeast(0.1f)
                val rotation = entry.optDouble("rotationDeg", 0.0).toFloat()
                val start = entry.optLong("startMs", 0L)
                val endValue = if (entry.has("endMs")) entry.optLong("endMs", Long.MAX_VALUE) else Long.MAX_VALUE
                val end = if (endValue >= start) endValue else start
                val color = parseOverlayColor(entry.optString("color"))
                overlays.add(
                    PreviewView.TextOverlay(
                        text = text,
                        x = x,
                        y = y,
                        scale = scale,
                        rotationDeg = rotation,
                        color = color,
                        startMs = start,
                        endMs = end,
                    ),
                )
            }
            overlays
        } catch (error: Exception) {
            Log.w(TAG, "Failed to parse overlay ops", error)
            emptyList()
        }
    }

    private fun parseOverlayColor(raw: String?): Int {
        if (raw.isNullOrBlank()) {
            return Color.WHITE
        }
        return try {
            Color.parseColor(raw)
        } catch (_: IllegalArgumentException) {
            Color.WHITE
        }
    }

    fun release() {
        releasePlayer()
        currentViewId = null
        currentMediaPath = null
        currentTimelineJson = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun emitEvent(payload: Map<String, Any?>) {
        mainHandler.post { eventSink?.success(payload) }
    }

    override fun onPlaybackStateChanged(playbackState: Int) {
        val player = this.player ?: return
        val stateString = when (playbackState) {
            Player.STATE_READY -> "ready"
            Player.STATE_ENDED -> "ended"
            Player.STATE_BUFFERING -> "buffering"
            Player.STATE_IDLE -> "idle"
            else -> playbackState.toString()
        }
        emitEvent(
            mapOf(
                "type" to "state",
                "state" to stateString,
                "positionMs" to player.currentPosition,
            ),
        )
    }
}
