import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

const String kDbName = 'xiaoman.db';
const int kDbVersion = 5;

/// 内置的账户类型。`accounts.type` 里存的是**名字**，不是 key，
/// 这样用户改名时只需要 UPDATE 一次，不用维护一张映射表。
const List<String> kSeedAccountTypes = <String>[
  '活期存款',
  '定期存款',
  '银行卡',
  '电子钱包',
  '现金',
];

/// 老版本 `accounts.type` 存的是英文 key，迁移时换成名字。
const Map<String, String> kLegacyAccountTypes = <String, String>{
  'savings': '活期存款',
  'deposit': '定期存款',
  'bank': '银行卡',
  'ewallet': '电子钱包',
  'cash': '现金',
};

Future<Database> openLedgerDb() async {
  final String path = p.join(await getDatabasesPath(), kDbName);
  return openDatabase(
    path,
    version: kDbVersion,
    onConfigure: (Database db) => db.execute('PRAGMA foreign_keys = ON'),
    onCreate: _createSchema,
    onUpgrade: _upgrade,
  );
}

const List<String> _schema = <String>[
  '''
  CREATE TABLE accounts(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    type TEXT NOT NULL,
    initial_balance INTEGER NOT NULL DEFAULT 0,
    is_liability INTEGER NOT NULL DEFAULT 0,
    include_in_total INTEGER NOT NULL DEFAULT 1,
    note TEXT,
    sort INTEGER NOT NULL DEFAULT 0,
    archived INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE categories(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    kind TEXT NOT NULL,
    parent_id INTEGER,
    sort INTEGER NOT NULL DEFAULT 0,
    archived INTEGER NOT NULL DEFAULT 0
  )
  ''',
  '''
  CREATE TABLE txns(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    kind TEXT NOT NULL,
    amount INTEGER NOT NULL,
    occurred_at INTEGER NOT NULL,
    account_id INTEGER NOT NULL,
    to_account_id INTEGER,
    category_id INTEGER,
    note TEXT,
    merchant TEXT,
    source TEXT NOT NULL DEFAULT 'manual',
    external_id TEXT,
    dedup_hash TEXT,
    in_budget INTEGER NOT NULL DEFAULT 1,
    mood INTEGER NOT NULL DEFAULT 0,
    work_state TEXT,
    deleted_at INTEGER,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )
  ''',
  'CREATE UNIQUE INDEX idx_txns_external ON txns(source, external_id) '
      'WHERE external_id IS NOT NULL',
  'CREATE INDEX idx_txns_time ON txns(occurred_at DESC)',
  'CREATE INDEX idx_txns_dedup ON txns(dedup_hash)',
  'CREATE INDEX idx_txns_account ON txns(account_id, occurred_at DESC)',
  '''
  CREATE TABLE import_batches(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source TEXT NOT NULL,
    file_name TEXT,
    imported_at INTEGER NOT NULL,
    total INTEGER NOT NULL DEFAULT 0,
    inserted INTEGER NOT NULL DEFAULT 0,
    skipped INTEGER NOT NULL DEFAULT 0
  )
  ''',
  '''
  CREATE TABLE import_rows(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    batch_id INTEGER NOT NULL,
    raw_json TEXT,
    txn_id INTEGER,
    result TEXT
  )
  ''',
  '''
  CREATE TABLE recurring_rules(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    amount INTEGER NOT NULL,
    day_of_month INTEGER NOT NULL,
    from_account_id INTEGER NOT NULL,
    to_account_id INTEGER,
    category_id INTEGER,
    note TEXT,
    active INTEGER NOT NULL DEFAULT 1,
    last_run_at INTEGER,
    created_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE budgets(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    scope TEXT NOT NULL,
    category_id INTEGER,
    amount INTEGER NOT NULL DEFAULT 0,
    active INTEGER NOT NULL DEFAULT 1,
    created_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE settings(
    key TEXT PRIMARY KEY,
    value TEXT
  )
  ''',
  '''
  CREATE TABLE account_types(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    sort INTEGER NOT NULL DEFAULT 0,
    archived INTEGER NOT NULL DEFAULT 0
  )
  ''',
];

Future<void> _createSchema(Database db, int version) async {
  final Batch batch = db.batch();
  for (final String sql in _schema) {
    batch.execute(sql);
  }
  await batch.commit(noResult: true);
  await _seed(db);
}

