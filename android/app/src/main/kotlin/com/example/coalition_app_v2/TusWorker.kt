package com.example.coalition_app_v2

import android.content.Context
import android.content.SharedPreferences
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.Data
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import io.tus.android.client.TusPreferencesURLStore
import io.tus.java.client.ProtocolException
import io.tus.java.client.TusClient
import io.tus.java.client.TusExecutor
import io.tus.java.client.TusUpload
import java.io.File
import java.io.IOException
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext

/**
 * Background TUS uploader driven by WorkManager.
 * Inputs: filePath (String), endpoint (String), metadata (String? JSON base64 or key=value CSV).
 * Outputs (progress via setProgress): bytesUploaded, bytesTotal
 */
class TusWorker(
  appContext: Context,
  params: WorkerParameters,
) : CoroutineWorker(appContext, params) {

  companion object {
    const val KEY_FILE_PATH = "filePath"
    const val KEY_ENDPOINT  = "endpoint"
    const val KEY_METADATA  = "metadata" // optional
    const val PROGRESS_BYTES_UPLOADED = "bytesUploaded"
    const val PROGRESS_BYTES_TOTAL    = "bytesTotal"
    private const val NOTIF_CHANNEL_ID = "uploads"
    private const val NOTIF_ID = 0x74555 // arbitrary
  }

  override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
    // Ensure foreground to keep running under background constraints.
    setForeground(getForegroundInfo())

    val path = inputData.getString(KEY_FILE_PATH) ?: return@withContext Result.failure()
    val endpoint = inputData.getString(KEY_ENDPOINT) ?: return@withContext Result.failure()
    val file = File(path)
    if (!file.exists() || !file.isFile) return@withContext Result.failure()

    val client = TusClient().apply {
      uploadCreationURL = URL(endpoint)
      // Persist upload URLs for resume support (SharedPreferences required).
      val prefs: SharedPreferences =
        applicationContext.getSharedPreferences("tus", Context.MODE_PRIVATE)
      enableResuming(TusPreferencesURLStore(prefs))
    }

    val upload = TusUpload(file).apply {
      // Optional per-server metadata format; safe to omit.
      inputData.getString(KEY_METADATA)?.let { meta ->
        // TusUpload#setMetadata expects key=value pairs; keep as-is if provided by caller.
        setMetadata(mapOf("meta" to meta))
      }
    }

    try {
      val executor = object : TusExecutor() {
        @Throws(ProtocolException::class, IOException::class)
        override fun makeAttempt() {
          val uploader = client.resumeOrCreateUpload(upload)
          // 8 MiB chunks match our dio fallback and TUS server defaults.
          uploader.setChunkSize(8 * 1024 * 1024)

          var chunk: Int
          do {
            chunk = uploader.uploadChunk()
            if (chunk > 0) {
              // Report progress via suspend setProgress to avoid ListenableFuture APIs
              runBlocking {
                this@TusWorker.setProgress(
                  workDataOf(
                    PROGRESS_BYTES_UPLOADED to uploader.offset,
                    PROGRESS_BYTES_TOTAL to upload.size,
                  )
                )
              }
            }
          } while (chunk > -1)

          uploader.finish()
        }
      }

      executor.makeAttempts()
      Result.success(
        workDataOf(
          PROGRESS_BYTES_UPLOADED to upload.size,
          PROGRESS_BYTES_TOTAL to upload.size,
        )
      )
    } catch (e: Exception) {
      // Protocol issues: retry is reasonable; IO/network: retry; otherwise fail.
      when (e) {
        is ProtocolException, is IOException -> Result.retry()
        else -> Result.failure(
          workDataOf("error" to (e.message ?: e::class.java.simpleName))
        )
      }
    }
  }

  override suspend fun getForegroundInfo(): ForegroundInfo {
    // Minimal ongoing notification; Notification channel "uploads" must exist (created in Flutter side).
    val notification = NotificationCompat.Builder(applicationContext, NOTIF_CHANNEL_ID)
      .setSmallIcon(android.R.drawable.stat_sys_upload)
      .setContentTitle("Uploading video")
      .setOngoing(true)
      .build()
    return ForegroundInfo(NOTIF_ID, notification)
  }
}
