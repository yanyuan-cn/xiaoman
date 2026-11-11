import 'db.dart';

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.type,
    required this.initialBalance,
    this.isLiability = false,
    this.includeInTotal = true,
    this.note,
  });

  final int id;
  final String name;
  final String type;
  final int initialBalance;
  final bool isLiability;
  final bool includeInTotal;

  /// 账户备注，显示在名称后面（如「工资卡，每月 15 号发薪」）。
  final String? note;

  /// 选择账户时显示的名字：有备注就带上，方便区分同一家银行的不同卡。
  String get displayName {
    final String n = (note ?? '').trim();
    return n.isEmpty ? name : '$name · $n';
  }

  factory Account.fromMap(Map<String, Object?> m) => Account(
        id: m['id']! as int,
        name: m['name']! as String,
        type: m['type']! as String,
        initialBalance: (m['initial_balance'] as int?) ?? 0,
        isLiability: ((m['is_liability'] as num?)?.toInt() ?? 0) == 1,
        includeInTotal: ((m['include_in_total'] as num?)?.toInt() ?? 1) == 1,
        note: m['note'] as String?,
      );

  /// 老版本 `accounts.type` 存的是英文 key，这里兜底转成中文。
  /// 新数据存的就是名字，直接返回。
  static String typeLabel(String type) {
    final String? legacy = kLegacyAccountTypes[type];
    if (legacy != null) return legacy;
    return type;
  }
}

/// 账户类型（活期存款 / 银行卡 / 自定义…）。
class AccountType {
  const AccountType({
    required this.id,
    required this.name,
    this.sort = 0,
    this.archived = false,
  });

  final int id;
  final String name;
  final int sort;
  final bool archived;

  factory AccountType.fromMap(Map<String, Object?> m) => AccountType(
        id: m['id']! as int,
        name: (m['name'] as String?) ?? '',
        sort: (m['sort'] as num?)?.toInt() ?? 0,
        archived: ((m['archived'] as num?)?.toInt() ?? 0) == 1,
      );
}

class TxnCategory {
  const TxnCategory({
    required this.id,
    required this.name,
    required this.kind,
    required this.sort,
    this.parentId,
  });

  final int id;
  final String name;
  final String kind;
  final int sort;
  final int? parentId;

  bool get isTop => parentId == null;

  factory TxnCategory.fromMap(Map<String, Object?> m) => TxnCategory(
        id: m['id']! as int,
        name: m['name']! as String,
        kind: m['kind']! as String,
        sort: (m['sort'] as int?) ?? 0,
        parentId: m['parent_id'] as int?,
      );
}

class BudgetRule {
  const BudgetRule({
    required this.scope,
    required this.amount,
    this.categoryId,
  });

  /// 'all' = 总预算；'category' = 某个一级分类的预算
  final String scope;
  final int amount;
  final int? categoryId;

  bool get isAll => scope == 'all';

  factory BudgetRule.fromMap(Map<String, Object?> m) => BudgetRule(
        scope: (m['scope'] as String?) ?? 'all',
        amount: (m['amount'] as num?)?.toInt() ?? 0,
        categoryId: (m['category_id'] as num?)?.toInt(),
      );
}

class RecurringRule {
  const RecurringRule({
    required this.id,
    required this.name,
    required this.amount,
    required this.dayOfMonth,
    required this.fromAccountId,
    this.toAccountId,
    this.categoryId,
    this.note,
    this.active = true,
    this.lastRunAt,
    this.createdAt = 0,
  });

  final int id;
  final String name;
  final int amount;
  final int dayOfMonth;
  final int fromAccountId;
  final int? toAccountId;
  final int? categoryId;
  final String? note;
  final bool active;
  final int? lastRunAt;
  final int createdAt;

  bool get isRepayment => toAccountId != null;

  factory RecurringRule.fromMap(Map<String, Object?> m) => RecurringRule(
        id: m['id']! as int,
        name: (m['name'] as String?) ?? '',
        amount: (m['amount'] as num?)?.toInt() ?? 0,
        dayOfMonth: (m['day_of_month'] as num?)?.toInt() ?? 1,
        fromAccountId: (m['from_account_id'] as num?)?.toInt() ?? 0,
        toAccountId: (m['to_account_id'] as num?)?.toInt(),
        categoryId: (m['category_id'] as num?)?.toInt(),
        note: m['note'] as String?,
        active: ((m['active'] as num?)?.toInt() ?? 1) == 1,
        lastRunAt: (m['last_run_at'] as num?)?.toInt(),
        createdAt: (m['created_at'] as num?)?.toInt() ?? 0,
      );
}

/// 这笔钱花得值不值。0 = 没标，1 = 值得，2 = 一般，3 = 后悔。
///
/// 只用三档：多到五档没人愿意点，少到两档又表达不了「还行」。
enum XmMood {
  none(0, '未标记', ''),
  worth(1, '值得', '😊'),
  normal(2, '一般', '😐'),
  regret(3, '后悔', '😞');

  const XmMood(this.code, this.label, this.emoji);

  final int code;
  final String label;
  final String emoji;

