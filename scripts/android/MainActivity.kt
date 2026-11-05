package com.xiaoman.xiaoman

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Native bridge:
 *  - "xiaoman/icon"  launcher icon switch (two activity-alias entries)
 */
class MainActivity : FlutterActivity() {

    private val iconChannel = "xiaoman/icon"

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
