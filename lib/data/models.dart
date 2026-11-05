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

  factory Account.fromMap(Map<String, Object?> m) => Account(
        id: m['id']! as int,
        name: m['name']! as String,
        type: m['type']! as String,
        initialBalance: (m['initial_balance'] as int?) ?? 0,
        isLiability: ((m['is_liability'] as num?)?.toInt() ?? 0) == 1,
        includeInTotal: ((m['include_in_total'] as num?)?.toInt() ?? 1) == 1,
        note: m['note'] as String?,
      );

  static String typeLabel(String type) {
    switch (type) {
      case 'bank':
        return '银行卡';
      case 'ewallet':
        return '电子钱包';
      case 'deposit':
        return '定期存款';
      case 'savings':
        return '活期存款';
      case 'cash':
        return '现金';
      default:
        return '其他';
    }
  }
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

/// 记账时的情绪标记。0 = 没标，1 = 满意，2 = 后悔。
///
/// 只用正面 / 负面两个表情，不做五档评分：记账是一天几十次的动作，
/// 选项一多就没人愿意点。
enum XmMood {
  none(0, '未标记', ''),
  happy(1, '满意', '😌'),
  regret(2, '后悔', '😖');

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

/// 记账时的状态标签（“当时在干什么”）。存字符串，方便以后加词。
class XmWorkState {
  XmWorkState._();

  static const List<String> presets = <String>[
    '工作',
    '加班',
    '休息',
    '通勤',
    '出差',
    '假期',
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
