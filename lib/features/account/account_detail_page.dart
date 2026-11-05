import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../ui/components.dart';

/// 账户详情 / 新增账户。
///
/// 从资产列表的某一行放大进来（见 [XmExpandRoute]），风格与记账面板一致：
/// 同一套输入框、同一套标签、同一套开关卡。
class AccountDetailPage extends StatefulWidget {
  const AccountDetailPage({super.key, required this.repo, this.account});

  final Repo repo;
  final Account? account;

  @override
  State<AccountDetailPage> createState() => _AccountDetailPageState();
}

class _AccountDetailPageState extends State<AccountDetailPage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _balance = TextEditingController();
  final TextEditingController _note = TextEditingController();

  String _type = '银行卡';
  bool _isLiability = false;
  bool _includeInTotal = true;
  bool _loaded = false;
  bool _saving = false;

  int _delta = 0;
  List<Txn> _txns = const <Txn>[];
  List<AccountType> _types = const <AccountType>[];
  Map<int, TxnCategory> _categories = const <int, TxnCategory>{};

  bool get _isEditing => widget.account != null;

  /// 选择列表：库里现有的类型；如果这个账户用的类型已经被隐藏/是老的英文 key，
  /// 也把它补进来，避免保存时被悄悄换掉。
  List<String> get _typeChoices {
    final List<String> names =
        <String>[for (final AccountType t in _types) t.name];
    if (!names.contains(_type)) {
      names.insert(0, Account.typeLabel(_type));
    }
    return names;
  }

  @override
  void initState() {
    super.initState();
    final Account? a = widget.account;
    if (a != null) {
      _name.text = a.name;
      _note.text = a.note ?? '';
      _type = Account.typeLabel(a.type);
      _isLiability = a.isLiability;
      _includeInTotal = a.includeInTotal;
    }
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final Map<int, int> deltas = await widget.repo.accountDeltas();
    final List<TxnCategory> cats = await widget.repo.categories();
    final List<AccountType> types = await widget.repo.accountTypes();

    List<Txn> txns = const <Txn>[];
    int delta = 0;
    final Account? a = widget.account;
    if (a != null) {
      txns = await widget.repo.txnsForAccount(a.id);
      delta = deltas[a.id] ?? 0;
    }

    if (!mounted) return;
    setState(() {
      _categories = <int, TxnCategory>{for (final TxnCategory c in cats) c.id: c};
      _types = types;
      if (!_isEditing && types.isNotEmpty && !types.any((AccountType t) => t.name == _type)) {
        _type = types.first.name;
      }
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

    final String note = _note.text.trim();
    setState(() => _saving = true);
    if (_isEditing) {
      await widget.repo.updateAccount(
        id: widget.account!.id,
        name: name,
        type: _type,
        initialBalance: entered - _delta,
        isLiability: _isLiability,
        includeInTotal: _includeInTotal,
        note: note.isEmpty ? null : note,
      );
    } else {
      await widget.repo.addAccount(
        name: name,
        type: _type,
        initialBalance: entered,
        isLiability: _isLiability,
        includeInTotal: _includeInTotal,
        note: note.isEmpty ? null : note,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return XmPageScaffold(
      title: _isEditing ? '编辑账户' : '新增账户',
      subtitle: _isEditing ? '改动会立即影响净资产' : '填现在实际有多少钱',
      actions: <Widget>[
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: SizedBox(
            height: 36,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11)),
              ),
              child: Text(_saving ? '保存中' : '保存'),
            ),
          ),
        ),
      ],
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: <Widget>[
                XmField(
                  controller: _name,
                  label: '名称',
                  hint: '例如：招商银行工资卡',
                  maxLength: 16,
                ),
                const SizedBox(height: 14),
                XmField(
                  controller: _note,
                  label: '备注',
                  hint: '例如：每月 15 号发薪（可选）',
                  maxLength: 24,
                ),
                const SizedBox(height: 14),
                _section(
                  '类型',
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final String name in _typeChoices)
                        XmChoice(
                          label: name,
                          dense: true,
                          selected: _type == name,
                          onTap: () => setState(() => _type = name),
                        ),
                    ],
                  ),
                ),
                XmField(
                  controller: _balance,
                  label: '当前余额',
                  hint: '填这个账户现在实际有多少钱',
                  helper: '负债请填负数，例如 -45000',
                  keyboardType:
                      const TextInputType.numberWithOptions(signed: true),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Xm.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Xm.line),
                  ),
                  child: Column(
                    children: <Widget>[
                      _switchRow(
                        '这是负债账户',
                        '比如房贷、车贷、信用卡欠款',
                        _isLiability,
                        (bool v) => setState(() => _isLiability = v),
                      ),
                      const XmDivider(indent: 0, endIndent: 0),
                      _switchRow(
                        '计入总资产',
                        '关掉后这个账户不参与净资产计算',
                        _includeInTotal,
                        (bool v) => setState(() => _includeInTotal = v),
                      ),
                    ],
                  ),
                ),
                if (_isEditing) ...<Widget>[
                  const SizedBox(height: 22),
                  Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 8),
                    child: Text('最近流水',
                        style: Xm.text(12, FontWeight.w500,
                            spacing: 0.3, color: Xm.ink3)),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Xm.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Xm.line),
                    ),
                    child: Column(
                      children: <Widget>[
                        for (int i = 0; i < _txns.length; i++) ...<Widget>[
                          if (i > 0) const XmDivider(indent: 14, endIndent: 14),
                          _txnRow(_txns[i]),
                        ],
                        if (_txns.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Text('还没有流水',
                                style: Xm.text(12, FontWeight.w400,
                                    color: Xm.ink3)),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _section(String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 7),
            child: Text(title,
                style:
                    Xm.text(12, FontWeight.w500, spacing: 0.3, color: Xm.ink3)),
          ),
          child,
        ],
      ),
    );
  }

  Widget _switchRow(
      String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(title, style: Xm.text(14, FontWeight.w600)),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 10),
                child: Text(subtitle,
                    style: Xm.text(11, FontWeight.w400, color: Xm.ink3)),
              ),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _txnRow(Txn t) {
    final TxnCategory? c =
        t.categoryId == null ? null : _categories[t.categoryId];
    final String title = t.isTransfer ? '转账' : (c?.name ?? '未分类');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Xm.text(13.5, FontWeight.w500)),
                const SizedBox(height: 2),
                Text(
                  '${t.occurredAt.month}月${t.occurredAt.day}日',
                  style: Xm.text(11, FontWeight.w400, color: Xm.ink3),
                ),
              ],
            ),
          ),
          Text(
            '${t.isTransfer ? '' : (t.isExpense ? '-' : '+')}¥${formatCents(t.amount)}',
            style: Xm.text(13.5, FontWeight.w600, tabular: true),
          ),
        ],
      ),
    );
  }
}
