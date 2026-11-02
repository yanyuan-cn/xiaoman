class Account {
  const Account({
    required this.id,
    required this.name,
    required this.type,
    required this.initialBalance,
  });

  final int id;
  final String name;
  final String type;
  final int initialBalance;

  factory Account.fromMap(Map<String, Object?> m) => Account(
        id: m['id']! as int,
        name: m['name']! as String,
        type: m['type']! as String,
        initialBalance: (m['initial_balance'] as int?) ?? 0,
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

  DateTime get occurredAt =>
      DateTime.fromMillisecondsSinceEpoch(occurredAtMs, isUtc: true).toLocal();

  bool get isExpense => kind == 'expense';

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
      );
}
