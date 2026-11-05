import 'models.dart';
import 'repo.dart';

extension RepoBudget on Repo {
  Future<List<BudgetRule>> budgets() async {
    final List<Map<String, Object?>> rows =
        await db.query('budgets', where: 'active = 1', orderBy: 'id ASC');
    return rows.map(BudgetRule.fromMap).toList(growable: false);
  }

  /// 金额填 0 等于删除这条预算
  Future<void> saveBudget({
    required String scope,
    int? categoryId,
    required int amount,
  }) async {
    if (amount <= 0) {
      await deleteBudget(scope: scope, categoryId: categoryId);
      return;
    }
    final List<Map<String, Object?>> rows = await db.query(
      'budgets',
      where: categoryId == null
          ? "scope = 'all'"
          : 'scope = ? AND category_id = ?',
      whereArgs:
          categoryId == null ? null : <Object>['category', categoryId],
      limit: 1,
    );
    if (rows.isEmpty) {
      await db.insert('budgets', <String, Object?>{
        'scope': scope,
        'category_id': categoryId,
        'amount': amount,
        'active': 1,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
    } else {
      await db.update(
        'budgets',
        <String, Object?>{'amount': amount},
        where: 'id = ?',
        whereArgs: <Object?>[rows.first['id']],
      );
    }
  }

  Future<void> deleteBudget({required String scope, int? categoryId}) async {
    if (categoryId == null) {
      await db.delete('budgets', where: "scope = 'all'");
      return;
    }
    await db.delete('budgets',
        where: 'scope = ? AND category_id = ?',
        whereArgs: <Object>[scope, categoryId]);
  }

  /// 本期已用（只算计入预算的支出）。parentCategoryId 为 null 时算全部支出。
  Future<int> budgetSpent({
    required DateTime from,
    required DateTime to,
    int? parentCategoryId,
  }) async {
    if (parentCategoryId == null) {
      final List<Map<String, Object?>> rows = await db.rawQuery(
        "SELECT SUM(amount) AS total FROM txns "
        "WHERE deleted_at IS NULL AND kind = 'expense' AND in_budget = 1 "
        'AND occurred_at >= ? AND occurred_at < ?',
        <Object>[toUtcMs(from), toUtcMs(to)],
      );
      return (rows.first['total'] as num?)?.toInt() ?? 0;
    }
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT SUM(t.amount) AS total FROM txns t '
      'JOIN categories c ON c.id = t.category_id '
      'WHERE t.deleted_at IS NULL AND t.kind = ? AND t.in_budget = 1 '
      'AND t.occurred_at >= ? AND t.occurred_at < ? '
      'AND (c.id = ? OR c.parent_id = ?)',
      <Object>[
        'expense',
        toUtcMs(from),
        toUtcMs(to),
        parentCategoryId,
        parentCategoryId,
      ],
    );
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }
}
