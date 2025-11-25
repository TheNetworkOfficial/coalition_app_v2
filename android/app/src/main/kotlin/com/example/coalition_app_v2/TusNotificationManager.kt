package com.example.coalition_app_v2

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.work.ForegroundInfo

object TusNotificationManager {
    const val UPLOAD_CHANNEL_ID = "native_uploads"
    private const val CHANNEL_NAME = "Uploads"
    private const val CHANNEL_DESCRIPTION = "Background uploads and processing progress."

    private fun notificationManager(context: Context): NotificationManagerCompat {
        ensureUploadChannel(context)
        return NotificationManagerCompat.from(context)
    }

    @JvmStatic
    fun ensureUploadChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(UPLOAD_CHANNEL_ID) == null) {
            val channel = NotificationChannel(
                UPLOAD_CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW,
            )
            channel.description = CHANNEL_DESCRIPTION
            channel.enableVibration(false)
            channel.setShowBadge(false)
            manager.createNotificationChannel(channel)
        }
    }

    fun foregroundInfo(
        context: Context,
        request: NativeTusRequest,
        sent: Long,
        total: Long,
    ): ForegroundInfo {
        val notification = buildBaseNotification(context, request)
            .setContentText(progressLabel(sent, total, request))
            .setProgress(
                if (total > Int.MAX_VALUE) Int.MAX_VALUE else total.toInt(),
                if (sent > Int.MAX_VALUE) Int.MAX_VALUE else sent.toInt(),
                total <= 0,
            )
            .setOngoing(true)
            .build()
        return ForegroundInfo(notificationId(request.taskId), notification)
    }

    fun showProcessing(context: Context, request: NativeTusRequest) {
        val notification = buildBaseNotification(context, request)
            .setContentTitle("Processing video…")
            .setContentText("We’ll notify you when it is ready.")
            .setProgress(0, 0, true)
            .setOngoing(true)
            .build()
        notificationManager(context).notify(notificationId(request.taskId), notification)
    }

    fun showSuccess(context: Context, request: NativeTusRequest, message: String) {
        val notification = buildBaseNotification(context, request)
            .setContentTitle("Post successful")
            .setContentText(message)
            .setOngoing(false)
            .setAutoCancel(true)
            .setProgress(0, 0, false)
            .build()
        notificationManager(context).notify(notificationId(request.taskId), notification)
        TusUploadStore.remove(context, request.taskId)
    }

    fun cancel(context: Context, taskId: String) {
        notificationManager(context).cancel(notificationId(taskId))
    }

    private fun buildBaseNotification(
        context: Context,
        request: NativeTusRequest,
    ): NotificationCompat.Builder {
        ensureUploadChannel(context)
        return NotificationCompat.Builder(context, UPLOAD_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setContentTitle(request.notificationTitle ?: "Uploading media")
            .setContentText(request.notificationBody ?: request.description)
    }

    private fun progressLabel(sent: Long, total: Long, request: NativeTusRequest): String {
        if (total <= 0) {
            return "Uploading ${request.postType}"
        }
        val percent = (sent.toDouble() / total.toDouble()).coerceIn(0.0, 1.0) * 100
        return "Uploading ${percent.toInt()}%"
    }

    fun notificationId(taskId: String): Int = taskId.hashCode()
}
