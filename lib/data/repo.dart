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
  });

  final String kind;
  final int amount;
  final DateTime occurredAt;
  final int accountId;
  final int categoryId;
  final String? note;
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
    String source = 'manual',
    String? externalId,
    String? dedupHash,
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
      'merchant': null,
      'source': source,
      'external_id': externalId,
      'dedup_hash': dedupHash,
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
          'merchant': null,
          'source': source,
          'external_id': null,
          'dedup_hash': dedupHashFor(
            kind: it.kind,
            amount: it.amount,
            at: it.occurredAt,
            note: it.note,
          ),
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
}
