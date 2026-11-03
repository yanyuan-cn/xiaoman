import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../state/data_bus.dart';
import '../../state/ledger.dart';
import '../budget/budget_page.dart';
import '../detail/txn_detail_page.dart';
import '../import/import_page.dart';
import '../record/record_page.dart';

class LedgerPage extends StatefulWidget {
  const LedgerPage({super.key, required this.repo});

  final Repo repo;

  @override
  State<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends State<LedgerPage> {
  late final LedgerState _state = LedgerState(widget.repo);

  @override
  void initState() {
    super.initState();
    DataBus.instance.addListener(_onDataChanged);
    _runAutoBills();
  }

  Future<void> _runAutoBills() async {
    final List<int> ids = await widget.repo.runDueRecurringRules();
    if (!mounted || ids.isEmpty) return;
    await _state.load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已自动记 ${ids.length} 笔定期账单'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () async {
            await widget.repo.undoAutoTxns(ids);
            if (mounted) await _state.load();
          },
        ),
      ),
    );
  }

  void _onDataChanged() {
    _state.load();
  }

  @override
  void dispose() {
    DataBus.instance.removeListener(_onDataChanged);
    _state.dispose();
    super.dispose();
  }

  Future<void> _openRecord() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext _) => RecordPage(repo: widget.repo),
      ),
    );
    DataBus.instance.bump();
  }

  Future<void> _openDetail(Txn t) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext _) =>
            TxnDetailPage(repo: widget.repo, txn: t),
      ),
    );
    if (mounted) DataBus.instance.bump();
  }

  Future<void> _onDelete(Txn t) async {
    await _state.delete(t);
    DataBus.instance.bump();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('已删除'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => _state.undoDelete(),
        ),
      ),
    );
  }

  Future<void> _openImport() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => ImportPage(repo: widget.repo),
      ),
    );
    if (mounted) await _state.load();
  }

  Future<void> _undoImport() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('撤销上次导入'),
        content: const Text('会删除最近一次导入的全部记录，手工记的不受影响。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('撤销'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final int n = await widget.repo.undoLastImport();
    await _state.load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(n == 0 ? '没有可撤销的导入' : '已撤销 $n 笔')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _state,
      builder: (BuildContext context, Widget? child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('小满',
                style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 2)),
            actions: <Widget>[
              IconButton(
                tooltip: '刷新',
                onPressed: _state.loading ? null : () => _state.load(),
                icon: const Icon(Icons.refresh),
              ),
              PopupMenuButton<String>(
                onSelected: (String value) {
                  if (value == 'import') _openImport();
                  if (value == 'undo') _undoImport();
                },
                itemBuilder: (BuildContext ctx) => const <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'import',
                    child: Text('导入账单'),
                  ),
                  PopupMenuItem<String>(
                    value: 'undo',
                    child: Text('撤销上次导入'),
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            children: <Widget>[
              _monthBar(),
              _summaryCard(),
              Expanded(child: _list()),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _openRecord,
            icon: const Icon(Icons.add),
            label: const Text('记一笔'),
          ),
        );
      },
    );
  }

  Widget _monthBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: () => _state.shiftMonth(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          Text(
            fmtMonth(_state.month),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          IconButton(
            onPressed: () => _state.shiftMonth(1),
            icon: const Icon(Icons.chevron_right),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => _state.backToThisMonth(),
            child: const Text('本月'),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard() {
    final bool showBudget = _state.isCurrentPeriod && !_state.loading;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF3F7D58),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(0, 16, 0, showBudget ? 10 : 16),
            child: Row(
              children: <Widget>[
                _stat('支出', formatCents(_state.summary.expense), Colors.white),
                _stat('收入', formatCents(_state.summary.income), Colors.white),
                _stat('结余', formatCents(_state.summary.net),
                    const Color(0xFFFFE08A)),
              ],
            ),
          ),
          if (showBudget) _budgetSection(),
        ],
      ),
    );
  }

  Future<void> _openBudget() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext _) => BudgetPage(repo: widget.repo),
      ),
    );
    if (mounted) await _state.load();
  }

  Widget _budgetSection() {
    final LedgerState s = _state;
    if (!s.hasBudget) {
      return InkWell(
        onTap: _openBudget,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 12, 14),
          child: Row(
            children: <Widget>[
              Text(
                '设置预算，看看每月还能花多少',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
              const Spacer(),
              Icon(Icons.chevron_right,
                  size: 18, color: Colors.white.withValues(alpha: 0.8)),
            ],
          ),
        ),
      );
    }

    final int used = s.budgetSpentTotal;
    final int total = s.budgetTotal;
    final int remaining = total - used;
    final double ratio =
        total <= 0 ? 0 : (used / total).clamp(0.0, 1.0).toDouble();
    final Color remainColor = remaining < 0
        ? const Color(0xFFFF8A80)
        : const Color(0xFFFFE08A);

    return InkWell(
      onTap: _openBudget,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Divider(height: 1, color: Colors.white.withValues(alpha: 0.18)),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  total > 0 ? '预算 ¥${formatCents(total)}' : '预算',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                const Spacer(),
                if (total > 0)
                  Text(
                    remaining < 0
                        ? '超支 ¥${formatCents(-remaining)}'
                        : '剩余 ¥${formatCents(remaining)}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: remainColor,
                    ),
                  ),
              ],
            ),
            if (total > 0) ...<Widget>[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 5,
                  backgroundColor: Colors.white.withValues(alpha: 0.22),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    remaining < 0 ? const Color(0xFFFF8A80) : Colors.white,
                  ),
                ),
              ),
            ],
            if (s.budgetFood > 0 || s.budgetShop > 0) ...<Widget>[
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  if (s.budgetFood > 0)
                    Expanded(
                      child: _miniBudget(
                          '餐饮', s.budgetSpentFood, s.budgetFood),
                    ),
                  if (s.budgetFood > 0 && s.budgetShop > 0)
                    const SizedBox(width: 16),
                  if (s.budgetShop > 0)
                    Expanded(
                      child: _miniBudget(
                          '购物', s.budgetSpentShop, s.budgetShop),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _miniBudget(String label, int used, int total) {
    final int remain = total - used;
    final double ratio = (used / total).clamp(0.0, 1.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.75))),
            const SizedBox(width: 6),
            Text(
              remain < 0
                  ? '超 ¥${formatCents(-remain)}'
                  : '余 ¥${formatCents(remain)}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: remain < 0
                    ? const Color(0xFFFF8A80)
                    : Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 3,
            backgroundColor: Colors.white.withValues(alpha: 0.18),
            valueColor: AlwaysStoppedAnimation<Color>(
              remain < 0 ? const Color(0xFFFF8A80) : Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: Colors.white.withValues(alpha: 0.75))),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '¥$value',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list() {
    if (_state.loading && _state.txns.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_state.txns.isEmpty) return _empty();

    final Map<int, Account> acc = _state.accountById;
    final Map<int, TxnCategory> cat = _state.categoryById;
    final List<Widget> items = <Widget>[];
    String? lastKey;
    for (final Txn t in _state.txns) {
      final DateTime d = t.occurredAt;
      final String key = fmtDayKey(d);
      if (key != lastKey) {
        lastKey = key;
        items.add(_dayHeader(d));
      }
      items.add(_row(t, acc, cat));
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: items.length,
      itemBuilder: (BuildContext context, int i) => items[i],
    );
  }

  Widget _dayHeader(DateTime d) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        '${fmtMonthDay(d)} ${fmtWeekday(d)}',
        style: const TextStyle(fontSize: 12, color: Colors.black45),
      ),
    );
  }

  Widget _row(Txn t, Map<int, Account> acc, Map<int, TxnCategory> cat) {
    final TxnCategory? c = t.categoryId == null ? null : cat[t.categoryId];
    final Account? a = acc[t.accountId];
    final Account? to = t.toAccountId == null ? null : acc[t.toAccountId];

    String title;
    String sub;
    String amountText;
    Color amountColor;

    if (t.isTransfer) {
      title = '转账';
      sub = '${a?.name ?? '未知'} → ${to?.name ?? '未知'}';
      if ((t.note ?? '').isNotEmpty) sub = '$sub · ${t.note}';
      amountText = '¥${formatCents(t.amount)}';
      amountColor = Colors.black54;
    } else {
      final TxnCategory? parent =
          (c == null || c.parentId == null) ? null : cat[c.parentId!];
      title = parent == null ? (c?.name ?? '未分类') : '${parent.name} · ${c!.name}';
      final List<String> parts = <String>[
        if (a != null) a.name,
        if ((t.note ?? '').isNotEmpty) t.note!,
      ];
      sub = parts.isEmpty ? fmtDateTime(t.occurredAt) : parts.join(' · ');
      amountText = '${t.isExpense ? '-' : '+'}¥${formatCents(t.amount)}';
      amountColor = t.isExpense ? Colors.black87 : const Color(0xFF2E7D32);
    }

    return InkWell(
      onTap: () => _openDetail(t),
      onLongPress: () => _onDelete(t),
      child: Container(
        color: Colors.white,
        margin: const EdgeInsets.only(bottom: 1),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(
                    sub.isEmpty ? fmtDateTime(t.occurredAt) : sub,
                    style: const TextStyle(fontSize: 12, color: Colors.black45),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              amountText,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: amountColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.receipt_long_outlined, size: 56, color: Colors.black12),
          const SizedBox(height: 12),
          const Text('这个月还没有记录',
              style: TextStyle(color: Colors.black45, fontSize: 14)),
          const SizedBox(height: 4),
          const Text('点右下角「记一笔」开始',
              style: TextStyle(fontSize: 12, color: Colors.black26)),
        ],
      ),
    );
  }
}
