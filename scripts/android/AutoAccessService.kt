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
 * 微信/支付宝的账单详情页里，金额是**独立的一行纯数字**（`-151.20`、`−9.90`），
 * 既没有 ¥ 也没有「元」，所以不能只靠带货币符号的正则。
 *
 * 触发策略：
 *  - 只看 TYPE_WINDOW_STATE_CHANGED（页面切换）。CONTENT_CHANGED 会在滚动/刷新时
 *    疯狂触发，是「一秒内连弹好几次」的根因。
 *  - 同一金额 2 分钟内不重复弹；两次弹窗之间至少隔 3 秒。
 */
class AutoAccessService : AccessibilityService() {

    companion object {
        private const val WECHAT = "com.tencent.mm"
        private const val ALIPAY = "com.eg.android.AlipayGphone"

        /** 支付完成后等多久再弹窗：太即时容易被风控判定异常 */
        private const val POPUP_DELAY_MS = 900L

        /** 两次弹窗的最小间隔，防止页面反复重建导致连弹 */
        private const val MIN_POPUP_GAP_MS = 3000L

        /** 同一金额多久内不重复识别 */
        private const val DEDUPE_MS = 120000L

        /** 从微信/支付宝切走后，多久内还认为「可能刚付完款」 */
        private const val SDK_RETURN_WINDOW_MS = 25000L

        private const val AUTO_DISMISS_MS = 12000L

        private val SUCCESS_WORDS = arrayOf(
            "支付成功", "付款成功", "交易成功", "已支付", "支付完成",
            "转账成功", "收款成功", "付款完成"
        )

        /** 带货币符号/单位的金额 */
        private val MONEY_AMOUNT = Regex(
            "(?:[¥￥]\\s?(\\d+(?:\\.\\d{1,2})?))" +
                "|(?:(\\d+(?:\\.\\d{1,2})?)\\s?元)" +
                "|(?:人民币\\s?(\\d+(?:\\.\\d{1,2})?))"
        )

        /** 整行只有一个金额：可带负号（含全角减号），必须带小数，避免把卡号/单号当金额 */
        private val BARE_AMOUNT = Regex("^[−\\-]?\\s?(\\d{1,7}\\.\\d{1,2})$")
    }

    private val handler = Handler(Looper.getMainLooper())
    private var lastPayAppAt = 0L
    private var lastPopupAt = 0L
    private var lastAmountCents = -1
    private var lastAmountAt = 0L
    private var overlay: View? = null
    private var overlayTimer: Runnable? = null

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val e = event ?: return
        if (!PendingStore.switchOn(this, PendingStore.KEY_MASTER)) return
        if (!PendingStore.switchOn(this, PendingStore.KEY_ACCESS)) return
        if (e.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return

        val pkg = e.packageName?.toString() ?: return
        val now = System.currentTimeMillis()
        if (pkg == WECHAT || pkg == ALIPAY) {
            lastPayAppAt = now
        } else if (now - lastPayAppAt > SDK_RETURN_WINDOW_MS) {
            return
        }

        val root = rootInActiveWindow ?: return
        val lines = ArrayList<String>(48)
        collectText(root, lines, 0)
        if (lines.isEmpty()) return

        // 必须真的出现「支付成功/交易成功」这类文案，不再靠拼接假装
        if (!lines.any { line -> SUCCESS_WORDS.any { line.contains(it) } }) return

        val cents = pickAmount(lines) ?: return
        if (cents <= 0) return

        // 同一金额短时间内重复出现：直接丢弃
        if (cents == lastAmountCents && now - lastAmountAt < DEDUPE_MS) return
        // 弹窗太频繁：丢弃
        if (now - lastPopupAt < MIN_POPUP_GAP_MS) return

        val merchant = pickMerchant(lines, pkg)
        val raw = buildRaw(pkg, lines)

        lastAmountCents = cents
        lastAmountAt = now

        handler.postDelayed({
            offerBill(cents, merchant, raw, now)
        }, POPUP_DELAY_MS)
    }

