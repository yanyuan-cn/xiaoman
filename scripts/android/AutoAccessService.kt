package com.xiaoman.xiaoman

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * 无障碍识别支付结果页。
 *
 * 微信支付成功后**不会发通知**，所以只能读屏。范围限定微信/支付宝，
 * 以及「从微信/支付宝切回调用方 App」后 25 秒内的页面（微信/支付宝 SDK 支付完
 * 会回到商户 App 显示「支付成功」，这种也要能抓到）。
 *
 * 弹窗故意延迟 [POPUP_DELAY_MS]，避免支付刚完成就盖一层悬浮窗被风控判定为异常。
 */
class AutoAccessService : AccessibilityService() {

    companion object {
        private const val WECHAT = "com.tencent.mm"
        private const val ALIPAY = "com.eg.android.AlipayGphone"

        /** 支付完成后等多久再弹窗：一木也是延迟弹，太即时反而容易被判定异常 */
        private const val POPUP_DELAY_MS = 1600L

        /** 从微信/支付宝切走后，多久内还认为「可能刚付完款」 */
        private const val SDK_RETURN_WINDOW_MS = 25000L

        private const val DEDUPE_MS = 90000L
        private const val AUTO_DISMISS_MS = 12000L

        private val SUCCESS_WORDS = arrayOf(
            "支付成功", "付款成功", "交易成功", "已支付", "支付完成",
            "转账成功", "收款成功", "付款完成"
        )

        private val AMOUNT = Regex(
            "(?:[¥￥]\\s?(\\d+(?:\\.\\d{1,2})?))" +
                "|(?:(\\d+(?:\\.\\d{1,2})?)\\s?元)"
        )
    }

    private val handler = Handler(Looper.getMainLooper())
    private var lastPayAppAt = 0L
    private var overlay: View? = null
    private var overlayTimer: Runnable? = null

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val e = event ?: return
        val pkg = e.packageName?.toString() ?: return
        if (!PendingStore.switchOn(this, "switch_access")) return

        val now = System.currentTimeMillis()
        if (pkg == WECHAT || pkg == ALIPAY) {
            lastPayAppAt = now
        } else if (now - lastPayAppAt > SDK_RETURN_WINDOW_MS) {
            // 和微信/支付宝无关的页面，忽略
            return
        }

        if (e.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            e.eventType != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
        ) return

        val root = rootInActiveWindow ?: return
        val texts = ArrayList<String>(32)
        collectText(root, texts, 0)
        if (texts.isEmpty()) return

        val joined = TextUtils.join(" ", texts)
        if (!looksLikeSuccess(joined)) return

        val cents = parseAmountCents(joined) ?: return
        val merchant = pickMerchant(texts, pkg)
        val raw = buildRaw(pkg, texts)

        if (PendingStore.hasRecent(this, raw, DEDUPE_MS)) return

