import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../state/data_bus.dart';
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
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: <Widget>[
                  _netCard(net, totalAsset, totalLiability),
                  const SizedBox(height: 18),
                  _sectionTitle('资产'),
                  if (assets.isEmpty)
                    _emptyHint('还没有资产账户')
                  else
                    for (final Account a in assets) _tile(a),
                  const SizedBox(height: 18),
                  _sectionTitle('负债'),
                  if (liabilities.isEmpty)
                    _emptyHint('还没有负债项目')
                  else
                    for (final Account a in liabilities) _tile(a),
                  const SizedBox(height: 16),
                  const Text(
                    '余额 = 期初余额 + 收入 − 支出；负债记为负数，还款会减少欠款',
                    style: TextStyle(fontSize: 11, color: Colors.black38),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _netCard(int net, int asset, int liability) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF3F7D58),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('净资产',
              style: TextStyle(fontSize: 12, color: Colors.white70)),
          const SizedBox(height: 8),
          Text('¥${formatCents(net)}',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                color: net < 0 ? const Color(0xFFFFD7D2) : Colors.white,
              )),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              _miniStat('总资产', asset),
              const SizedBox(width: 20),
              _miniStat('总负债', liability),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, int value) {
    return Row(
      children: <Widget>[
        Text('$label ',
            style: const TextStyle(fontSize: 11, color: Colors.white70)),
        Text('¥${formatCents(value)}',
            style: const TextStyle(fontSize: 13, color: Colors.white)),
      ],
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(text,
          style: const TextStyle(fontSize: 12, color: Colors.black45)),
    );
  }

  Widget _emptyHint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Text(text,
          style: const TextStyle(fontSize: 12, color: Colors.black26)),
    );
  }

  Widget _tile(Account a) {
    final int balance = _balance(a);
    final int shown = a.isLiability ? -balance : balance;
    final String sub = <String>[
      Account.typeLabel(a.type),
      if (!a.includeInTotal) '不计入总资产',
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        onTap: () => _openAccount(a),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2ED),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            a.isLiability
                ? Icons.credit_card_off_outlined
                : Icons.account_balance_wallet_outlined,
            size: 18,
            color: const Color(0xFF3F7D58),
          ),
        ),
        title: Text(a.name,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(sub,
              style: const TextStyle(fontSize: 11, color: Colors.black38)),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(
              '¥${formatCents(shown)}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: shown < 0 ? const Color(0xFFB3261E) : Colors.black87,
              ),
            ),
            if (a.isLiability)
              const Text('待还',
                  style: TextStyle(fontSize: 10, color: Colors.black38)),
          ],
        ),
      ),
    );
  }
}
