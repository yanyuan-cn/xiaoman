package com.xiaoman.xiaoman

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import java.util.Calendar

/**
 * 每日记账提醒。
 *
 * 用 AlarmManager 排下一次，触发后由 ReminderReceiver 自己排下一天；
 * 不开前台服务、不引插件，进程死了也能响（AlarmManager 是系统级的）。
 */
object Reminder {
    private const val PREFS = "xiaoman_reminder"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_HOUR = "hour"
    private const val KEY_MINUTE = "minute"

    const val CHANNEL_ID = "xiaoman_daily"
    private const val REQ_ALARM = 4101
    private const val REQ_OPEN = 4103
    private const val NOTIFY_ID = 4102

    private fun prefs(ctx: Context) =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun isEnabled(ctx: Context): Boolean = prefs(ctx).getBoolean(KEY_ENABLED, false)

    fun hour(ctx: Context): Int = prefs(ctx).getInt(KEY_HOUR, 21)

    fun minute(ctx: Context): Int = prefs(ctx).getInt(KEY_MINUTE, 0)

    fun set(ctx: Context, enabled: Boolean, hour: Int, minute: Int) {
        prefs(ctx).edit()
            .putBoolean(KEY_ENABLED, enabled)
            .putInt(KEY_HOUR, hour)
            .putInt(KEY_MINUTE, minute)
            .apply()
        if (enabled) scheduleNext(ctx) else cancel(ctx)
    }

    private fun immutableFlag(): Int =
        if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0

    private fun alarmIntent(ctx: Context): PendingIntent {
        val i = Intent(ctx, ReminderReceiver::class.java)
        return PendingIntent.getBroadcast(
            ctx,
            REQ_ALARM,
            i,
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
        )
    }

    /** 下一次该响的时刻（毫秒）：今天这个点过了就排明天 */
    fun nextTriggerMs(hour: Int, minute: Int): Long {
        val target = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val now = Calendar.getInstance()
        if (!target.after(now)) target.add(Calendar.DAY_OF_YEAR, 1)
        return target.timeInMillis
    }

    fun scheduleNext(ctx: Context) {
        if (!isEnabled(ctx)) return
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val at = nextTriggerMs(hour(ctx), minute(ctx))
        val pi = alarmIntent(ctx)
        try {
            if (Build.VERSION.SDK_INT >= 31 && !am.canScheduleExactAlarms()) {
                // 没给精确闹钟权限就退化成不精确的，可能晚几分钟但一定会响
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            } else {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            }
        } catch (e: SecurityException) {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        }
    }

    fun cancel(ctx: Context) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        am.cancel(alarmIntent(ctx))
    }

    fun canExactAlarm(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT < 31) return true
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return false
        return am.canScheduleExactAlarms()
    }

    fun openExactAlarmSettings(ctx: Context) {
        if (Build.VERSION.SDK_INT < 31) return
        try {
            val i = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
            i.data = Uri.parse("package:${ctx.packageName}")
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ctx.startActivity(i)
        } catch (_: Exception) {
        }
    }

    private fun ensureChannel(ctx: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val ch = NotificationChannel(
            CHANNEL_ID,
            "记账提醒",
            NotificationManager.IMPORTANCE_HIGH
        )
        ch.description = "每天提醒你记一笔"
        nm.createNotificationChannel(ch)
    }

    fun notificationsEnabled(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT < 24) return true
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return false
        return nm.areNotificationsEnabled()
    }

    fun notifyNow(ctx: Context) {
        ensureChannel(ctx)
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return

        val open = Intent(ctx, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val pi = PendingIntent.getActivity(
            ctx,
            REQ_OPEN,
            open,
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
        )

        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(ctx, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(ctx)
        }

        val n = builder
            .setContentTitle("今天记一笔了吗？")
            .setContentText("点一下打开小满，30 秒就能记完")
            .setSmallIcon(notificationIcon(ctx))
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()

        try {
            nm.notify(NOTIFY_ID, n)
        } catch (_: Exception) {
        }
    }

    /** 应用图标做通知图标；个别 ROM 不认就用系统图标兜底，避免直接崩 */
    private fun notificationIcon(ctx: Context): Int {
        val own = ctx.applicationInfo.icon
        return if (own != 0) own else android.R.drawable.ic_dialog_info
    }
}

/** 到点响一次，然后排下一天 */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Reminder.notifyNow(context)
        Reminder.scheduleNext(context)
    }
}

/** 重启后闹钟会丢，这里补排 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (Reminder.isEnabled(context)) Reminder.scheduleNext(context)
    }
}
