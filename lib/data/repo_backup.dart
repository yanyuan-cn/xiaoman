import 'package:sqflite/sqflite.dart';

import 'db.dart';
import 'repo.dart';

/// 备份包含的表。顺序即恢复时的写入顺序，恢复时按倒序清空。
const List<String> kBackupTables = <String>[
  'account_types',
  'accounts',
  'categories',
  'txns',
  'budgets',
  'recurring_rules',
  'import_batches',
  'import_rows',
  'settings',
];

const int kBackupFormatFull = 2;

/// 一次恢复要做的事：每张表要写哪些行。已经按 [kBackupTables] 排好序、
/// 并且只保留了目标库里真实存在的列。
class BackupPlan {
  const BackupPlan({required this.tables, required this.full});

  final Map<String, List<Map<String, Object?>>> tables;

  /// true = format 2 全量备份；false = 旧版部分备份
  final bool full;

  int get total =>
      tables.values.fold<int>(0, (int a, List<Map<String, Object?>> b) => a + b.length);
}

/// 把一份备份数据规划成「要写哪些行」。
///
/// 抽成纯函数是为了能测：它不碰数据库，所以 `flutter test` 里可以直接喂
/// 各种坏数据，验证哪些被拒绝、哪些字段被裁掉、写入顺序对不对。
///
/// [columns] 是目标库每张表真实存在的列名；备份里多出来的字段会被丢掉，
/// 这样「新版本导出的文件在旧版本里恢复」不会直接插入失败。
BackupPlan planBackupRestore(
  Map<String, Object?> data, {
  required Map<String, Set<String>> columns,
  required int currentSchema,
  int? nowMs,
}) {
  final int schema = (data['schema'] as num?)?.toInt() ?? 0;
  final bool full = (data['format'] as num?)?.toInt() == kBackupFormatFull ||
      schema > 0;
  if (schema > currentSchema) {
    throw BackupException('备份来自更新的版本（数据库 v$schema），请先升级应用');
  }

  final Map<String, List<Map<String, Object?>>> raw =
      <String, List<Map<String, Object?>>>{};
  if (full) {
    for (final String t in kBackupTables) {
      final Object? rows = data[t];
      if (rows is! List) continue;
      raw[t] = <Map<String, Object?>>[
        for (final Object? row in rows)
          if (row is Map) Map<String, Object?>.from(row),
      ];
    }
  } else {
    raw.addAll(legacyBackupRows(data, nowMs: nowMs));
  }

  if ((raw['accounts'] ?? const <Map<String, Object?>>[]).isEmpty &&
      (raw['txns'] ?? const <Map<String, Object?>>[]).isEmpty) {
    throw BackupException('这个文件里没有可恢复的数据');
  }

  final Map<String, List<Map<String, Object?>>> tables =
      <String, List<Map<String, Object?>>>{};
  for (final String t in kBackupTables) {
    final List<Map<String, Object?>> rows =
        raw[t] ?? const <Map<String, Object?>>[];
    if (rows.isEmpty) continue;
    final Set<String> cols = columns[t] ?? const <String>{};
    if (cols.isEmpty) continue;
    final List<Map<String, Object?>> clean = <Map<String, Object?>>[];
    for (final Map<String, Object?> row in rows) {
      final Map<String, Object?> kept = <String, Object?>{
        for (final MapEntry<String, Object?> e in row.entries)
          if (cols.contains(e.key)) e.key: e.value,
      };
      if (kept.isNotEmpty) clean.add(kept);
    }
    if (clean.isNotEmpty) tables[t] = clean;
  }

  return BackupPlan(tables: tables, full: full);
}

