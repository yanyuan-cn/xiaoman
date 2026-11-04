import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../state/data_bus.dart';
import '../../ui/components.dart';

/// 分类配色：从品牌绿出发，越往后越淡，最后用哑光金收尾（§2.1）。
const List<Color> _kPalette = <Color>[
  Color(0xFF2F6B4F),
  Color(0xFF4C8E6D),
  Color(0xFF7FAE93),
  Color(0xFFB7D5C2),
  Color(0xFFB08442),
  Color(0xFF9AA8A0),
];

class StatsPage extends StatefulWidget {
  const StatsPage({super.key, required this.repo});

  final Repo repo;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  static Color get _green => Xm.brand;

  String _mode = 'month';
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  int _year = DateTime.now().year;
  String _kind = 'expense';
  bool _loading = true;

  Map<int, int> _totals = const <int, int>{};
  Map<int, int> _yearExpense = const <int, int>{};
  Map<int, int> _yearIncome = const <int, int>{};
  List<TxnCategory> _categories = const <TxnCategory>[];
  List<DateTime> _months = const <DateTime>[];
  List<int> _trend = const <int>[];
  List<MonthSummary> _yearMonths = const <MonthSummary>[];

  @override
  void initState() {
    super.initState();
    DataBus.instance.addListener(_reload);
    _load();
  }

  @override
  void dispose() {
    DataBus.instance.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final List<TxnCategory> cats = await widget.repo.categories();

    if (_mode == 'month') {
      final DateTime from = DateTime(_month.year, _month.month);
      final DateTime to = DateTime(_month.year, _month.month + 1);
      final Map<int, int> totals =
          await widget.repo.categoryTotals(from: from, to: to, kind: _kind);

      final List<DateTime> months = <DateTime>[];
      final List<int> trend = <int>[];
      for (int i = 5; i >= 0; i--) {
        final DateTime m = DateTime(_month.year, _month.month - i);
        final MonthSummary s = await widget.repo.summaryBetween(
          DateTime(m.year, m.month),
          DateTime(m.year, m.month + 1),
        );
        months.add(m);
        trend.add(_kind == 'expense' ? s.expense : s.income);
      }

      if (!mounted) return;
      setState(() {
        _categories = cats;
        _totals = totals;
        _months = months;
        _trend = trend;
        _loading = false;
      });
      return;
    }

    final Map<int, int> exp = await widget.repo.categoryTotals(
      from: DateTime(_year),
      to: DateTime(_year + 1),
      kind: 'expense',
    );
    final Map<int, int> inc = await widget.repo.categoryTotals(
      from: DateTime(_year),
      to: DateTime(_year + 1),
      kind: 'income',
    );
    final List<MonthSummary> months = <MonthSummary>[];
    for (int m = 1; m <= 12; m++) {
      months.add(await widget.repo.summaryBetween(
        DateTime(_year, m),
        DateTime(_year, m + 1),
      ));
    }

    if (!mounted) return;
    setState(() {
      _categories = cats;
      _yearExpense = exp;
      _yearIncome = inc;
      _yearMonths = months;
      _loading = false;
    });
  }

  Future<void> _shift(int delta) async {
    setState(() {
      if (_mode == 'month') {
        _month = DateTime(_month.year, _month.month + delta);
      } else {
        _year += delta;
      }
    });
    await _load();
  }

