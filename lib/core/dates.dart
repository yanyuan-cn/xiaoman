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
