import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../state/data_bus.dart';
import '../../state/ledger.dart';
import '../../ui/components.dart';
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
    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x6B0A120E),
      builder: (BuildContext _) => RecordPage(repo: widget.repo),
    );
    if (saved == true) DataBus.instance.bump();
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

  Future<void> _openBudget() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext _) => BudgetPage(repo: widget.repo),
      ),
    );
    if (mounted) await _state.load();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _state,
      builder: (BuildContext context, Widget? child) {
        return Scaffold(
          appBar: AppBar(
            // 首页标题是品牌名，不是"首页"（§4.1）
            title: const Text('小满'),
            actions: <Widget>[
              _iconButton(Icons.refresh_rounded, '刷新',
                  _state.loading ? null : () => _state.load()),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                tooltip: '更多',
                icon: const Icon(Icons.more_horiz_rounded),
                onSelected: (String value) {
                  if (value == 'import') _openImport();
                  if (value == 'undo') _undoImport();
                },
                itemBuilder: (BuildContext ctx) =>
                    const <PopupMenuEntry<String>>[
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
              const SizedBox(width: 8),
            ],
          ),
          body: Column(
            children: <Widget>[
              _periodBar(),
              Expanded(child: _content()),
            ],
          ),
        );
      },
    );
  }

  Widget _iconButton(IconData icon, String tooltip, VoidCallback? onTap) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        foregroundColor: Xm.ink2,
        minimumSize: const Size(34, 34),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _periodBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 14),
      child: Row(
        children: <Widget>[
          _circleButton(Icons.chevron_left_rounded, () => _state.shiftMonth(-1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              fmtMonth(_state.month),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
                color: Xm.ink,
              ),
            ),
          ),
          _circleButton(
              Icons.chevron_right_rounded, () => _state.shiftMonth(1)),
          const Spacer(),
          GestureDetector(
            onTap: () => _state.backToThisMonth(),
            child: const XmTag('本月'),
          ),
        ],
      ),
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        iconSize: 18,
        icon: Icon(icon),
        style: IconButton.styleFrom(foregroundColor: Xm.ink2),
      ),
    );
  }

  Widget _content() {
    return Stack(
      children: <Widget>[
        if (_state.loading && _state.txns.isEmpty)
          const Center(child: CircularProgressIndicator())
        else
          _list(),
        Positioned(right: 18, bottom: 94, child: _fab()),
      ],
    );
  }

  Widget _list() {
    final Map<int, Account> acc = _state.accountById;
    final Map<int, TxnCategory> cat = _state.categoryById;

    final List<Widget> children = <Widget>[
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _hero()),
    ];

    if (_state.txns.isEmpty) {
      children.add(_empty());
    } else {
      String? lastKey;
      List<Widget> rows = <Widget>[];
      int i = 0;

      for (final Txn t in _state.txns) {
        final DateTime d = t.occurredAt;
        final String key = fmtDayKey(d);
        if (key != lastKey) {
          if (rows.isNotEmpty) {
            children.add(_dayCard(rows));
            rows = <Widget>[];
          }
          lastKey = key;
          children.add(_dayHeader(d, _dayExpense(d)));
        }
        rows.add(XmEntrance(
          index: i++,
          step: 55,
          base: 80,
          offsetY: 10,
          child: XmSwipeDelete(
            onDelete: () => _onDelete(t),
            child: _row(t, acc, cat, first: rows.isEmpty),
          ),
        ));
      }
      if (rows.isNotEmpty) children.add(_dayCard(rows));
    }

    children.add(const SizedBox(height: 96));

    return ListView(
      padding: EdgeInsets.zero,
      children: children,
    );
  }

  Widget _dayCard(List<Widget> rows) => XmCard(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: Column(children: rows),
      );

  int _dayExpense(DateTime day) {
    int sum = 0;
    for (final Txn t in _state.txns) {
      if (t.isExpense &&
          !t.isTransfer &&
          fmtDayKey(t.occurredAt) == fmtDayKey(day)) {
        sum += t.amount;
      }
    }
    return sum;
  }

  Widget _hero() {
    final bool showBudget = _state.isCurrentPeriod && !_state.loading;
    final MonthSummary s = _state.summary;

    return XmHeroCard(
      margin: const EdgeInsets.only(bottom: 18),
      child: Column(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              _heroStat('支出', formatCents(s.expense), Colors.white,
                  CrossAxisAlignment.start),
              _heroStat('收入', formatCents(s.income), Colors.white,
                  CrossAxisAlignment.center),
              _heroStat('结余', formatCents(s.net), Xm.goldOnDark,
                  CrossAxisAlignment.end),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1, thickness: 1, color: Xm.onDarkLine),
          ),
          _budgetSection(showBudget),
        ],
      ),
    );
  }

  Widget _heroStat(
      String label, String value, Color color, CrossAxisAlignment align) {
    return Expanded(
      child: Column(
        crossAxisAlignment: align,
        children: <Widget>[
          Text(label, style: Xm.onDarkLabelStyle),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: align == CrossAxisAlignment.start
                ? Alignment.centerLeft
                : (align == CrossAxisAlignment.end
                    ? Alignment.centerRight
                    : Alignment.center),
            child: XmAmount(
              text: value,
              style: Xm.amountS.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _budgetSection(bool showBudget) {
    if (!showBudget) return const SizedBox.shrink();

    final LedgerState s = _state;
    if (!s.hasBudget) {
      return InkWell(
        onTap: _openBudget,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            children: <Widget>[
              Text('设置预算，看看每月还能花多少',
                  style: Xm.text(11.5, FontWeight.w400, color: Xm.onDarkNote)),
              const Spacer(),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: Xm.onDarkNote),
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
    final bool overdue = remaining < 0;

    return InkWell(
      onTap: _openBudget,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                '预算 ¥${formatCents(total)}',
                style: Xm.text(11.5, FontWeight.w400, color: Xm.onDarkNote),
              ),
              const SizedBox(width: 10),
              const Spacer(),
              Text(
                overdue ? '超支 ¥${formatCents(-remaining)}'
                    : '剩余 ¥${formatCents(remaining)}',
                style: Xm.amountXS.copyWith(
                  color: overdue ? const Color(0xFFFF9B90) : Xm.goldOnDark,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: XmProgressBar(
              value: ratio,
              height: 6,
              overdue: overdue,
              track: Colors.white.withValues(alpha: 0.16),
            ),
          ),
          if (s.budgetFood > 0 || s.budgetShop > 0) ...<Widget>[
            const SizedBox(height: 2),
            Row(
              children: <Widget>[
                if (s.budgetFood > 0)
                  Expanded(
                    child: _miniBudget('餐饮', s.budgetSpentFood, s.budgetFood),
                  ),
                if (s.budgetFood > 0 && s.budgetShop > 0)
                  const SizedBox(width: 16),
                if (s.budgetShop > 0)
                  Expanded(
                    child: _miniBudget('购物', s.budgetSpentShop, s.budgetShop),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniBudget(String label, int used, int total) {
    final int remain = total - used;
    final bool overdue = remain < 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label,
            style: Xm.text(11, FontWeight.w400, color: Xm.onDarkNote)),
        const SizedBox(height: 3),
        Row(
          children: <Widget>[
            Text('余',
                style: Xm.text(11, FontWeight.w500, color: Xm.onDarkNote)),
            const SizedBox(width: 3),
            Text(
              '¥${formatCents(remain.abs())}',
              style: Xm.text(13, FontWeight.w600,
                  color: overdue ? const Color(0xFFFF9B90) : Xm.onDarkStrong,
                  tabular: true),
            ),
          ],
        ),
      ],
    );
  }

  Widget _dayHeader(DateTime d, int expense) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
      child: Row(
        children: <Widget>[
          Text(
            '${fmtMonthDay(d)} · ${fmtWeekday(d)}',
            style: Xm.caption,
          ),
          const Spacer(),
          if (expense > 0)
            Text('支出 ¥${formatCents(expense)}', style: Xm.captionS),
        ],
      ),
    );
  }

  Widget _row(Txn t, Map<int, Account> acc, Map<int, TxnCategory> cat,
      {bool first = false}) {
    final TxnCategory? c = t.categoryId == null ? null : cat[t.categoryId];
    final Account? a = acc[t.accountId];
    final Account? to = t.toAccountId == null ? null : acc[t.toAccountId];

    String title;
    String sub;
    String amount;
    Color amountColor;
    String glyph;

    if (t.isTransfer) {
      title = '转账';
      sub = '${a?.name ?? '未知'} → ${to?.name ?? '未知'}';
      if ((t.note ?? '').isNotEmpty) sub = '$sub · ${t.note}';
      amount = formatCents(t.amount);
      amountColor = Xm.ink2;
      glyph = '转';
    } else {
      final TxnCategory? parent =
          (c == null || c.parentId == null) ? null : cat[c.parentId!];
      final String catName = parent?.name ?? c?.name ?? '未分类';
      title = (c == null || parent == null) ? catName : '${parent.name} · ${c.name}';
      final List<String> parts = <String>[
        if (a != null) a.name,
        if ((t.note ?? '').isNotEmpty) t.note!,
      ];
      sub = parts.isEmpty ? fmtDateTime(t.occurredAt) : parts.join(' · ');
      amount = '${t.isExpense ? '-' : '+'}${formatCents(t.amount)}';
      amountColor = t.isExpense ? Xm.ink : Xm.income;
      glyph = catName;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openDetail(t),
        child: Column(
          children: <Widget>[
            if (!first) const XmDivider(),
            SizedBox(
              height: 66,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: <Widget>[
                    XmIconBlock.char(glyph),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Xm.body,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Xm.captionS,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      amount,
                      style: Xm.bodyM.copyWith(color: amountColor),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fab() {
    return Semantics(
      button: true,
      label: '记一笔',
      child: GestureDetector(
        onTap: _openRecord,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            gradient: Xm.buttonGradient,
            borderRadius: BorderRadius.circular(Xm.rHero),
            boxShadow: Xm.fabShadow,
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.add_rounded, size: 20, color: Colors.white),
              SizedBox(width: 7),
              Text(
                '记一笔',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: <Widget>[
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Xm.brandLL,
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(Icons.receipt_long_outlined,
                size: 28, color: Xm.brand),
          ),
          const SizedBox(height: 14),
          const Text('这个月还没有记录', style: TextStyle(fontSize: 14, color: Xm.ink2)),
          const SizedBox(height: 4),
          const Text('点右下角「记一笔」开始',
              style: TextStyle(fontSize: 12, color: Xm.ink3)),
        ],
      ),
    );
  }
}
