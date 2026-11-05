import 'package:sqflite/sqflite.dart';

import 'repo.dart';

extension RepoImport on Repo {
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
}
