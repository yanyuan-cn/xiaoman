import '../../core/money.dart';

/// 一条从通知/短信里解析出来的候选账单。
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

  /// 'notification' | 'sms'
  final String source;
  final String raw;
  final DateTime at;

  /// 'expense' | 'income'
  final String kind;
  final int amountCents;
  final String? merchant;
  final String? note;

  /// 去重用的稳定键：同一条通知重复推送只入账一次。
  String get dedupeKey => 'auto:${_fnv(raw)}';

  static String _fnv(String s) {
    int h = 0x811c9dc5;
    for (final int c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16);
  }
}

/// 不该当成账单的文本。
final RegExp _noise = RegExp(
  '验证码|校验码|动态码|动态密码|登录|登陆|密码|优惠券|活动|广告|积分|额度|'
  '账单已出|还款日|到期|提醒您|抽奖|红包已过期',
);

/// 收入向的关键词；命中越多越倾向收入。
final List<String> _incomeHints = <String>[
  '到账', '收款', '收入', '退款', '入账', '转入', '收到', '返还', '红包',
];

/// 支出向的关键词。
final List<String> _expenseHints = <String>[
  '支付', '付款', '消费', '扣款', '支出', '转出', '取款', '付给', '消费金额',
];

/// 金额：优先带货币符号/单位的，再退到「数字 + 元」。
final List<RegExp> _amountPatterns = <RegExp>[
  RegExp(r'(?:人民币|RMB|CNY)\s?([0-9]+(?:\.[0-9]{1,2})?)', caseSensitive: false),
  RegExp(r'[¥￥]\s?([0-9]+(?:\.[0-9]{1,2})?)'),
  RegExp(r'([0-9]+(?:\.[0-9]{1,2})?)\s?元'),
];

/// 常见商户，用于给账单填上「商户」。
const List<String> _merchants = <String>[
  '支付宝', '微信', '云闪付', '美团', '饿了么', '淘宝', '天猫', '京东', '拼多多',
  '滴滴', '星巴克', '肯德基', '麦当劳', '瑞幸', '盒马', '山姆', '沃尔玛',
  '招商银行', '工商银行', '建设银行', '农业银行', '中国银行', '交通银行',
  '重庆农村商业银行',
];

/// 解析一条原始文本；不是账单则返回 null。
///
/// 规则尽量保守：宁可漏，也不要把验证码、额度提醒这类东西记成账。
AutoBill? parseAutoBill({
  required String source,
  required String raw,
  required DateTime at,
}) {
  final String text = _normalize(raw);
  if (text.isEmpty) return null;
  if (_noise.hasMatch(text)) return null;

  int? cents;
  for (final RegExp p in _amountPatterns) {
    final RegExpMatch? m = p.firstMatch(text);
    if (m != null) {
      cents = parseYuanToCents(m.group(1) ?? '');
      if (cents != null && cents > 0) break;
      cents = null;
    }
  }
  if (cents == null || cents <= 0) return null;
  // 金额离谱（> 100 万）多半是额度/积分，不是真实交易
  if (cents > 100000000) return null;

  final int incomeScore =
      _incomeHints.where((String k) => text.contains(k)).length;
  final int expenseScore =
      _expenseHints.where((String k) => text.contains(k)).length;

  // 没有任何金额语义词（支付/到账/消费…）的文本不当账单，
  // 否则「今天天气不错 ¥12.50」这种也会被记上。
  if (incomeScore == 0 && expenseScore == 0) return null;

  // 只有「收入向」明显占优才算收入，其余默认支出（记账场景里支出更多）
  final String kind =
      (incomeScore > 0 && incomeScore > expenseScore) ? 'income' : 'expense';

  String? merchant;
  for (final String m in _merchants) {
    if (text.contains(m)) {
      merchant = m;
      break;
    }
  }

  return AutoBill(
    source: source,
    raw: raw,
    at: at,
    kind: kind,
    amountCents: cents,
    merchant: merchant,
    note: _noteOf(text),
  );
}

String _normalize(String raw) => raw
    .replaceAll('\u00A0', ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _noteOf(String text) {
  final String t = text.trim();
  if (t.length <= 40) return t;
  return '${t.substring(0, 40)}…';
}
