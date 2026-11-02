import 'package:flutter/foundation.dart';

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

  bool _disposed = false;

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
    loading = false;
    _notify();
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
