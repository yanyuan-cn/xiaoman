package com.xiaoman.xiaoman

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Two native bridges:
 *  - "xiaoman/icon"      launcher icon switch (two activity-alias entries)
 *  - "xiaoman/reminder"  daily reminder (AlarmManager + NotificationManager)
 */
class MainActivity : FlutterActivity() {

    private val iconChannel = "xiaoman/icon"
    private val reminderChannel = "xiaoman/reminder"
    private val reqNotifications = 4201

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, iconChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "get" -> result.success(currentIcon())
                    "set" -> {
                        val id = call.argument<String>("id") ?: "d1"
                        applyIcon(id)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, reminderChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "get" -> result.success(
                        mapOf(
                            "enabled" to Reminder.isEnabled(this),
                            "hour" to Reminder.hour(this),
                            "minute" to Reminder.minute(this)
                        )
                    )
                    "set" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        val hour = call.argument<Int>("hour") ?: 21
                        val minute = call.argument<Int>("minute") ?: 0
                        Reminder.set(this, enabled, hour, minute)
                        result.success(true)
                    }
                    "notificationsEnabled" -> result.success(Reminder.notificationsEnabled(this))
                    "requestNotifications" -> {
                        if (Build.VERSION.SDK_INT >= 33) {
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), reqNotifications)
                        }
                        result.success(true)
                    }
                    "canExactAlarm" -> result.success(Reminder.canExactAlarm(this))
                    "openExactAlarmSettings" -> {
                        Reminder.openExactAlarmSettings(this)
                        result.success(true)
                    }
                    "test" -> {
                        Reminder.notifyNow(this)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // 开机/更新后把闹钟补上（应用被打开时也补一次，双保险）
        Reminder.scheduleNext(this)
    }

    // ---------------- launcher icon ----------------

    private fun prefs() =
        getSharedPreferences("xiaoman_icon", Context.MODE_PRIVATE)

    private fun currentIcon(): String = prefs().getString("icon", "d1") ?: "d1"

    private fun applyIcon(id: String) {
        val pm = packageManager
        val d1 = ComponentName(this, "$packageName.LauncherD1")
        val d3 = ComponentName(this, "$packageName.LauncherD3")
        val target = if (id == "d3") d3 else d1
        val other = if (id == "d3") d1 else d3

        // Enable the target before disabling the other, so the launcher never
        // ends up with zero entries.
        pm.setComponentEnabledSetting(
            target,
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP
        )
        pm.setComponentEnabledSetting(
            other,
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP
        )
        prefs().edit().putString("icon", id).apply()
    }
}
