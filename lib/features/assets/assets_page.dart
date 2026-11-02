import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../state/data_bus.dart';

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

  String _typeLabel(String type) {
    switch (type) {
      case 'bank':
        return '银行卡';
      case 'ewallet':
        return '电子钱包';
      case 'cash':
        return '现金';
      default:
        return '其他';
    }
  }

  @override
  Widget build(BuildContext context) {
    int total = 0;
    for (final Account a in _accounts) {
      total += _balance(a);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('资产')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3F7D58),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text('总资产',
                            style:
                                TextStyle(fontSize: 12, color: Colors.white70)),
                        const SizedBox(height: 8),
                        Text('¥${formatCents(total)}',
                            style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text('账户',
                      style: TextStyle(fontSize: 12, color: Colors.black45)),
                  const SizedBox(height: 8),
                  for (final Account a in _accounts) _tile(a),
                  const SizedBox(height: 12),
                  const Text(
                    '余额 = 初始余额 + 收入 − 支出',
                    style: TextStyle(fontSize: 11, color: Colors.black38),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _tile(Account a) {
    final int balance = _balance(a);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2ED),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              a.type == 'bank'
                  ? Icons.credit_card
                  : Icons.account_balance_wallet,
              size: 18,
              color: const Color(0xFF3F7D58),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(a.name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(_typeLabel(a.type),
                    style:
                        const TextStyle(fontSize: 11, color: Colors.black38)),
              ],
            ),
          ),
          Text('¥${formatCents(balance)}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: balance < 0 ? const Color(0xFFB3261E) : Colors.black87,
              )),
        ],
      ),
    );
  }
}
