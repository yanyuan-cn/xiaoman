/// 预算周期：month = 每月第 startDay 天重置；week = 每周一重置。

class BudgetPeriod {
  const BudgetPeriod({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

BudgetPeriod budgetPeriodOf(String type, int startDay, {DateTime? now}) {
  final DateTime n = now ?? DateTime.now();
  final DateTime today = DateTime(n.year, n.month, n.day);

  if (type == 'week') {
    final DateTime start = today.subtract(Duration(days: today.weekday - 1));
    return BudgetPeriod(
      start: start,
      end: DateTime(start.year, start.month, start.day + 7),
    );
  }

  final int day = startDay < 1 ? 1 : (startDay > 28 ? 28 : startDay);
  final DateTime start = today.day >= day
      ? DateTime(today.year, today.month, day)
      : DateTime(today.year, today.month - 1, day);
  return BudgetPeriod(
    start: start,
    end: DateTime(start.year, start.month + 1, day),
  );
}

String _two(int v) => v.toString().padLeft(2, '0');

String budgetPeriodLabel(BudgetPeriod p, String type) {
  if (type == 'week') {
    return '${_two(p.start.month)}/${_two(p.start.day)} – '
        '${_two(p.end.month)}/${_two(p.end.day)}';
  }
  return '${p.start.year}/${_two(p.start.month)}/${_two(p.start.day)} 起';
}