/// 旧版导出（camelCase、字段不全）转成表行。
Map<String, List<Map<String, Object?>>> legacyBackupRows(
  Map<String, Object?> data, {
  int? nowMs,
}) {
  final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;

  List<Map<String, Object?>> list(String key) {
    final Object? raw = data[key];
    if (raw is! List) return <Map<String, Object?>>[];
    return <Map<String, Object?>>[
      for (final Object? e in raw)
        if (e is Map) Map<String, Object?>.from(e),
    ];
  }

  final List<Map<String, Object?>> accounts = <Map<String, Object?>>[];
  int i = 0;
  for (final Map<String, Object?> a in list('accounts')) {
    final String rawType = (a['type'] as String?) ?? 'cash';
    accounts.add(<String, Object?>{
      'id': a['id'],
      'name': a['name'] ?? '',
      // 老备份里 type 是 savings / bank 这种 key，换成新的中文名
      'type': kLegacyAccountTypes[rawType] ?? rawType,
      'initial_balance': (a['initialBalance'] as num?)?.toInt() ?? 0,
      'is_liability': 0,
      'include_in_total': 1,
      'sort': i++,
      'archived': 0,
      'created_at': now,
    });
  }

  final List<Map<String, Object?>> cats = <Map<String, Object?>>[];
  i = 0;
  for (final Map<String, Object?> c in list('categories')) {
    cats.add(<String, Object?>{
      'id': c['id'],
      'name': c['name'] ?? '',
      'kind': c['kind'] ?? 'expense',
      'parent_id': c['parentId'],
      'sort': i++,
      'archived': 0,
    });
  }

  final List<Map<String, Object?>> txns = <Map<String, Object?>>[];
  for (final Map<String, Object?> t in list('txns')) {
    final String? at = t['occurredAt'] as String?;
    txns.add(<String, Object?>{
      'kind': t['kind'] ?? 'expense',
      'amount': (t['amount'] as num?)?.toInt() ?? 0,
      'occurred_at':
          at == null ? now : DateTime.parse(at).toUtc().millisecondsSinceEpoch,
      'account_id': (t['accountId'] as num?)?.toInt() ?? 0,
      'to_account_id': null,
      'category_id': (t['categoryId'] as num?)?.toInt(),
      'note': t['note'],
      'merchant': null,
      'source': t['source'] ?? 'manual',
      'external_id': null,
      'dedup_hash': null,
      'in_budget': 1,
      'deleted_at': null,
      'created_at': now,
      'updated_at': now,
    });
  }

  return <String, List<Map<String, Object?>>>{
    'accounts': accounts,
    'categories': cats,
    'txns': txns,
  };
}

extension RepoBackup on Repo {
  /// 全量导出：直接取原始行，不裁剪任何字段，保证导出什么就能恢复什么。
  Future<Map<String, Object?>> exportBackup() async {
    final Map<String, Object?> data = <String, Object?>{'schema': kDbVersion};
    for (final String t in kBackupTables) {
      data[t] = await db.query(t);
    }
    return data;
  }

  /// 恢复备份。
  ///
  /// format 2（带 schema 字段）走全量恢复，保留原始 id，外键关系不变；
  /// 更早的导出只含 accounts/categories/txns 的部分字段，只能尽力恢复。
  Future<BackupSummary> importBackup(Map<String, Object?> data) async {
    // 目标库每张表真实有哪些列
    final Map<String, Set<String>> columns = <String, Set<String>>{};
    for (final String t in kBackupTables) {
      columns[t] = <String>{
        for (final Map<String, Object?> r
            in await db.rawQuery('PRAGMA table_info($t)'))
          r['name']! as String,
      };
    }

    final BackupPlan plan = planBackupRestore(
      data,
      columns: columns,
      currentSchema: kDbVersion,
    );

    final Map<String, int> counts = <String, int>{};
    await db.transaction((Transaction txn) async {
      for (final String t in kBackupTables.reversed) {
        await txn.delete(t);
      }
      for (final String t in kBackupTables) {
        final List<Map<String, Object?>> rows =
            plan.tables[t] ?? const <Map<String, Object?>>[];
        for (final Map<String, Object?> row in rows) {
          await txn.insert(t, row);
        }
        counts[t] = rows.length;
      }
    });

    return BackupSummary(counts: counts, full: plan.full);
  }
}

/// 恢复结果：每张表实际写入的行数。
class BackupSummary {
  const BackupSummary({required this.counts, required this.full});

  final Map<String, int> counts;

  /// true = format 2 全量备份；false = 旧版部分备份
  final bool full;

  int count(String table) => counts[table] ?? 0;

  int get accounts => count('accounts');
  int get categories => count('categories');
  int get txns => count('txns');
}

class BackupException implements Exception {
  BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}
