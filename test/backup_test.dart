import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoman/data/repo_backup.dart';

/// 目标库每张表真实存在的列（够测就行，不要求和真库完全一致）。
const Map<String, Set<String>> _columns = <String, Set<String>>{
  'accounts': <String>{
    'id', 'name', 'type', 'initial_balance', 'is_liability',
    'include_in_total', 'note', 'sort', 'archived', 'created_at',
  },
  'categories': <String>{
    'id', 'name', 'kind', 'parent_id', 'sort', 'archived',
  },
  'txns': <String>{
    'id', 'kind', 'amount', 'occurred_at', 'account_id', 'to_account_id',
    'category_id', 'note', 'merchant', 'source', 'external_id',
    'dedup_hash', 'in_budget', 'mood', 'work_state', 'deleted_at',
    'created_at', 'updated_at',
  },
};

Map<String, Object?> _fullBackup({int schema = 4}) => <String, Object?>{
      'schema': schema,
      'accounts': <Map<String, Object?>>[
        <String, Object?>{'id': 1, 'name': '支付宝', 'type': 'ewallet'},
        <String, Object?>{'id': 2, 'name': '招商银行', 'type': 'bank'},
      ],
      'categories': <Map<String, Object?>>[
        <String, Object?>{'id': 1, 'name': '食品餐饮', 'kind': 'expense'},
      ],
      'txns': <Map<String, Object?>>[
        <String, Object?>{
          'id': 10,
          'kind': 'expense',
          'amount': 1234,
          'account_id': 1,
          'mood': 3,
          'work_state': '加班',
        },
      ],
    };

