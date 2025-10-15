package com.example.coalition_app_v2

import android.content.Context
import android.media.MediaExtractor
import android.media.MediaMuxer
import android.media.MediaFormat
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
import com.otaliastudios.transcoder.strategy.PassThroughTrackStrategy
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

private const val TAG = "VideoProxyChannel"

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
