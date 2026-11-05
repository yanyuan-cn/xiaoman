import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../state/data_bus.dart';
import '../../state/ledger.dart';
import '../../ui/components.dart';
import '../../ui/motion.dart';
import '../budget/budget_page.dart';
import '../detail/txn_detail_page.dart';
import '../import/import_page.dart';
import '../record/record_page.dart';
import '../search/search_page.dart';

/// 首页：概览 + 二级分类菜单 + 当日流水 + 底部记账条。
class LedgerPage extends StatefulWidget {
  const LedgerPage({super.key, required this.repo});

  final Repo repo;

  @override
  State<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends State<LedgerPage> {
  late final LedgerState _state = LedgerState(widget.repo);

  /// 记账条的矩形——记账面板就是从这里长出来的。
  final GlobalKey _barKey = GlobalKey();

  /// 每行一个 key，点开时用它算起始矩形。
  final Map<int, GlobalKey> _rowKeys = <int, GlobalKey>{};

  /// 二级菜单当前选中的分类（null = 全部）。
  int? _filterCategory;

  @override
  void initState() {
    super.initState();
    DataBus.instance.addListener(_onDataChanged);
    _runRecurring();
  }

  @override
  void dispose() {
    DataBus.instance.removeListener(_onDataChanged);
    _state.dispose();
    super.dispose();
  }

  void _onDataChanged() => _state.load();

  /// 定期扣款到点自动生成账单。
  Future<void> _runRecurring() async {
    final List<int> ids = await widget.repo.runDueRecurringRules();
    if (!mounted || ids.isEmpty) return;
    await _state.load();
    if (!mounted) return;
    showUndoSnack(
      context,
      message: '已自动记 ${ids.length} 笔定期账单',
      onUndo: () async {
        await widget.repo.undoAutoTxns(ids);
        if (mounted) await _state.load();
      },
    );
  }

  // ------------------------------------------------------------------
  // 跳转
  // ------------------------------------------------------------------

  Future<void> _openSearch() async {
    await Navigator.of(context).push<void>(
      XmExpandRoute<void>(
        builder: (BuildContext _) => SearchPage(repo: widget.repo),
      ),
    );
    if (mounted) await _state.load();
  }

  /// 展开记账面板：从记账条的位置长出来，而不是从屏幕底部滑上来。
  Future<void> _openRecord({String kind = 'expense'}) async {
    final Rect? from = xmGlobalRect(_barKey);
    final bool? saved = await showXmExpandSheet<bool>(
      context: context,
      from: from,
      heightFactor: RecordPage.heightFactor,
      builder: (BuildContext _) => RecordPage(
        repo: widget.repo,
        initialKind: kind,
        initialCategoryId: _filterCategory,
      ),
    );
    if (saved == true) DataBus.instance.bump();
  }

  Future<void> _openDetail(Txn t) async {
    final Rect? from = xmGlobalRect(_rowKeys[t.id]);
    // 只有真的改了（编辑 / 删除）才整表重查，单纯看一眼不动数据，
    // 免得返回动画还没结束就丢一次全量查询进来。
    final bool? changed = await Navigator.of(context).push<bool>(
      XmExpandRoute<bool>(
        from: from,
        builder: (BuildContext _) => TxnDetailPage(repo: widget.repo, txn: t),
      ),
    );
    if (changed == true && mounted) DataBus.instance.bump();
  }

  Future<void> _onDelete(Txn t) async {
    await _state.delete(t);
    DataBus.instance.bump();
    if (!mounted) return;
    showUndoSnack(context, message: '已删除', onUndo: () => _state.undoDelete());
  }

  Future<void> _openImport() async {
    await Navigator.of(context).push<void>(
      XmExpandRoute<void>(
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(n == 0 ? '没有可撤销的导入' : '已撤销 $n 笔')));
  }

  Future<void> _openBudget() async {
    await Navigator.of(context).push<bool>(
      XmExpandRoute<bool>(
        builder: (BuildContext _) => BudgetPage(repo: widget.repo),
      ),
    );
    if (mounted) await _state.load();
  }

  // ------------------------------------------------------------------
  // 计算
  // ------------------------------------------------------------------

  /// 当前筛选下的流水。
  List<Txn> get _visible {
    final int? cat = _filterCategory;
    if (cat == null) return _state.txns;
    return <Txn>[
      for (final Txn t in _state.txns)
        if (t.categoryId == cat ||
            (_state.categoryById[t.categoryId]?.parentId == cat))
          t,
    ];
  }

  /// 二级菜单：全部 + 本月真正用到的支出一级分类（最多 8 个）。
  List<MapEntry<int?, String>> get _menu {
    final Map<int, int> counts = <int, int>{};
    for (final Txn t in _state.txns) {
      if (t.isTransfer) continue;
      final TxnCategory? c =
          t.categoryId == null ? null : _state.categoryById[t.categoryId];
      final int id = c?.parentId ?? c?.id ?? 0;
      if (id == 0) continue;
      counts[id] = (counts[id] ?? 0) + t.amount;
    }
    final List<int> ids = counts.keys.toList()
      ..sort((int a, int b) => counts[b]!.compareTo(counts[a]!));
    return <MapEntry<int?, String>>[
      const MapEntry<int?, String>(null, '全部'),
      for (final int id in ids.take(8))
        MapEntry<int?, String>(id, _state.categoryById[id]?.name ?? '其他'),
    ];
  }

  int get _todayExpense {
    final DateTime now = DateTime.now();
    int sum = 0;
    for (final Txn t in _state.txns) {
      if (!t.isExpense) continue;
      final DateTime d = t.occurredAt;
      if (d.year == now.year && d.month == now.month && d.day == now.day) {
        sum += t.amount;
      }
    }
    return sum;
  }

  // ------------------------------------------------------------------
  // 界面
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _state,
      builder: (BuildContext context, Widget? child) {
        return Scaffold(
          backgroundColor: Xm.bg,
          appBar: AppBar(
            title: const Text('小满'),
            actions: <Widget>[
              XmIconButton(
                icon: Icons.search_rounded,
                tooltip: '搜索',
                onTap: _openSearch,
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                tooltip: '更多',
                icon: const Icon(Icons.more_horiz_rounded, size: 20),
                onSelected: (String value) {
                  if (value == 'import') _openImport();
                  if (value == 'undo') _undoImport();
                  if (value == 'reload') _state.load();
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
                  PopupMenuItem<String>(
                    value: 'reload',
                    child: Text('刷新数据'),
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

  Widget _periodBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: <Widget>[
          _circleButton(Icons.chevron_left_rounded, () => _state.shiftMonth(-1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              fmtMonth(_state.month),
              style: Xm.text(17, FontWeight.w700, spacing: -0.2),
            ),
          ),
          _circleButton(Icons.chevron_right_rounded, () => _state.shiftMonth(1)),
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
        Positioned(left: 0, right: 0, bottom: 94, child: _recordBar()),
      ],
    );
  }

  Widget _list() {
    final Map<int, Account> acc = _state.accountById;
    final Map<int, TxnCategory> cat = _state.categoryById;
    final List<Txn> visible = _visible;

    final List<Widget> children = <Widget>[
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _hero(),
      ),
      const SizedBox(height: 16),
      _menuRow(),
      const SizedBox(height: 6),
    ];

    if (visible.isEmpty) {
      children.add(_empty());
    } else {
      String? lastKey;
      List<Widget> rows = <Widget>[];
      int i = 0;

      for (final Txn t in visible) {
        final String key = fmtDayKey(t.occurredAt);
        if (key != lastKey) {
          if (rows.isNotEmpty) {
            children.add(_dayCard(rows));
            rows = <Widget>[];
          }
          lastKey = key;
          children.add(_dayHeader(t.occurredAt, _dayExpense(t.occurredAt)));
        }
        final Widget row = XmSwipeDelete(
          onDelete: () => _onDelete(t),
          child: _row(t, acc, cat, first: rows.isEmpty),
        );
        // 只有前 6 条做入场动画：列表一长，几十个 Timer + AnimationController
        // 同时启动就是切页掉帧的直接原因。
        rows.add(i < 6
            ? XmEntrance(
                index: i,
                step: 40,
                base: 40,
                offsetY: 8,
                child: row,
              )
            : row);
        i++;
      }
      if (rows.isNotEmpty) children.add(_dayCard(rows));
    }

    children.add(const SizedBox(height: 170));

    return ListView(
      padding: EdgeInsets.zero,
      children: children,
    );
  }

  Widget _menuRow() {
    final List<MapEntry<int?, String>> menu = _menu;
    int index = menu.indexWhere(
        (MapEntry<int?, String> e) => e.key == _filterCategory);
    if (index < 0) index = 0;
    return XmScrollTabs(
      items: <String>[for (final MapEntry<int?, String> e in menu) e.value],
      index: index,
      onTap: (int i) => setState(() => _filterCategory = menu[i].key),
    );
  }

  Widget _dayCard(List<Widget> rows) => XmCard(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        radius: 18,
        child: Column(children: rows),
      );

  int _dayExpense(DateTime day) {
    int sum = 0;
    final String key = fmtDayKey(day);
    for (final Txn t in _visible) {
      if (t.isExpense && t.categoryId != null && fmtDayKey(t.occurredAt) == key) {
        sum += t.amount;
      }
    }
    return sum;
  }

  Widget _hero() {
    final bool showBudget = _state.isCurrentPeriod && !_state.loading;
    final MonthSummary s = _state.summary;

    return XmHeroCard(
      margin: const EdgeInsets.only(top: 4),
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
                overdue
                    ? '超支 ¥${formatCents(-remaining)}'
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
        Text(label, style: Xm.text(11, FontWeight.w400, color: Xm.onDarkNote)),
        const SizedBox(height: 3),
        Row(
          children: <Widget>[
            Text('余', style: Xm.text(11, FontWeight.w500, color: Xm.onDarkNote)),
            const SizedBox(width: 3),
            Text(
              '¥${formatCents(remain.abs())}',
              style: Xm.text(
                13,
                FontWeight.w600,
                color: overdue ? const Color(0xFFFF9B90) : Xm.onDarkStrong,
                tabular: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _dayHeader(DateTime d, int expense) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
      child: Row(
        children: <Widget>[
          Text('${fmtMonthDay(d)} · ${fmtWeekday(d)}', style: Xm.caption),
          const Spacer(),
          if (expense > 0)
            Text('支出 ¥${formatCents(expense)}', style: Xm.captionS),
        ],
      ),
    );
  }

  Widget _row(Txn t, Map<int, Account> acc, Map<int, TxnCategory> cat,
      {bool first = false}) {
    final GlobalKey key = _rowKeys.putIfAbsent(t.id, () => GlobalKey());
    final TxnCategory? c = t.categoryId == null ? null : cat[t.categoryId];
    final Account? a = acc[t.accountId];
    final Account? to = t.toAccountId == null ? null : acc[t.toAccountId];
    final XmMood mood = t.moodEnum;

    String title;
    String sub;
    String amount;
    String glyph;
    Color amountColor;

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

    final bool hasState = (t.workState ?? '').isNotEmpty;

    return Material(
      key: key,
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openDetail(t),
        child: Column(
          children: <Widget>[
            if (!first) const XmDivider(indent: 68),
            SizedBox(
              height: 68,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: <Widget>[
                    XmIconBlock.char(glyph, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Flexible(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Xm.body,
                                ),
                              ),
                              if (hasState) ...<Widget>[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: Xm.brandLL,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    t.workState!,
                                    style: Xm.text(10.5, FontWeight.w600,
                                        color: Xm.brand),
                                  ),
                                ),
                              ],
                            ],
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
                    const SizedBox(width: 10),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Text(
                          amount,
                          style: Xm.bodyM.copyWith(color: amountColor),
                        ),
                        if (mood.isSet)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              mood.emoji,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                      ],
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

  /// 记账条：整条可点，展开成记账面板。
  Widget _recordBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Semantics(
        button: true,
        label: '记一笔',
        child: GestureDetector(
          key: _barKey,
          onTap: _openRecord,
          child: Container(
            height: 58,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Xm.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: Xm.fabShadow,
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: Xm.buttonGradient,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.add_rounded,
                      size: 22, color: Colors.white),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('记一笔',
                          style: Xm.text(15, FontWeight.w700, spacing: -0.2)),
                      const SizedBox(height: 2),
                      Text(
                        _todayExpense > 0
                            ? '今日支出 ¥${formatCents(_todayExpense)}'
                            : '今天还没有支出',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Xm.captionS,
                      ),
                    ],
                  ),
                ),
                XmIconButton(
                  icon: Icons.keyboard_arrow_up_rounded,
                  tooltip: '展开记账',
                  onTap: _openRecord,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.only(top: 54),
      child: Column(
        children: <Widget>[
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Xm.brandLL,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(Icons.receipt_long_outlined,
                size: 28, color: Xm.brand),
          ),
          const SizedBox(height: 14),
          Text(
            _filterCategory == null ? '这个月还没有记录' : '这个分类下还没有记录',
            style: TextStyle(fontSize: 14, color: Xm.ink2),
          ),
          const SizedBox(height: 4),
          Text('点下面的「记一笔」开始',
              style: TextStyle(fontSize: 12, color: Xm.ink3)),
        ],
      ),
    );
  }
}
