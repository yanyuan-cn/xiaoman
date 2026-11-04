import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repo.dart';

class RecordPage extends StatefulWidget {
  const RecordPage({
    super.key,
    required this.repo,
    this.initialKind = 'expense',
    this.editing,
  });

  final Repo repo;
  final String initialKind;
  final Txn? editing;

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  late String _kind = widget.editing?.kind ?? widget.initialKind;
  String _amount = '';
  int? _parentId;
  int? _childId;
  int? _accountId;
  int? _toAccountId;
  DateTime _date = DateTime.now();
  final TextEditingController _note = TextEditingController();

  List<Account> _accounts = const <Account>[];
  List<TxnCategory> _categories = const <TxnCategory>[];
  bool _ready = false;
  bool _saving = false;
  late bool _inBudget = widget.editing?.inBudget ?? true;

  bool get _isEditing => widget.editing != null;
  bool get _isTransfer => _kind == 'transfer';

  /// 金额 > 0 才允许提交（§4.5 交互规则）
  bool get _canSave => (parseYuanToCents(_amount) ?? 0) > 0;

  @override
  void initState() {
    super.initState();
    final Txn? e = widget.editing;
    if (e != null) {
      _amount = formatCentsPlain(e.amount);
      _date = e.occurredAt;
      _accountId = e.accountId;
      _toAccountId = e.toAccountId;
      _note.text = e.note ?? '';
    }
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final List<Account> accounts = await widget.repo.accounts();
    final List<TxnCategory> categories = await widget.repo.categories();
    if (!mounted) return;

    final Txn? e = widget.editing;
    if (e != null && e.categoryId != null) {
      for (final TxnCategory c in categories) {
        if (c.id == e.categoryId) {
          if (c.parentId == null) {
            _parentId = c.id;
          } else {
            _parentId = c.parentId;
            _childId = c.id;
          }
          break;
        }
      }
    }

    setState(() {
      _accounts = accounts;
      _categories = categories;
      _accountId ??= accounts.isEmpty ? null : accounts.first.id;
      _ready = true;
    });
  }

  List<TxnCategory> get _topCategories => _categories
      .where((TxnCategory c) => c.kind == _kind && c.parentId == null)
      .toList(growable: false);

  List<TxnCategory> get _childCategories => _parentId == null
      ? const <TxnCategory>[]
      : _categories
          .where((TxnCategory c) => c.parentId == _parentId)
          .toList(growable: false);

  void _switchKind(String kind) {
    if (kind == _kind) return;
    setState(() {
      _kind = kind;
      if (kind == 'transfer') {
        _parentId = null;
        _childId = null;
      }
    });
  }

  void _tapKey(String key) {
    setState(() {
      if (key == '<') {
        if (_amount.isNotEmpty) {
          _amount = _amount.substring(0, _amount.length - 1);
        }
        return;
      }
      if (key == '.') {
        if (_amount.contains('.')) return;
        _amount = _amount.isEmpty ? '0.' : '$_amount.';
        return;
      }
      if (_amount.contains('.')) {
        if (_amount.split('.')[1].length >= 2) return;
      } else if (_amount.replaceAll('.', '').length >= 9) {
        return;
      }
      if (_amount == '0') {
        _amount = key;
        return;
      }
      _amount += key;
    });
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) return;
    setState(() =>
        _date = DateTime(picked.year, picked.month, picked.day, 12));
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _save() async {
    final int? cents = parseYuanToCents(_amount);
    if (cents == null || cents <= 0) {
      _toast('请输入金额');
      return;
    }
    final int? accountId = _accountId;
    if (accountId == null) {
      _toast('请选择账户');
      return;
    }

    if (!_isTransfer && _parentId == null) {
      _toast('请选择分类');
      return;
    }
    if (_isTransfer) {
      final int? to = _toAccountId;
      if (to == null) {
        _toast('请选择转入账户');
        return;
      }
      if (to == accountId) {
        _toast('转出和转入不能是同一个账户');
        return;
      }
    }

    setState(() => _saving = true);
    final String note = _note.text.trim();
    final int? categoryId = _isTransfer ? null : (_childId ?? _parentId);

    if (_isEditing) {
      await widget.repo.updateTxn(
        id: widget.editing!.id,
        kind: _kind,
        amount: cents,
        occurredAt: _date,
        accountId: accountId,
        toAccountId: _isTransfer ? _toAccountId : null,
        categoryId: categoryId,
        note: note.isEmpty ? null : note,
        inBudget: _inBudget,
      );
    } else if (_isTransfer) {
      await widget.repo.addTransfer(
        amount: cents,
        occurredAt: _date,
        fromAccountId: accountId,
        toAccountId: _toAccountId!,
        note: note.isEmpty ? null : note,
      );
    } else {
      await widget.repo.addTxn(
        kind: _kind,
        amount: cents,
        occurredAt: _date,
        accountId: accountId,
        categoryId: categoryId,
        note: note.isEmpty ? null : note,
        inBudget: _inBudget,
      );
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.86,
      child: Container(
        decoration: BoxDecoration(
          color: Xm.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: <Widget>[
            const SizedBox(height: 8),
            _handle(),
            _header(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: SegmentedButton<String>(
                segments: const <ButtonSegment<String>>[
                  ButtonSegment<String>(value: 'expense', label: Text('支出')),
                  ButtonSegment<String>(value: 'income', label: Text('收入')),
                  ButtonSegment<String>(value: 'transfer', label: Text('转账')),
                ],
                selected: <String>{_kind},
                onSelectionChanged: (Set<String> s) => _switchKind(s.first),
              ),
            ),
            _amountBar(),
            Expanded(
              child: _ready
                  ? _form()
                  : const Center(child: CircularProgressIndicator()),
            ),
            _keypad(),
            _saveButton(),
          ],
        ),
      ),
    );
  }