        // 延迟弹出，避免支付刚结束就出现悬浮窗
        handler.postDelayed({
            offerBill(cents, merchant, raw, now)
        }, POPUP_DELAY_MS)
    }

    // ---------------- 识别 ----------------

    private fun collectText(node: AccessibilityNodeInfo?, out: MutableList<String>, depth: Int) {
        if (node == null || depth > 25 || out.size > 80) return
        val t = node.text?.toString()?.trim().orEmpty()
        if (t.isNotEmpty() && t.length <= 60) out.add(t)
        val d = node.contentDescription?.toString()?.trim().orEmpty()
        if (d.isNotEmpty() && d.length <= 60 && d != t) out.add(d)
        for (i in 0 until node.childCount) {
            collectText(node.getChild(i), out, depth + 1)
        }
    }

    private fun looksLikeSuccess(text: String): Boolean =
        SUCCESS_WORDS.any { text.contains(it) }

    private fun parseAmountCents(text: String): Int? {
        for (m in AMOUNT.findAll(text)) {
            val s = m.groupValues.getOrNull(1)?.takeIf { it.isNotEmpty() }
                ?: m.groupValues.getOrNull(2)?.takeIf { it.isNotEmpty() }
                ?: continue
            val parts = s.split(".")
            val yuan = parts[0].toLongOrNull() ?: continue
            val cents = if (parts.size > 1) (parts[1] + "00").substring(0, 2).toInt() else 0
            val total = yuan * 100 + cents
            // 过滤明显不是交易的数字（页码、版本号、额度）
            if (total in 1..100_000_00) return total.toInt()
        }
        return null
    }

    /** 收款方 / 商户 一般紧跟在「收款方」标签后面，取不到就退回 App 名。 */
    private fun pickMerchant(texts: List<String>, pkg: String): String? {
        for (i in texts.indices) {
            val t = texts[i]
            if (t.startsWith("收款方") || t.startsWith("商户") || t.startsWith("转账给")) {
                val inline = t.substringAfter("：").substringAfter(":").trim()
                if (inline.isNotEmpty() && inline.length <= 24) return inline
                if (i + 1 < texts.size) {
                    val next = texts[i + 1].trim()
                    if (next.isNotEmpty() && next.length <= 24) return next
                }
            }
        }
        return if (pkg == WECHAT) "微信支付" else if (pkg == ALIPAY) "支付宝" else null
    }

    private fun buildRaw(pkg: String, texts: List<String>): String {
        val app = if (pkg == WECHAT) "微信" else if (pkg == ALIPAY) "支付宝" else pkg
        val head = texts.take(6).joinToString(" ")
        return "$app 支付成功 $head"
    }

    // ---------------- 悬浮窗 ----------------

    private fun offerBill(cents: Int, merchant: String?, raw: String, at: Long) {
        if (overlay != null) return // 已经有一个在显示
        if (!Settings.canDrawOverlays(this)) {
            // 没有悬浮窗权限：直接进待确认队列，不打扰
            PendingStore.push(this, "access", raw, at, "pending")
            return
        }
        showOverlay(cents, merchant, raw, at)
    }

    private fun showOverlay(cents: Int, merchant: String?, raw: String, at: Long) {
        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager

        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(14), dp(16), dp(10))
            background = GradientDrawable().apply {
                cornerRadius = dp(18).toFloat()
                setColor(Color.parseColor("#1F4C37"))
            }
        }

        card.addView(TextView(this).apply {
            text = "识别到一笔支出"
            setTextColor(Color.parseColor("#9EFFFFFF"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
        })

        card.addView(TextView(this).apply {
            text = "¥" + formatCents(cents)
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
            setPadding(0, dp(4), 0, 0)
        })

        card.addView(TextView(this).apply {
            text = merchant ?: "未识别商户"
            setTextColor(Color.parseColor("#CFFFFFFF"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            setPadding(0, dp(2), 0, dp(6))
        })

        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END
        }

        row.addView(Button(this).apply {
            text = "忽略"
            isAllCaps = false
            setTextColor(Color.parseColor("#CFFFFFFF"))
            background = GradientDrawable().apply {
                cornerRadius = dp(10).toFloat()
                setColor(Color.parseColor("#33FFFFFF"))
            }
            setOnClickListener {
                PendingStore.push(this@AutoAccessService, "access", raw, at, "ignored")
                dismissOverlay()
            }
        })

        row.addView(Button(this).apply {
            text = "记下"
            isAllCaps = false
            setTextColor(Color.parseColor("#12321F"))
            background = GradientDrawable().apply {
                cornerRadius = dp(10).toFloat()
                setColor(Color.parseColor("#F0D7A6"))
            }
            setOnClickListener {
                PendingStore.push(this@AutoAccessService, "access", raw, at, "confirmed")
                dismissOverlay()
            }
        })

        card.addView(row)

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = dp(96)
        }

        try {
            wm.addView(card, params)
            overlay = card
            val dismiss = Runnable { dismissOverlay(auto = true) }
            overlayTimer = dismiss
            handler.postDelayed(dismiss, AUTO_DISMISS_MS.toLong())
        } catch (_: Exception) {
            // 某些 ROM 会拒绝悬浮窗，退回队列
            PendingStore.push(this, "access", raw, at, "pending")
        }
    }

    private fun dismissOverlay(auto: Boolean = false) {
        val v = overlay ?: return
        overlay = null
        overlayTimer?.let { handler.removeCallbacks(it) }
        overlayTimer = null
        try {
            (getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeView(v)
        } catch (_: Exception) {
            // 已经被系统移除
        }
        if (auto) {
            // 超时未处理：按忽略处理，避免下次又弹同一条
            // raw 已经写入队列，这里不再重复写
        }
    }

    private fun dp(v: Int): Int =
        (v * resources.displayMetrics.density).toInt()

    private fun formatCents(cents: Int): String {
        val yuan = cents / 100
        val frac = cents % 100
        return "$yuan.${frac.toString().padStart(2, '0')}"
    }

    override fun onInterrupt() {
        dismissOverlay()
    }

    override fun onDestroy() {
        dismissOverlay()
        super.onDestroy()
    }
}
