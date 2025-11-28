package com.example.coalition_app_v2

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONObject

data class NativeTusRequest(
    val taskId: String,
    val uploadId: String,
    val filePath: String,
    val fileSize: Long,
    val fileName: String,
    val endpoint: String,
    val headers: Map<String, String>,
    val chunkSize: Int,
    val contentType: String,
    val description: String,
    val postType: String,
    val notificationTitle: String?,
    val notificationBody: String?,
    val metadata: Map<String, String>,
) {
    fun toJson(): String {
        val json = JSONObject()
        json.put("taskId", taskId)
        json.put("uploadId", uploadId)
        json.put("filePath", filePath)
        json.put("fileSize", fileSize)
        json.put("fileName", fileName)
        json.put("endpoint", endpoint)
        json.put("chunkSize", chunkSize)
        json.put("contentType", contentType)
        json.put("description", description)
        json.put("postType", postType)
        notificationTitle?.let { json.put("notificationTitle", it) }
        notificationBody?.let { json.put("notificationBody", it) }
        json.put("headers", JSONObject(headers))
        json.put("metadata", JSONObject(metadata))
        return json.toString()
    }

    companion object {
        fun fromMap(raw: Map<String, Any?>): NativeTusRequest {
            val headers = raw["headers"].asStringMap()
            val notification = (raw["notification"] as? Map<*, *>)?.asStringMap()
            val metadata = raw["metadata"].asStringMap()
            val chunkSize = (raw["chunkSize"] as? Number)?.toInt() ?: 8 * 1024 * 1024
            val fileSize = (raw["fileSize"] as? Number)?.toLong() ?: 0L
            return NativeTusRequest(
                taskId = raw["taskId"]?.toString().orEmpty(),
                uploadId = raw["uploadId"]?.toString().orEmpty(),
                filePath = raw["filePath"]?.toString().orEmpty(),
                fileSize = fileSize,
                fileName = raw["fileName"]?.toString().orEmpty(),
                endpoint = raw["endpoint"]?.toString().orEmpty(),
                headers = headers,
                chunkSize = chunkSize,
                contentType = raw["contentType"]?.toString().orEmpty(),
                description = raw["description"]?.toString().orEmpty(),
                postType = raw["postType"]?.toString().orEmpty(),
                notificationTitle = notification?.get("title"),
                notificationBody = notification?.get("body"),
                metadata = metadata,
            )
        }

        fun fromJson(json: String): NativeTusRequest {
            val obj = JSONObject(json)
            val headers = obj.optJSONObject("headers")?.toMap().orEmpty()
            val metadata = obj.optJSONObject("metadata")?.toMap().orEmpty()
            val title = if (obj.has("notificationTitle")) obj.getString("notificationTitle") else null
            val body = if (obj.has("notificationBody")) obj.getString("notificationBody") else null
            return NativeTusRequest(
                taskId = obj.getString("taskId"),
                uploadId = obj.getString("uploadId"),
                filePath = obj.getString("filePath"),
                fileSize = obj.optLong("fileSize", 0L),
                fileName = obj.optString("fileName"),
                endpoint = obj.getString("endpoint"),
                headers = headers,
                chunkSize = obj.optInt("chunkSize", 8 * 1024 * 1024),
                contentType = obj.optString("contentType"),
                description = obj.optString("description"),
                postType = obj.optString("postType"),
                notificationTitle = title,
                notificationBody = body,
                metadata = metadata,
            )
        }
    }
}

private fun Any?.asStringMap(): Map<String, String> {
    val map = this as? Map<*, *> ?: return emptyMap()
    val result = mutableMapOf<String, String>()
    for ((key, value) in map) {
        val stringKey = key?.toString() ?: continue
        val stringValue = value?.toString() ?: continue
        result[stringKey] = stringValue
    }
    return result
}

private fun JSONObject.toMap(): Map<String, String> {
    val map = mutableMapOf<String, String>()
    val iterator = keys()
    while (iterator.hasNext()) {
        val key = iterator.next()
        map[key] = optString(key)
    }
    return map
}

object TusUploadStore {
    private const val PREFS_NAME = "native_tus_uploads"

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun save(context: Context, request: NativeTusRequest) {
        prefs(context).edit().putString(request.taskId, request.toJson()).apply()
    }

    fun get(context: Context, taskId: String): NativeTusRequest? {
        val raw = prefs(context).getString(taskId, null) ?: return null
        return NativeTusRequest.fromJson(raw)
    }

    fun remove(context: Context, taskId: String) {
        prefs(context).edit().remove(taskId).apply()
    }
}
