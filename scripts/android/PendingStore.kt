package com.xiaoman.xiaoman

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Capture queue for auto bookkeeping.
 *
 * Native side only stores RAW text (package + title + body). All parsing happens
 * in Dart so the rules live in one place and are covered by unit tests.
 *
 * Queue is capped so a chatty phone cannot grow it without bound.
 */
object PendingStore {
    private const val PREFS = "xiaoman_auto"
    private const val KEY_QUEUE = "pending"
    private const val KEY_NOTIF = "switch_notif"
    private const val KEY_SMS = "switch_sms"
    private const val MAX = 60

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun switchOn(c: Context, key: String): Boolean = prefs(c).getBoolean(key, true)

    fun setSwitch(c: Context, key: String, on: Boolean) {
        prefs(c).edit().putBoolean(key, on).apply()
    }

    fun push(c: Context, source: String, raw: String, at: Long) {
        val p = prefs(c)
        val arr = try {
            JSONArray(p.getString(KEY_QUEUE, "[]"))
        } catch (_: Exception) {
            JSONArray()
        }
        val item = JSONObject()
        item.put("source", source)
        item.put("raw", raw)
        item.put("at", at)
        arr.put(item)
        while (arr.length() > MAX) arr.remove(0)
        p.edit().putString(KEY_QUEUE, arr.toString()).apply()
    }

    fun pending(c: Context): String = prefs(c).getString(KEY_QUEUE, "[]") ?: "[]"

    fun clear(c: Context) {
        prefs(c).edit().putString(KEY_QUEUE, "[]").apply()
    }
}