  TxnCategory? _cat(int id) {
    for (final TxnCategory c in _categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// 一级分类名称：二级分类归并到父级。
  String _topName(int id) {
    final TxnCategory? c = _cat(id);
    if (c == null) return '未分类';
    if (c.parentId != null) {
      final TxnCategory? p = _cat(c.parentId!);
      if (p != null) return p.name;
    }
    return c.name;
  }

  String _catName(int id) {
    final TxnCategory? c = _cat(id);
    if (c == null) return '未分类';
    if (c.parentId != null) {
      final TxnCategory? p = _cat(c.parentId!);
      if (p != null) return '${p.name} · ${c.name}';
    }
    return c.name;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('统计')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: <Widget>[
                _header(),
                const SizedBox(height: 12),
                _modeSwitch(),
                const SizedBox(height: 12),
                if (_mode == 'month') ...<Widget>[
                  _kindSwitch(),
                  const SizedBox(height: 14),
                  _pieCard(),
                  const SizedBox(height: 20),
                  _categoryCard(),
                  const SizedBox(height: 20),
                  _trendCard(),
                ] else ...<Widget>[
                  _yearSummaryCard(),
                  const SizedBox(height: 20),
                  _yearBarCard(),
                  const SizedBox(height: 20),
                  _yearListCard('支出分布', _yearExpense, const Color(0xFFC9704A)),
                  const SizedBox(height: 20),
                  _yearListCard('收入分布', _yearIncome, _green),
                ],
              ],
            ),
    );
  }