  bool get isSet => this != XmMood.none;

  static XmMood fromCode(int? code) {
    for (final XmMood m in XmMood.values) {
      if (m.code == code) return m;
    }
    return XmMood.none;
  }
}

/// 想买清单里的一项。
class Wish {
  const Wish({
    required this.id,
    required this.name,
    required this.price,
    this.targetAtMs,
    this.note,
    this.imagePath,
    this.bought = false,
    this.createdAtMs = 0,
    this.updatedAtMs = 0,
  });

  final int id;
  final String name;

  /// 目标价格（分）
  final int price;

  /// 预计购买日期（UTC 毫秒），空表示没定
  final int? targetAtMs;

  final String? note;

  /// 图片文件在应用私有目录里的绝对路径
  final String? imagePath;

  final bool bought;
  final int createdAtMs;
  final int updatedAtMs;

  DateTime? get targetAt => targetAtMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(targetAtMs!, isUtc: true).toLocal();

  DateTime get createdAt =>
      DateTime.fromMillisecondsSinceEpoch(createdAtMs).toLocal();

  /// 距离预计购买日期还有几天；没定日期返回 null。
  int? get daysLeft {
    final DateTime? t = targetAt;
    if (t == null) return null;
    final DateTime today = DateTime.now();
    final DateTime a = DateTime(today.year, today.month, today.day);
    final DateTime b = DateTime(t.year, t.month, t.day);
    return b.difference(a).inDays;
  }

  factory Wish.fromMap(Map<String, Object?> m) => Wish(
        id: m['id']! as int,
        name: (m['name'] as String?) ?? '',
        price: (m['price'] as num?)?.toInt() ?? 0,
        targetAtMs: (m['target_at'] as num?)?.toInt(),
        note: m['note'] as String?,
        imagePath: m['image_path'] as String?,
        bought: ((m['bought'] as num?)?.toInt() ?? 0) == 1,
        createdAtMs: (m['created_at'] as num?)?.toInt() ?? 0,
        updatedAtMs: (m['updated_at'] as num?)?.toInt() ?? 0,
      );
}

/// 记账时的场景标签（「当时在干嘛」）。存字符串，方便以后加词。
class XmWorkState {
  XmWorkState._();

  static const List<String> presets = <String>[
    '加班',
    '应酬',
    '情绪',
    '日常',
    '社交',
    '工作',
  ];
}

class Txn {
  const Txn({
    required this.id,
    required this.kind,
    required this.amount,
    required this.occurredAtMs,
    required this.accountId,
    required this.source,
    this.toAccountId,
    this.categoryId,
    this.note,
    this.merchant,
    this.externalId,
    this.inBudget = true,
    this.mood = 0,
    this.workState,
    this.createdAtMs = 0,
    this.updatedAtMs = 0,
  });

  final int id;
  final String kind;
  final int amount;
  final int occurredAtMs;
  final int accountId;
  final String source;
  final int? toAccountId;
  final int? categoryId;
  final String? note;
  final String? merchant;
  final String? externalId;

  /// 是否计入预算。转账默认不计入。
  final bool inBudget;

  /// 情绪标记，见 [XmMood]。
  final int mood;

  /// 状态标签，如「加班」，空表示没填。
  final String? workState;

  final int createdAtMs;
  final int updatedAtMs;

  XmMood get moodEnum => XmMood.fromCode(mood);

  DateTime get occurredAt =>
      DateTime.fromMillisecondsSinceEpoch(occurredAtMs, isUtc: true).toLocal();

  bool get isExpense => kind == 'expense';
  bool get isIncome => kind == 'income';
  bool get isTransfer => kind == 'transfer';

  String get sourceLabel {
    switch (source) {
      case 'manual':
        return '手工记账';
      case 'migration':
        return '从其他 App 导入';
      case 'alipay':
        return '支付宝导入';
      case 'wechat':
        return '微信导入';
      case 'auto':
        return '定期扣款（自动生成）';
      case 'auto_notify':
        return '通知自动记账';
      case 'auto_sms':
        return '短信自动记账';
      default:
        return source;
    }
  }

  factory Txn.fromMap(Map<String, Object?> m) => Txn(
        id: m['id']! as int,
        kind: m['kind']! as String,
        amount: (m['amount']! as num).toInt(),
        occurredAtMs: (m['occurred_at']! as num).toInt(),
        accountId: (m['account_id']! as num).toInt(),
        source: (m['source'] as String?) ?? 'manual',
        toAccountId: (m['to_account_id'] as num?)?.toInt(),
        categoryId: (m['category_id'] as num?)?.toInt(),
        note: m['note'] as String?,
        merchant: m['merchant'] as String?,
        externalId: m['external_id'] as String?,
        inBudget: ((m['in_budget'] as num?)?.toInt() ?? 1) == 1,
        mood: (m['mood'] as num?)?.toInt() ?? 0,
        workState: m['work_state'] as String?,
        createdAtMs: (m['created_at'] as num?)?.toInt() ?? 0,
        updatedAtMs: (m['updated_at'] as num?)?.toInt() ?? 0,
      );
}
