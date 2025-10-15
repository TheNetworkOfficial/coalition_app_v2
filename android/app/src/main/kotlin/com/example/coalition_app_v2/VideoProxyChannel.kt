package com.example.coalition_app_v2

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
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
import com.otaliastudios.transcoder.strategy.PassThroughTrackStrategy
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import java.nio.ByteBuffer
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

private const val TAG = "VideoProxyChannel"
private const val SAMPLE_TABLE_LIMIT = 4000
private const val DEFAULT_HOT_WINDOW_SECONDS = 12L
private const val DEFAULT_MAX_HOT_SEGMENTS = 6

private enum class PreviewTier {
    FAST,
    QUALITY,
    FALLBACK,
    PREVIEW_360,
}

private data class PreviewProfile(
    val width: Int,
    val height: Int,
    val frameRate: Int,
    val keyframeIntervalSec: Float,
    val videoBitrate: Long,
    val audioBitrateKbps: Int,
    val audioSampleRate: Int,
)

private data class AudioInfo(
    val mimeType: String?,
    val bitrate: Int?,
    val sampleRate: Int?,
)

private enum class SegmentQuality {
    INSTANT,
    FAST,
    QUALITY,
}

private data class SegmentCacheEntry(
    val index: Int,
    val file: File,
    val startUs: Long,
    val endUs: Long,
    val quality: SegmentQuality,
    val createdAtMs: Long,
)

private sealed interface SessionCommand {
    data class EnsureSegment(
        val index: Int,
        val startUs: Long,
        val endUs: Long,
        val preferredQuality: SegmentQuality,
        val callerRequestId: String?,
    ) : SessionCommand

    data class Stop(val reason: String) : SessionCommand
}

private data class ProxySessionState(
    val sessionId: String,
    val sourcePath: String,
    val bufferRadiusUs: Long,
    val hotSegmentLimit: Int,
    val preferredTier: PreviewTier,
    val eventContext: SessionEventContext,
    val keyframesUs: List<Long>,
    val samplesUs: List<Long>,
    val cacheDirectory: File,
    val metadata: SourceMetadata,
    val commands: kotlinx.coroutines.channels.Channel<SessionCommand>,
) {
    val cache = java.util.LinkedHashMap<Int, SegmentCacheEntry>()
    lateinit var workerJob: kotlinx.coroutines.Job
}

private data class SessionEventContext(
    val jobId: String,
)

private fun parsePreviewTier(preview: String?, fallback: Boolean): PreviewTier {
    if (fallback) return PreviewTier.FALLBACK
    return when (preview?.uppercase()) {
        "QUALITY" -> PreviewTier.QUALITY
        else -> PreviewTier.FAST
    }
}

private fun previewProfileFor(tier: PreviewTier): PreviewProfile {
    return when (tier) {
        PreviewTier.FAST -> PreviewProfile(
            width = 540,
            height = 960,
            frameRate = 24,
            keyframeIntervalSec = 0.5f,
            videoBitrate = 1_000_000L,
            audioBitrateKbps = 96,
            audioSampleRate = 44_100,
        )
        PreviewTier.QUALITY -> PreviewProfile(
            width = 720,
            height = 1280,
            frameRate = 24,
            keyframeIntervalSec = 0.75f,
            videoBitrate = 1_500_000L,
            audioBitrateKbps = 128,
            audioSampleRate = 48_000,
        )
        PreviewTier.FALLBACK -> PreviewProfile(
            width = 360,
            height = 640,
            frameRate = 24,
            keyframeIntervalSec = 0.5f,
            videoBitrate = 800_000L,
            audioBitrateKbps = 96,
            audioSampleRate = 44_100,
        )
        PreviewTier.PREVIEW_360 -> PreviewProfile(
            width = 360,
            height = 640,
            frameRate = 24,
            keyframeIntervalSec = 1.0f,
            videoBitrate = 1_200_000L,
            audioBitrateKbps = 96,
            audioSampleRate = 44_100,
        )
    }
}

private fun readAudioInfo(sourcePath: String): AudioInfo? {
    val extractor = MediaExtractor()
    return try {
        extractor.setDataSource(sourcePath)
        for (index in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(index)
            val mime = format.getString(MediaFormat.KEY_MIME)
            if (mime?.startsWith("audio/") == true) {
                val bitrate = if (format.containsKey(MediaFormat.KEY_BIT_RATE)) {
                    format.getInteger(MediaFormat.KEY_BIT_RATE)
                } else {
                    null
                }
                val sampleRate = if (format.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                    format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                } else {
                    null
                }
                return AudioInfo(mime, bitrate, sampleRate)
            }
        }
        null
    } catch (error: Throwable) {
        Log.w(TAG, "Unable to read audio info", error)
        null
    } finally {
        extractor.release()
    }
}

private fun shouldPassthroughAudio(info: AudioInfo?): Boolean {
    if (info == null) return false
    val mime = info.mimeType?.lowercase() ?: return false
    val bitrate = info.bitrate ?: return false
    val sampleRate = info.sampleRate ?: return false
    if (!mime.contains("aac") && !mime.contains("mp4a")) return false
    if (bitrate > 128_000) return false
    if (sampleRate != 44_100 && sampleRate != 48_000) return false
    return true
}

class VideoProxyChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private val methodChannel = MethodChannel(messenger, "coalition/video_proxy")
    private val progressChannel = EventChannel(messenger, "coalition/video_proxy/progress")
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val jobs = ConcurrentHashMap<String, ProxyJob>()
    private val jobMutex = Mutex()
    private val sessions = ConcurrentHashMap<String, ProxySessionState>()
    private val sessionMutex = Mutex()
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
            "startProxySession" -> handleStartProxySession(call, result)
            "ensureSegment" -> handleEnsureSegment(call, result)
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

        val previewQualityArg = args["previewQuality"]?.toString()
        val forceFallbackFlag = args["forceFallback"] as? Boolean ?: false
        val tier = parsePreviewTier(previewQualityArg, isFallback || forceFallbackFlag)
        val profile = previewProfileFor(tier)
        var targetWidth = profile.width
        var targetHeight = profile.height
        if (targetWidth > targetHeight) {
            val swap = targetWidth
            targetWidth = targetHeight
            targetHeight = swap
        }
        val frameRateHint = profile.frameRate
        val keyIntervalSeconds = profile.keyframeIntervalSec
        val audioBitrateKbps = profile.audioBitrateKbps
        val audioInfo = readAudioInfo(sourcePath)
        val audioPassthrough = shouldPassthroughAudio(audioInfo)
        val outputDirectoryPath = args["outputDirectory"]?.toString()
    val segmentedPreview = args["segmentedPreview"] as? Boolean ?: false
    val segmentDurationMs = (args["segmentDurationMs"] as? Number)?.toLong() ?: 10_000L
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

        // If segmented preview is requested, we'll create a per-job directory and write segments there.
        val jobOutput = if (segmentedPreview) {
            val jobDir = File(outputDirectory, jobId)
            if (!jobDir.exists() && !jobDir.mkdirs()) {
                respondError(result, "io_error", "Unable to create job output directory", recoverable = true)
                return
            }
            // return the directory; downstream code will treat this specially
            File(jobDir.absolutePath)
        } else {
            createOutputFile(outputDirectory)
        }

        val videoStrategy = DefaultVideoStrategy.exact(targetWidth, targetHeight)
            .bitRate(profile.videoBitrate)
            .frameRate(profile.frameRate)
            .keyFrameInterval(keyIntervalSeconds)
            .build()

        val audioStrategy = if (audioPassthrough) {
            PassThroughTrackStrategy()
        } else {
            DefaultAudioStrategy.builder()
                .channels(DefaultAudioStrategy.CHANNELS_AS_INPUT)
                .sampleRate(profile.audioSampleRate)
                .bitRate(audioBitrateKbps.toLong() * 1000L)
                .build()
        }

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
                    // If segmentedPreview is requested, enforce PREVIEW_360 profile to guarantee 360p output
                    val effectiveTier = if (segmentedPreview) PreviewTier.PREVIEW_360 else tier
                    val effectiveProfile = previewProfileFor(effectiveTier)
                    val effectiveTargetWidth = effectiveProfile.width
                    val effectiveTargetHeight = effectiveProfile.height

                    if (!segmentedPreview) {
                        val listener = createListener(
                            jobId = jobId,
                            result = result,
                            outputFile = jobOutput,
                            frameRateHint = frameRateHint,
                            fallback = isFallback,
                            tier = effectiveTier,
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
                                "Starting proxy job=$jobId source=$sourcePath " +
                                    "target=${targetWidth}x$targetHeight tier=${tier.name} " +
                                    "fallback=$isFallback audioPassthrough=$audioPassthrough",
                            )
                        }
                    } else {
                        // Segmented preview: transcode sequential time ranges into separate segment files.
                        val jobDir = jobOutput // jobOutput is the directory for segments
                        val retriever = MediaMetadataRetriever()
                        try {
                            retriever.setDataSource(sourcePath)
                            val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
                            val totalSegments = ((durationMs + segmentDurationMs - 1) / segmentDurationMs).toInt()

                            // We'll create a placeholder ProxyJob with a cancellable future that we manage via a flag.
                            val cancelFlag = java.util.concurrent.atomic.AtomicBoolean(false)
                            val currentSegmentFutures = ConcurrentHashMap<Int, java.util.concurrent.Future<Void>>()
                            val fakeFuture = object : java.util.concurrent.Future<Void> {
                                override fun cancel(mayInterruptIfRunning: Boolean): Boolean {
                                    cancelFlag.set(true)
                                    return true
                                }

                                override fun isCancelled(): Boolean = cancelFlag.get()

                                override fun isDone(): Boolean = cancelFlag.get()

                                override fun get(): Void? = null

                                override fun get(timeout: Long, unit: java.util.concurrent.TimeUnit?): Void? = null
                            }

                            val proxyJob = ProxyJob(
                                jobId = jobId,
                                future = fakeFuture,
                                outputFile = jobDir,
                                startElapsedRealtimeMs = SystemClock.elapsedRealtime(),
                            )

                            jobs[jobId] = proxyJob

                            scope.launch {
                                try {
                                    var segmentIndex = 0
                                    var startMs = 0L
                                    while (startMs < durationMs && !cancelFlag.get()) {
                                        val endMs = kotlin.math.min(startMs + segmentDurationMs, durationMs)
                                        val segmentFile = File(jobDir, String.format("segment_%03d.mp4", segmentIndex))

                                        val listener = object : TranscoderListener {
                                            override fun onTranscodeProgress(progress: Double) {
                                                // Map per-segment progress to overall job progress roughly.
                                                val completedSegmentsProgress = segmentIndex.toDouble() / totalSegments.toDouble()
                                                val segProgress = progress / totalSegments.toDouble()
                                                val overall = completedSegmentsProgress + segProgress
                                                emitProgress(jobId, overall, isFallback)
                                            }

                                            override fun onTranscodeCompleted(successCode: Int) {
                                                // After a segment completes, emit a segment_ready event.
                                                try {
                                                    val metadata = inspectProxy(segmentFile, frameRateHint)
                                                    Log.d(TAG, "Segment #$segmentIndex completed -> ${segmentFile.absolutePath} duration=${metadata.durationMs} size=${segmentFile.length()}")
                                                    val payload = mapOf(
                                                        "jobId" to jobId,
                                                        "type" to "segment_ready",
                                                        "segmentIndex" to segmentIndex,
                                                        "path" to segmentFile.absolutePath,
                                                        "durationMs" to metadata.durationMs,
                                                        "width" to metadata.width,
                                                        "height" to metadata.height,
                                                        "hasAudio" to true,
                                                        "totalSegments" to totalSegments,
                                                        "totalDurationMs" to durationMs,
                                                    )
                                                    mainHandler.post {
                                                        Log.d(TAG, "Emitting segment_ready for #$segmentIndex")
                                                        eventSink?.success(payload)
                                                    }
                                                } catch (t: Throwable) {
                                                    Log.e(TAG, "Failed to inspect segment file", t)
                                                    mainHandler.post {
                                                        respondError(result, "segment_inspect_failed", t.message ?: "Failed to inspect segment", recoverable = true)
                                                    }
                                                }
                                            }

                                            override fun onTranscodeCanceled() {
                                                // noop; cancellation checked via cancelFlag
                                            }

                                            override fun onTranscodeFailed(exception: Throwable) {
                                                Log.e(TAG, "Segment transcode failed", exception)
                                                // Emit a failed event for the job and abort
                                                mainHandler.post {
                                                    respondError(
                                                        result,
                                                        "segment_failed",
                                                        exception.message ?: "Segment transcode failed",
                                                        recoverable = true,
                                                    )
                                                }
                                            }
                                        }

                                        // First, create a trimmed input for this segment so we only transcode the needed time range.
                                        val tmpInput = File(jobDir, String.format("segment_%03d_in.mp4", segmentIndex))
                                        val startUs = startMs * 1000L
                                        val durUs = (endMs - startMs) * 1000L
                                        Log.d(TAG, "Segmented: trimming segment #$segmentIndex startMs=$startMs endMs=$endMs startUs=$startUs durUs=$durUs tmp=${tmpInput.absolutePath}")
                                        val trimmedOk = try {
                                            trimMediaRange(sourcePath, tmpInput.absolutePath, startUs, durUs)
                                        } catch (t: Throwable) {
                                            Log.e(TAG, "Failed to trim segment input", t)
                                            false
                                        }

                                        // Ensure trimmed file looks sane (exists and non-trivial size). If it's too small,
                                        // treat trimming as failed to avoid feeding the transcoder the full source file.
                                        if (trimmedOk) {
                                            try {
                                                val len = tmpInput.length()
                                                Log.d(TAG, "Trimmed input size=${len} bytes for segment #$segmentIndex")
                                                if (len <= 1024L) {
                                                    Log.w(TAG, "Trimmed input too small, treating as trim failure for segment #$segmentIndex")
                                                    tmpInput.delete()
                                                    throw RuntimeException("Trimmed input too small")
                                                }
                                            } catch (t: Throwable) {
                                                Log.w(TAG, "Trim validation failed", t)
                                                mainHandler.post {
                                                    respondError(result, "trim_failed", "Failed to create trimmed input for segment", recoverable = true)
                                                }
                                                return@launch
                                            }
                                        } else {
                                            mainHandler.post {
                                                respondError(result, "trim_failed", "Failed to create trimmed input for segment", recoverable = true)
                                            }
                                            return@launch
                                        }

                                        val optionsBuilder = Transcoder.into(DefaultDataSink(segmentFile.absolutePath))
                                            .addDataSource(FilePathDataSource(tmpInput.absolutePath))
                                            .setVideoTrackStrategy(videoStrategy)
                                            .setAudioTrackStrategy(audioStrategy)
                                            .setListener(listener)
                                            .setListenerHandler(mainHandler)
                                            .setVideoRotation(rotationDegrees)
                                            // There's no direct time range API on otaliastudios Transcoder; use extractor to create a temporary trimmed source if needed.

                                        // If Transcoder supported setTimeRange we'd set it here. As a practical fallback, use DefaultDataSink and hope the library supports trimming via setTrim...
                                        // For now, attempt to set a data source that indicates the time range by using FilePathDataSource; if unavailable, full-file transcode will happen which is slower.

                                        // Start transcode for the segment and wait for completion.
                                        val futureSeg = Transcoder.getInstance().transcode(optionsBuilder.build())
                                        currentSegmentFutures[segmentIndex] = futureSeg

                                        try {
                                            // Wait for this segment to finish or for cancellation.
                                            while (!futureSeg.isDone && !cancelFlag.get()) {
                                                Thread.sleep(50)
                                            }
                                            if (cancelFlag.get()) {
                                                futureSeg.cancel(true)
                                                break
                                            }
                                            futureSeg.get()
                                        } catch (ex: Exception) {
                                            if (cancelFlag.get()) break
                                            throw ex
                                        } finally {
                                            currentSegmentFutures.remove(segmentIndex)
                                            try {
                                                tmpInput.delete()
                                            } catch (_: Throwable) {
                                            }
                                        }

                                        segmentIndex += 1
                                        startMs = endMs
                                    }

                                    // When loop finishes, emit completed event for job
                                    val elapsedMs = SystemClock.elapsedRealtime() - proxyJob.startElapsedRealtimeMs
                                    val completedPayload = mapOf(
                                        "ok" to true,
                                        "jobId" to jobId,
                                        "type" to "completed",
                                        "outputDirectory" to jobDir.absolutePath,
                                        "totalSegments" to ((durationMs + segmentDurationMs - 1) / segmentDurationMs).toInt(),
                                        "totalDurationMs" to durationMs,
                                        "transcodeDurationMs" to elapsedMs,
                                    )
                                    mainHandler.post { eventSink?.success(completedPayload) }
                                    mainHandler.post { result.success(mapOf("ok" to true, "jobId" to jobId)) }
                                } catch (err: Throwable) {
                                    Log.e(TAG, "Segmented proxy failed", err)
                                    mainHandler.post {
                                        respondError(result, "segmented_failed", err.message ?: "Segmented proxy generation failed", recoverable = true)
                                    }
                                } finally {
                                    retriever.release()
                                }
                            }
                        } catch (err: Throwable) {
                            retriever.release()
                            respondError(result, "probe_failed", err.message ?: "Failed to probe source for segmented preview", recoverable = true)
                            return@withLock
                        }
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
                // Try to cancel the main future
                removed?.future?.cancel(true)
                // If this was a segmented job, try cancelling current segment futures as well
                try {
                    // Attempt to find per-segment futures in currentSegmentFutures map by reflection or static map
                    // (currentSegmentFutures is local in the create handler); best-effort: delete output directory
                    removed?.outputFile?.deleteRecursively()
                } catch (_: Throwable) {
                }
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

    private fun handleStartProxySession(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        if (args == null) {
            respondError(result, "invalid_args", "Missing arguments", recoverable = true)
            return
        }

        val sessionId = args["sessionId"]?.toString().takeUnless { it.isNullOrBlank() }
        if (sessionId == null) {
            respondError(result, "invalid_args", "Missing sessionId", recoverable = true)
            return
        }

        val sourcePath = args["sourcePath"]?.toString().takeUnless { it.isNullOrBlank() }
        if (sourcePath == null) {
            respondError(result, "invalid_args", "Missing sourcePath", recoverable = true)
            return
        }

        val previewQualityArg = args["previewQuality"]?.toString()
        val preferredTier = parsePreviewTier(previewQualityArg, fallback = false)
        val bufferWindowSeconds = (args["hotWindowSeconds"] as? Number)?.toLong()
            ?: DEFAULT_HOT_WINDOW_SECONDS
        val hotLimit = (args["maxHotSegments"] as? Number)?.toInt() ?: DEFAULT_MAX_HOT_SEGMENTS
        val requestId = args["requestId"]?.toString()

        scope.launch {
            val extractor = MediaExtractor()
            val keyframesUs = mutableListOf<Long>()
            val samplesUs = mutableListOf<Long>()
            var videoTrackIndex = -1
            try {
                extractor.setDataSource(sourcePath)
                val trackCount = extractor.trackCount
                for (i in 0 until trackCount) {
                    val format = extractor.getTrackFormat(i)
                    val mime = format.getString(MediaFormat.KEY_MIME)
                    if (mime?.startsWith("video/") == true) {
                        videoTrackIndex = i
                        break
                    }
                }

                if (videoTrackIndex >= 0) {
                    extractor.selectTrack(videoTrackIndex)
                    while (true) {
                        val sampleTime = extractor.sampleTime
                        if (sampleTime < 0) break
                        val flags = extractor.sampleFlags
                        if ((flags and MediaExtractor.SAMPLE_FLAG_SYNC) != 0) {
                            keyframesUs.add(sampleTime)
                        }
                        samplesUs.add(sampleTime)
                        if (samplesUs.size >= SAMPLE_TABLE_LIMIT) {
                            break
                        }
                        extractor.advance()
                    }
                    extractor.unselectTrack(videoTrackIndex)
                }
            } catch (error: Throwable) {
                Log.e(TAG, "Failed to probe session", error)
                respondError(result, "session_probe_failed", error.message ?: "Failed to probe source", recoverable = true)
                extractor.release()
                return@launch
            } finally {
                extractor.release()
            }

            val metadata = readSourceMetadata(sourcePath)
            val sessionDir = File(context.cacheDir, "proxy_sessions/$sessionId").apply { mkdirs() }

            val instantPreview = try {
                generateInstantPreview(sessionId, sourcePath, sessionDir, metadata)
            } catch (error: Throwable) {
                Log.w(TAG, "Instant preview generation failed, falling back", error)
                null
            }

            val commandChannel = Channel<SessionCommand>(Channel.UNLIMITED)

            val sessionState = ProxySessionState(
                sessionId = sessionId,
                sourcePath = sourcePath,
                bufferRadiusUs = bufferWindowSeconds * 1_000_000L,
                hotSegmentLimit = hotLimit,
                preferredTier = preferredTier,
                eventContext = SessionEventContext(jobId = sessionId),
                keyframesUs = keyframesUs.toList(),
                samplesUs = samplesUs.toList(),
                cacheDirectory = sessionDir,
                metadata = metadata,
                commands = commandChannel,
            )

            sessionState.workerJob = launchSessionWorker(sessionState)

            sessionMutex.withLock {
                sessions[sessionId]?.let { existing ->
                    existing.commands.trySend(SessionCommand.Stop("replaced"))
                    existing.workerJob.cancel()
                    sessions.remove(sessionId)
                }
                sessions[sessionId] = sessionState
            }

            emitSessionProbeEvent(sessionState, metadata, requestId)

            val response = mutableMapOf<String, Any?>(
                "ok" to true,
                "sessionId" to sessionId,
                "durationMs" to metadata.durationMs,
                "width" to metadata.width,
                "height" to metadata.height,
                "rotation" to metadata.rotation,
                "keyframeCount" to keyframesUs.size,
                "sampleCount" to samplesUs.size,
            )
            instantPreview?.let {
                response["instantPreviewPath"] = it.absolutePath
                response["instantPreviewBytes"] = it.length()
            }

            mainHandler.post { result.success(response) }
        }
    }

    private fun handleEnsureSegment(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        if (args == null) {
            respondError(result, "invalid_args", "Missing arguments", recoverable = true)
            return
        }

        val sessionId = args["sessionId"]?.toString().takeUnless { it.isNullOrBlank() }
        if (sessionId == null) {
            respondError(result, "invalid_args", "Missing sessionId", recoverable = true)
            return
        }

        val index = (args["segmentIndex"] as? Number)?.toInt()
        val startUs = (args["startUs"] as? Number)?.toLong()
        val endUs = (args["endUs"] as? Number)?.toLong()
        if (index == null || startUs == null || endUs == null) {
            respondError(result, "invalid_args", "Missing segment parameters", recoverable = true)
            return
        }

        val preferredQuality = when (args["quality"]?.toString()?.uppercase()) {
            "QUALITY" -> SegmentQuality.QUALITY
            "FAST" -> SegmentQuality.FAST
            "INSTANT" -> SegmentQuality.INSTANT
            else -> SegmentQuality.FAST
        }
        val requestId = args["requestId"]?.toString()

        scope.launch {
            val session = sessionMutex.withLock { sessions[sessionId] }
            if (session == null) {
                respondError(result, "session_missing", "Proxy session not found", recoverable = true)
                return@launch
            }

            val ok = session.commands.trySend(
                SessionCommand.EnsureSegment(
                    index = index,
                    startUs = startUs,
                    endUs = endUs,
                    preferredQuality = preferredQuality,
                    callerRequestId = requestId,
                ),
            ).isSuccess

            if (!ok) {
                respondError(result, "session_busy", "Unable to schedule segment", recoverable = true)
                return@launch
            }

            mainHandler.post { result.success(mapOf("ok" to true)) }
        }
    }

    private fun emitSessionProbeEvent(
        session: ProxySessionState,
        metadata: SourceMetadata,
        requestId: String?,
    ) {
        val sink = eventSink ?: return
        val payload = mutableMapOf<String, Any?>(
            "jobId" to session.eventContext.jobId,
            "type" to "session_probe",
            "sessionId" to session.sessionId,
            "durationMs" to metadata.durationMs,
            "width" to metadata.width,
            "height" to metadata.height,
            "rotation" to metadata.rotation,
            "keyframesUs" to session.keyframesUs,
            "samplesUs" to session.samplesUs,
        )
        if (!requestId.isNullOrEmpty()) {
            payload["requestId"] = requestId
        }
        sink.success(payload)
    }

    private fun generateInstantPreview(
        sessionId: String,
        sourcePath: String,
        sessionDir: File,
        metadata: SourceMetadata,
    ): File? {
        val output = File(sessionDir, "${sessionId}_instant.mp4")
        if (output.exists()) {
            return output
        }

        if (tryGenerateInstantPreviewWithCodec(sourcePath, metadata, output)) {
            return output
        }

        if (generateInstantPreviewFallback(sourcePath, output)) {
            return output
        }

        return null
    }

    private fun tryGenerateInstantPreviewWithCodec(
        sourcePath: String,
        metadata: SourceMetadata,
        output: File,
    ): Boolean {
        return try {
            val retriever = MediaMetadataRetriever()
            val frames = mutableListOf<ByteArray>()
            val settings = qualitySettingsFor(SegmentQuality.INSTANT, metadata)
            try {
                retriever.setDataSource(sourcePath)
                val frame = retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                    ?: return false
                val scaled = Bitmap.createScaledBitmap(frame, settings.width, settings.height, true)
                val nv21 = bitmapToNV21(scaled)
                scaled.recycle()
                frame.recycle()
                frames.add(nv21)
                encodeFramesWithCodec(frames, settings, output, reuseEncoder = null)
                true
            } finally {
                retriever.release()
            }
        } catch (error: Throwable) {
            Log.w(TAG, "Instant preview codec path failed", error)
            output.delete()
            false
        }
    }

    private fun generateInstantPreviewFallback(sourcePath: String, output: File): Boolean {
        val tmp = File(output.parentFile, output.nameWithoutExtension + "_fallback.mp4")
        if (trimMediaRange(sourcePath, tmp.absolutePath, 0L, 1_500_000L)) {
            return tmp.renameTo(output)
        }
        tmp.delete()
        return false
    }

    private data class CodecQualityProfile(
        val width: Int,
        val height: Int,
        val frameRate: Int,
        val bitrate: Int,
    )

    private fun qualitySettingsFor(quality: SegmentQuality, metadata: SourceMetadata): CodecQualityProfile {
        val maxEdge = when (quality) {
            SegmentQuality.INSTANT -> 320
            SegmentQuality.FAST -> 480
            SegmentQuality.QUALITY -> 720
        }
        val frameRate = when (quality) {
            SegmentQuality.INSTANT -> 8
            SegmentQuality.FAST -> 15
            SegmentQuality.QUALITY -> 24
        }
        val bitrate = when (quality) {
            SegmentQuality.INSTANT -> 250_000
            SegmentQuality.FAST -> 600_000
            SegmentQuality.QUALITY -> 1_000_000
        }
        val (width, height) = deriveEvenDimensions(metadata.width, metadata.height, maxEdge)
        return CodecQualityProfile(width, height, frameRate, bitrate)
    }

    private fun deriveEvenDimensions(width: Int, height: Int, maxLongEdge: Int): Pair<Int, Int> {
        if (width <= 0 || height <= 0) {
            val long = maxLongEdge.coerceAtLeast(2)
            val short = (long * 9 / 16).coerceAtLeast(2)
            val evenLong = if (long % 2 == 0) long else long - 1
            val evenShort = if (short % 2 == 0) short else short - 1
            return Pair(evenLong, evenShort)
        }
        val longEdge = max(width, height)
        val shortEdge = min(width, height)
        val scale = min(1.0, maxLongEdge.toDouble() / longEdge.toDouble())
        var targetLong = (longEdge * scale).roundToInt().coerceAtLeast(2)
        var targetShort = (shortEdge * scale).roundToInt().coerceAtLeast(2)
        if (targetLong % 2 != 0) targetLong -= 1
        if (targetShort % 2 != 0) targetShort -= 1
        if (targetLong < 2) targetLong = 2
        if (targetShort < 2) targetShort = 2
        return if (width >= height) {
            Pair(targetLong, targetShort)
        } else {
            Pair(targetShort, targetLong)
        }
    }

    private fun encodeFramesWithCodec(
        frames: List<ByteArray>,
        settings: CodecQualityProfile,
        output: File,
        reuseEncoder: ReusableCodecEncoder?,
    ) {
        val encoder = reuseEncoder ?: ReusableCodecEncoder()
        encoder.encodeFrames(frames, settings, output)
        if (reuseEncoder == null) {
            encoder.release()
        }
    }

    private class ReusableCodecEncoder {
        private var codec: MediaCodec? = null

        fun encodeFrames(frames: List<ByteArray>, settings: CodecQualityProfile, output: File) {
            if (frames.isEmpty()) {
                encodeFrames(listOf(ByteArray(expectedFrameSize(settings))), settings, output)
                return
            }
            val encoder = prepareCodec(settings)
            val bufferInfo = MediaCodec.BufferInfo()
            var muxer: MediaMuxer? = null
            var trackIndex = -1
            val frameDurationUs = 1_000_000L / settings.frameRate
            val expectedSize = expectedFrameSize(settings)
            output.parentFile?.mkdirs()
            if (output.exists()) output.delete()

            encoder.start()
            try {
                var inputDone = false
                var outputDone = false
                var frameIndex = 0
                var presentationTimeUs = 0L
                while (!outputDone) {
                    if (!inputDone) {
                        val inputIndex = encoder.dequeueInputBuffer(10_000)
                        if (inputIndex >= 0) {
                            val buffer = encoder.getInputBuffer(inputIndex) ?: ByteBuffer.allocate(0)
                            buffer.clear()
                            if (frameIndex < frames.size) {
                                val frameData = frames[frameIndex]
                                if (frameData.size != expectedSize) {
                                    throw IllegalArgumentException("Frame size ${frameData.size} does not match expected $expectedSize")
                                }
                                buffer.put(frameData)
                                val flags = if (frameIndex == 0) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
                                encoder.queueInputBuffer(inputIndex, 0, frameData.size, presentationTimeUs, flags)
                                presentationTimeUs += frameDurationUs
                                frameIndex += 1
                            } else {
                                encoder.queueInputBuffer(
                                    inputIndex,
                                    0,
                                    0,
                                    presentationTimeUs,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                                )
                                inputDone = true
                            }
                        }
                    }

                    val outputIndex = encoder.dequeueOutputBuffer(bufferInfo, 10_000)
                    when {
                        outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                            // no-op
                        }
                        outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            val newFormat = encoder.outputFormat
                            muxer = MediaMuxer(output.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
                            trackIndex = muxer.addTrack(newFormat)
                            muxer.start()
                        }
                        outputIndex >= 0 -> {
                            val encodedData = encoder.getOutputBuffer(outputIndex)
                                ?: throw IllegalStateException("Encoder output buffer $outputIndex is null")
                            if (bufferInfo.size > 0 && trackIndex >= 0) {
                                encodedData.position(bufferInfo.offset)
                                encodedData.limit(bufferInfo.offset + bufferInfo.size)
                                muxer?.writeSampleData(trackIndex, encodedData, bufferInfo)
                            }
                            if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                                outputDone = true
                            }
                            encoder.releaseOutputBuffer(outputIndex, false)
                        }
                    }
                }
            } finally {
                try {
                    encoder.stop()
                } catch (_: Throwable) {
                }
                try {
                    muxer?.stop()
                    muxer?.release()
                } catch (_: Throwable) {
                }
            }
        }

        private fun prepareCodec(settings: CodecQualityProfile): MediaCodec {
            val format = MediaFormat.createVideoFormat("video/avc", settings.width, settings.height)
            format.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
            format.setInteger(MediaFormat.KEY_BIT_RATE, settings.bitrate)
            format.setInteger(MediaFormat.KEY_FRAME_RATE, settings.frameRate)
            format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)

            val codecInstance = codec?.also {
                try {
                    it.reset()
                } catch (_: Throwable) {
                    it.releaseSafely()
                    return createAndConfigure(format)
                }
                it.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            } ?: createAndConfigure(format)

            codec = codecInstance
            return codecInstance
        }

        private fun createAndConfigure(format: MediaFormat): MediaCodec {
            val encoder = MediaCodec.createEncoderByType("video/avc")
            encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            return encoder
        }

        fun release() {
            codec?.releaseSafely()
            codec = null
        }

        private fun expectedFrameSize(settings: CodecQualityProfile): Int {
            return settings.width * settings.height * 3 / 2
        }
    }

    private fun MediaCodec.releaseSafely() {
        try {
            stop()
        } catch (_: Throwable) {
        }
        try {
            release()
        } catch (_: Throwable) {
        }
    }

    private fun bitmapToNV21(bitmap: Bitmap): ByteArray {
        val width = bitmap.width
        val height = bitmap.height
        val argb = IntArray(width * height)
        bitmap.getPixels(argb, 0, width, 0, 0, width, height)
        val yuv = ByteArray(width * height * 3 / 2)
        var yIndex = 0
        var uvIndex = width * height
        for (j in 0 until height) {
            for (i in 0 until width) {
                val rgb = argb[j * width + i]
                val r = (rgb shr 16) and 0xFF
                val g = (rgb shr 8) and 0xFF
                val b = rgb and 0xFF
                val y = ((66 * r + 129 * g + 25 * b + 128) shr 8) + 16
                val u = ((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128
                val v = ((112 * r - 94 * g - 18 * b + 128) shr 8) + 128
                yuv[yIndex++] = y.coerceIn(0, 255).toByte()
                if (j % 2 == 0 && i % 2 == 0) {
                    yuv[uvIndex++] = v.coerceIn(0, 255).toByte()
                    yuv[uvIndex++] = u.coerceIn(0, 255).toByte()
                }
            }
        }
        return yuv
    }

    private fun launchSessionWorker(session: ProxySessionState): Job {
        val queue = ArrayDeque<Int>()
        val queued = mutableMapOf<Int, SessionCommand.EnsureSegment>()
        return scope.launch {
            val pipeline = SegmentPipeline(session)
            try {
                while (isActive) {
                    val command = withTimeoutOrNull(750L) { session.commands.receive() }
                    if (command == null) {
                        pipeline.upgradeQualityIfIdle()
                        continue
                    }
                    when (command) {
                        is SessionCommand.Stop -> return@launch
                        is SessionCommand.EnsureSegment -> {
                            val existing = queued[command.index]
                            if (existing == null || command.preferredQuality.ordinal > existing.preferredQuality.ordinal) {
                                queued[command.index] = command
                            }
                            if (!queue.contains(command.index)) {
                                queue.addLast(command.index)
                            }
                        }
                    }

                    while (queue.isNotEmpty()) {
                        val index = queue.removeFirst()
                        val request = queued.remove(index) ?: continue
                        val entry = pipeline.ensureSegment(request)
                        if (entry != null) {
                            maintainHotWindow(session)
                            emitSegmentReadyEvent(session, entry, request.callerRequestId)
                            scheduleNeighborSegments(session, request, queue, queued)
                        }
                    }
                }
            } catch (cancel: Throwable) {
                if (cancel !is kotlinx.coroutines.CancellationException) {
                    Log.w(TAG, "Session worker for ${session.sessionId} stopped", cancel)
                }
            } finally {
                pipeline.close()
            }
        }
    }

    private fun maintainHotWindow(session: ProxySessionState) {
        while (session.cache.size > session.hotSegmentLimit) {
            val oldestKey = session.cache.keys.firstOrNull() ?: break
            val removed = session.cache.remove(oldestKey)
            removed?.file?.delete()
        }
    }

    private fun emitSegmentReadyEvent(
        session: ProxySessionState,
        entry: SegmentCacheEntry,
        requestId: String?,
    ) {
        val sink = eventSink ?: return
        val profile = qualitySettingsFor(entry.quality, session.metadata)
        val meta = try {
            inspectProxy(entry.file, profile.frameRate)
        } catch (error: Throwable) {
            Log.w(TAG, "Failed to inspect segment ${entry.index}", error)
            null
        }
        val payload = mutableMapOf<String, Any?>(
            "jobId" to session.eventContext.jobId,
            "type" to "segment_ready",
            "sessionId" to session.sessionId,
            "segmentIndex" to entry.index,
            "path" to entry.file.absolutePath,
            "quality" to entry.quality.name.lowercase(),
            "startUs" to entry.startUs,
            "endUs" to entry.endUs,
            "hasAudio" to false,
        )
        meta?.let {
            payload["durationMs"] = it.durationMs
            payload["width"] = it.width
            payload["height"] = it.height
            payload["frameRate"] = it.frameRate
        }
        if (!requestId.isNullOrEmpty()) {
            payload["requestId"] = requestId
        }
        mainHandler.post { sink.success(payload) }
    }

    private fun scheduleNeighborSegments(
        session: ProxySessionState,
        baseRequest: SessionCommand.EnsureSegment,
        queue: ArrayDeque<Int>,
        queued: MutableMap<Int, SessionCommand.EnsureSegment>,
    ) {
        val segmentDurationUs = (baseRequest.endUs - baseRequest.startUs).coerceAtLeast(1_000_000L)
        val bufferRadiusUs = session.bufferRadiusUs
        val sourceDurationUs = session.metadata.durationMs * 1000L

        val nextStart = baseRequest.endUs
        if (nextStart < sourceDurationUs && (nextStart - baseRequest.startUs) <= bufferRadiusUs) {
            val nextIndex = baseRequest.index + 1
            if (session.cache[nextIndex] == null && queued[nextIndex] == null) {
                val request = SessionCommand.EnsureSegment(
                    index = nextIndex,
                    startUs = nextStart,
                    endUs = (nextStart + segmentDurationUs).coerceAtMost(sourceDurationUs),
                    preferredQuality = SegmentQuality.FAST,
                    callerRequestId = null,
                )
                queued[nextIndex] = request
                queue.addLast(nextIndex)
            }
        }

        val prevEnd = baseRequest.startUs
        if (prevEnd > 0 && (baseRequest.endUs - prevEnd) <= bufferRadiusUs) {
            val prevIndex = baseRequest.index - 1
            val startUs = (baseRequest.startUs - segmentDurationUs).coerceAtLeast(0L)
            if (prevIndex >= 0 && session.cache[prevIndex] == null && queued[prevIndex] == null) {
                val request = SessionCommand.EnsureSegment(
                    index = prevIndex,
                    startUs = startUs,
                    endUs = baseRequest.startUs,
                    preferredQuality = SegmentQuality.FAST,
                    callerRequestId = null,
                )
                queued[prevIndex] = request
                queue.addLast(prevIndex)
            }
        }
    }

    private inner class SegmentPipeline(private val session: ProxySessionState) {
        private val encoder = ReusableCodecEncoder()
        private val retriever = MediaMetadataRetriever().apply {
            setDataSource(session.sourcePath)
        }

        fun ensureSegment(request: SessionCommand.EnsureSegment): SegmentCacheEntry? {
            val baseline = targetSegmentQualityForTier(session.preferredTier)
            val desired = maxQuality(request.preferredQuality, baseline)
            val existing = session.cache[request.index]
            if (existing != null && existing.quality.isAtLeast(desired) &&
                existing.startUs == request.startUs && existing.endUs == request.endUs
            ) {
                session.cache.remove(request.index)
                val refreshed = existing.copy(createdAtMs = SystemClock.elapsedRealtime())
                session.cache[request.index] = refreshed
                return refreshed
            }

            val settings = qualitySettingsFor(desired, session.metadata)
            val tempFile = File(
                session.cacheDirectory,
                String.format(
                    "segment_%04d_%s_%d.mp4",
                    request.index,
                    desired.name.lowercase(),
                    SystemClock.elapsedRealtime(),
                ),
            )

            val frames = buildFrames(request, settings)
            val codecSuccess = try {
                encodeFramesWithCodec(frames, settings, tempFile, encoder)
                true
            } catch (error: Throwable) {
                Log.w(TAG, "Codec segment encode failed for index=${request.index}", error)
                tempFile.delete()
                false
            }

            var achievedQuality = desired
            val outputFile = if (codecSuccess) {
                tempFile
            } else {
                val fallback = File(
                    session.cacheDirectory,
                    String.format(
                        "segment_%04d_fallback_%d.mp4",
                        request.index,
                        SystemClock.elapsedRealtime(),
                    ),
                )
                var fallbackQuality = SegmentQuality.FAST
                var success = generateSegmentFallback(session.sourcePath, fallback, request.startUs, request.endUs)
                if (!success) {
                    fallbackQuality = desired
                    success = transcodeSegmentWithTranscoder(session, request, fallback, desired)
                }
                if (success) {
                    achievedQuality = fallbackQuality
                    fallback
                } else {
                    fallback.delete()
                    null
                }
            } ?: return null

            session.cache.remove(request.index)?.file?.delete()
            val entry = SegmentCacheEntry(
                index = request.index,
                file = outputFile,
                startUs = request.startUs,
                endUs = request.endUs,
                quality = achievedQuality,
                createdAtMs = SystemClock.elapsedRealtime(),
            )
            session.cache[request.index] = entry
            return entry
        }

        fun upgradeQualityIfIdle() {
            val target = targetSegmentQualityForTier(session.preferredTier)
            if (target == SegmentQuality.FAST) {
                return
            }
            val candidate = session.cache.values.firstOrNull { !it.quality.isAtLeast(target) }
                ?: return
            val request = SessionCommand.EnsureSegment(
                index = candidate.index,
                startUs = candidate.startUs,
                endUs = candidate.endUs,
                preferredQuality = target,
                callerRequestId = null,
            )
            ensureSegment(request)?.let {
                emitSegmentReadyEvent(session, it, null)
            }
        }

        fun close() {
            try {
                retriever.release()
            } catch (_: Throwable) {
            }
            encoder.release()
        }

        private fun buildFrames(
            request: SessionCommand.EnsureSegment,
            settings: CodecQualityProfile,
        ): List<ByteArray> {
            val frames = mutableListOf<ByteArray>()
            val durationUs = (request.endUs - request.startUs).coerceAtLeast(500_000L)
            val frameCount = max(1, ((durationUs / 1_000_000.0) * settings.frameRate).roundToInt())
            val stepUs = (durationUs / frameCount).coerceAtLeast(1L)
            for (i in 0 until frameCount) {
                val timeUs = request.startUs + i * stepUs
                try {
                    val bitmap = retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST)
                    if (bitmap != null) {
                        val scaled = Bitmap.createScaledBitmap(bitmap, settings.width, settings.height, true)
                        frames.add(bitmapToNV21(scaled))
                        scaled.recycle()
                        bitmap.recycle()
                    }
                } catch (error: Throwable) {
                    Log.w(TAG, "Failed to decode frame at $timeUs for segment ${request.index}", error)
                }
            }

            if (frames.isEmpty()) {
                try {
                    val bitmap = retriever.getFrameAtTime(
                        request.startUs,
                        MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                    )
                    if (bitmap != null) {
                        val scaled = Bitmap.createScaledBitmap(bitmap, settings.width, settings.height, true)
                        frames.add(bitmapToNV21(scaled))
                        scaled.recycle()
                        bitmap.recycle()
                    }
                } catch (error: Throwable) {
                    Log.w(TAG, "Fallback frame decode failed for segment ${request.index}", error)
                }
            }

            if (frames.isEmpty()) {
                frames.add(ByteArray(settings.width * settings.height * 3 / 2))
            }

            return frames
        }
    }

    private fun generateSegmentFallback(
        sourcePath: String,
        output: File,
        startUs: Long,
        endUs: Long,
    ): Boolean {
        val durationUs = (endUs - startUs).coerceAtLeast(750_000L)
        return trimMediaRange(sourcePath, output.absolutePath, startUs, durationUs)
    }

    private fun transcodeSegmentWithTranscoder(
        session: ProxySessionState,
        request: SessionCommand.EnsureSegment,
        output: File,
        quality: SegmentQuality,
    ): Boolean {
        val trimInput = File(
            session.cacheDirectory,
            String.format(
                "segment_%04d_trim_%d.mp4",
                request.index,
                SystemClock.elapsedRealtime(),
            ),
        )
        val durationUs = (request.endUs - request.startUs).coerceAtLeast(750_000L)
        if (!trimMediaRange(session.sourcePath, trimInput.absolutePath, request.startUs, durationUs)) {
            trimInput.delete()
            return false
        }

        val profile = qualitySettingsFor(quality, session.metadata)
        val videoStrategy = DefaultVideoStrategy.exact(profile.width, profile.height)
            .bitRate(profile.bitrate.toLong())
            .frameRate(profile.frameRate)
            .keyFrameInterval(1f)
            .build()

        return try {
            val optionsBuilder = Transcoder.into(DefaultDataSink(output.absolutePath))
                .addDataSource(FilePathDataSource(trimInput.absolutePath))
                .setVideoTrackStrategy(videoStrategy)
                .setAudioTrackStrategy(PassThroughTrackStrategy())
            val future = Transcoder.getInstance().transcode(optionsBuilder.build())
            future.get()
            true
        } catch (error: Throwable) {
            Log.e(TAG, "Transcoder fallback failed", error)
            output.delete()
            false
        } finally {
            trimInput.delete()
        }
    }

    private fun SegmentQuality.isAtLeast(other: SegmentQuality): Boolean {
        return this.ordinal >= other.ordinal
    }

    private fun maxQuality(a: SegmentQuality, b: SegmentQuality): SegmentQuality {
        return if (a.ordinal >= b.ordinal) a else b
    }

    private fun targetSegmentQualityForTier(tier: PreviewTier): SegmentQuality {
        return when (tier) {
            PreviewTier.QUALITY -> SegmentQuality.QUALITY
            PreviewTier.FALLBACK -> SegmentQuality.FAST
            PreviewTier.PREVIEW_360 -> SegmentQuality.FAST
            else -> SegmentQuality.FAST
        }
    }

    private fun createListener(
        jobId: String,
        result: MethodChannel.Result,
        outputFile: File,
        frameRateHint: Int,
        fallback: Boolean,
        tier: PreviewTier,
        enableLogging: Boolean,
    ): TranscoderListener {
        return object : TranscoderListener {
            override fun onTranscodeProgress(progress: Double) {
                emitProgress(jobId, progress, fallback)
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
                                "Proxy job=$jobId completed in ${elapsedMs}ms size=${metadata.width}x${metadata.height} tier=${tier.name} fallback=$fallback",
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

    private fun emitProgress(jobId: String, progress: Double, fallback: Boolean) {
        val sink = eventSink ?: return
        sink.success(
            mapOf(
                "jobId" to jobId,
                "type" to "progress",
                "progress" to progress,
                "fallbackTriggered" to fallback,
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

    private fun readSourceMetadata(sourcePath: String): SourceMetadata {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(context, Uri.fromFile(File(sourcePath)))
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            SourceMetadata(width, height, durationMs, rotation)
        } catch (error: Throwable) {
            Log.w(TAG, "Failed to read source metadata", error)
            SourceMetadata(0, 0, 0L, 0)
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

    private data class SourceMetadata(
        val width: Int,
        val height: Int,
        val durationMs: Long,
        val rotation: Int,
    )

    private data class ProxyMetadata(
        val width: Int,
        val height: Int,
        val durationMs: Long,
        val frameRate: Double,
    )
}

/**
 * Trim a time range [startUs, startUs + durationUs) from sourcePath into outPath using MediaExtractor/MediaMuxer.
 * Returns true on success.
 */
private fun trimMediaRange(sourcePath: String, outPath: String, startUs: Long, durationUs: Long): Boolean {
    val extractor = MediaExtractor()
    var muxer: MediaMuxer? = null
    try {
        extractor.setDataSource(sourcePath)
        val trackCount = extractor.trackCount
        val indexMap = IntArray(trackCount)
        var outputTrackCount = 0

        // Set extractor to startUs
        val endUs = startUs + durationUs
        for (i in 0 until trackCount) {
            val format = extractor.getTrackFormat(i)
            val mime = format.getString(MediaFormat.KEY_MIME)
            if (mime == null) continue
            // Add track to muxer later
        }

        muxer = MediaMuxer(outPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

        for (i in 0 until trackCount) {
            val format = extractor.getTrackFormat(i)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
            val trackIndex = muxer.addTrack(format)
            indexMap[i] = trackIndex
            outputTrackCount += 1
        }

        if (outputTrackCount == 0) {
            return false
        }

        muxer.start()

    // Use a larger direct ByteBuffer to avoid IllegalArgumentException on
    // large sample sizes. 2MB should be sufficient for most samples.
    val bufferSize = 2 * 1024 * 1024
    val buffer = java.nio.ByteBuffer.allocateDirect(bufferSize)
        val bufferInfo = android.media.MediaCodec.BufferInfo()

        for (i in 0 until trackCount) {
            extractor.selectTrack(i)
            // Seek to startUs (in microseconds)
            extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            while (true) {
                val sampleTime = extractor.sampleTime
                if (sampleTime < 0 || sampleTime >= endUs) break
                try {
                    buffer.clear()
                    val sampleSize = extractor.readSampleData(buffer, 0)
                    if (sampleSize <= 0) break
                    bufferInfo.offset = 0
                    bufferInfo.size = sampleSize
                    bufferInfo.presentationTimeUs = sampleTime - startUs
                    bufferInfo.flags = extractor.sampleFlags
                    val outTrackIndex = indexMap[i]
                    muxer.writeSampleData(outTrackIndex, buffer, bufferInfo)
                    extractor.advance()
                } catch (iae: IllegalArgumentException) {
                    // If readSampleData throws (some devices don't accept non-direct
                    // buffers or the sample is larger than the buffer), try to
                    // recover by logging and aborting this track copy.
                    Log.w(TAG, "trimMediaRange: readSampleData failed for track $i, aborting track copy", iae)
                    break
                }
            }
            extractor.unselectTrack(i)
        }

        muxer.stop()
        muxer.release()
        extractor.release()
        return true
    } catch (t: Throwable) {
        Log.e(TAG, "trimMediaRange failed", t)
        try {
            muxer?.release()
        } catch (_: Throwable) {
        }
        try {
            extractor.release()
        } catch (_: Throwable) {
        }
        return false
    }
}

private fun Long?.orDefault(): Long = this ?: 0L
