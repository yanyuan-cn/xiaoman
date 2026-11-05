package com.xiaoman.xiaoman

/**
 * Cheap pre-filter: only messages that look like a payment get queued, so the
 * Dart parser does not have to chew through every notification on the phone.
 * The real parsing still happens in Dart.
 */
object AutoFilter {

    private val amount = Regex(
        "(?:[¥￥]\\s?\\d+(?:\\.\\d{1,2})?)" +
            "|(?:\\d+(?:\\.\\d{1,2})?\\s?元)" +
            "|(?:人民币\\s?\\d+(?:\\.\\d{1,2})?)"
    )

    private val money = Regex(
        "支付|付款|消费|扣款|支出|转出|取款|到账|收款|收入|退款|入账|转入"
    )

    private val noise = Regex(
        "验证码|校验码|动态码|登录|密码|红包已过期|优惠券|活动|广告"
    )

    fun looksLikePayment(text: String): Boolean {
        if (text.isBlank()) return false
        if (noise.containsMatchIn(text)) return false
        return amount.containsMatchIn(text) && money.containsMatchIn(text)
    }
}
