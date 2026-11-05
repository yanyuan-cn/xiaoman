import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../ui/components.dart';

/// 记账面板。从首页的「记账条」长出来，所以高度比例是公开常量，
/// 调用方用 [showXmExpandSheet] 时必须传同一个值。
class RecordPage extends StatefulWidget {
  const RecordPage({
    super.key,
    required this.repo,
    this.initialKind = 'expense',
    this.initialCategoryId,
    this.editing,
  });

  static const double heightFactor = 0.88;

  final Repo repo;
  final String initialKind;
  final int? initialCategoryId;
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
  int _mood = 0;
  String? _workState;
  final TextEditingController _note = TextEditingController();

  List<Account> _accounts = const <Account>[];
  List<TxnCategory> _categories = const <TxnCategory>[];
  bool _ready = false;
  bool _saving = false;
  late bool _inBudget = widget.editing?.inBudget ?? true;

  bool get _isEditing => widget.editing != null;
  bool get _isTransfer => _kind == 'transfer';

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
      _mood = e.mood;
      _workState = e.workState;
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
    } else if (widget.initialCategoryId != null) {
      _parentId = widget.initialCategoryId;
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
    setState(() => _date = DateTime(picked.year, picked.month, picked.day, 12));
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
    final int mood = _isTransfer ? 0 : _mood;
    final String? state = _isTransfer ? null : _workState;

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
        mood: mood,
        workState: state,
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
        mood: mood,
        workState: state,
      );
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final double h = MediaQuery.sizeOf(context).height * RecordPage.heightFactor;
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: h,
        width: double.infinity,
        child: Container(
          decoration: BoxDecoration(
            color: Xm.bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: <Widget>[
              XmSheetHeader(
                title: _isEditing ? '编辑账单' : '记一笔',
                subtitle: _isEditing ? null : '选好分类，输入金额就行',
                onClose: () => Navigator.of(context).pop(false),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                child: XmSegmented<String>(
                  values: const <String>['expense', 'income', 'transfer'],
                  labels: const <String>['支出', '收入', '转账'],
                  value: _kind,
                  onChanged: _switchKind,
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
      ),
    );
  }

  Widget _amountBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      decoration: BoxDecoration(
        color: Xm.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Xm.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text('¥',
                style: Xm.text(19, FontWeight.w600, color: Xm.ink3)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                _amount.isEmpty ? '0.00' : _amount,
                style: Xm.text(
                  38,
                  FontWeight.w700,
                  spacing: -1,
                  height: 1,
                  tabular: true,
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: <Widget>[
        _section(
          '分类',
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final TxnCategory c in _topCategories)
                XmChoice(
                  label: c.name,
                  dense: true,
                  selected: _parentId == c.id,
                  onTap: () => setState(() {
                    _parentId = c.id;
                    _childId = null;
                  }),
                ),
            ],
          ),
        ),
        if (_childCategories.isNotEmpty)
          _section(
            '二级分类',
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final TxnCategory c in _childCategories)
                  XmChoice(
                    label: c.name,
                    dense: true,
                    selected: _childId == c.id,
                    onTap: () => setState(
                        () => _childId = _childId == c.id ? null : c.id),
                  ),
              ],
            ),
          ),
        _section(
          '账户',
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final Account a in _accounts)
                XmChoice(
                  label: a.name,
                  dense: true,
                  selected: _accountId == a.id,
                  onTap: () => setState(() => _accountId = a.id),
                ),
            ],
          ),
        ),
        _section(
          '这笔钱花得',
          Row(
            children: <Widget>[
              for (final XmMood m in <XmMood>[XmMood.happy, XmMood.regret])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _moodButton(m),
                ),
            ],
          ),
        ),
        _section(
          '当时在',
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final String s in XmWorkState.presets)
                XmChoice(
                  label: s,
                  dense: true,
                  selected: _workState == s,
                  onTap: () => setState(
                      () => _workState = _workState == s ? null : s),
                ),
            ],
          ),
        ),
        _section(
          '其他',
          Container(
            padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
            decoration: BoxDecoration(
              color: Xm.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Xm.line),
            ),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text('日期', style: Xm.text(14, FontWeight.w500)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.event_rounded, size: 17),
                      label: Text(fmtDate(_date),
                          style: Xm.text(14, FontWeight.w600)),
                    ),
                  ],
                ),
                const XmDivider(indent: 0, endIndent: 0),
                Row(
                  children: <Widget>[
                    Text('计入预算', style: Xm.text(14, FontWeight.w500)),
                    const Spacer(),
                    Switch(
                      value: _inBudget,
                      onChanged: (bool v) => setState(() => _inBudget = v),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        XmField(
          controller: _note,
          hint: '备注（可选）',
          maxLength: 40,
          textInputAction: TextInputAction.done,
        ),
      ],
    );
  }

  Widget _moodButton(XmMood m) {
    final bool selected = _mood == m.code;
    return GestureDetector(
      onTap: () => setState(() => _mood = selected ? 0 : m.code),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Xm.brand : Xm.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? Colors.transparent : Xm.line,
          ),
        ),
        child: Text(
          '${m.emoji} ${m.label}',
          style: Xm.text(
            13.5,
            FontWeight.w600,
            color: selected
                ? (Xm.isDark ? const Color(0xFF08120D) : Colors.white)
                : Xm.ink2,
          ),
        ),
      ),
    );
  }

  Widget _transferForm() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: <Widget>[
        _section(
          '从哪个账户转出',
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final Account a in _accounts)
                XmChoice(
                  label: a.name,
                  dense: true,
                  selected: _accountId == a.id,
                  onTap: () => setState(() => _accountId = a.id),
                ),
            ],
          ),
        ),
        _section(
          '转到哪个账户',
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final Account a in _accounts)
                XmChoice(
                  label: a.name,
                  dense: true,
                  selected: _toAccountId == a.id,
                  onTap: () => setState(() => _toAccountId = a.id),
                ),
            ],
          ),
        ),
        _section(
          '日期',
          Row(
            children: <Widget>[
              TextButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event_rounded, size: 17),
                label: Text(fmtDate(_date)),
              ),
            ],
          ),
        ),
        XmField(
          controller: _note,
          hint: '备注（可选）',
          maxLength: 40,
          textInputAction: TextInputAction.done,
        ),
      ],
    );
  }

  Widget _section(String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 7),
            child: Text(title,
                style: Xm.text(12, FontWeight.w500,
                    spacing: 0.3, color: Xm.ink3)),
          ),
          child,
        ],
      ),
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
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
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
      height: 48,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          color: Xm.surface,
          borderRadius: BorderRadius.circular(13),
          child: InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: () => _tapKey(k),
            child: Center(
              child: k == '<'
                  ? Icon(Icons.backspace_outlined, size: 21, color: Xm.ink2)
                  : Text(
                      k,
                      style: Xm.text(23, FontWeight.w600, height: 1),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _saveButton() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 6, 16, 10 + MediaQuery.paddingOf(context).bottom * 0.2),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: _canSave ? Xm.buttonGradient : null,
            color: _canSave ? null : (Xm.isDark ? Xm.surface2 : Xm.line),
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
                  style: Xm.text(
                    15.5,
                    FontWeight.w600,
                    spacing: 1,
                    color: _canSave ? Colors.white : Xm.ink3,
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
