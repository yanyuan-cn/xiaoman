import 'package:flutter/foundation.dart';

import '../core/budget_period.dart';
import '../data/models.dart';
import '../data/repo.dart';

class LedgerState extends ChangeNotifier {
  LedgerState(this.repo) {
    load();
  }

  final Repo repo;

  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  bool loading = true;
  List<Txn> txns = const <Txn>[];
  List<Account> accounts = const <Account>[];
  List<TxnCategory> categories = const <TxnCategory>[];
  MonthSummary summary = const MonthSummary();
  Txn? lastDeleted;

  /// 预算：周期来自 settings，金额来自 budgets 表。
  String budgetType = 'month';
  int budgetStartDay = 1;
  int budgetTotal = 0;
  int budgetFood = 0;
  int budgetShop = 0;
  int? foodCategoryId;
  int? shopCategoryId;
  int budgetSpentTotal = 0;
  int budgetSpentFood = 0;
  int budgetSpentShop = 0;

  bool _disposed = false;

  bool get hasBudget => budgetTotal > 0 || budgetFood > 0 || budgetShop > 0;

  bool get isCurrentPeriod {
    final BudgetPeriod p = budgetPeriodOf(budgetType, budgetStartDay);
    final DateTime now = DateTime.now();
    return !now.isBefore(p.start) && now.isBefore(p.end);
  }

  Map<int, Account> get accountById =>
      <int, Account>{for (final Account a in accounts) a.id: a};

  Map<int, TxnCategory> get categoryById =>
      <int, TxnCategory>{for (final TxnCategory c in categories) c.id: c};

  DateTime get monthStart => DateTime(month.year, month.month);
  DateTime get monthEnd => DateTime(month.year, month.month + 1);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    loading = true;
    _notify();
    accounts = await repo.accounts();
    categories = await repo.categories();
    txns = await repo.txnsBetween(monthStart, monthEnd);
    summary = await repo.summaryBetween(monthStart, monthEnd);
    await _loadBudget();
    loading = false;
    _notify();
  }

  Future<void> _loadBudget() async {
    final String? type = await repo.getSetting('budget_type');
    final String? day = await repo.getSetting('budget_start_day');
    budgetType = (type == null || type.isEmpty) ? 'month' : type;
    budgetStartDay = int.tryParse(day ?? '') ?? 1;

    int? foodId;
    int? shopId;
    for (final TxnCategory c in categories) {
      if (c.kind != 'expense' || c.parentId != null) continue;
      if (c.name == '食品餐饮') foodId = c.id;
      if (c.name == '购物消费') shopId = c.id;
    }
    foodCategoryId = foodId;
    shopCategoryId = shopId;

    final List<BudgetRule> rules = await repo.budgets();
    int amountOf(String scope, int? categoryId) {
      for (final BudgetRule r in rules) {
        if (r.scope == scope && r.categoryId == categoryId) return r.amount;
      }
      return 0;
    }

    budgetTotal = amountOf('all', null);
    budgetFood = foodId == null ? 0 : amountOf('category', foodId);
    budgetShop = shopId == null ? 0 : amountOf('category', shopId);

    final BudgetPeriod p = budgetPeriodOf(budgetType, budgetStartDay);
    budgetSpentTotal = await repo.budgetSpent(from: p.start, to: p.end);
    budgetSpentFood = foodId == null
        ? 0
        : await repo.budgetSpent(
            from: p.start,
            to: p.end,
            parentCategoryId: foodId,
          );
    budgetSpentShop = shopId == null
        ? 0
        : await repo.budgetSpent(
            from: p.start,
            to: p.end,
            parentCategoryId: shopId,
          );
  }

  Future<void> shiftMonth(int delta) async {
    month = DateTime(month.year, month.month + delta);
    await load();
  }

  Future<void> backToThisMonth() async {
    month = DateTime(DateTime.now().year, DateTime.now().month);
    await load();
  }

  Future<void> delete(Txn t) async {
    lastDeleted = t;
    await repo.softDelete(t.id);
    await load();
  }

  Future<void> undoDelete() async {
    final Txn? t = lastDeleted;
    if (t == null) return;
    lastDeleted = null;
    await repo.restore(t.id);
    await load();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