    // ---------------- 识别 ----------------

    private fun collectText(node: AccessibilityNodeInfo?, out: MutableList<String>, depth: Int) {
        if (node == null || depth > 25 || out.size > 60) return
        val t = node.text?.toString()?.trim().orEmpty()
        if (t.isNotEmpty() && t.length <= 60) out.add(t)
        val d = node.contentDescription?.toString()?.trim().orEmpty()
        if (d.isNotEmpty() && d.length <= 60 && d != t) out.add(d)
        for (i in 0 until node.childCount) {
            collectText(node.getChild(i), out, depth + 1)
        }
    }

    /** 优先整行的纯金额，其次带 ¥ / 元 的写法。 */
    private fun pickAmount(lines: List<String>): Int? {
        for (line in lines) {
            val m = BARE_AMOUNT.find(line) ?: continue
            val value = m.groupValues[1]
            val cents = toCents(value) ?: continue
            if (cents in 1..100000000) return cents
        }
        for (line in lines) {
            val m = MONEY_AMOUNT.find(line) ?: continue
            val value = m.groupValues.drop(1).firstOrNull { it.isNotEmpty() } ?: continue
            val cents = toCents(value) ?: continue
            if (cents in 1..100000000) return cents
        }
        return null
    }

    private fun toCents(value: String): Int? {
        val parts = value.split(".")
        val yuan = parts[0].replace(",", "").toLongOrNull() ?: return null
        val frac = if (parts.size > 1) (parts[1] + "00").substring(0, 2).toInt() else 0
        val total = yuan * 100 + frac
        if (total <= 0 || total > 100000000) return null
        return total.toInt()
    }

    /**
     * 商户：优先「收款方全称 / 商户全称」的下一行，其次取金额上面那行（通常是品牌名），
     * 最后退回 App 名。
     */
    private fun pickMerchant(lines: List<String>, pkg: String): String? {
        for (i in lines.indices) {
            val t = lines[i]
            if (t.startsWith("收款方") || t.startsWith("商户全称") || t.startsWith("商户名称")) {
                // 有的机型把值放在同一行冒号后面
                val inline = t.substringAfter("：", "").trim()
                if (inline.isNotEmpty() && inline.length in 2..24) return inline
                if (i + 1 < lines.size) {
                    val next = lines[i + 1].trim()
                    if (next.isNotEmpty() && next.length in 2..24 && !next.contains(":")) return next
                }
            }
        }
        // 金额上一行一般就是品牌名
        for (i in lines.indices) {
            if (BARE_AMOUNT.matches(lines[i]) && i > 0) {
                val prev = lines[i - 1].trim()
                if (prev.length in 2..24 && !prev.contains("成功")) return prev
            }
        }
        return when (pkg) {
            WECHAT -> "微信支付"
            ALIPAY -> "支付宝"
            else -> null
        }
    }

    private fun buildRaw(pkg: String, lines: List<String>): String {
        val app = when (pkg) {
            WECHAT -> "微信"
            ALIPAY -> "支付宝"
            else -> pkg
        }
        // 保留换行：Dart 侧按行判断「整行金额」和「金额上一行是商户」
        return "$app\n" + lines.take(12).joinToString("\n")
    }

    // ---------------- 悬浮窗 ----------------

    private fun offerBill(cents: Int, merchant: String?, raw: String, at: Long) {
        if (overlay != null) return
        if (!Settings.canDrawOverlays(this)) {
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
            lastPopupAt = System.currentTimeMillis()
            val dismiss = Runnable { dismissOverlay() }
            overlayTimer = dismiss
            handler.postDelayed(dismiss, AUTO_DISMISS_MS.toLong())
        } catch (_: Exception) {
            PendingStore.push(this, "access", raw, at, "pending")
        }
    }

    private fun dismissOverlay() {
        val v = overlay ?: return
        overlay = null
        overlayTimer?.let { handler.removeCallbacks(it) }
        overlayTimer = null
        try {
            (getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeView(v)
        } catch (_: Exception) {
            // 已经被系统移除
        }
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

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