  Widget _handle() {
    return Container(
      width: 38,
      height: 4.5,
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFD8E0DA),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
      child: Row(
        children: <Widget>[
          Text(
            _isEditing ? '编辑账单' : '记一笔',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消',
                style: TextStyle(fontSize: 14, color: Xm.ink3)),
          ),
        ],
      ),
    );
  }

  Widget _amountBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('¥', style: TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                _amount.isEmpty ? '0.00' : _amount,
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w600,
                  color: _amount.isEmpty ? Xm.ink3 : Xm.ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _form() {
    if (_isTransfer) return _transferForm();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      children: <Widget>[
        _label('分类'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final TxnCategory c in _topCategories)
              _chip(
                c.name,
                _parentId == c.id,
                () => setState(() {
                  _parentId = c.id;
                  _childId = null;
                }),
              ),
          ],
        ),
        if (_childCategories.isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          _label('二级分类（可选）'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final TxnCategory c in _childCategories)
                _chip(
                  c.name,
                  _childId == c.id,
                  () => setState(() => _childId = _childId == c.id ? null : c.id),
                ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        _label('账户'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final Account a in _accounts)
              _chip(a.name, _accountId == a.id,
                  () => setState(() => _accountId = a.id)),
          ],
        ),
        const SizedBox(height: 6),
        _dateRow(),
        _noteField(),
        _budgetSwitch(),
      ],
    );
  }

  Widget _transferForm() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      children: <Widget>[
        _label('从哪个账户转出'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final Account a in _accounts)
              _chip(a.name, _accountId == a.id,
                  () => setState(() => _accountId = a.id)),
          ],
        ),
        const SizedBox(height: 16),
        _label('转到哪个账户'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final Account a in _accounts)
              _chip(a.name, _toAccountId == a.id,
                  () => setState(() => _toAccountId = a.id)),
          ],
        ),
        const SizedBox(height: 6),
        _dateRow(),
        _noteField(),
      ],
    );
  }

  Widget _budgetSwitch() {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('计入预算', style: TextStyle(fontSize: 14)),
                SizedBox(height: 2),
                Text('关掉后这笔钱不算进预算已用',
                    style: TextStyle(fontSize: 11, color: Xm.ink3)),
              ],
            ),
          ),
          Switch(
            value: _inBudget,
            onChanged: (bool v) => setState(() => _inBudget = v),
          ),
        ],
      ),
    );
  }

  Widget _dateRow() {
    return Row(
      children: <Widget>[
        TextButton.icon(
          onPressed: _pickDate,
          icon: const Icon(Icons.event, size: 18),
          label: Text(fmtDate(_date)),
        ),
      ],
    );
  }

  Widget _noteField() {
    return TextField(
      controller: _note,
      maxLength: 40,
      textInputAction: TextInputAction.done,
      decoration: const InputDecoration(
        hintText: '备注（可选）',
        counterText: '',
        isDense: true,
        border: OutlineInputBorder(),
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

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (bool _) => onTap(),
    );
  }

  Widget _keypad() {
    const List<List<String>> rows = <List<String>>[
      <String>['1', '2', '3'],
      <String>['4', '5', '6'],
      <String>['7', '8', '9'],
      <String>['.', '0', '<'],
    ];
    return Container(
      color: Xm.surface2,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final List<String> row in rows)
            Row(
              children: <Widget>[
                for (final String k in row) Expanded(child: _key(k)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _key(String k) {
    return SizedBox(
      height: 50,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          color: Xm.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _tapKey(k),
            child: Center(
              child: k == '<'
                  ? Icon(Icons.backspace_outlined,
                      size: 22, color: Xm.ink2)
                  : Text(k,
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w600,
                        color: Xm.ink,
                      )),
            ),
          ),
        ),
      ),
    );
  }

  Widget _saveButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: _canSave ? Xm.buttonGradient : null,
            color: _canSave ? null : Xm.ink3,
            borderRadius: BorderRadius.circular(Xm.rButton),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(Xm.rButton),
              onTap: _saving ? null : _save,
              child: Center(
                child: Text(
                  _saving ? '保存中…' : (_isEditing ? '保存修改' : '完成'),
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
