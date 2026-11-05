import '../../core/money.dart';

/// 一条从通知/短信/屏幕识别里解析出来的候选账单。
class AutoBill {
  const AutoBill({
    required this.source,
    required this.raw,
    required this.at,
    required this.kind,
    required this.amountCents,
    this.merchant,
    this.note,
  });

  /// 'access' | 'notification' | 'sms'
  final String source;
  final String raw;
  final DateTime at;

  /// 'expense' | 'income'
  final String kind;
  final int amountCents;
  final String? merchant;
  final String? note;

  /// 去重键：来源 + 金额 + 商户 + 2 分钟时间段。
  ///
  /// 不用整段原文——屏幕上的原文每次都可能差一点（滚动位置、角标、时间秒数），
  /// 用原文做键会导致同一笔被重复记账。
  String get dedupeKey {
    final int bucket = at.millisecondsSinceEpoch ~/ 120000;
    return 'auto:$source:$amountCents:${merchant ?? ''}:$bucket';
  }
}

/// 不该当成账单的文本。
final RegExp _noise = RegExp(
  '验证码|校验码|动态码|动态密码|登录|登陆|密码|优惠券|活动|广告|积分|额度|'
  '账单已出|还款日|到期|提醒您|抽奖|红包已过期',
);

/// 支付成功类文案（屏幕识别必须有其一）。
final List<String> _successWords = <String>[
  '支付成功', '付款成功', '交易成功', '已支付', '支付完成',
  '转账成功', '收款成功', '付款完成',
];

/// 收入向的关键词。
final List<String> _incomeHints = <String>[
  '到账', '收款', '收入', '退款', '入账', '转入', '收到', '返还',
];

/// 支出向的关键词。
final List<String> _expenseHints = <String>[
  '支付', '付款', '消费', '扣款', '支出', '转出', '取款', '付给', '交易成功',
];

/// 带货币符号 / 单位的金额。
final List<RegExp> _moneyPatterns = <RegExp>[
  RegExp(r'(?:人民币|RMB|CNY)\s?([0-9]+(?:\.[0-9]{1,2})?)', caseSensitive: false),
  RegExp(r'[¥￥]\s?([0-9]+(?:\.[0-9]{1,2})?)'),
  RegExp(r'([0-9]+(?:\.[0-9]{1,2})?)\s?元'),
];

/// 整行只有一个金额，可带负号（含全角减号）。
///
/// 微信/支付宝账单详情页就是这样显示的：`-151.20`、`−9.90`，
/// 没有 ¥ 也没有「元」。必须要求小数点，避免把卡号(2642)、单号当成金额。
final RegExp _bareAmount = RegExp(r'^[−\-]?\s?([0-9]{1,7}\.[0-9]{1,2})$');

/// 常见商户，用于给通知/短信补商户名。
const List<String> _merchants = <String>[
  '支付宝', '微信', '云闪付', '美团', '饿了么', '淘宝', '天猫', '京东', '拼多多',
  '滴滴', '星巴克', '肯德基', '麦当劳', '瑞幸', '盒马', '山姆', '沃尔玛',
  '招商银行', '工商银行', '建设银行', '农业银行', '中国银行', '交通银行',
  '重庆农村商业银行',
];

/// 解析一条原始文本；不是账单则返回 null。
///
/// [raw] 可能有多行（屏幕识别），也可能是单行（通知/短信）。
AutoBill? parseAutoBill({
  required String source,
  required String raw,
  required DateTime at,
}) {
  final List<String> lines = raw
      .split('\n')
      .map((String s) => s.replaceAll('\u00A0', ' ').trim())
      .where((String s) => s.isNotEmpty)
      .toList();
  if (lines.isEmpty) return null;

  final String text = lines.join(' ');
  if (_noise.hasMatch(text)) return null;

  final int? cents = _pickAmount(lines, text);
  if (cents == null || cents <= 0) return null;

  if (source == 'access') {
    // 屏幕识别：必须真的出现「支付成功 / 交易成功」之类，避免把普通页面误判
    if (!lines.any((String l) => _successWords.any(l.contains))) return null;
  } else {
    // 通知/短信：没有成功文案，靠金额语义词判断
    if (!_expenseHints.any(text.contains) && !_incomeHints.any(text.contains)) {
      return null;
    }
  }

  final int incomeScore =
      _incomeHints.where((String k) => text.contains(k)).length;
  final int expenseScore =
      _expenseHints.where((String k) => text.contains(k)).length;
  final String kind =
      (incomeScore > 0 && incomeScore > expenseScore) ? 'income' : 'expense';

  final String? merchant = source == 'access'
      ? _merchantFromLines(lines)
      : _merchantFromText(text);

  return AutoBill(
    source: source,
    raw: raw,
    at: at,
    kind: kind,
    amountCents: cents,
    merchant: merchant,
    note: _noteOf(lines, merchant),
  );
}

int? _pickAmount(List<String> lines, String text) {
  // 1) 整行纯金额（账单详情页的显示方式）
  for (final String line in lines) {
    final RegExpMatch? m = _bareAmount.firstMatch(line);
    if (m == null) continue;
    final int? cents = parseYuanToCents(m.group(1) ?? '');
    if (cents != null && cents > 0 && cents <= 100000000) return cents;
  }
  // 2) 带 ¥ / 元 / 人民币
  for (final RegExp p in _moneyPatterns) {
    final RegExpMatch? m = p.firstMatch(text);
    if (m == null) continue;
    final int? cents = parseYuanToCents(m.group(1) ?? '');
    if (cents != null && cents > 0 && cents <= 100000000) return cents;
  }
  return null;
}

/// 屏幕识别：优先「收款方全称 / 商户全称」的下一行，其次取金额上一行（品牌名）。
String? _merchantFromLines(List<String> lines) {
  for (int i = 0; i < lines.length; i++) {
    final String t = lines[i];
    if (t.startsWith('收款方') ||
        t.startsWith('商户全称') ||
        t.startsWith('商户名称')) {
      final String inline = t.contains('：')
          ? t.substring(t.indexOf('：') + 1).trim()
          : (t.contains(':') ? t.substring(t.indexOf(':') + 1).trim() : '');
      if (inline.length >= 2 && inline.length <= 24) return inline;
      if (i + 1 < lines.length) {
        final String next = lines[i + 1];
        if (next.length >= 2 && next.length <= 24 && !next.contains(':')) {
          return next;
        }
      }
    }
  }
  // 金额上一行一般是品牌名
  for (int i = 1; i < lines.length; i++) {
    if (_bareAmount.hasMatch(lines[i])) {
      final String prev = lines[i - 1];
      if (prev.length >= 2 && prev.length <= 24 && !prev.contains('成功')) {
        return prev;
      }
    }
  }
  return null;
}

String? _merchantFromText(String text) {
  for (final String m in _merchants) {
    if (text.contains(m)) return m;
  }
  return null;
}

String _noteOf(List<String> lines, String? merchant) {
  final String joined = lines.take(3).join(' · ');
  final String t = joined.length <= 60 ? joined : '${joined.substring(0, 60)}…';
  return t;
}