/// v1 -> v2：账户增加「负债 / 计入总资产」，并预建定期扣款规则表
Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
  if (oldVersion < 2) {
    final List<String> columns = <String>[
      for (final Map<String, Object?> r in await db.rawQuery(
          'PRAGMA table_info(accounts)'))
        r['name']! as String,
    ];
    if (!columns.contains('is_liability')) {
      await db.execute(
          'ALTER TABLE accounts ADD COLUMN is_liability INTEGER NOT NULL DEFAULT 0');
    }
    if (!columns.contains('include_in_total')) {
      await db.execute(
          'ALTER TABLE accounts ADD COLUMN include_in_total INTEGER NOT NULL DEFAULT 1');
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS recurring_rules(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        amount INTEGER NOT NULL,
        day_of_month INTEGER NOT NULL,
        from_account_id INTEGER NOT NULL,
        to_account_id INTEGER,
        category_id INTEGER,
        note TEXT,
        active INTEGER NOT NULL DEFAULT 1,
        last_run_at INTEGER,
        created_at INTEGER NOT NULL
      )
    ''');
  }

  if (oldVersion < 3) {
    final List<String> columns = <String>[
      for (final Map<String, Object?> r in await db.rawQuery(
          'PRAGMA table_info(txns)'))
        r['name']! as String,
    ];
    if (!columns.contains('in_budget')) {
      await db.execute(
          'ALTER TABLE txns ADD COLUMN in_budget INTEGER NOT NULL DEFAULT 1');
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS budgets(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        scope TEXT NOT NULL,
        category_id INTEGER,
        amount INTEGER NOT NULL DEFAULT 0,
        active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL
      )
    ''');
  }

  // v4：流水加「表情 / 状态」，账户加「备注」。
  if (oldVersion < 4) {
    final List<String> txnCols = <String>[
      for (final Map<String, Object?> r in await db.rawQuery(
          'PRAGMA table_info(txns)'))
        r['name']! as String,
    ];
    if (!txnCols.contains('mood')) {
      await db.execute(
          'ALTER TABLE txns ADD COLUMN mood INTEGER NOT NULL DEFAULT 0');
    }
    if (!txnCols.contains('work_state')) {
      await db.execute('ALTER TABLE txns ADD COLUMN work_state TEXT');
    }

    final List<String> accCols = <String>[
      for (final Map<String, Object?> r in await db.rawQuery(
          'PRAGMA table_info(accounts)'))
        r['name']! as String,
    ];
    if (!accCols.contains('note')) {
      await db.execute('ALTER TABLE accounts ADD COLUMN note TEXT');
    }
  }

  // v5：账户类型改成可自定义（一张表 + 把老的英文 key 换成中文名）
  if (oldVersion < 5) {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS account_types(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        sort INTEGER NOT NULL DEFAULT 0,
        archived INTEGER NOT NULL DEFAULT 0
      )
    ''');
    final List<Map<String, Object?>> existing =
        await db.query('account_types', limit: 1);
    if (existing.isEmpty) {
      int i = 0;
      for (final String name in kSeedAccountTypes) {
        await db.insert('account_types', <String, Object?>{
          'name': name,
          'sort': i++,
          'archived': 0,
        });
      }
    }
    for (final MapEntry<String, String> e in kLegacyAccountTypes.entries) {
      await db.update(
        'accounts',
        <String, Object?>{'type': e.value},
        where: 'type = ?',
        whereArgs: <Object>[e.key],
      );
    }
  }
}
const List<List<String>> _seedAccounts = <List<String>>[
  <String>['支付宝', '电子钱包'],
  <String>['微信', '电子钱包'],
  <String>['招商银行工资卡', '银行卡'],
  <String>['重庆农村商业银行', '银行卡'],
  <String>['工商银行', '银行卡'],
];

/// 支出一级分类 -> 二级分类（来自用户 2026 年真实账单）
const Map<String, List<String>> _expenseTree = <String, List<String>>{
  '食品餐饮': <String>['早餐', '午餐', '晚餐', '生鲜食品', '休闲零食', '饮料酒水', '聚餐', '请客吃饭'],
  '购物消费': <String>['日常家居', '服饰运动', '个护美妆', '虚拟充值', '手机数码', '宠物用品', '母婴玩具', '生活电器'],
  '居家生活': <String>['话费宽带', '水费', '电费', '燃气费', '家政清洁', '车位费', '房租还贷'],
  '出行交通': <String>['打车', '公共交通', '加油', '停车费', '保养修车', '充电', '火车'],
  '休闲娱乐': <String>['运动健身', '棋牌桌游', '电影唱歌', '旅游度假'],
  '健康医疗': <String>['买药', '门诊', '理疗', '体检'],
  '文化教育': <String>['书报杂志', '学费', '课程培训'],
  '送礼人情': <String>['礼物', '孝敬长辈', '红包', '借出'],
  '其他': <String>['罚款赔偿', '理财支出', '其他支出'],
};

/// 收入一级分类
const List<String> _incomeTop = <String>[
  '工资', '中奖', '礼金人情', '报销', '借入', '二手闲置', '补贴', '其他收入',
];

Future<void> _seed(Database db) async {
  final int now = DateTime.now().millisecondsSinceEpoch;

  int typeSort = 0;
  for (final String name in kSeedAccountTypes) {
    await db.insert('account_types', <String, Object?>{
      'name': name,
      'sort': typeSort++,
      'archived': 0,
    });
  }

  for (int i = 0; i < _seedAccounts.length; i++) {
    await db.insert('accounts', <String, Object?>{
      'name': _seedAccounts[i][0],
      'type': _seedAccounts[i][1],
      'initial_balance': 0,
      'is_liability': 0,
      'include_in_total': 1,
      'sort': i,
      'archived': 0,
      'created_at': now,
    });
  }

  int topSort = 0;
  for (final MapEntry<String, List<String>> entry in _expenseTree.entries) {
    final int parentId = await db.insert('categories', <String, Object?>{
      'name': entry.key,
      'kind': 'expense',
      'parent_id': null,
      'sort': topSort++,
      'archived': 0,
    });
    int childSort = 0;
    for (final String child in entry.value) {
      await db.insert('categories', <String, Object?>{
        'name': child,
        'kind': 'expense',
        'parent_id': parentId,
        'sort': childSort++,
        'archived': 0,
      });
    }
  }

  int incomeSort = 0;
  for (final String name in _incomeTop) {
    await db.insert('categories', <String, Object?>{
      'name': name,
      'kind': 'income',
      'parent_id': null,
      'sort': incomeSort++,
      'archived': 0,
    });
  }
}