  Widget _header() {
    final bool isMonth = _mode == 'month';
    final String label =
        isMonth ? '${_month.year}年${_month.month}月' : '$_year年';
    final int total = isMonth
        ? _totals.values.fold<int>(0, (int a, int b) => a + b)
        : (_kind == 'expense'
            ? _yearExpense.values.fold<int>(0, (int a, int b) => a + b)
            : _yearIncome.values.fold<int>(0, (int a, int b) => a + b));

    return Row(
      children: <Widget>[
        IconButton(
          onPressed: () => _shift(-1),
          icon: const Icon(Icons.chevron_left),
        ),
        Text(label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        IconButton(
          onPressed: () => _shift(1),
          icon: const Icon(Icons.chevron_right),
        ),
        const Spacer(),
        if (isMonth)
          Text(
            '¥${formatCents(total)}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
      ],
    );
  }

  Widget _modeSwitch() {
    return Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<String>(
        segments: const <ButtonSegment<String>>[
          ButtonSegment<String>(value: 'month', label: Text('按月')),
          ButtonSegment<String>(value: 'year', label: Text('按年')),
        ],
        selected: <String>{_mode},
        showSelectedIcon: false,
        onSelectionChanged: (Set<String> s) {
          setState(() => _mode = s.first);
          _load();
        },
      ),
    );
  }

  Widget _kindSwitch() {
    return SegmentedButton<String>(
      segments: const <ButtonSegment<String>>[
        ButtonSegment<String>(value: 'expense', label: Text('支出')),
        ButtonSegment<String>(value: 'income', label: Text('收入')),
      ],
      selected: <String>{_kind},
      onSelectionChanged: (Set<String> s) {
        setState(() => _kind = s.first);
        _load();
      },
    );
  }

  // ---------------- 月：饼图 ----------------

  List<MapEntry<String, int>> _topSlices(Map<int, int> totals, int limit) {
    final Map<String, int> merged = <String, int>{};
    for (final MapEntry<int, int> e in totals.entries) {
      final String name = _topName(e.key);
      merged[name] = (merged[name] ?? 0) + e.value;
    }
    final List<MapEntry<String, int>> list = merged.entries.toList()
      ..sort((MapEntry<String, int> a, MapEntry<String, int> b) =>
          b.value.compareTo(a.value));
    if (list.length <= limit) return list;
    final int rest = list
        .skip(limit - 1)
        .fold<int>(0, (int s, MapEntry<String, int> e) => s + e.value);
    return <MapEntry<String, int>>[
      ...list.take(limit - 1),
      MapEntry<String, int>('其他', rest),
    ];
  }

  Widget _pieCard() {
    if (_totals.isEmpty) {
      return _emptyBox('这个月还没有记录');
    }
    final List<MapEntry<String, int>> slices = _topSlices(_totals, 6);
    final int sum =
        slices.fold<int>(0, (int s, MapEntry<String, int> e) => s + e.value);
    final List<Color> colors = <Color>[
      for (int i = 0; i < slices.length; i++)
        i == slices.length - 1 && slices.length == 6
            ? const Color(0xFFBFC4CA)
            : _kPalette[i % _kPalette.length],
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: Xm.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 180,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 1020),
                  curve: XmEase.e1,
                  builder: (BuildContext ctx, double t, Widget? _) => CustomPaint(
                    size: const Size(180, 180),
                    painter: _DonutPainter(
                      slices: <int>[
                        for (final MapEntry<String, int> e in slices) e.value
                      ],
                      colors: colors,
                      progress: t,
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(_kind == 'expense' ? '支出' : '收入',
                        style: TextStyle(
                            fontSize: 11, color: Xm.ink3)),
                    const SizedBox(height: 2),
                    Text('¥${formatCents(sum)}',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < slices.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colors[i],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(slices[i].key,
                        style: const TextStyle(fontSize: 13)),
                  ),
                  Text('¥${formatCents(slices[i].value)}',
                      style: TextStyle(
                          fontSize: 12, color: Xm.ink3)),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 48,
                    child: Text(
                      sum == 0
                          ? '0%'
                          : '${(slices[i].value * 100 / sum).toStringAsFixed(1)}%',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ---------------- 年 ----------------

  Widget _yearSummaryCard() {
    int exp = 0;
    int inc = 0;
    for (final MonthSummary s in _yearMonths) {
      exp += s.expense;
      inc += s.income;
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: _green,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          _stat('全年支出', formatCents(exp), Colors.white),
          _stat('全年收入', formatCents(inc), Colors.white),
          _stat('全年结余', formatCents(inc - exp), const Color(0xFFFFE08A)),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: Colors.white.withValues(alpha: 0.75))),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('¥$value',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: color)),
          ),
        ],
      ),
    );
  }

  Widget _yearBarCard() {
    final int max = _yearMonths.fold<int>(
        0, (int a, MonthSummary s) => math.max(a, math.max(s.expense, s.income)));
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      decoration: BoxDecoration(
        color: Xm.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(left: 4, bottom: 12),
            child: Text('每月支出 / 收入',
                style: TextStyle(fontSize: 12, color: Xm.ink3)),
          ),
          SizedBox(
            height: 140,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (int i = 0; i < _yearMonths.length; i++)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: <Widget>[
                            _bar(_yearMonths[i].expense, max,
                                const Color(0xFFC9704A)),
                            const SizedBox(width: 2),
                            _bar(_yearMonths[i].income, max, _green),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('${i + 1}',
                            style: TextStyle(
                                fontSize: 9, color: Xm.ink3)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              _legendDot(const Color(0xFFC9704A), '支出'),
              const SizedBox(width: 14),
              _legendDot(_green, '收入'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bar(int value, int max, Color color) {
    final double h = max == 0 ? 2 : (100 * value / max) + 2;
    return Container(
      width: 7,
      height: h,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(fontSize: 11, color: Xm.ink3)),
      ],
    );
  }

  Widget _yearListCard(String title, Map<int, int> totals, Color color) {
    if (totals.isEmpty) return _emptyBox('这一年还没有$title'.replaceAll('分布', ''));
    final List<MapEntry<int, int>> entries = totals.entries.toList()
      ..sort((MapEntry<int, int> a, MapEntry<int, int> b) =>
          b.value.compareTo(a.value));
    final int max = entries.first.value;
    final int sum =
        entries.fold<int>(0, (int s, MapEntry<int, int> e) => s + e.value);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: Xm.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title,
              style: TextStyle(fontSize: 12, color: Xm.ink3)),
          const SizedBox(height: 12),
          for (final MapEntry<int, int> e in entries.take(10))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(_catName(e.key),
                            style: const TextStyle(fontSize: 13)),
                      ),
                      Text('¥${formatCents(e.value)}',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 46,
                        child: Text(
                          '${(e.value * 100 / sum).toStringAsFixed(1)}%',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontSize: 11, color: Xm.ink3),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: max == 0 ? 0 : e.value / max,
                      minHeight: 5,
                      backgroundColor: const Color(0xFFEDEFED),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---------------- 月：分类榜 / 趋势 ----------------

  Widget _categoryCard() {
    if (_totals.isEmpty) return _emptyBox('这个月还没有记录');

    final List<MapEntry<int, int>> entries = _totals.entries.toList()
      ..sort((MapEntry<int, int> a, MapEntry<int, int> b) =>
          b.value.compareTo(a.value));
    final int max = entries.first.value;
    final int sum =
        entries.fold<int>(0, (int s, MapEntry<int, int> e) => s + e.value);

    return Column(
      children: <Widget>[
        for (final MapEntry<int, int> e in entries.take(10))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(_catName(e.key),
                          style: const TextStyle(fontSize: 13)),
                    ),
                    Text('¥${formatCents(e.value)}',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${(e.value * 100 / sum).toStringAsFixed(1)}%',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 11, color: Xm.ink3),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: max == 0 ? 0 : e.value / max,
                    minHeight: 5,
                    backgroundColor: Xm.surface2,
                    valueColor: AlwaysStoppedAnimation<Color>(_green),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _trendCard() {
    final int max = _trend.fold<int>(0, (int a, int b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('近 6 个月',
            style: TextStyle(fontSize: 12, color: Xm.ink3)),
        const SizedBox(height: 10),
        SizedBox(
          height: 120,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 720),
            curve: XmEase.e1,
            builder: (BuildContext ctx, double t, Widget? _) => Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (int i = 0; i < _months.length; i++)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        Text(
                          _trend[i] == 0 ? '' : _short(_trend[i]),
                          style: TextStyle(
                              fontSize: 9, color: Xm.ink3),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          height: max == 0
                              ? 2
                              : ((70 * _trend[i] / max) + 2) * t,
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            gradient: i == _months.length - 1
                                ? const LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: <Color>[
                                      Color(0xFF3E8163),
                                      Color(0xFF2A6047)
                                    ],
                                  )
                                : null,
                            color: i == _months.length - 1
                                ? null
                                : const Color(0xFFBFD5C7),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6),
                              bottom: Radius.circular(3),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text('${_months[i].month}月',
                            style: TextStyle(
                              fontSize: 10,
                              color: i == _months.length - 1
                                  ? Xm.brand
                                  : Xm.ink3,
                              fontWeight: i == _months.length - 1
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            )),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyBox(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(text,
            style: TextStyle(color: Xm.ink3, fontSize: 13)),
      ),
    );
  }

  String _short(int cents) {
    if (cents >= 10000 * 1000) return '${(cents / 1000000).toStringAsFixed(0)}w';
    if (cents >= 1000000) return '${(cents / 100000).toStringAsFixed(0)}k';
    return (cents ~/ 100).toString();
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.slices,
    required this.colors,
    this.progress = 1,
  });

  final List<int> slices;
  final List<Color> colors;

  /// 0 → 1 的扫入进度（§5 环形图扫入）
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final int total = slices.fold<int>(0, (int a, int b) => a + b);
    if (total <= 0) return;

    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = math.min(size.width, size.height) / 2 - 2;
    const double stroke = 26;
    final Rect rect = Rect.fromCircle(center: center, radius: radius - stroke / 2);
    // 段间留 2.2° 缝隙，缝隙是「分段」的视觉线索，不随段数变化（§6.2 C14）
    final double gap = slices.length > 1 ? 2.2 * math.pi / 180 : 0;

    double start = -math.pi / 2;
    for (int i = 0; i < slices.length; i++) {
      final double full = 2 * math.pi * slices[i] / total;
      final double sweep = full * progress - gap;
      if (sweep > 0) {
        final Paint paint = Paint()
          ..color = colors[i]
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.butt;
        canvas.drawArc(rect, start, sweep, false, paint);
      }
      start += full;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.slices != slices ||
      old.colors != colors ||
      old.progress != progress;
}
