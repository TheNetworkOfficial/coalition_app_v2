package com.example.coalition_app_v2

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import com.otaliastudios.transcoder.Transcoder
import com.otaliastudios.transcoder.TranscoderListener
import com.otaliastudios.transcoder.sink.DefaultDataSink
import com.otaliastudios.transcoder.source.FilePathDataSource
import com.otaliastudios.transcoder.strategy.DefaultAudioStrategy
import com.otaliastudios.transcoder.strategy.DefaultVideoStrategy
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.max

private const val TAG = "VideoProxyChannel"

class VideoProxyChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private val methodChannel = MethodChannel(messenger, "coalition/video_proxy")
    private val progressChannel = EventChannel(messenger, "coalition/video_proxy/progress")
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val jobs = ConcurrentHashMap<String, ProxyJob>()
    private val jobMutex = Mutex()
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    init {
        methodChannel.setMethodCallHandler(this)
        progressChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "createProxy" -> handleCreateProxy(call, result, isFallback = false)
            "createProxyFallback720p" -> handleCreateProxy(call, result, isFallback = true)
            "cancelProxy" -> handleCancel(call, result)
            "probeSource" -> handleProbe(call, result)
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun handleCreateProxy(
        call: MethodCall,
        result: MethodChannel.Result,
        isFallback: Boolean,
    ) {
        val args = call.arguments as? Map<*, *>
        if (args == null) {
            respondError(result, "invalid_args", "Missing arguments", recoverable = true)
            return
        }

        val jobId = args["jobId"]?.toString().takeUnless { it.isNullOrBlank() }
        if (jobId == null) {
            respondError(result, "invalid_args", "Missing jobId", recoverable = true)
            return
        }

        val sourcePath = args["sourcePath"]?.toString().takeUnless { it.isNullOrBlank() }
        if (sourcePath == null) {
            respondError(result, "invalid_args", "Missing sourcePath", recoverable = true)
            return
        }

        val targetCanvas = args["targetCanvas"] as? Map<*, *>
        val targetWidth = (targetCanvas?.get("width") as? Number)?.toInt() ?: 1080
        val targetHeight = (targetCanvas?.get("height") as? Number)?.toInt() ?: 1920
        val frameRateHint = (args["frameRateHint"] as? Number)?.toInt() ?: 30
        val keyIntervalSeconds = (args["keyframeIntervalSeconds"] as? Number)?.toFloat() ?: 2f
        val audioBitrateKbps = (args["audioBitrateKbps"] as? Number)?.toInt() ?: 128
        val outputDirectoryPath = args["outputDirectory"]?.toString()
        val enableLogging = args["enableLogging"] as? Boolean ?: true

        if (outputDirectoryPath.isNullOrEmpty()) {
            respondError(result, "invalid_args", "Missing outputDirectory", recoverable = true)
            return
        }

        val outputDirectory = File(outputDirectoryPath)
        if (!outputDirectory.exists() && !outputDirectory.mkdirs()) {
            respondError(result, "io_error", "Unable to create proxy cache directory", recoverable = true)
            return
        }

        val maxEdge = max(targetWidth, targetHeight)
        val targetBitrate = if (maxEdge <= 1280) 3_000_000L else 5_000_000L

        val jobOutput = createOutputFile(outputDirectory)

        val videoStrategy = DefaultVideoStrategy.exact(targetWidth, targetHeight)
            .bitRate(targetBitrate)
            .frameRate(frameRateHint)
            .keyFrameInterval(keyIntervalSeconds)
            .build()

        val audioStrategy = DefaultAudioStrategy.builder()
            .channels(2)
            .sampleRate(48_000)
            .bitRate(audioBitrateKbps * 1000)
            .build()

        val rotationDegrees = readRotationDegrees(sourcePath)

        scope.launch {
            jobMutex.withLock {
                if (jobs.containsKey(jobId)) {
                    respondError(
                        result,
                        "job_exists",
                        "Proxy job already running",
                        recoverable = true,
                    )
                    return@withLock
                }

                try {
                    val listener = createListener(
                        jobId = jobId,
                        result = result,
                        outputFile = jobOutput,
                        frameRateHint = frameRateHint,
                        fallback = isFallback,
                        enableLogging = enableLogging,
                    )

                    val optionsBuilder = Transcoder.into(DefaultDataSink(jobOutput.absolutePath))
                        .addDataSource(FilePathDataSource(sourcePath))
                        .setVideoTrackStrategy(videoStrategy)
                        .setAudioTrackStrategy(audioStrategy)
                        .setListener(listener)
                        .setListenerHandler(mainHandler)
                        .setVideoRotation(rotationDegrees)

                    val future = Transcoder.getInstance().transcode(optionsBuilder.build())

                val proxyJob = ProxyJob(
                    jobId = jobId,
                    future = future,
                    outputFile = jobOutput,
                    startElapsedRealtimeMs = SystemClock.elapsedRealtime(),
                )

                    jobs[jobId] = proxyJob

                    if (enableLogging) {
                        Log.d(
                            TAG,
                            "Starting proxy job=$jobId source=$sourcePath target=${targetWidth}x$targetHeight fallback=$isFallback",
                        )
                    }
                } catch (error: Throwable) {
                    jobs.remove(jobId)
                    jobOutput.delete()
                    Log.e(TAG, "Failed to start proxy", error)
                    respondError(
                        result,
                        "start_failed",
                        error.message ?: "Failed to start proxy",
                        recoverable = true,
                    )
                }
            }
        }
    }

    private fun handleCancel(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        val jobId = args?.get("jobId")?.toString()
        if (jobId.isNullOrEmpty()) {
            respondError(result, "invalid_args", "Missing jobId", recoverable = true)
            return
        }

        val job = jobs[jobId]
        if (job == null) {
            result.success(mapOf("ok" to true))
            return
        }

        scope.launch {
            val removed = jobMutex.withLock {
                jobs.remove(jobId)
            }
            removed?.future?.cancel(true)
            removed?.outputFile?.delete()
            mainHandler.post { result.success(mapOf("ok" to true)) }
        }
    }

    private fun handleProbe(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        val sourcePath = args?.get("sourcePath")?.toString()
        if (sourcePath.isNullOrEmpty()) {
            respondError(result, "invalid_args", "Missing sourcePath", recoverable = true)
            return
        }

        scope.launch {
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(context, Uri.fromFile(File(sourcePath)))
                val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
                val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull()
                val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull()
                val rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull()
                val codec = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_MIMETYPE)
                val response = mapOf(
                    "ok" to true,
                    "durationMs" to durationMs,
                    "width" to width,
                    "height" to height,
                    "rotation" to rotation,
                    "codec" to codec,
                )
                mainHandler.post { result.success(response) }
            } catch (error: Throwable) {
                Log.w(TAG, "probeSource failed", error)
                mainHandler.post {
                    respondError(result, "probe_failed", error.message ?: "Probe failed", recoverable = true)
                }
            } finally {
                retriever.release()
            }
        }
    }

    private fun createListener(
        jobId: String,
        result: MethodChannel.Result,
        outputFile: File,
        frameRateHint: Int,
        fallback: Boolean,
        enableLogging: Boolean,
    ): TranscoderListener {
        return object : TranscoderListener {
            override fun onTranscodeProgress(progress: Double) {
                emitProgress(jobId, progress)
            }

            override fun onTranscodeCompleted(successCode: Int) {
                scope.launch {
                    val proxyJob = jobMutex.withLock { jobs.remove(jobId) }
                    val elapsedMs = SystemClock.elapsedRealtime() - proxyJob?.startElapsedRealtimeMs.orDefault()
                    try {
                        val metadata = inspectProxy(outputFile, frameRateHint)
                        if (enableLogging) {
                            Log.d(
                                TAG,
                                "Proxy job=$jobId completed in ${elapsedMs}ms size=${metadata.width}x${metadata.height} fallback=$fallback",
                            )
                        }
                        val payload = mapOf(
                            "ok" to true,
                            "proxyPath" to outputFile.absolutePath,
                            "width" to metadata.width,
                            "height" to metadata.height,
                            "durationMs" to metadata.durationMs,
                            "frameRate" to metadata.frameRate,
                            "rotationBaked" to true,
                            "usedFallback720p" to fallback,
                            "transcodeDurationMs" to elapsedMs,
                        )
                        mainHandler.post { result.success(payload) }
                    } catch (error: Throwable) {
                        outputFile.delete()
                        Log.e(TAG, "Proxy job=$jobId inspection failed", error)
                        mainHandler.post {
                            respondError(
                                result,
                                "probe_failed",
                                error.message ?: "Failed to inspect proxy",
                                recoverable = true,
                            )
                        }
                    }
                }
            }

            override fun onTranscodeCanceled() {
                scope.launch {
                    jobMutex.withLock { jobs.remove(jobId) }
                    outputFile.delete()
                    mainHandler.post {
                        respondError(
                            result,
                            "cancelled",
                            "Proxy generation canceled",
                            recoverable = true,
                        )
                    }
                }
            }

            override fun onTranscodeFailed(exception: Throwable) {
                scope.launch {
                    jobMutex.withLock { jobs.remove(jobId) }
                    outputFile.delete()
                    Log.e(TAG, "Proxy job=$jobId failed", exception)
                    mainHandler.post {
                        respondError(
                            result,
                            "transcode_failed",
                            exception.message ?: "Proxy generation failed",
                            recoverable = true,
                        )
                    }
                }
            }
        }
    }

    private fun emitProgress(jobId: String, progress: Double) {
        val sink = eventSink ?: return
        sink.success(
            mapOf(
                "jobId" to jobId,
                "type" to "progress",
                "progress" to progress,
            ),
        )
    }

    private fun createOutputFile(directory: File): File {
        val prefix = "proxy_${System.currentTimeMillis()}_${UUID.randomUUID()}_"
        val tempFile = File.createTempFile(prefix, ".mp4", directory)
        return tempFile
    }

    private fun readRotationDegrees(sourcePath: String): Int {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(context, Uri.fromFile(File(sourcePath)))
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
        } catch (error: Throwable) {
            Log.w(TAG, "Unable to read rotation", error)
            0
        } finally {
            retriever.release()
        }
    }

    private fun inspectProxy(outputFile: File, frameRateHint: Int): ProxyMetadata {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(context, Uri.fromFile(outputFile))
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0
            val frameRate = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE)?.toDoubleOrNull()
                ?: frameRateHint.toDouble()
            ProxyMetadata(width, height, durationMs, frameRate)
        } finally {
            retriever.release()
        }
    }

    private fun respondError(
        result: MethodChannel.Result,
        code: String,
        message: String,
        recoverable: Boolean,
    ) {
        mainHandler.post {
            result.success(
                mapOf(
                    "ok" to false,
                    "code" to code,
                    "message" to message,
                    "recoverable" to recoverable,
                ),
            )
        }
    }

    private data class ProxyJob(
        val jobId: String,
        val future: java.util.concurrent.Future<Void>,
        val outputFile: File,
        val startElapsedRealtimeMs: Long,
    )

    private data class ProxyMetadata(
        val width: Int,
        val height: Int,
        val durationMs: Long,
        val frameRate: Double,
    )
}

private fun Long?.orDefault(): Long = this ?: 0L