void main() {
  group('planBackupRestore · 全量备份', () {
    test('保留原始行与 id，按固定的表顺序规划', () {
      final BackupPlan plan = planBackupRestore(
        _fullBackup(),
        columns: _columns,
        currentSchema: 4,
      );

      expect(plan.full, isTrue);
      expect(plan.tables['accounts']!.length, 2);
      expect(plan.tables['txns']!.length, 1);
      expect(plan.tables['txns']!.first['amount'], 1234);
      expect(plan.tables['txns']!.first['mood'], 3);
      // accounts 必须排在 txns 前面，否则外键关系会乱
      final List<String> order = plan.tables.keys.toList();
      expect(order.indexOf('accounts'), lessThan(order.indexOf('txns')));
      expect(plan.total, 4);
    });

    test('备份里多出来的列会被裁掉，不会插进目标库', () {
      final Map<String, Object?> data = _fullBackup();
      (data['accounts']! as List<Object?>)[0] = <String, Object?>{
        'id': 1,
        'name': '支付宝',
        'type': 'ewallet',
        'future_column': 'x',
      };

      final BackupPlan plan =
          planBackupRestore(data, columns: _columns, currentSchema: 4);

      expect(plan.tables['accounts']!.first.containsKey('future_column'),
          isFalse);
      expect(plan.tables['accounts']!.first['name'], '支付宝');
    });

    test('目标库没有的表会被忽略', () {
      final Map<String, Object?> data = _fullBackup();
      data['weird_table'] = <Map<String, Object?>>[
        <String, Object?>{'id': 1},
      ];
      data['settings'] = <Map<String, Object?>>[
        <String, Object?>{'key': 'theme_mode', 'value': 'dark'},
      ];

      final BackupPlan plan =
          planBackupRestore(data, columns: _columns, currentSchema: 4);

      // settings 在 kBackupTables 里，但 _columns 没给，所以整表跳过
      expect(plan.tables.containsKey('settings'), isFalse);
      expect(plan.tables.containsKey('weird_table'), isFalse);
    });

    test('空行 / 全是无效列的行直接丢弃', () {
      final Map<String, Object?> data = _fullBackup();
      data['accounts'] = <Map<String, Object?>>[
        <String, Object?>{'id': 1, 'name': '支付宝', 'type': 'ewallet'},
        <String, Object?>{'junk': 1},
        <String, Object?>{},
      ];

      final BackupPlan plan =
          planBackupRestore(data, columns: _columns, currentSchema: 4);

      expect(plan.tables['accounts']!.length, 1);
    });

    test('format:2 但没有 schema，也算全量', () {
      final Map<String, Object?> data = _fullBackup()..['schema'] = 0;
      data['format'] = 2;

      final BackupPlan plan =
          planBackupRestore(data, columns: _columns, currentSchema: 4);

      expect(plan.full, isTrue);
      expect(plan.tables['accounts']!.length, 2);
    });
  });

  group('planBackupRestore · 拒绝坏数据', () {
    test('备份来自更高版本时拒绝，而不是写坏库', () {
      expect(
        () => planBackupRestore(
          _fullBackup(schema: 99),
          columns: _columns,
          currentSchema: 4,
        ),
        throwsA(isA<BackupException>().having(
          (BackupException e) => e.message,
          'message',
          contains('更新的版本'),
        )),
      );
    });

    test('文件里既没有账户也没有流水时拒绝', () {
      expect(
        () => planBackupRestore(
          <String, Object?>{'schema': 4, 'accounts': <Object>[], 'txns': <Object>[]},
          columns: _columns,
          currentSchema: 4,
        ),
        throwsA(isA<BackupException>()),
      );
    });

    test('完全空的 map 也拒绝', () {
      expect(
        () => planBackupRestore(<String, Object?>{
          'foo': 'bar',
        }, columns: _columns, currentSchema: 4),
        throwsA(isA<BackupException>()),
      );
    });
  });

  group('planBackupRestore · 旧版备份（camelCase）', () {
    Map<String, Object?> legacy() => <String, Object?>{
          'accounts': <Map<String, Object?>>[
            <String, Object?>{'id': 7, 'name': '微信', 'type': 'ewallet', 'initialBalance': 5000},
          ],
          'categories': <Map<String, Object?>>[
            <String, Object?>{'id': 3, 'name': '午餐', 'kind': 'expense', 'parentId': 1},
          ],
          'txns': <Map<String, Object?>>[
            <String, Object?>{
              'kind': 'expense',
              'amount': 2350,
              'occurredAt': '2026-03-01T12:30:00.000Z',
              'accountId': 7,
              'categoryId': 3,
              'note': '食堂',
              'source': 'migration',
            },
          ],
        };

    test('字段名从 camelCase 转成表列名', () {
      final BackupPlan plan = planBackupRestore(
        legacy(),
        columns: _columns,
        currentSchema: 4,
        nowMs: 1700000000000,
      );

      expect(plan.full, isFalse);
      expect(plan.tables['accounts']!.first['initial_balance'], 5000);
      expect(plan.tables['categories']!.first['parent_id'], 1);

      final Map<String, Object?> txn = plan.tables['txns']!.first;
      expect(txn['amount'], 2350);
      expect(txn['account_id'], 7);
      expect(txn['note'], '食堂');
      expect(txn['source'], 'migration');
      expect(txn['in_budget'], 1);
    });

    test('occurredAt 解析成 UTC 毫秒', () {
      final BackupPlan plan = planBackupRestore(
        legacy(),
        columns: _columns,
        currentSchema: 4,
      );
      final int ms =
          plan.tables['txns']!.first['occurred_at']! as int;
      expect(DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String(),
          '2026-03-01T12:30:00.000Z');
    });

    test('缺少 occurredAt 时用 nowMs 兜底，不会抛', () {
      final Map<String, Object?> data = legacy();
      (data['txns']! as List<Object?>)[0] =
          <String, Object?>{'kind': 'expense', 'amount': 100};

      final BackupPlan plan = planBackupRestore(
        data,
        columns: _columns,
        currentSchema: 4,
        nowMs: 1700000000000,
      );
      expect(plan.tables['txns']!.first['occurred_at'], 1700000000000);
    });
  });

  test('kBackupTables 的顺序保证父表先于子表', () {
    final List<String> t = kBackupTables;
    expect(t.indexOf('accounts'), lessThan(t.indexOf('txns')));
    expect(t.indexOf('categories'), lessThan(t.indexOf('txns')));
  });
}
