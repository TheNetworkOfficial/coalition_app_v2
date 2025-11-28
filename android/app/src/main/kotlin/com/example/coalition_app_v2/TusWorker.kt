package com.example.coalition_app_v2

import android.app.Notification
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.ServiceInfo
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
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
import java.net.MalformedURLException
import java.net.URL
import org.json.JSONException
import org.json.JSONObject
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
    private const val DEFAULT_CHUNK_BYTES = 8 * 1024 * 1024
    private const val TAG = "TusWorker"
    const val KEY_FILE_PATH = "filePath"
    const val KEY_ENDPOINT  = "endpoint"
    const val KEY_TASK_ID   = "taskId"
    const val KEY_HEADERS   = "headersJson"
    const val KEY_METADATA  = "metadata" // optional
    const val KEY_CHUNK_SIZE = "chunkSize"
    const val PROGRESS_BYTES_UPLOADED = "bytesUploaded"
    const val PROGRESS_BYTES_TOTAL    = "bytesTotal"
    private const val UPLOAD_NOTIFICATION_ID = 0x74555 // arbitrary
  }

  override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
    // Ensure typed foreground service before touching network I/O.
    setForeground(buildTypedForegroundInfo())

    val taskId = inputData.getString(KEY_TASK_ID)
    val path = inputData.getString(KEY_FILE_PATH)
    val endpoint = inputData.getString(KEY_ENDPOINT)

    if (taskId.isNullOrEmpty() || path.isNullOrEmpty() || endpoint.isNullOrEmpty()) {
      return@withContext Result.failure()
    }

    val file = File(path)
    if (!file.exists() || !file.isFile) {
      emitTusEvent(taskId, "failed", 0, 0, "File missing")
      return@withContext Result.failure()
    }

    val headers = parseJsonMap(inputData.getString(KEY_HEADERS))
      // TusClient injects Tus-Resumable, so strip any duplicates from the payload.
      .filterKeys { !it.equals("Tus-Resumable", ignoreCase = true) }
    val metadata = parseJsonMap(inputData.getString(KEY_METADATA))
    val chunkSize =
      inputData.getLong(KEY_CHUNK_SIZE, DEFAULT_CHUNK_BYTES.toLong())
        .coerceAtLeast(64 * 1024)
        .coerceAtMost(Int.MAX_VALUE.toLong())
        .toInt()

    val uploadUrl = try {
      URL(endpoint)
    } catch (error: MalformedURLException) {
      val message = "Invalid upload endpoint"
      Log.e(TAG, "$message: $endpoint", error)
      emitTusEvent(taskId, "failed", 0, 0, message)
      return@withContext Result.failure(
        workDataOf("error" to message)
      )
    }

    val prefs: SharedPreferences =
      applicationContext.getSharedPreferences("tus", Context.MODE_PRIVATE)
    val urlStore = TusPreferencesURLStore(prefs)
    val client = TusClient()

    val upload = TusUpload(file).apply {
      if (metadata.isNotEmpty()) {
        setMetadata(metadata)
      }
    }
    upload.fingerprint?.let { fingerprint ->
      urlStore.set(fingerprint, uploadUrl)
    } ?: Log.w(TAG, "Missing fingerprint for $path; resume support disabled for this upload")
    val totalBytes = upload.size.takeIf { it > 0 } ?: file.length()
    client.enableResuming(urlStore)
    client.setHeaders(headers)
    var lastBytesSent = 0L

    try {
      val executor = object : TusExecutor() {
        @Throws(ProtocolException::class, IOException::class)
        override fun makeAttempt() {
          val uploader = client.resumeUpload(upload)
          // Honor chunk size negotiated on the Dart side.
          uploader.setChunkSize(chunkSize)
          fun notifyProgress() {
            lastBytesSent = uploader.offset
            runBlocking {
              this@TusWorker.setProgress(
                workDataOf(
                  PROGRESS_BYTES_UPLOADED to uploader.offset,
                  PROGRESS_BYTES_TOTAL to totalBytes,
                )
              )
            }
            emitTusEvent(taskId, "running", uploader.offset, totalBytes)
          }

          notifyProgress()

          var chunk: Int
          do {
            chunk = uploader.uploadChunk()
            if (chunk > 0) {
              notifyProgress()
            }
          } while (chunk > -1)

          uploader.finish()
        }
      }

      executor.makeAttempts()
      emitTusEvent(taskId, "uploaded", totalBytes, totalBytes)
      Result.success(
        workDataOf(
          PROGRESS_BYTES_UPLOADED to totalBytes,
          PROGRESS_BYTES_TOTAL to totalBytes,
        )
      )
    } catch (e: ProtocolException) {
      val errorMessage = e.message ?: "Protocol error"
      Log.e(TAG, "Protocol error for task=$taskId: $errorMessage", e)
      emitTusEvent(taskId, "failed", lastBytesSent, totalBytes, errorMessage)
      Result.failure(
        workDataOf("error" to errorMessage)
      )
    } catch (e: IOException) {
      val errorMessage = e.message ?: "IO error"
      Log.w(TAG, "IO error during upload task=$taskId, will retry: $errorMessage", e)
      Result.retry()
    } catch (e: Exception) {
      val errorMessage = e.message ?: e::class.java.simpleName
      Log.e(TAG, "Unexpected error for task=$taskId: $errorMessage", e)
      emitTusEvent(taskId, "failed", lastBytesSent, totalBytes, errorMessage)
      Result.failure(
        workDataOf("error" to errorMessage)
      )
    }
  }

  override suspend fun getForegroundInfo(): ForegroundInfo = buildTypedForegroundInfo()

  private fun buildUploadNotification(): Notification {
    TusNotificationManager.ensureUploadChannel(applicationContext)

    return NotificationCompat.Builder(applicationContext, TusNotificationManager.UPLOAD_CHANNEL_ID)
      .setSmallIcon(android.R.drawable.stat_sys_upload)
      .setContentTitle("Uploading video")
      .setContentText("Uploading in background…")
      .setOngoing(true)
      .setOnlyAlertOnce(true)
      .build()
  }

  private fun buildTypedForegroundInfo(): ForegroundInfo {
    val notification = buildUploadNotification()
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      ForegroundInfo(
        UPLOAD_NOTIFICATION_ID,
        notification,
        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
      )
    } else {
      ForegroundInfo(UPLOAD_NOTIFICATION_ID, notification)
    }
  }

  private fun emitTusEvent(
    taskId: String,
    state: String,
    sent: Long,
    total: Long,
    error: String? = null,
  ) {
    val intent = Intent(TusUploadChannel.ACTION_EVENT).apply {
      `package` = applicationContext.packageName
      putExtra(TusUploadChannel.EXTRA_TASK_ID, taskId)
      putExtra(TusUploadChannel.EXTRA_STATE, state)
      putExtra(TusUploadChannel.EXTRA_BYTES_SENT, sent)
      putExtra(TusUploadChannel.EXTRA_BYTES_TOTAL, total)
      if (!error.isNullOrEmpty()) {
        putExtra(TusUploadChannel.EXTRA_ERROR, error)
      }
    }
    applicationContext.sendBroadcast(intent)
  }

  private fun parseJsonMap(json: String?): Map<String, String> {
    if (json.isNullOrEmpty()) {
      return emptyMap()
    }
    return try {
      val obj = JSONObject(json)
      val result = mutableMapOf<String, String>()
      val keys = obj.keys()
      while (keys.hasNext()) {
        val key = keys.next()
        result[key] = obj.optString(key)
      }
      result
    } catch (error: JSONException) {
      emptyMap()
    }
  }
}
