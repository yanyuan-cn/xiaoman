import 'repo.dart';

extension RepoStats on Repo {
  Future<MonthSummary> summaryBetween(DateTime from, DateTime to) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT kind, SUM(amount) AS total FROM txns '
      "WHERE deleted_at IS NULL AND kind IN ('expense', 'income') "
      'AND occurred_at >= ? AND occurred_at < ? GROUP BY kind',
      <Object>[toUtcMs(from), toUtcMs(to)],
    );
    int expense = 0;
    int income = 0;
    for (final Map<String, Object?> row in rows) {
      final int total = (row['total'] as num?)?.toInt() ?? 0;
      if (row['kind'] == 'expense') {
        expense = total;
      } else if (row['kind'] == 'income') {
        income = total;
      }
    }
    return MonthSummary(expense: expense, income: income);
  }

  /// 某个时间段内，按分类汇总的金额
  Future<Map<int, int>> categoryTotals({
    required DateTime from,
    required DateTime to,
    required String kind,
  }) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT category_id AS id, SUM(amount) AS total FROM txns '
      'WHERE deleted_at IS NULL AND kind = ? '
      'AND occurred_at >= ? AND occurred_at < ? AND category_id IS NOT NULL '
      'GROUP BY category_id ORDER BY total DESC',
      <Object>[kind, toUtcMs(from), toUtcMs(to)],
    );
    final Map<int, int> out = <int, int>{};
    for (final Map<String, Object?> r in rows) {
      final int? id = (r['id'] as num?)?.toInt();
      if (id != null) out[id] = (r['total'] as num?)?.toInt() ?? 0;
    }
    return out;
  }

  /// 某一年的 12 个月收支（索引 0 = 1 月）
  Future<List<MonthSummary>> monthlySummary(int year) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      "SELECT kind, occurred_at, amount FROM txns "
      "WHERE deleted_at IS NULL AND kind IN ('expense', 'income') "
      'AND occurred_at >= ? AND occurred_at < ?',
      <Object>[toUtcMs(DateTime(year)), toUtcMs(DateTime(year + 1))],
    );
    final List<int> exp = List<int>.filled(12, 0);
    final List<int> inc = List<int>.filled(12, 0);
    for (final Map<String, Object?> r in rows) {
      final DateTime d = DateTime.fromMillisecondsSinceEpoch(
        (r['occurred_at'] as num).toInt(),
        isUtc: true,
      ).toLocal();
      final int i = d.month - 1;
      final int amount = (r['amount'] as num).toInt();
      if (r['kind'] == 'expense') {
        exp[i] += amount;
      } else {
        inc[i] += amount;
      }
    }
    return List<MonthSummary>.generate(
      12,
      (int i) => MonthSummary(expense: exp[i], income: inc[i]),
      growable: false,
    );
  }
}
