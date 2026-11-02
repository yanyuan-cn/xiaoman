import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/repo.dart';

class RecordPage extends StatefulWidget {
  const RecordPage({super.key, required this.repo, this.initialKind = 'expense'});

  final Repo repo;
  final String initialKind;

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  late String _kind = widget.initialKind;
  String _amount = '';
  int? _parentId;
  int? _childId;
  int? _accountId;
  DateTime _date = DateTime.now();
  final TextEditingController _note = TextEditingController();

  List<Account> _accounts = const <Account>[];
  List<TxnCategory> _categories = const <TxnCategory>[];
  bool _ready = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
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
      _parentId = null;
      _childId = null;
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
    final int? parentId = _parentId;
    if (parentId == null) {
      _toast('请选择分类');
      return;
    }
    final int? accountId = _accountId;
    if (accountId == null) {
      _toast('请选择账户');
      return;
    }
    setState(() => _saving = true);
    final String note = _note.text.trim();
    await widget.repo.addTxn(
      kind: _kind,
      amount: cents,
      occurredAt: _date,
      accountId: accountId,
      categoryId: _childId ?? parentId,
      note: note.isEmpty ? null : note,
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('记一笔')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SegmentedButton<String>(
                segments: const <ButtonSegment<String>>[
                  ButtonSegment<String>(value: 'expense', label: Text('支出')),
                  ButtonSegment<String>(value: 'income', label: Text('收入')),
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
                  color: _amount.isEmpty ? Colors.black26 : Colors.black87,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _form() {
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
        Row(
          children: <Widget>[
            TextButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event, size: 18),
              label: Text(fmtDate(_date)),
            ),
          ],
        ),
        TextField(
          controller: _note,
          maxLength: 40,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            hintText: '备注（可选）',
            counterText: '',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: const TextStyle(fontSize: 12, color: Colors.black45)),
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
      color: const Color(0xFFEDEFED),
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
      height: 52,
      child: TextButton(
        onPressed: () => _tapKey(k),
        child: k == '<'
            ? const Icon(Icons.backspace_outlined, size: 20)
            : Text(k,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _saveButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '保存中…' : '保存'),
        ),
      ),
    );
  }
}
