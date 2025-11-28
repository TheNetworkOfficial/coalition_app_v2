package com.example.coalition_app_v2.editor

import androidx.media3.transformer.Effects
import org.json.JSONArray
import org.json.JSONObject

data class TimelineConfig(
    val trimStartMs: Long?,
    val trimEndMs: Long?,
    val speed: Float,
    val rotationDegrees: Float,
    val effects: Effects,
)

class EffectBuilder {
    fun parseTimeline(json: String?): TimelineConfig {
        if (json.isNullOrEmpty()) {
            return TimelineConfig(null, null, 1f, 0f, Effects.EMPTY)
        }
        val root = JSONObject(json)
        val ops = root.optJSONArray("ops") ?: JSONArray()
        var trimStart: Long? = null
        var trimEnd: Long? = null
        var speed = 1f
        var rotationTurns = 0
        for (i in 0 until ops.length()) {
            val entry = ops.optJSONObject(i) ?: continue
            when (entry.optString("type")) {
                "trim" -> {
                    trimStart = entry.optLong("startMs")
                    trimEnd = entry.optLong("endMs")
                }
                "speed" -> {
                    val factor = entry.optDouble("factor", 1.0)
                    if (factor > 0) {
                        speed = factor.toFloat()
                    }
                }
                "rotate" -> rotationTurns = entry.optInt("turns")
            }
        }
        val normalizedTurns = ((rotationTurns % 4) + 4) % 4
        return TimelineConfig(
            trimStart,
            trimEnd,
            speed,
            normalizedTurns * 90f,
            Effects.EMPTY,
        )
    }
}
