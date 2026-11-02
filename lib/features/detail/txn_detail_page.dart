import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../state/data_bus.dart';
import '../record/record_page.dart';

class TxnDetailPage extends StatefulWidget {
  const TxnDetailPage({super.key, required this.repo, required this.txn});

  final Repo repo;
  final Txn txn;

  @override
  State<TxnDetailPage> createState() => _TxnDetailPageState();
}

class _TxnDetailPageState extends State<TxnDetailPage> {
  Map<int, Account> _accounts = const <int, Account>{};
  Map<int, TxnCategory> _categories = const <int, TxnCategory>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<Account> accounts = await widget.repo.accounts();
    final List<TxnCategory> cats = await widget.repo.categories();
    if (!mounted) return;
    setState(() {
      _accounts = <int, Account>{for (final Account a in accounts) a.id: a};
      _categories = <int, TxnCategory>{for (final TxnCategory c in cats) c.id: c};
    });
  }

  Txn get _t => widget.txn;

  String get _categoryText {
    final TxnCategory? c = _t.categoryId == null ? null : _categories[_t.categoryId];
    if (c == null) return '未分类';
    if (c.parentId == null) return c.name;
    final TxnCategory? p = _categories[c.parentId];
    return p == null ? c.name : '${p.name} · ${c.name}';
  }

  String get _accountText => _accounts[_t.accountId]?.name ?? '未知账户';

  String get _toAccountText {
    if (_t.toAccountId == null) return '';
    return _accounts[_t.toAccountId]?.name ?? '未知账户';
  }

  String get _kindText {
    if (_t.isTransfer) return '转账';
    return _t.isExpense ? '支出' : '收入';
  }

  String _fullTime(DateTime d) =>
      '${fmtDate(d)} ${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';

  String _two(int v) => v.toString().padLeft(2, '0');

  Future<void> _edit() async {
    final bool? ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext _) =>
            RecordPage(repo: widget.repo, editing: _t),
      ),
    );
    if (ok == true) {
      DataBus.instance.bump();
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  Future<void> _delete() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('删除这条记录'),
        content: const Text('删除后可以在首页长按撤销（5 秒内）。'),
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
    await widget.repo.softDelete(_t.id);
    DataBus.instance.bump();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final bool isTransfer = _t.isTransfer;
    final Color amountColor = isTransfer
        ? Colors.black87
        : (_t.isExpense ? Colors.black87 : const Color(0xFF2E7D32));
    final String sign = isTransfer ? '' : (_t.isExpense ? '-' : '+');

    return Scaffold(
      appBar: AppBar(
        title: const Text('账单详情'),
        actions: <Widget>[
          IconButton(
            tooltip: '编辑',
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: '删除',
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: <Widget>[
                Text(_kindText,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black45)),
                const SizedBox(height: 10),
                Text(
                  '$sign¥${formatCents(_t.amount)}',
                  style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w600,
                      color: amountColor),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _card(<Widget>[
            _row('分类', isTransfer ? '—' : _categoryText),
            _row('账户',
                isTransfer ? _accountText : _accountText),
            if (isTransfer) _row('转入账户', _toAccountText),
            _row('时间', _fullTime(_t.occurredAt)),
            _row('商户', _t.merchant ?? '—'),
            _row('订单号', _t.externalId ?? '—', selectable: true),
            _row('备注', (_t.note ?? '').isEmpty ? '—' : _t.note!),
          ]),
          const SizedBox(height: 16),
          _card(<Widget>[
            _row('来源', _t.sourceLabel),
            _row(
              '创建时间',
              _t.createdAtMs == 0
                  ? '—'
                  : _fullTime(DateTime.fromMillisecondsSinceEpoch(
                      _t.createdAtMs)),
            ),
            _row(
              '最后修改',
              _t.updatedAtMs == 0
                  ? '—'
                  : _fullTime(DateTime.fromMillisecondsSinceEpoch(
                      _t.updatedAtMs)),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: children),
    );
  }

  Widget _row(String label, String value, {bool selectable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 76,
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: Colors.black45)),
          ),
          Expanded(
            child: selectable
                ? SelectableText(value,
                    style: const TextStyle(fontSize: 14, height: 1.4))
                : Text(value,
                    style: const TextStyle(fontSize: 14, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
