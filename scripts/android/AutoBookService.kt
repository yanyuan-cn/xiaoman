package com.xiaoman.xiaoman

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Reads payment notifications from a small whitelist of apps.
 *
 * Requires the user to grant "notification access" in system settings; the app
 * checks `AutoBookStatus.notificationAccess` before showing the switch as on.
 */
class AutoBookService : NotificationListenerService() {

    companion object {
        // 支付宝、微信、常见银行/云闪付
        private val SOURCES = setOf(
            "com.eg.android.AlipayGphone",   // 支付宝
            "com.tencent.mm",                // 微信
            "com.unionpay",                  // 云闪付
            "cmb.pb",                        // 招商银行
            "com.icbc",                      // 工商银行
            "com.chinamworld.main",          // 建设银行
            "com.android.bankabc",           // 农业银行
            "com.bankcomm.Bankcomm",         // 交通银行
            "com.cmbchina.ccd.pluto.cmbActivity"
        )
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val notification = sbn ?: return
        if (!PendingStore.switchOn(this, "switch_notif")) return
        if (!SOURCES.contains(notification.packageName)) return

        val extras = notification.notification?.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val body = (
            extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
                ?: extras.getCharSequence(Notification.EXTRA_TEXT)
                ?: notification.notification?.tickerText
            )?.toString().orEmpty()

        if (title.isEmpty() && body.isEmpty()) return
        val merged = "$title $body".trim()
        if (!AutoFilter.looksLikePayment(merged)) return

        PendingStore.push(this, "notification", merged, System.currentTimeMillis())
    }
}
