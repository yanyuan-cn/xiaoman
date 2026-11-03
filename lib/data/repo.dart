import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// 本地时间 -> UTC 毫秒（库里统一存 UTC）
int toUtcMs(DateTime local) => local.toUtc().millisecondsSinceEpoch;

/// 去重指纹：方向 + 金额 + 分钟 + 备注
String dedupHashFor({
  required String kind,
  required int amount,
  required DateTime at,
  String? note,
}) {
  final String s =
      '$kind|$amount|${at.millisecondsSinceEpoch ~/ 60000}|${(note ?? '').trim()}';
  int h = 0x811c9dc5;
  for (final int c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h.toRadixString(16);
}

class MonthSummary {
  const MonthSummary({this.expense = 0, this.income = 0});

  final int expense;
  final int income;

  int get net => income - expense;
}

class ImportItem {
  const ImportItem({
    required this.kind,
    required this.amount,
    required this.occurredAt,
    required this.accountId,
    required this.categoryId,
    this.note,
    this.merchant,
    this.externalId,
    this.inBudget = true,
  });

  final String kind;
  final int amount;
  final DateTime occurredAt;
  final int accountId;
  final int categoryId;
  final String? note;
  final String? merchant;
  final String? externalId;
  final bool inBudget;
}

class ImportResult {
  const ImportResult({
    required this.batchId,
    required this.inserted,
    required this.skipped,
  });

  final int batchId;
  final int inserted;
  final int skipped;
}

class Repo {
  Repo(this.db);

  final Database db;

  Future<List<Account>> accounts() async {
    final List<Map<String, Object?>> rows = await db.query(
      'accounts',
      where: 'archived = 0',
      orderBy: 'sort ASC, id ASC',
    );
    return rows.map(Account.fromMap).toList(growable: false);
  }

  Future<List<TxnCategory>> categories() async {
    final List<Map<String, Object?>> rows = await db.query(
      'categories',
      where: 'archived = 0',
      orderBy: 'kind ASC, sort ASC, id ASC',
    );
    return rows.map(TxnCategory.fromMap).toList(growable: false);
  }

  Future<List<Txn>> txnsBetween(DateTime from, DateTime to) async {
    final List<Map<String, Object?>> rows = await db.query(
      'txns',
      where: 'deleted_at IS NULL AND occurred_at >= ? AND occurred_at < ?',
      whereArgs: <Object>[toUtcMs(from), toUtcMs(to)],
      orderBy: 'occurred_at DESC, id DESC',
    );
    return rows.map(Txn.fromMap).toList(growable: false);
  }

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

  Future<int> addTxn({
    required String kind,
    required int amount,
    required DateTime occurredAt,
    required int accountId,
    int? categoryId,
    String? note,
    String? merchant,
    String source = 'manual',
    String? externalId,
    String? dedupHash,
    bool inBudget = true,
  }) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    return db.insert('txns', <String, Object?>{
      'kind': kind,
      'amount': amount,
      'occurred_at': toUtcMs(occurredAt),
      'account_id': accountId,
      'to_account_id': null,
      'category_id': categoryId,
      'note': note,
      'merchant': merchant,
      'source': source,
      'external_id': externalId,
      'dedup_hash': dedupHash,
      'in_budget': inBudget ? 1 : 0,
      'deleted_at': null,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> softDelete(int id) async {
    await db.update(
      'txns',
      <String, Object?>{'deleted_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
  }

  Future<void> restore(int id) async {
    await db.update(
      'txns',
      <String, Object?>{'deleted_at': null},
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
  }

  /// 已存在流水的指纹集合（含手工记的，用于跨来源去重）
  Future<Set<String>> _existingHashes() async {
    final List<Map<String, Object?>> rows = await db.query(
      'txns',
      columns: <String>['kind', 'amount', 'occurred_at', 'note'],
      where: 'deleted_at IS NULL',
    );
    final Set<String> out = <String>{};
    for (final Map<String, Object?> r in rows) {
      out.add(dedupHashFor(
        kind: r['kind'] as String,
        amount: (r['amount'] as num).toInt(),
        at: DateTime.fromMillisecondsSinceEpoch(
          (r['occurred_at'] as num).toInt(),
          isUtc: true,
        ).toLocal(),
        note: r['note'] as String?,
      ));
    }
    return out;
  }

  Future<bool> hasImportBatch() async {
    final List<Map<String, Object?>> rows =
        await db.query('import_batches', limit: 1);
    return rows.isNotEmpty;
  }

  Future<ImportResult> importItems(
    List<ImportItem> items, {
    required String source,
    String? fileName,
  }) async {
    final Set<String> existing = await _existingHashes();
    final Set<String> seen = <String>{};
    final List<ImportItem> accepted = <ImportItem>[];
    int skipped = 0;

    for (final ImportItem it in items) {
      final String h = dedupHashFor(
        kind: it.kind,
        amount: it.amount,
        at: it.occurredAt,
        note: it.note,
      );
      if (existing.contains(h) || seen.contains(h)) {
        skipped++;
        continue;
      }
      seen.add(h);
      accepted.add(it);
    }

    final int batchId = await db.insert('import_batches', <String, Object?>{
      'source': source,
      'file_name': fileName,
      'imported_at': DateTime.now().millisecondsSinceEpoch,
      'total': items.length,
      'inserted': 0,
      'skipped': skipped,
    });

    final int now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((Transaction txn) async {
      for (final ImportItem it in accepted) {
        final int id = await txn.insert('txns', <String, Object?>{
          'kind': it.kind,
          'amount': it.amount,
          'occurred_at': toUtcMs(it.occurredAt),
          'account_id': it.accountId,
          'to_account_id': null,
          'category_id': it.categoryId,
          'note': it.note,
          'merchant': it.merchant,
          'source': source,
          'external_id': it.externalId,
          'dedup_hash': dedupHashFor(
            kind: it.kind,
            amount: it.amount,
            at: it.occurredAt,
            note: it.note,
          ),
          'in_budget': it.inBudget ? 1 : 0,
          'deleted_at': null,
          'created_at': now,
          'updated_at': now,
        });
        await txn.insert('import_rows', <String, Object?>{
          'batch_id': batchId,
          'raw_json': null,
          'txn_id': id,
          'result': 'ok',
        });
      }
      await txn.update(
        'import_batches',
        <String, Object?>{'inserted': accepted.length},
        where: 'id = ?',
        whereArgs: <Object>[batchId],
      );
    });

    return ImportResult(
      batchId: batchId,
      inserted: accepted.length,
      skipped: skipped,
    );
  }

  /// 撤销最近一次导入，返回受影响的条数
  Future<int> undoLastImport() async {
    final List<Map<String, Object?>> batches = await db.query(
      'import_batches',
      orderBy: 'id DESC',
      limit: 1,
    );
    if (batches.isEmpty) return 0;

    final int batchId = batches.first['id']! as int;
    final List<Map<String, Object?>> rows = await db.query(
      'import_rows',
      where: 'batch_id = ?',
      whereArgs: <Object>[batchId],
    );

    int count = 0;
    for (final Map<String, Object?> r in rows) {
      final int? txnId = (r['txn_id'] as num?)?.toInt();
      if (txnId != null) {
        await softDelete(txnId);
        count++;
      }
    }
    await db.delete('import_rows',
        where: 'batch_id = ?', whereArgs: <Object>[batchId]);
    await db.delete('import_batches',
        where: 'id = ?', whereArgs: <Object>[batchId]);
    return count;
  }

  /// 每个账户的收支增减（不含初始余额）
  Future<Map<int, int>> accountDeltas() async {
    final Map<int, int> out = <int, int>{};
    final List<Map<String, Object?>> rows = await db.rawQuery(
      "SELECT account_id AS id, "
      "SUM(CASE WHEN kind = 'expense' THEN -amount "
      "WHEN kind = 'income' THEN amount "
      "WHEN kind = 'transfer' THEN -amount ELSE 0 END) AS delta "
      "FROM txns WHERE deleted_at IS NULL GROUP BY account_id",
    );
    for (final Map<String, Object?> r in rows) {
      final int? id = (r['id'] as num?)?.toInt();
      if (id != null) out[id] = (r['delta'] as num?)?.toInt() ?? 0;
    }
    final List<Map<String, Object?>> inRows = await db.rawQuery(
      'SELECT to_account_id AS id, SUM(amount) AS delta FROM txns '
      'WHERE deleted_at IS NULL AND to_account_id IS NOT NULL '
      'GROUP BY to_account_id',
    );
    for (final Map<String, Object?> r in inRows) {
      final int? id = (r['id'] as num?)?.toInt();
      if (id != null) {
        out[id] = (out[id] ?? 0) + ((r['delta'] as num?)?.toInt() ?? 0);
      }
    }
    return out;
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

  /// 全部流水（导出用）
  Future<List<Txn>> allTxns() async {
    final List<Map<String, Object?>> rows = await db.query(
      'txns',
      where: 'deleted_at IS NULL',
      orderBy: 'occurred_at DESC, id DESC',
    );
    return rows.map(Txn.fromMap).toList(growable: false);
  }

  Future<void> updateTxn({
    required int id,
    required String kind,
    required int amount,
    required DateTime occurredAt,
    required int accountId,
    int? toAccountId,
    int? categoryId,
    String? note,
    bool inBudget = true,
  }) async {
    await db.update(
      'txns',
      <String, Object?>{
        'kind': kind,
        'amount': amount,
        'occurred_at': toUtcMs(occurredAt),
        'account_id': accountId,
        'to_account_id': toAccountId,
        'category_id': categoryId,
        'note': note,
        'in_budget': inBudget ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
  }

  /// 账户之间转账：一条记录，from 减、to 加
  Future<int> addTransfer({
    required int amount,
    required DateTime occurredAt,
    required int fromAccountId,
    required int toAccountId,
    String? note,
  }) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    return db.insert('txns', <String, Object?>{
      'kind': 'transfer',
      'amount': amount,
      'occurred_at': toUtcMs(occurredAt),
      'account_id': fromAccountId,
      'to_account_id': toAccountId,
      'category_id': null,
      'note': note,
      'merchant': null,
      'source': 'manual',
      'external_id': null,
      'dedup_hash': null,
      'in_budget': 0,
      'deleted_at': null,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<int> addCategory({
    required String name,
    required String kind,
    int? parentId,
  }) async {
    final List<Map<String, Object?>> rows = await db.query(
      'categories',
      columns: <String>['sort'],
      where: parentId == null ? 'kind = ? AND parent_id IS NULL' : 'parent_id = ?',
      whereArgs: <Object>[parentId ?? kind],
      orderBy: 'sort DESC',
      limit: 1,
    );
    final int nextSort =
        rows.isEmpty ? 0 : ((rows.first['sort'] as num?)?.toInt() ?? 0) + 1;
    return db.insert('categories', <String, Object?>{
      'name': name,
      'kind': kind,
      'parent_id': parentId,
      'sort': nextSort,
      'archived': 0,
    });
  }

  Future<void> renameCategory(int id, String name) async {
    await db.update('categories', <String, Object?>{'name': name},
        where: 'id = ?', whereArgs: <Object>[id]);
  }

  /// 归档分类，子分类一起归档（历史流水仍保留原分类）
  Future<void> archiveCategory(int id) async {
    await db.update('categories', <String, Object?>{'archived': 1},
        where: 'id = ? OR parent_id = ?', whereArgs: <Object>[id, id]);
  }

  /// 某个分类下还有多少条流水
  Future<int> categoryUsage(int id) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM txns WHERE deleted_at IS NULL AND category_id = ?',
      <Object>[id],
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<int> addAccount({
    required String name,
    required String type,
    required int initialBalance,
    required bool isLiability,
    required bool includeInTotal,
  }) async {
    final List<Map<String, Object?>> rows = await db.query(
      'accounts',
      columns: <String>['sort'],
      orderBy: 'sort DESC',
      limit: 1,
    );
    final int nextSort =
        rows.isEmpty ? 0 : ((rows.first['sort'] as num?)?.toInt() ?? 0) + 1;
    return db.insert('accounts', <String, Object?>{
      'name': name,
      'type': type,
      'initial_balance': initialBalance,
      'is_liability': isLiability ? 1 : 0,
      'include_in_total': includeInTotal ? 1 : 0,
      'sort': nextSort,
      'archived': 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> updateAccount({
    required int id,
    required String name,
    required String type,
    required int initialBalance,
    required bool isLiability,
    required bool includeInTotal,
  }) async {
    await db.update(
      'accounts',
      <String, Object?>{
        'name': name,
        'type': type,
        'initial_balance': initialBalance,
        'is_liability': isLiability ? 1 : 0,
        'include_in_total': includeInTotal ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
  }

  /// 某个账户最近的流水（含转入的）
  Future<List<Txn>> txnsForAccount(int accountId, {int limit = 20}) async {
    final List<Map<String, Object?>> rows = await db.query(
      'txns',
      where: 'deleted_at IS NULL AND (account_id = ? OR to_account_id = ?)',
      whereArgs: <Object>[accountId, accountId],
      orderBy: 'occurred_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(Txn.fromMap).toList(growable: false);
  }

  Future<Map<String, int>> storageStats() async {
    final List<Map<String, Object?>> tx = await db
        .rawQuery('SELECT COUNT(*) AS c FROM txns WHERE deleted_at IS NULL');
    final List<Map<String, Object?>> cat =
        await db.rawQuery('SELECT COUNT(*) AS c FROM categories');
    final List<Map<String, Object?>> acc = await db
        .rawQuery('SELECT COUNT(*) AS c FROM accounts WHERE archived = 0');
    return <String, int>{
      'txns': (tx.first['c'] as num?)?.toInt() ?? 0,
      'categories': (cat.first['c'] as num?)?.toInt() ?? 0,
      'accounts': (acc.first['c'] as num?)?.toInt() ?? 0,
    };
  }

  Future<String?> getSetting(String key) async {
    final List<Map<String, Object?>> rows = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: <Object>[key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await db.delete('settings', where: 'key = ?', whereArgs: <Object>[key]);
      return;
    }
    await db.insert(
      'settings',
      <String, Object?>{'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------------- 预算 ----------------

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

  Future<void> setTxnInBudget(int id, bool inBudget) async {
    await db.update(
      'txns',
      <String, Object?>{'in_budget': inBudget ? 1 : 0},
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
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

  // ---------------- 定期扣款 / 贷款还款 ----------------

  Future<List<RecurringRule>> recurringRules() async {
    final List<Map<String, Object?>> rows =
        await db.query('recurring_rules', orderBy: 'id ASC');
    return rows.map(RecurringRule.fromMap).toList(growable: false);
  }

  Future<int> saveRecurringRule({
    int? id,
    required String name,
    required int amount,
    required int dayOfMonth,
    required int fromAccountId,
    int? toAccountId,
    int? categoryId,
    String? note,
    bool active = true,
  }) async {
    final Map<String, Object?> values = <String, Object?>{
      'name': name,
      'amount': amount,
      'day_of_month': dayOfMonth,
      'from_account_id': fromAccountId,
      'to_account_id': toAccountId,
      'category_id': categoryId,
      'note': note,
      'active': active ? 1 : 0,
    };
    if (id == null) {
      values['created_at'] = DateTime.now().millisecondsSinceEpoch;
      return db.insert('recurring_rules', values);
    }
    await db.update('recurring_rules', values,
        where: 'id = ?', whereArgs: <Object>[id]);
    return id;
  }

  Future<void> deleteRecurringRule(int id) async {
    await db.delete('recurring_rules', where: 'id = ?', whereArgs: <Object>[id]);
  }

  Future<void> setRecurringRuleActive(int id, bool active) async {
    await db.update(
      'recurring_rules',
      <String, Object?>{'active': active ? 1 : 0},
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
  }

  /// 补跑所有到期规则，返回本次新生成的流水 id（用于撤销）
  Future<List<int>> runDueRecurringRules({DateTime? now}) async {
    final DateTime n = now ?? DateTime.now();
    final List<Map<String, Object?>> rows =
        await db.query('recurring_rules', where: 'active = 1');
    final List<int> created = <int>[];

    for (final Map<String, Object?> row in rows) {
      final RecurringRule r = RecurringRule.fromMap(row);
      DateTime cursor = r.createdAt > 0
          ? DateTime.fromMillisecondsSinceEpoch(r.createdAt)
          : DateTime(n.year, n.month);
      cursor = DateTime(cursor.year, cursor.month);

      for (int guard = 0; guard < 24; guard++) {
        if (cursor.isAfter(DateTime(n.year, n.month))) break;
        final int day = r.dayOfMonth < 1
            ? 1
            : (r.dayOfMonth > 28 ? 28 : r.dayOfMonth);
        final DateTime due = DateTime(cursor.year, cursor.month, day, 12);
        if (!due.isAfter(n)) {
          final String ext =
              'rule:${r.id}:${due.year}-${due.month.toString().padLeft(2, '0')}';
          final List<Map<String, Object?>> hit = await db.query(
            'txns',
            columns: <String>['id'],
            where: 'source = ? AND external_id = ?',
            whereArgs: <Object>['auto', ext],
            limit: 1,
          );
          if (hit.isEmpty) {
            final int id = await db.insert('txns', <String, Object?>{
              'kind': r.toAccountId == null ? 'expense' : 'transfer',
              'amount': r.amount,
              'occurred_at': toUtcMs(due),
              'account_id': r.fromAccountId,
              'to_account_id': r.toAccountId,
              'category_id': r.categoryId,
              'note': (r.note ?? '').isEmpty ? r.name : r.note,
              'merchant': null,
              'source': 'auto',
              'external_id': ext,
              'dedup_hash': null,
              'in_budget': r.toAccountId == null ? 1 : 0,
              'deleted_at': null,
              'created_at': n.millisecondsSinceEpoch,
              'updated_at': n.millisecondsSinceEpoch,
            });
            created.add(id);
          }
        }
        cursor = DateTime(cursor.year, cursor.month + 1);
      }

      await db.update(
        'recurring_rules',
        <String, Object?>{'last_run_at': n.millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: <Object>[r.id],
      );
    }
    return created;
  }

  Future<void> undoAutoTxns(List<int> ids) async {
    if (ids.isEmpty) return;
    final int now = DateTime.now().millisecondsSinceEpoch;
    for (final int id in ids) {
      await db.update(
        'txns',
        <String, Object?>{'deleted_at': now},
        where: 'id = ?',
        whereArgs: <Object>[id],
      );
    }
  }
}
