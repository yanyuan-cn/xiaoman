package com.xiaoman.xiaoman

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

/**
 * Bank / payment SMS. Only queued when the SMS switch is on and the text looks
 * like a transaction; parsing happens in Dart.
 */
class SmsReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context?, intent: Intent?) {
        val ctx = context ?: return
        val action = intent?.action ?: return
        if (action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        if (!PendingStore.switchOn(ctx, "switch_sms")) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        if (messages.isEmpty()) return

        val body = buildString {
            for (m in messages) append(m.messageBody ?: "")
        }
        if (body.isBlank()) return

        val sender = messages.firstOrNull()?.originatingAddress.orEmpty()
        if (!AutoFilter.looksLikePayment(body)) return

        PendingStore.push(ctx, "sms", "【$sender】$body", System.currentTimeMillis())
    }
}
