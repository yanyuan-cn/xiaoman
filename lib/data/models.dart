class Account {
  const Account({
    required this.id,
    required this.name,
    required this.type,
    required this.initialBalance,
    this.isLiability = false,
    this.includeInTotal = true,
  });

  final int id;
  final String name;
  final String type;
  final int initialBalance;
  final bool isLiability;
  final bool includeInTotal;

  factory Account.fromMap(Map<String, Object?> m) => Account(
        id: m['id']! as int,
        name: m['name']! as String,
        type: m['type']! as String,
        initialBalance: (m['initial_balance'] as int?) ?? 0,
        isLiability: ((m['is_liability'] as num?)?.toInt() ?? 0) == 1,
        includeInTotal: ((m['include_in_total'] as num?)?.toInt() ?? 1) == 1,
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
  final int createdAtMs;
  final int updatedAtMs;

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
        createdAtMs: (m['created_at'] as num?)?.toInt() ?? 0,
        updatedAtMs: (m['updated_at'] as num?)?.toInt() ?? 0,
      );
}
