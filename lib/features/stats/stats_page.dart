import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../state/data_bus.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key, required this.repo});

  final Repo repo;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String _kind = 'expense';
  bool _loading = true;

  Map<int, int> _totals = const <int, int>{};
  List<TxnCategory> _categories = const <TxnCategory>[];
  List<DateTime> _months = const <DateTime>[];
  List<int> _trend = const <int>[];

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
    final DateTime from = DateTime(_month.year, _month.month);
    final DateTime to = DateTime(_month.year, _month.month + 1);

    final Map<int, int> totals =
        await widget.repo.categoryTotals(from: from, to: to, kind: _kind);
    final List<TxnCategory> cats = await widget.repo.categories();

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
      _totals = totals;
      _categories = cats;
      _months = months;
      _trend = trend;
      _loading = false;
    });
  }

  Future<void> _shiftMonth(int delta) async {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    await _load();
  }

  TxnCategory? _cat(int id) {
    for (final TxnCategory c in _categories) {
      if (c.id == id) return c;
    }
    return null;
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
                const SizedBox(height: 16),
                _kindSwitch(),
                const SizedBox(height: 12),
                _categoryCard(),
                const SizedBox(height: 16),
                _trendCard(),
              ],
            ),
    );
  }

  Widget _header() {
    return Row(
      children: <Widget>[
        IconButton(
          onPressed: () => _shiftMonth(-1),
          icon: const Icon(Icons.chevron_left),
        ),
        Text('${_month.year}年${_month.month}月',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        IconButton(
          onPressed: () => _shiftMonth(1),
          icon: const Icon(Icons.chevron_right),
        ),
        const Spacer(),
        Text(
          '¥${formatCents(_totals.values.fold<int>(0, (int a, int b) => a + b))}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ],
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

  Widget _categoryCard() {
    if (_totals.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('这个月还没有记录',
              style: TextStyle(color: Colors.black38, fontSize: 13)),
        ),
      );
    }

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
                        style: const TextStyle(
                            fontSize: 11, color: Colors.black38),
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
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF3F7D58)),
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
        const Text('近 6 个月',
            style: TextStyle(fontSize: 12, color: Colors.black45)),
        const SizedBox(height: 10),
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              for (int i = 0; i < _months.length; i++)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      Text(
                        _trend[i] == 0 ? '' : _short(_trend[i]),
                        style: const TextStyle(
                            fontSize: 9, color: Colors.black38),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        height: max == 0 ? 2 : (70 * _trend[i] / max) + 2,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: i == _months.length - 1
                              ? const Color(0xFF3F7D58)
                              : const Color(0xFFBFD5C7),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('${_months[i].month}月',
                          style: const TextStyle(
                              fontSize: 10, color: Colors.black45)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _short(int cents) {
    if (cents >= 10000 * 1000) return '${(cents / 1000000).toStringAsFixed(0)}w';
    if (cents >= 1000000) return '${(cents / 100000).toStringAsFixed(0)}k';
    return (cents ~/ 100).toString();
  }
}
