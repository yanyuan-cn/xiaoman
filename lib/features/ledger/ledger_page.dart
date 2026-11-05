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

/// 首页：额度卡（可展开本月账本）+ 超支分类（可展开流水）+ 本月流水。
///
/// 两层「原地展开」是这一版的主结构：额度卡的「本月账本」和分类卡里的
/// 流水都在同一页展开，不跳转。
class LedgerPage extends StatefulWidget {
  const LedgerPage({super.key, required this.repo});

  final Repo repo;

  @override
  State<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends State<LedgerPage> {
  late final LedgerState _state = LedgerState(widget.repo);

  final GlobalKey _fabKey = GlobalKey();
  final Map<int, GlobalKey> _rowKeys = <int, GlobalKey>{};

  /// 额度卡里的「本月账本」是否展开
  bool _bookOpen = false;

  /// 展开着的分类卡 id
  int? _openCategory;

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

  /// 记账面板从右下角那颗按钮的位置长出来。
  Future<void> _openRecord({String kind = 'expense'}) async {
    final Rect? from = xmGlobalRect(_fabKey);
    final bool? saved = await showXmExpandSheet<bool>(
      context: context,
      from: from,
      heightFactor: RecordPage.heightFactor,
      builder: (BuildContext _) => RecordPage(repo: widget.repo, initialKind: kind),
    );
    if (saved == true) DataBus.instance.bump();
  }

  Future<void> _openDetail(Txn t) async {
    final Rect? from = xmGlobalRect(_rowKeys[t.id]);
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

  MonthSummary get _sum => _state.summary;

  /// 本月还能花多少：有预算按预算，没预算按本月结余。
  int get _available =>
      _state.hasBudget ? _state.budgetTotal - _state.budgetSpentTotal : _sum.net;

  /// 本月剩余天数（含今天）。
  int get _daysLeft {
    final DateTime now = DateTime.now();
    final DateTime last = DateTime(now.year, now.month + 1, 0);
    return last.day - now.day + 1;
  }

  int get _dailyQuota {
    final int d = _daysLeft;
    if (d <= 0) return 0;
    return (_available / d).floor();
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

  /// 昨天花的钱，用来算「昨日结余」。
  int get _yesterdayExpense {
    final DateTime y = DateTime.now().subtract(const Duration(days: 1));
    int sum = 0;
    for (final Txn t in _state.txns) {
      if (!t.isExpense) continue;
      final DateTime d = t.occurredAt;
      if (d.year == y.year && d.month == y.month && d.day == y.day) sum += t.amount;
    }
    return sum;
  }

  /// 本月支出最高的三个一级分类。
  List<_CatStat> get _topCats {
    final Map<int, _CatStat> map = <int, _CatStat>{};
    for (final Txn t in _state.txns) {
      if (!t.isExpense) continue;
      final TxnCategory? c =
          t.categoryId == null ? null : _state.categoryById[t.categoryId];
      final int id = c?.parentId ?? c?.id ?? 0;
      if (id == 0) continue;
      final _CatStat s = map.putIfAbsent(
        id,
        () => _CatStat(
          id: id,
          name: _state.categoryById[id]?.name ?? '其他',
          color: Xm.catColor(id),
        ),
      );
      s.spent += t.amount;
      s.txns.add(t);
    }
    final List<_CatStat> list = map.values.toList()
      ..sort((_CatStat a, _CatStat b) => b.spent.compareTo(a.spent));
    return list.take(3).toList(growable: false);
  }

  /// 某个分类的预算；没有就返回 0。
  int _catBudget(int id) {
    if (id == _state.foodCategoryId) return _state.budgetFood;
    if (id == _state.shopCategoryId) return _state.budgetShop;
    return 0;
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
          body: Stack(
            children: <Widget>[
              if (_state.loading && _state.txns.isEmpty)
                const Center(child: CircularProgressIndicator())
              else
                RefreshIndicator(
                  onRefresh: _state.load,
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: <Widget>[
                      _header(),
                      _quotaCard(),
                      ..._catsSection(),
                      _recentSection(),
                      const SizedBox(height: 120),
                    ],
                  ),
                ),
              Positioned(right: 18, bottom: 94, child: _fab()),
            ],
          ),
        );
      },
    );
  }

  Widget _header() {
    final DateTime now = DateTime.now();
    return Padding(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 8, 16, 10),
      child: XmHeader(
        padding: EdgeInsets.zero,
        kicker: '${fmtMonthDay(now)} · ${fmtWeekday(now)}',
        title: '今天还能花',
        trailing: XmAvatarButton(
          label: '满',
          tooltip: '更多',
          onTap: _showMore,
        ),
      ),
    );
  }

  void _showMore() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Xm.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 6),
            ListTile(
              leading: const Icon(Icons.search_rounded),
              title: const Text('搜索账单'),
              onTap: () {
                Navigator.of(ctx).pop();
                _openSearch();
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_chart_outlined),
              title: const Text('导入账单'),
              onTap: () {
                Navigator.of(ctx).pop();
                _openImport();
              },
            ),
            ListTile(
              leading: const Icon(Icons.pie_chart_outline),
              title: const Text('预算设置'),
              onTap: () {
                Navigator.of(ctx).pop();
                _openBudget();
              },
            ),
            ListTile(
              leading: const Icon(Icons.undo_rounded),
              title: const Text('撤销上次导入'),
              onTap: () {
                Navigator.of(ctx).pop();
                _undoImport();
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh_rounded),
              title: const Text('刷新'),
              onTap: () {
                Navigator.of(ctx).pop();
                _state.load();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ---------------- 额度卡 ----------------

  Widget _quotaCard() {
    final int used = _state.hasBudget ? _state.budgetSpentTotal : _sum.expense;
    final int total = _state.hasBudget ? _state.budgetTotal : 0;
    final double ratio =
        total <= 0 ? 0 : (used / total).clamp(0.0, 1.0).toDouble();
    final bool overdue = _available < 0;
    final int yesterday = _yesterdayExpense;
    final int perDay = _dailyQuota;
    final int diff = perDay - yesterday;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: Xm.heroGradient,
          boxShadow: Xm.heroShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.76, -0.36),
                    radius: 1.2,
                    colors: <Color>[
                      Colors.white.withValues(alpha: 0.20),
                      Colors.transparent,
                    ],
                    stops: const <double>[0, 0.62],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Xm.goldOnDark,
                          shape: BoxShape.circle,
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: Xm.goldOnDark.withValues(alpha: 0.14),
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        _state.hasBudget
                            ? '今日额度 · 剩 $_daysLeft 天'
                            : '今日还能花 · 剩 $_daysLeft 天',
                        style: Xm.text(12, FontWeight.w400,
                            spacing: 0.8, color: Xm.onDarkLabel),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      Text('¥',
                          style: Xm.text(22, FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.85))),
                      const SizedBox(width: 3),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            formatCents(perDay.abs()),
                            style: Xm.text(42, FontWeight.w700,
                                spacing: -2, height: 1, tabular: true,
                                color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: <Widget>[
                      Text('今日已花 ¥${formatCents(_todayExpense)}',
                          style: Xm.text(11.5, FontWeight.w400,
                              color: Xm.onDarkNote, tabular: true)),
                      const Spacer(),
                      Icon(Icons.schedule_rounded,
                          size: 11, color: Colors.white.withValues(alpha: 0.5)),
                      const SizedBox(width: 3),
                      Text(
                        '昨日结余 ${diff >= 0 ? '+' : '-'}¥${formatCents(diff.abs())}',
                        style: Xm.text(11.5, FontWeight.w400,
                            color: Xm.onDarkNote, tabular: true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  XmProgressBar(
                    value: ratio,
                    height: 5,
                    overdue: overdue,
                    track: Colors.white.withValues(alpha: 0.16),
                  ),
                  const SizedBox(height: 2),
                  // 「本月账本」——整行可点，原地展开
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _bookOpen = !_bookOpen),
                    child: Container(
                      margin: const EdgeInsets.only(top: 7),
                      padding: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Xm.onDarkLine, width: 1),
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              _state.hasBudget
                                  ? '本月账本 · 可支配 ¥${formatCents(_state.budgetTotal)}'
                                  : '本月账本 · 可支配 ¥${formatCents(_sum.net)}',
                              style: Xm.text(11.5, FontWeight.w400,
                                  spacing: 0.4,
                                  color: Colors.white.withValues(alpha: 0.70),
                                  tabular: true),
                            ),
                          ),
                          XmChevron(
                            expanded: _bookOpen,
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ],
                      ),
                    ),
                  ),
                  XmExpandable(
                    expanded: _bookOpen,
                    child: _monthBook(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _monthBook() {
    final int income = _sum.income;
    final int expense = _sum.expense;
    final int net = income - expense;
    final int budget = _state.budgetTotal;
    final int budgetLeft = budget - _state.budgetSpentTotal;

    Widget row(String label, String value, {bool hi = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.5),
        child: Row(
          children: <Widget>[
            Text(label,
                style: Xm.text(12.5, FontWeight.w400,
                    color: Colors.white.withValues(alpha: 0.58))),
            const Spacer(),
            Text(value,
                style: Xm.text(hi ? 14 : 12.5, FontWeight.w600,
                    spacing: -0.2,
                    color: hi ? Xm.goldOnDark : Colors.white.withValues(alpha: 0.95),
                    tabular: true)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        children: <Widget>[
          row('本月收入', '+¥${formatCents(income)}'),
          row('本月支出', '−¥${formatCents(expense)}'),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Divider(height: 1, thickness: 1, color: Xm.onDarkLine),
          ),
          row('可支配', '¥${formatCents(net)}'),
          if (budget > 0) ...<Widget>[
            row('本月预算', '¥${formatCents(budget)}'),
            row('剩余', '¥${formatCents(budgetLeft)}', hi: true),
          ],
          row('日均可用（$_daysLeft 天）', '¥${formatCents(_dailyQuota)}'),
        ],
      ),
    );
  }

  // ---------------- 分类卡（二级菜单） ----------------

  List<Widget> _catsSection() {
    final List<_CatStat> cats = _topCats;
    if (cats.isEmpty) return const <Widget>[];

    final bool anyOver =
        cats.any((_CatStat c) => _catBudget(c.id) > 0 && c.spent > _catBudget(c.id));

    return <Widget>[
      XmSect(
        anyOver ? '这几项在超' : '这三项花得最多',
        trailing: '本月 ${cats.length}/${cats.length}',
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: <Widget>[
            for (final _CatStat c in cats)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _catCard(c),
              ),
          ],
        ),
      ),
    ];
  }

  Widget _catCard(_CatStat c) {
    final bool open = _openCategory == c.id;
    final int budget = _catBudget(c.id);
    final bool over = budget > 0 && c.spent > budget;
    final int monthExpense = _sum.expense == 0 ? 1 : _sum.expense;
    final double ratio = budget > 0
        ? (c.spent / budget).clamp(0.0, 1.0).toDouble()
        : (c.spent / monthExpense).clamp(0.0, 1.0).toDouble();
    final double pct = budget > 0
        ? ((c.spent - budget) / budget * 100)
        : (c.spent / monthExpense * 100);

    final List<Txn> recent = (<Txn>[...c.txns]
          ..sort((Txn a, Txn b) => b.occurredAtMs.compareTo(a.occurredAtMs)))
        .take(3)
        .toList(growable: false);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: Xm.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: open
            ? <BoxShadow>[
                BoxShadow(
                  color: Xm.isDark
                      ? const Color(0x66000000)
                      : const Color(0x3812211A),
                  blurRadius: 22,
                  spreadRadius: -12,
                  offset: const Offset(0, 8),
                ),
              ]
            : Xm.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          InkWell(
            onTap: () => setState(() => _openCategory = open ? null : c.id),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(15, 7, 15, 7),
              child: Row(
                children: <Widget>[
                  XmColorBlock(c.name, color: c.color),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Flexible(
                              child: Text(c.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Xm.text(15, FontWeight.w600,
                                      spacing: -0.1)),
                            ),
                            if (budget > 0) ...<Widget>[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: over
                                      ? (Xm.isDark
                                          ? const Color(0xFF3A221F)
                                          : const Color(0xFFFBEDE9))
                                      : Xm.brandLL,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  '${over ? '超' : '用'} ${pct.round()}%',
                                  style: Xm.text(10.5, FontWeight.w600,
                                      color: over ? Xm.warn : Xm.brand,
                                      height: 1),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 5),
                        XmProgressBar(
                          value: ratio,
                          height: 4,
                          overdue: over,
                          track: Xm.isDark
                              ? Xm.surface2
                              : const Color(0xFFEDF1ED),
                          fill: LinearGradient(
                            colors: <Color>[c.color, c.color],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Text('¥${formatCents(c.spent)}',
                          style: Xm.text(16.5, FontWeight.w700,
                              spacing: -0.5,
                              color: over ? Xm.warn : Xm.ink,
                              tabular: true)),
                      const SizedBox(height: 3),
                      Text(
                        budget > 0
                            ? '预算 ${formatCents(budget)}'
                            : '占 ${pct.round()}%',
                        style: Xm.text(10.5, FontWeight.w400,
                            spacing: 0.2, color: Xm.ink3),
                      ),
                    ],
                  ),
                  const SizedBox(width: 2),
                  XmChevron(expanded: open, size: 12),
                ],
              ),
            ),
          ),
          XmExpandable(
            expanded: open,
            child: Container(
              width: double.infinity,
              color: Xm.isDark ? Xm.surface2 : Xm.surface2,
              padding: const EdgeInsets.only(top: 2, bottom: 6),
              child: Column(
                children: <Widget>[
                  for (int i = 0; i < recent.length; i++)
                    _miniRow(recent[i], first: i == 0),
                  if (recent.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text('这个分类还没有记录',
                          style: Xm.text(12, FontWeight.w400, color: Xm.ink3)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniRow(Txn t, {bool first = false}) {
    final XmMood mood = t.moodEnum;
    final List<String> bits = <String>[
      if ((t.workState ?? '').isNotEmpty) t.workState!,
      if ((t.note ?? '').isNotEmpty) t.note!,
    ];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openDetail(t),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 14, 10),
          decoration: BoxDecoration(
            border: first
                ? null
                : Border(
                    top: BorderSide(color: Xm.line, width: 0.6),
                  ),
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 46,
                child: Text(fmtShortDay(t.occurredAt),
                    style: Xm.text(11, FontWeight.w400, color: Xm.ink3)),
              ),
              Expanded(
                child: Text(
                  bits.isEmpty ? _subCategory(t) : bits.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Xm.text(13.5, FontWeight.w400, color: Xm.ink2),
                ),
              ),
              Text(formatCents(t.amount),
                  style: Xm.text(14, FontWeight.w600,
                      spacing: -0.3, tabular: true)),
              if (mood.isSet)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(mood.emoji,
                      style: const TextStyle(fontSize: 11.5)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _subCategory(Txn t) {
    final TxnCategory? c =
        t.categoryId == null ? null : _state.categoryById[t.categoryId];
    if (c == null) return '未分类';
    return c.parentId == null ? '支出' : c.name;
  }

  // ---------------- 本月流水 ----------------

  Widget _recentSection() {
    final List<Txn> list = _state.txns;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        XmSect('本月流水',
            trailing: list.isEmpty ? null : '共 ${list.length} 笔'),
        if (list.isEmpty)
          _empty()
        else
          ..._groupedList(list),
      ],
    );
  }

  List<Widget> _groupedList(List<Txn> list) {
    final List<Widget> out = <Widget>[];
    String? lastKey;
    List<Widget> rows = <Widget>[];
    int i = 0;

    for (final Txn t in list) {
      final String key = fmtDayKey(t.occurredAt);
      if (key != lastKey) {
        if (rows.isNotEmpty) {
          out.add(_dayCard(rows));
          rows = <Widget>[];
        }
        lastKey = key;
        out.add(_dayHeader(t.occurredAt));
      }
      final Widget row = XmSwipeDelete(
        onDelete: () => _onDelete(t),
        child: _row(t, first: rows.isEmpty),
      );
      rows.add(i < 5
          ? XmEntrance(index: i, step: 40, base: 40, offsetY: 8, child: row)
          : row);
      i++;
    }
    if (rows.isNotEmpty) out.add(_dayCard(rows));
    return out;
  }

  Widget _dayCard(List<Widget> rows) => XmCard(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        radius: 20,
        child: Column(children: rows),
      );

  Widget _dayHeader(DateTime d) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 7),
      child: Row(
        children: <Widget>[
          Text('${fmtMonthDay(d)} · ${fmtWeekday(d)}', style: Xm.caption),
          const Spacer(),
          Text('支出 ¥${formatCents(_dayExpense(d))}', style: Xm.captionS),
        ],
      ),
    );
  }

  int _dayExpense(DateTime day) {
    final String key = fmtDayKey(day);
    int sum = 0;
    for (final Txn t in _state.txns) {
      if (t.isExpense && fmtDayKey(t.occurredAt) == key) sum += t.amount;
    }
    return sum;
  }

  Widget _row(Txn t, {bool first = false}) {
    final GlobalKey key = _rowKeys.putIfAbsent(t.id, () => GlobalKey());
    final TxnCategory? c =
        t.categoryId == null ? null : _state.categoryById[t.categoryId];
    final Account? a = _state.accountById[t.accountId];
    final Account? to =
        t.toAccountId == null ? null : _state.accountById[t.toAccountId];
    final XmMood mood = t.moodEnum;

    final String title;
    final Color iconColor;
    final String meta;
    final String amount;

    if (t.isTransfer) {
      title = '转账';
      iconColor = Xm.catColor(4);
      meta = '${a?.name ?? '未知'} → ${to?.name ?? '未知'}'
          '${(t.note ?? '').isNotEmpty ? ' · ${t.note}' : ''}';
      amount = formatCents(t.amount);
    } else {
      final TxnCategory? parent =
          (c == null || c.parentId == null) ? null : _state.categoryById[c.parentId!];
      title = parent?.name ?? c?.name ?? '未分类';
      iconColor = Xm.catColor(parent?.id ?? c?.id);
      final List<String> bits = <String>[
        if (a != null) a.name,
        if ((t.note ?? '').isNotEmpty) t.note!,
      ];
      meta = bits.isEmpty ? fmtDateTime(t.occurredAt) : bits.join(' · ');
      amount = '${t.isExpense ? '-' : '+'}${formatCents(t.amount)}';
    }

    return Material(
      key: key,
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openDetail(t),
        child: Container(
          decoration: BoxDecoration(
            border: first
                ? null
                : Border(top: BorderSide(color: Xm.line, width: 0.6)),
          ),
          padding: const EdgeInsets.fromLTRB(15, 7, 15, 7),
          child: Row(
            children: <Widget>[
              XmColorBlock(title, color: iconColor, size: 36),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Xm.text(15, FontWeight.w600,
                                  spacing: -0.1)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: <Widget>[
                        if ((t.workState ?? '').isNotEmpty) ...<Widget>[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: Xm.brandLL,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(t.workState!,
                                style: Xm.text(9.5, FontWeight.w600,
                                    color: Xm.brand, height: 1.2)),
                          ),
                          const SizedBox(width: 5),
                        ],
                        Flexible(
                          child: Text(meta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Xm.text(11.5, FontWeight.w400,
                                  color: Xm.ink3)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    amount,
                    style: Xm.text(
                      16,
                      FontWeight.w700,
                      spacing: -0.4,
                      tabular: true,
                      color: t.isExpense ? Xm.ink : Xm.income,
                    ),
                  ),
                  if (mood.isSet)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(mood.emoji,
                          style: const TextStyle(fontSize: 12.5)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fab() {
    return Semantics(
      button: true,
      label: '记一笔',
      child: GestureDetector(
        key: _fabKey,
        onTap: _openRecord,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            gradient: Xm.buttonGradient,
            borderRadius: BorderRadius.circular(26),
            boxShadow: Xm.fabShadow,
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.add_rounded, size: 18, color: Colors.white),
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
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        children: <Widget>[
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Xm.brandLL,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(Icons.receipt_long_outlined, size: 28, color: Xm.brand),
          ),
          const SizedBox(height: 14),
          Text('这个月还没有记录',
              style: Xm.text(14, FontWeight.w400, color: Xm.ink2)),
          const SizedBox(height: 4),
          Text('点右下角「记一笔」开始',
              style: Xm.text(12, FontWeight.w400, color: Xm.ink3)),
        ],
      ),
    );
  }
}

/// 首页分类卡的统计快照。
class _CatStat {
  _CatStat({required this.id, required this.name, required this.color});

  final int id;
  final String name;
  final Color color;
  int spent = 0;
  final List<Txn> txns = <Txn>[];
}
