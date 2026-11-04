import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../state/data_bus.dart';
import '../../ui/components.dart';
import '../account/account_detail_page.dart';

class AssetsPage extends StatefulWidget {
  const AssetsPage({super.key, required this.repo});

  final Repo repo;

  @override
  State<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends State<AssetsPage> {
  List<Account> _accounts = const <Account>[];
  Map<int, int> _deltas = const <int, int>{};
  bool _loading = true;

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
    final List<Account> accounts = await widget.repo.accounts();
    final Map<int, int> deltas = await widget.repo.accountDeltas();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _deltas = deltas;
      _loading = false;
    });
  }

  int _balance(Account a) => a.initialBalance + (_deltas[a.id] ?? 0);

  Future<void> _openAccount(Account? account) async {
    final bool? changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext _) =>
            AccountDetailPage(repo: widget.repo, account: account),
      ),
    );
    if (changed == true) DataBus.instance.bump();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final List<Account> assets = <Account>[];
    final List<Account> liabilities = <Account>[];
    int totalAsset = 0;
    int totalLiability = 0;
    int net = 0;

    for (final Account a in _accounts) {
      final int b = _balance(a);
      if (a.isLiability) {
        liabilities.add(a);
        if (a.includeInTotal) totalLiability += -b;
      } else {
        assets.add(a);
        if (a.includeInTotal) totalAsset += b;
      }
      if (a.includeInTotal) net += b;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('资产'),
        actions: <Widget>[
          IconButton(
            tooltip: '新增账户',
            onPressed: () => _openAccount(null),
            icon: const Icon(Icons.add_rounded, size: 22),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.zero,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                    child: _netCard(net, totalAsset, totalLiability),
                  ),
                  XmSectionTitle('资产', subtitle: '${assets.length} 个账户'),
                  if (assets.isEmpty)
                    _emptyHint('还没有资产账户')
                  else
                    _accountCard(assets),
                  const SizedBox(height: 18),
                  XmSectionTitle('负债', subtitle: '${liabilities.length} 个账户'),
                  if (liabilities.isEmpty)
                    _emptyHint('还没有负债项目')
                  else
                    _accountCard(liabilities),
                  Padding(
                    padding: EdgeInsets.fromLTRB(22, 18, 22, 96),
                    child: Text(
                      '余额 = 期初余额 + 收入 − 支出；负债记为负数，还款会减少欠款',
                      style: TextStyle(fontSize: 11, color: Xm.ink3),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _netCard(int net, int asset, int liability) {
    return XmHeroCard(
      variant: XmHeroVariant.assets,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '净资产',
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 0.6,
              color: Xm.onDarkLabel,
            ),
          ),
          const SizedBox(height: 10),
          // 36dp 金额必须给足高度，否则会被卡片裁切（§7.2 坑 1）
          SizedBox(
            height: 40,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: XmAmount(
                  text: formatCents(net),
                  style: Xm.display.copyWith(
                    color: net < 0 ? const Color(0xFFFFC9C2) : Colors.white,
                  ),
                  currencyScale: 0.58,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              _foot('总资产', asset),
              const SizedBox(width: 22),
              _foot('总负债', liability),
            ],
          ),
        ],
      ),
    );
  }

  Widget _foot(String label, int value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            color: Xm.onDarkNote,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '¥${formatCents(value)}',
          style: Xm.text(14, FontWeight.w600,
              spacing: -0.2, color: Colors.white, tabular: true),
        ),
      ],
    );
  }

  Widget _emptyHint(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 6),
      child: Text(text, style: TextStyle(fontSize: 12, color: Xm.ink3)),
    );
  }

  Widget _accountCard(List<Account> list) {
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < list.length; i++) {
      rows.add(XmSwipeDelete(
        onDelete: () => _deleteAccount(list[i]),
        child: _row(list[i], first: i == 0),
      ));
    }
    return XmCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: rows),
    );
  }

  /// 删除账户（归档，可撤销）。有流水时先确认，避免一键把账户名变成「未知」。
  Future<void> _deleteAccount(Account a) async {
    final int count = await widget.repo.accountTxnCount(a.id);
    if (count > 0) {
      if (!mounted) return;
      final bool? ok = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('删除账户'),
          content: Text(
            '「${a.name}」下还有 $count 笔流水。删除后账户不再显示，'
            '这些流水会保留但账户名显示为「未知」。\n\n要继续吗？',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    await widget.repo.archiveAccount(a.id);
    await _load();
    DataBus.instance.bump();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已删除「${a.name}」'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () async {
            await widget.repo.restoreAccount(a.id);
            await _load();
            DataBus.instance.bump();
          },
        ),
      ),
    );
  }

  Widget _row(Account a, {bool first = false}) {
    final int balance = _balance(a);
    final int shown = a.isLiability ? -balance : balance;
    final String sub = <String>[
      Account.typeLabel(a.type),
      if (!a.includeInTotal) '不计入总资产',
    ].join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openAccount(a),
        child: Column(
          children: <Widget>[
            if (!first) const XmDivider(indent: 63),
            SizedBox(
              height: 63,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: <Widget>[
                    XmIconBlock.icon(
                      a.isLiability
                          ? Icons.credit_card_off_outlined
                          : Icons.account_balance_wallet_outlined,
                      size: 34,
                      iconSize: 18,
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(a.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Xm.body),
                          const SizedBox(height: 2),
                          Text(sub,
                              style: TextStyle(
                                  fontSize: 11.5, color: Xm.ink3)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Text(
                          '¥${formatCents(shown)}',
                          style: Xm.bodyM.copyWith(
                            color: shown < 0 ? Xm.expense : Xm.ink,
                          ),
                        ),
                        if (a.isLiability)
                          Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Text('待还',
                                style: TextStyle(
                                    fontSize: 10.5, color: Xm.ink3)),
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
}
