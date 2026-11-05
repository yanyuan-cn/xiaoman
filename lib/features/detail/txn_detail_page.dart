import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../state/data_bus.dart';
import '../../ui/components.dart';
import '../../ui/motion.dart';
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
  late bool _inBudget = widget.txn.inBudget;

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
    final TxnCategory? c =
        _t.categoryId == null ? null : _categories[_t.categoryId];
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
    final bool? ok = await showXmExpandSheet<bool>(
      context: context,
      heightFactor: RecordPage.heightFactor,
      builder: (BuildContext _) => RecordPage(repo: widget.repo, editing: _t),
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
        content: const Text('删除后在首页可以点「撤销」找回（3 秒内）。'),
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
        ? Xm.ink
        : (_t.isExpense ? Xm.ink : Xm.income);
    final String sign = isTransfer ? '' : (_t.isExpense ? '-' : '+');
    final XmMood mood = _t.moodEnum;

    return XmPageScaffold(
      title: '账单详情',
      subtitle: _kindText,
      actions: <Widget>[
        XmIconButton(icon: Icons.edit_outlined, tooltip: '编辑', onTap: _edit),
        const SizedBox(width: 4),
        XmIconButton(
            icon: Icons.delete_outline_rounded, tooltip: '删除', onTap: _delete),
        const SizedBox(width: 4),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: <Widget>[
          // 金额区：一块浅色面，不抢第二张主色卡的戏
          Container(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            decoration: BoxDecoration(
              color: Xm.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Xm.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                    isTransfer
                        ? '转账金额'
                        : (_t.isExpense ? '支出金额' : '收入金额'),
                    style: Xm.caption),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: XmAmount(
                    text: '${formatCents(_t.amount)}',
                    style: Xm.text(34, FontWeight.w700,
                        spacing: -1.2, height: 1, tabular: true, color: amountColor),
                    currencyScale: 0.56,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    _pill('$sign${_kindText}'),
                    _pill(_categoryText),
                    if (mood.isSet) _pill('${mood.emoji} ${mood.label}'),
                    if ((_t.workState ?? '').isNotEmpty)
                      _pill('⏱ ${_t.workState}'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _card(<Widget>[
            _row('账户', _accountText),
            if (isTransfer) _row('转入账户', _toAccountText),
            _row('时间', _fullTime(_t.occurredAt)),
            _row('备注', (_t.note ?? '').isEmpty ? '—' : _t.note!),
            if (!isTransfer) _row('商户', _t.merchant ?? '—'),
          ]),
          const SizedBox(height: 14),
          _card(<Widget>[
            if (!isTransfer)
              _switchRow('计入预算', _inBudget, (bool v) => _setInBudget(v)),
            _row('来源', _t.sourceLabel),
            _row(
              '创建时间',
              _t.createdAtMs == 0
                  ? '—'
                  : _fullTime(
                      DateTime.fromMillisecondsSinceEpoch(_t.createdAtMs)),
            ),
            _row(
              '最后修改',
              _t.updatedAtMs == 0
                  ? '—'
                  : _fullTime(
                      DateTime.fromMillisecondsSinceEpoch(_t.updatedAtMs)),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Xm.isDark ? Xm.surface2 : const Color(0xFFF1F4EF),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(text,
          style: Xm.text(12, FontWeight.w500, color: Xm.ink2)),
    );
  }

  Future<void> _setInBudget(bool value) async {
    await widget.repo.setTxnInBudget(_t.id, value);
    if (!mounted) return;
    setState(() => _inBudget = value);
    DataBus.instance.bump();
  }

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 76,
            child: Text(label, style: Xm.text(13, FontWeight.w500, color: Xm.ink3)),
          ),
          Expanded(
            child: Text('关掉后不计入预算已用',
                style: Xm.text(12, FontWeight.w400, color: Xm.ink3)),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Xm.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Xm.line),
      ),
      child: Column(children: children),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 76,
            child: Text(label,
                style: Xm.text(13, FontWeight.w500, color: Xm.ink3)),
          ),
          Expanded(
            child: Text(value,
                style: Xm.text(14, FontWeight.w500, height: 1.4, tabular: true)),
          ),
        ],
      ),
    );
  }
}
