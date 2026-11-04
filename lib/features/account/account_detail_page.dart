import 'package:flutter/material.dart';

import '../../core/theme.dart';

import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/repo.dart';

class AccountDetailPage extends StatefulWidget {
  const AccountDetailPage({super.key, required this.repo, this.account});

  final Repo repo;
  final Account? account;

  @override
  State<AccountDetailPage> createState() => _AccountDetailPageState();
}

const Map<String, String> _typeOptions = <String, String>{
  'savings': '活期存款',
  'deposit': '定期存款',
  'bank': '银行卡',
  'ewallet': '电子钱包',
  'cash': '现金',
};

class _AccountDetailPageState extends State<AccountDetailPage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _balance = TextEditingController();

  String _type = 'bank';
  bool _isLiability = false;
  bool _includeInTotal = true;
  bool _loaded = false;
  bool _saving = false;

  int _delta = 0;
  List<Txn> _txns = const <Txn>[];
  Map<int, TxnCategory> _categories = const <int, TxnCategory>{};
  Map<int, Account> _accounts = const <int, Account>{};

  bool get _isEditing => widget.account != null;

  @override
  void initState() {
    super.initState();
    final Account? a = widget.account;
    if (a != null) {
      _name.text = a.name;
      _type = a.type;
      _isLiability = a.isLiability;
      _includeInTotal = a.includeInTotal;
    }
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final List<Account> accounts = await widget.repo.accounts();
    final Map<int, int> deltas = await widget.repo.accountDeltas();
    final List<TxnCategory> cats = await widget.repo.categories();

    List<Txn> txns = const <Txn>[];
    int delta = 0;
    final Account? a = widget.account;
    if (a != null) {
      txns = await widget.repo.txnsForAccount(a.id);
      delta = deltas[a.id] ?? 0;
    }

    if (!mounted) return;
    setState(() {
      _accounts = <int, Account>{for (final Account x in accounts) x.id: x};
      _categories = <int, TxnCategory>{for (final TxnCategory c in cats) c.id: c};
      _txns = txns;
      _delta = delta;
      if (a != null) {
        _balance.text = formatCentsPlain(a.initialBalance + delta);
      }
      _loaded = true;
    });
  }

  int? _parseSigned(String raw) {
    String t = raw.trim().replaceAll(',', '');
    bool negative = false;
    if (t.startsWith('-')) {
      negative = true;
      t = t.substring(1);
    }
    final int? cents = parseYuanToCents(t);
    if (cents == null) return null;
    return negative ? -cents : cents;
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _save() async {
    final String name = _name.text.trim();
    if (name.isEmpty) {
      _toast('请填写名称');
      return;
    }
    final int? entered = _parseSigned(_balance.text);
    if (entered == null) {
      _toast('余额格式不对，可以输入负数');
      return;
    }

    setState(() => _saving = true);
    if (_isEditing) {
      await widget.repo.updateAccount(
        id: widget.account!.id,
        name: name,
        type: _type,
        initialBalance: entered - _delta,
        isLiability: _isLiability,
        includeInTotal: _includeInTotal,
      );
    } else {
      await widget.repo.addAccount(
        name: name,
        type: _type,
        initialBalance: entered,
        isLiability: _isLiability,
        includeInTotal: _includeInTotal,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑账户' : '新增账户'),
        actions: <Widget>[
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: <Widget>[
                _label('名称'),
                TextField(
                  controller: _name,
                  maxLength: 16,
                  decoration: const InputDecoration(
                    hintText: '例如：招商银行工资卡',
                    counterText: '',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 18),
                _label('类型'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final MapEntry<String, String> e in _typeOptions.entries)
                      ChoiceChip(
                        label: Text(e.value),
                        selected: _type == e.key,
                        showCheckmark: false,
                        onSelected: (bool _) => setState(() => _type = e.key),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                _label('当前余额'),
                TextField(
                  controller: _balance,
                  keyboardType:
                      const TextInputType.numberWithOptions(signed: true),
                  decoration: const InputDecoration(
                    prefixText: '¥ ',
                    hintText: '填这个账户现在实际有多少钱',
                    helperText: '负债请填负数，例如 -45000',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  decoration: BoxDecoration(
                    color: Xm.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: <Widget>[
                      SwitchListTile(
                        value: _isLiability,
                        onChanged: (bool v) => setState(() => _isLiability = v),
                        title: const Text('这是负债账户',
                            style: TextStyle(fontSize: 14)),
                        subtitle: Text('比如房贷、车贷、信用卡欠款',
                            style:
                                TextStyle(fontSize: 11, color: Xm.ink3)),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        value: _includeInTotal,
                        onChanged: (bool v) =>
                            setState(() => _includeInTotal = v),
                        title: const Text('计入总资产',
                            style: TextStyle(fontSize: 14)),
                        subtitle: Text('关掉后这个账户不参与净资产计算',
                            style:
                                TextStyle(fontSize: 11, color: Xm.ink3)),
                      ),
                    ],
                  ),
                ),
                if (_isEditing) ...<Widget>[
                  const SizedBox(height: 22),
                  _label('最近流水'),
                  for (final Txn t in _txns) _txnRow(t),
                  if (_txns.isEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('还没有流水',
                          style:
                              TextStyle(fontSize: 12, color: Xm.ink3)),
                    ),
                ],
              ],
            ),
    );
  }

  Widget _txnRow(Txn t) {
    final TxnCategory? c = t.categoryId == null ? null : _categories[t.categoryId];
    final String title = t.isTransfer
        ? '转账'
        : (c?.name ?? '未分类');
    final Account? other = t.isTransfer && t.toAccountId != null
        ? _accounts[t.toAccountId]
        : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      color: Xm.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  other == null
                      ? '${t.occurredAt.month}月${t.occurredAt.day}日'
                      : '${t.occurredAt.month}月${t.occurredAt.day}日 · 转入 ${other.name}',
                  style:
                      TextStyle(fontSize: 11, color: Xm.ink3),
                ),
              ],
            ),
          ),
          Text(
            '${t.isTransfer ? '' : (t.isExpense ? '-' : '+')}¥${formatCents(t.amount)}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: TextStyle(fontSize: 12, color: Xm.ink3)),
    );
  }
}
