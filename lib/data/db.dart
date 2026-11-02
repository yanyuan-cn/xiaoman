import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

const String kDbName = 'xiaoman.db';
const int kDbVersion = 1;

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
    deleted_at INTEGER,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )
  ''',
  'CREATE UNIQUE INDEX idx_txns_external ON txns(source, external_id) '
      'WHERE external_id IS NOT NULL',
  'CREATE INDEX idx_txns_time ON txns(occurred_at DESC)',
  'CREATE INDEX idx_txns_dedup ON txns(dedup_hash)',
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
  CREATE TABLE settings(
    key TEXT PRIMARY KEY,
    value TEXT
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

/// 升级入口。第一版只有 v1，后续加表都在这里按版本号补。
Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
  // 结构变更示例：
  // if (oldVersion < 2) {
  //   await db.execute('ALTER TABLE txns ADD COLUMN xxx TEXT');
  // }
}

const List<List<String>> _seedAccounts = <List<String>>[
  <String>['支付宝', 'ewallet'],
  <String>['微信', 'ewallet'],
  <String>['招商银行工资卡', 'bank'],
  <String>['重庆农村商业银行', 'bank'],
  <String>['工商银行', 'bank'],
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

/// 收入一级分类（原来挤在二级里的，提升为一级）
const List<String> _incomeTop = <String>[
  '工资', '中奖', '礼金人情', '报销', '借入', '二手闲置', '补贴', '其他收入',
];

Future<void> _seed(Database db) async {
  final int now = DateTime.now().millisecondsSinceEpoch;

  for (int i = 0; i < _seedAccounts.length; i++) {
    await db.insert('accounts', <String, Object?>{
      'name': _seedAccounts[i][0],
      'type': _seedAccounts[i][1],
      'initial_balance': 0,
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
