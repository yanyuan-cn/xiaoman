String two(int v) => v.toString().padLeft(2, '0');

String fmtMonth(DateTime d) => '${d.year}年${d.month}月';

String fmtMonthDay(DateTime d) => '${two(d.month)}月${two(d.day)}日';

String fmtDate(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

String fmtDateTime(DateTime d) => '${fmtDate(d)} ${two(d.hour)}:${two(d.minute)}';

const List<String> _weekdays = <String>[
  '周一', '周二', '周三', '周四', '周五', '周六', '周日',
];

String fmtWeekday(DateTime d) => _weekdays[d.weekday - 1];

String fmtDayKey(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

/// 列表里的短日期：今天 / 昨天 / 11/03
String fmtShortDay(DateTime d) {
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime day = DateTime(d.year, d.month, d.day);
  final int diff = today.difference(day).inDays;
  if (diff == 0) return '今天';
  if (diff == 1) return '昨天';
  return '${two(d.month)}/${two(d.day)}';
}
