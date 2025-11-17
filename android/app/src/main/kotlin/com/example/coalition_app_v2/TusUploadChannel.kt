package com.example.coalition_app_v2

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import androidx.core.content.ContextCompat
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class TusUploadChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val METHOD_CHANNEL = "coalition/native_tus"
        private const val EVENT_CHANNEL = "coalition/native_tus/events"
        const val ACTION_EVENT = "com.example.coalition_app_v2.TUS_EVENT"
        const val EXTRA_TASK_ID = "taskId"
        const val EXTRA_STATE = "state"
        const val EXTRA_BYTES_SENT = "bytesSent"
        const val EXTRA_BYTES_TOTAL = "bytesTotal"
        const val EXTRA_ERROR = "error"
    }

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val workManager = WorkManager.getInstance(context)

    private var eventSink: EventChannel.EventSink? = null
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            if (intent == null) return
            val taskId = intent.getStringExtra(EXTRA_TASK_ID) ?: return
            val payload = mapOf(
                "taskId" to taskId,
                "state" to intent.getStringExtra(EXTRA_STATE),
                "bytesSent" to intent.getLongExtra(EXTRA_BYTES_SENT, 0),
                "bytesTotal" to intent.getLongExtra(EXTRA_BYTES_TOTAL, 0),
                "error" to intent.getStringExtra(EXTRA_ERROR),
            )
            eventSink?.success(payload)
        }
    }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        ContextCompat.registerReceiver(
            context,
            receiver,
            IntentFilter(ACTION_EVENT),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "enqueueTusUpload" -> handleEnqueue(call, result)
            "cancelTusUpload" -> handleCancel(call, result)
            "markPostReady" -> handleMarkReady(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleEnqueue(call: MethodCall, result: MethodChannel.Result) {
        val raw = call.arguments
        if (raw !is Map<*, *>) {
            result.error("invalid_args", "Request payload missing", null)
            return
        }
        val request = NativeTusRequest.fromMap(raw as Map<String, Any?>)
        if (request.taskId.isEmpty() || request.endpoint.isEmpty()) {
            result.error("invalid_args", "taskId/endpoint required", null)
            return
        }

        TusUploadStore.save(context, request)
        val metadataString = if (request.metadata.isNotEmpty()) {
            JSONObject(request.metadata as Map<*, *>).toString()
        } else {
            null
        }
        val dataBuilder = Data.Builder()
            .putString(TusWorker.KEY_FILE_PATH, request.filePath)
            .putString(TusWorker.KEY_ENDPOINT, request.endpoint)
        metadataString?.let { dataBuilder.putString(TusWorker.KEY_METADATA, it) }
        val data = dataBuilder.build()
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()
        val work = OneTimeWorkRequestBuilder<TusWorker>()
            .setInputData(data)
            .setConstraints(constraints)
            .addTag(request.taskId)
            .build()
        workManager.enqueueUniqueWork(
            request.taskId,
            ExistingWorkPolicy.REPLACE,
            work,
        )
        emitLocalEvent(request.taskId, "queued", 0, request.fileSize)
        result.success(request.taskId)
    }

    private fun handleCancel(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        val taskId = args?.get("taskId")?.toString()
        if (taskId.isNullOrEmpty()) {
            result.error("invalid_args", "taskId missing", null)
            return
        }
        workManager.cancelUniqueWork(taskId)
        UploadNotificationManager.cancel(context, taskId)
        emitLocalEvent(taskId, "canceled", 0, 0)
        TusUploadStore.remove(context, taskId)
        result.success(null)
    }

    private fun handleMarkReady(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        val taskId = args?.get("taskId")?.toString()
        val message = args?.get("message")?.toString() ?: "Video ready"
        if (taskId.isNullOrEmpty()) {
            result.error("invalid_args", "taskId missing", null)
            return
        }
        val request = TusUploadStore.get(context, taskId)
        if (request != null) {
            UploadNotificationManager.showSuccess(context, request, message)
        } else {
            UploadNotificationManager.cancel(context, taskId)
        }
        result.success(null)
    }

    private fun emitLocalEvent(
        taskId: String,
        state: String,
        sent: Long,
        total: Long,
    ) {
        val payload = mapOf(
            "taskId" to taskId,
            "state" to state,
            "bytesSent" to sent,
            "bytesTotal" to total,
        )
        eventSink?.success(payload)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun dispose() {
        context.unregisterReceiver(receiver)
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }
}
