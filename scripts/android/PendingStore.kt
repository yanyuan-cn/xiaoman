package com.xiaoman.xiaoman

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Capture queue for auto bookkeeping.
 *
 * Native side only stores RAW text; parsing lives in Dart so the rules are in
 * one place and unit-tested.
 *
 * `decision`:
 *   "pending"   - captured, waiting for the user to confirm in the app
 *   "confirmed" - user tapped 记下 in the floating window, insert silently
 *   "ignored"   - user tapped 忽略 (or it timed out), just drop it
 */
object PendingStore {
    private const val PREFS = "xiaoman_auto"
    private const val KEY_QUEUE = "pending"
    private const val KEY_NOTIF = "switch_notif"
    private const val KEY_SMS = "switch_sms"
    private const val KEY_ACCESS = "switch_access"
    private const val MAX = 60

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun switchOn(c: Context, key: String): Boolean = prefs(c).getBoolean(key, true)

    fun setSwitch(c: Context, key: String, on: Boolean) {
        prefs(c).edit().putBoolean(key, on).apply()
    }

    @Synchronized
    fun push(c: Context, source: String, raw: String, at: Long, decision: String = "pending") {
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
        item.put("decision", decision)
        arr.put(item)
        while (arr.length() > MAX) arr.remove(0)
        p.edit().putString(KEY_QUEUE, arr.toString()).apply()
    }

    /** 同一条内容在 [withinMs] 内已经抓过就不再抓（悬浮窗会重复触发）。 */
    @Synchronized
    fun hasRecent(c: Context, raw: String, withinMs: Long): Boolean {
        return try {
            val arr = JSONArray(prefs(c).getString(KEY_QUEUE, "[]"))
            val now = System.currentTimeMillis()
            for (i in arr.length() - 1 downTo 0) {
                val o = arr.getJSONObject(i)
                if (now - o.optLong("at") > withinMs) continue
                if (o.optString("raw") == raw) return true
            }
            false
        } catch (_: Exception) {
            false
        }
    }

    fun pending(c: Context): String = prefs(c).getString(KEY_QUEUE, "[]") ?: "[]"

    fun clear(c: Context) {
        prefs(c).edit().putString(KEY_QUEUE, "[]").apply()
    }
}
