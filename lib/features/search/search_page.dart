import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../detail/txn_detail_page.dart';

/// 搜索 + 筛选（关键字 / 类型 / 分类 / 账户 / 时间 / 金额区间）。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.repo});

  final Repo repo;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _keyword = TextEditingController();

  List<Txn> _results = const <Txn>[];
  List<TxnCategory> _categories = const <TxnCategory>[];
  List<Account> _accounts = const <Account>[];
  bool _loading = true;

  _Filters _filters = const _Filters();

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  @override
  void dispose() {
    _keyword.dispose();
    super.dispose();
  }

  Future<void> _loadMeta() async {
    final List<TxnCategory> cats = await widget.repo.categories();
    final List<Account> accounts = await widget.repo.accounts();
    if (!mounted) return;
    setState(() {
      _categories = cats.where((TxnCategory c) => c.parentId == null).toList();
      _accounts = accounts;
    });
    await _search();
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    final (DateTime?, DateTime?) range = _filters.range.resolve();
    final List<Txn> list = await widget.repo.searchTxns(
      keyword: _keyword.text,
      kind: _filters.kind,
      categoryId: _filters.categoryId,
      accountId: _filters.accountId,
      from: range.$1,
      to: range.$2,
      minCents: _filters.minCents,
      maxCents: _filters.maxCents,
    );
    if (!mounted) return;
    setState(() {
      _results = list;
      _loading = false;
    });
  }

  Future<void> _openFilters() async {
    final _Filters? next = await showModalBottomSheet<_Filters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x6B0A120E),
      builder: (BuildContext _) => _FilterSheet(
        current: _filters,
        categories: _categories,
        accounts: _accounts,
      ),
    );
    if (next == null) return;
    setState(() => _filters = next);
    await _search();
  }

  int get _activeCount => _filters.activeCount;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _keyword,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          onChanged: (_) => _search(),
          decoration: InputDecoration(
            hintText: '搜备注或商户',
            border: InputBorder.none,
            hintStyle: TextStyle(fontSize: 15, color: Xm.ink3),
            suffixIcon: _keyword.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      _keyword.clear();
                      _search();
                    },
                  ),
          ),
          style: Xm.bodyM.copyWith(fontWeight: FontWeight.w500),
        ),
        actions: <Widget>[
          Stack(
            alignment: Alignment.center,
            children: <Widget>[
              IconButton(
                tooltip: '筛选',
                onPressed: _openFilters,
                icon: const Icon(Icons.tune_rounded, size: 20),
              ),
              if (_activeCount > 0)
                Positioned(
                  right: 6,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Xm.brand,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('$_activeCount',
                        style: const TextStyle(fontSize: 9, color: Colors.white)),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: <Widget>[
                _summaryBar(),
                Expanded(child: _list()),
              ],
            ),
    );
  }

  Widget _summaryBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: <Widget>[
          Text('${_results.length} 条结果', style: Xm.captionS),
          const Spacer(),
          if (_activeCount > 0)
            TextButton(
              onPressed: () async {
                setState(() => _filters = const _Filters());
                await _search();
              },
              child: Text('清空筛选',
                  style: TextStyle(fontSize: 12, color: Xm.ink2)),
            ),
        ],
      ),
    );
  }

  Widget _list() {
    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.search_off_rounded, size: 40, color: Xm.ink3),
            const SizedBox(height: 10),
            Text('没有匹配的记录', style: Xm.text(13, FontWeight.w400, color: Xm.ink3)),
          ],
        ),
      );
    }

    final Map<int, TxnCategory> cat = <int, TxnCategory>{
      for (final TxnCategory c in _categories) c.id: c,
    };
    final Map<int, Account> acc = <int, Account>{
      for (final Account a in _accounts) a.id: a,
    };

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      itemCount: _results.length,
      separatorBuilder: (BuildContext _, int __) => const SizedBox(height: 1),
      itemBuilder: (BuildContext context, int i) {
        final Txn t = _results[i];
        final String title;
        if (t.isTransfer) {
          title = '转账 · ${acc[t.accountId]?.name ?? '?'} → ${acc[t.toAccountId]?.name ?? '?'}';
        } else {
          final TxnCategory? c = t.categoryId == null ? null : cat[t.categoryId];
          title = '${c?.name ?? '未分类'}${(t.note ?? '').isEmpty ? '' : ' · ${t.note}'}';
        }
        final String sub = <String>[
          fmtDate(t.occurredAt),
          if (acc[t.accountId] != null) acc[t.accountId]!.name,
        ].join(' · ');

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (BuildContext _) =>
                      TxnDetailPage(repo: widget.repo, txn: t),
                ),
              );
              await _search();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Xm.body),
                        const SizedBox(height: 3),
                        Text(sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Xm.captionS),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${t.isExpense ? '-' : (t.isIncome ? '+' : '')}${formatCents(t.amount)}',
                    style: Xm.bodyM.copyWith(
                      color: t.isExpense ? Xm.ink : Xm.income,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

enum _Range { all, thisMonth, last3Months, thisYear }

extension on _Range {
  String get label => switch (this) {
        _Range.all => '全部时间',
        _Range.thisMonth => '本月',
        _Range.last3Months => '近 3 个月',
        _Range.thisYear => '今年',
      };

  (DateTime?, DateTime?) resolve() {
    final DateTime now = DateTime.now();
    switch (this) {
      case _Range.all:
        return (null, null);
      case _Range.thisMonth:
        return (DateTime(now.year, now.month), DateTime(now.year, now.month + 1));
      case _Range.last3Months:
        return (DateTime(now.year, now.month - 2), DateTime(now.year, now.month + 1));
      case _Range.thisYear:
        return (DateTime(now.year), DateTime(now.year + 1));
    }
  }
}

class _Filters {
  const _Filters({
    this.kind = 'all',
    this.categoryId,
    this.accountId,
    this.range = _Range.all,
    this.minCents,
    this.maxCents,
  });

  final String kind;
  final int? categoryId;
  final int? accountId;
  final _Range range;
  final int? minCents;
  final int? maxCents;

  int get activeCount {
    int n = 0;
    if (kind != 'all') n++;
    if (categoryId != null) n++;
    if (accountId != null) n++;
    if (range != _Range.all) n++;
    if (minCents != null || maxCents != null) n++;
    return n;
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.current,
    required this.categories,
    required this.accounts,
  });

  final _Filters current;
  final List<TxnCategory> categories;
  final List<Account> accounts;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String _kind = widget.current.kind;
  late int? _categoryId = widget.current.categoryId;
  late int? _accountId = widget.current.accountId;
  late _Range _range = widget.current.range;
  late final TextEditingController _min =
      TextEditingController(text: _yuan(widget.current.minCents));
  late final TextEditingController _max =
      TextEditingController(text: _yuan(widget.current.maxCents));

  static String _yuan(int? cents) =>
      cents == null ? '' : formatCentsPlain(cents);

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.78,
      child: Container(
        decoration: BoxDecoration(
          color: Xm.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: <Widget>[
            const SizedBox(height: 8),
            Container(
              width: 38,
              height: 4.5,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Xm.line,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
              child: Row(
                children: <Widget>[
                  Text('筛选', style: Xm.bodyL),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _kind = 'all';
                        _categoryId = null;
                        _accountId = null;
                        _range = _Range.all;
                        _min.clear();
                        _max.clear();
                      });
                    },
                    child: const Text('重置', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: <Widget>[
                  _label('类型'),
                  _chips<String>(
                    values: const <String>['all', 'expense', 'income', 'transfer'],
                    labels: const <String>['全部', '支出', '收入', '转账'],
                    selected: _kind,
                    onSelect: (String v) => setState(() => _kind = v),
                  ),
                  const SizedBox(height: 14),
                  _label('分类'),
                  _chips<int>(
                    values: <int>[0, ...widget.categories.map((TxnCategory c) => c.id)],
                    labels: <String>['全部', ...widget.categories.map((TxnCategory c) => c.name)],
                    selected: _categoryId ?? 0,
                    onSelect: (int v) => setState(() => _categoryId = v == 0 ? null : v),
                  ),
                  const SizedBox(height: 14),
                  _label('账户'),
                  _chips<int>(
                    values: <int>[0, ...widget.accounts.map((Account a) => a.id)],
                    labels: <String>['全部', ...widget.accounts.map((Account a) => a.name)],
                    selected: _accountId ?? 0,
                    onSelect: (int v) => setState(() => _accountId = v == 0 ? null : v),
                  ),
                  const SizedBox(height: 14),
                  _label('时间'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final _Range r in _Range.values)
                        _pill(r.label, r == _range, () => setState(() => _range = r)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _label('金额区间（元）'),
                  Row(
                    children: <Widget>[
                      Expanded(child: _amountField(_min, '最低')),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text('—', style: TextStyle(color: Xm.ink3)),
                      ),
                      Expanded(child: _amountField(_max, '最高')),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(
                    _Filters(
                      kind: _kind,
                      categoryId: _categoryId,
                      accountId: _accountId,
                      range: _range,
                      minCents: parseYuanToCents(_min.text),
                      maxCents: parseYuanToCents(_max.text),
                    ),
                  ),
                  child: const Text('应用'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 2),
        child: Text(text,
            style: TextStyle(
                fontSize: 12, color: Xm.ink3, letterSpacing: 0.5)),
      );

  Widget _amountField(TextEditingController c, String hint) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: Xm.bodyM.copyWith(fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 13, color: Xm.ink3),
        filled: true,
        fillColor: Xm.surface2,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Xm.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Xm.line),
        ),
      ),
    );
  }

  Widget _chips<T>({
    required List<T> values,
    required List<String> labels,
    required T selected,
    required ValueChanged<T> onSelect,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (int i = 0; i < values.length; i++)
          _pill(labels[i], values[i] == selected, () => onSelect(values[i])),
      ],
    );
  }

  Widget _pill(String text, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: active ? Xm.brand : Xm.surface2,
          borderRadius: BorderRadius.circular(Xm.rChip),
          border: Border.all(color: active ? Xm.brand : Xm.line),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : Xm.ink2,
          ),
        ),
      ),
    );
  }
}
