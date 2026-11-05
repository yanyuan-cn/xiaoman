package com.xiaoman.xiaoman

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Two native bridges:
 *  - "xiaoman/icon"      launcher icon switch (two activity-alias entries)
 *  - "xiaoman/autobook"  auto bookkeeping: notification listener + SMS receiver
 */
class MainActivity : FlutterActivity() {

    private val iconChannel = "xiaoman/icon"
    private val autoChannel = "xiaoman/autobook"

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, autoChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPending" -> result.success(PendingStore.pending(this))
                    "clearPending" -> {
                        PendingStore.clear(this)
                        result.success(true)
                    }
                    "notificationAccess" -> result.success(hasNotificationAccess())
                    "openNotificationSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(true)
                    }
                    "hasSmsPermission" -> result.success(
                        checkSelfPermission(Manifest.permission.RECEIVE_SMS) ==
                            PackageManager.PERMISSION_GRANTED
                    )
                    "requestSmsPermission" -> {
                        requestPermissions(arrayOf(Manifest.permission.RECEIVE_SMS), 1001)
                        result.success(true)
                    }
                    "openAppSettings" -> {
                        val intent = Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.fromParts("package", packageName, null)
                        )
                        startActivity(intent)
                        result.success(true)
                    }
                    "getSwitch" -> {
                        val key = call.argument<String>("key") ?: ""
                        result.success(PendingStore.switchOn(this, key))
                    }
                    "setSwitch" -> {
                        val key = call.argument<String>("key") ?: ""
                        val on = call.argument<Boolean>("on") ?: true
                        PendingStore.setSwitch(this, key, on)
                        result.success(true)
                    }
                    "accessibilityEnabled" -> result.success(hasAccessibility())
                    "openAccessibilitySettings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(true)
                    }
                    "hasOverlayPermission" -> result.success(Settings.canDrawOverlays(this))
                    "openOverlaySettings" -> {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
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

    // ---------------- auto bookkeeping ----------------

    private fun hasNotificationAccess(): Boolean {
        val flat = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners"
        ) ?: return false
        return flat.contains(packageName)
    }

    /** 无障碍服务是否已被系统启用（用户可能在系统设置里关掉）。 */
    private fun hasAccessibility(): Boolean {
        val am = getSystemService(Context.ACCESSIBILITY_SERVICE)
            as? android.view.accessibility.AccessibilityManager ?: return false
        val services = am.getEnabledAccessibilityServiceList(
            android.accessibilityservice.AccessibilityServiceInfo.FEEDBACK_ALL_MASK
        )
        return services.any {
            it.resolveInfo?.serviceInfo?.packageName == packageName
        }
    }
}
