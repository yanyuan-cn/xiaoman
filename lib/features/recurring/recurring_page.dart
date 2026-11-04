import 'package:flutter/material.dart';

import '../../core/theme.dart';

import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../state/data_bus.dart';

class RecurringPage extends StatefulWidget {
  const RecurringPage({super.key, required this.repo});

  final Repo repo;

  @override
  State<RecurringPage> createState() => _RecurringPageState();
}

class _RecurringPageState extends State<RecurringPage> {
  List<RecurringRule> _rules = const <RecurringRule>[];
  List<Account> _accounts = const <Account>[];
  List<TxnCategory> _categories = const <TxnCategory>[];
  Map<int, int> _deltas = const <int, int>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<RecurringRule> rules = await widget.repo.recurringRules();
    final List<Account> accounts = await widget.repo.accounts();
    final List<TxnCategory> categories = await widget.repo.categories();
    final Map<int, int> deltas = await widget.repo.accountDeltas();
    if (!mounted) return;
    setState(() {
      _rules = rules;
      _accounts = accounts;
      _categories = categories;
      _deltas = deltas;
      _loading = false;
    });
  }

  int _balance(Account a) => a.initialBalance + (_deltas[a.id] ?? 0);

  Account? _account(int id) {
    for (final Account a in _accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  Future<void> _edit([RecurringRule? rule]) async {
    final bool? ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext _) => _RuleEditorPage(
          repo: widget.repo,
          accounts: _accounts,
          categories: _categories,
          rule: rule,
        ),
      ),
    );
    if (ok != true) return;
    await _load();
    DataBus.instance.bump();
  }

  Future<void> _delete(RecurringRule r) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('删除「${r.name}」'),
        content: const Text('已经自动生成的账单不会被删除。'),
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
    await widget.repo.deleteRecurringRule(r.id);
    await _load();
    DataBus.instance.bump();
  }

  Future<void> _toggle(RecurringRule r, bool active) async {
    await widget.repo.setRecurringRuleActive(r.id, active);
    await _load();
  }

  Future<void> _runNow() async {
    final List<int> ids = await widget.repo.runDueRecurringRules();
    await _load();
    DataBus.instance.bump();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ids.isEmpty ? '暂时没有到期的账单' : '已生成 ${ids.length} 笔'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('定期扣款'),
        actions: <Widget>[
          IconButton(
            tooltip: '立即检查到期',
            onPressed: _runNow,
            icon: const Icon(Icons.play_circle_outline),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2ED),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '到设定的日子会自动生成一笔账单。还款按「转账」处理：'
                    '钱从资产账户转到贷款账户，负债减少，不增加当月支出。',
                    style: TextStyle(
                        fontSize: 12, color: Color(0xFF2F5F44), height: 1.6),
                  ),
                ),
                const SizedBox(height: 16),
                if (_rules.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('还没有定期扣款',
                          style: TextStyle(fontSize: 13, color: Xm.ink3)),
                    ),
                  )
                else
                  for (final RecurringRule r in _rules) _ruleTile(r),
                const SizedBox(height: 20),
                if (_liabilities.isNotEmpty) ...<Widget>[
                  Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 8),
                    child: Text('贷款 / 负债账户',
                        style:
                            TextStyle(fontSize: 12, color: Xm.ink3)),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Xm.surface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: <Widget>[
                        for (final Account a in _liabilities)
                          ListTile(
                            dense: true,
                            title: Text(a.name,
                                style: const TextStyle(fontSize: 14)),
                            subtitle: Text('待还 ${formatCents(_balance(a).abs())}',
                                style: TextStyle(
                                    fontSize: 11, color: Xm.ink3)),
                            trailing: TextButton(
                              onPressed: () => _editNewFor(a),
                              child: const Text('加还款计划'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('新增规则'),
      ),
    );
  }

  List<Account> get _liabilities =>
      _accounts.where((Account a) => a.isLiability).toList(growable: false);

  Future<void> _editNewFor(Account liability) async {
    final List<Account> assets =
        _accounts.where((Account a) => !a.isLiability).toList(growable: false);
    final bool? ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext _) => _RuleEditorPage(
          repo: widget.repo,
          accounts: _accounts,
          categories: _categories,
          presetToAccountId: liability.id,
          presetFromAccountId: assets.isEmpty ? null : assets.first.id,
        ),
      ),
    );
    if (ok != true) return;
    await _load();
    DataBus.instance.bump();
  }

  Widget _ruleTile(RecurringRule r) {
    final Account? from = _account(r.fromAccountId);
    final Account? to = r.toAccountId == null ? null : _account(r.toAccountId!);
    final String detail = to == null
        ? '每月 ${r.dayOfMonth} 号 · 从 ${from?.name ?? '未知'} 支出'
        : '每月 ${r.dayOfMonth} 号 · ${from?.name ?? '未知'} → ${to.name}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: Xm.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: InkWell(
              onTap: () => _edit(r),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(r.name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 3),
                  Text(detail,
                      style: TextStyle(
                          fontSize: 11, color: Xm.ink3)),
                  const SizedBox(height: 3),
                  Text('¥${formatCents(r.amount)}',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          Switch(
            value: r.active,
            onChanged: (bool v) => _toggle(r, v),
          ),
          IconButton(
            tooltip: '删除',
            onPressed: () => _delete(r),
            icon: Icon(Icons.delete_outline,
                size: 20, color: Xm.ink3),
          ),
        ],
      ),
    );
  }
}

class _RuleEditorPage extends StatefulWidget {
  const _RuleEditorPage({
    required this.repo,
    required this.accounts,
    required this.categories,
    this.rule,
    this.presetToAccountId,
    this.presetFromAccountId,
  });

  final Repo repo;
  final List<Account> accounts;
  final List<TxnCategory> categories;
  final RecurringRule? rule;
  final int? presetToAccountId;
  final int? presetFromAccountId;

  @override
  State<_RuleEditorPage> createState() => _RuleEditorPageState();
}

class _RuleEditorPageState extends State<_RuleEditorPage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();

  int _day = 1;
  int? _fromId;
  int? _toId;
  int? _categoryId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final RecurringRule? r = widget.rule;
    if (r != null) {
      _name.text = r.name;
      _amount.text = formatCentsPlain(r.amount);
      _note.text = r.note ?? '';
      _day = r.dayOfMonth;
      _fromId = r.fromAccountId;
      _toId = r.toAccountId;
      _categoryId = r.categoryId;
    } else {
      _toId = widget.presetToAccountId;
      _fromId = widget.presetFromAccountId ??
          (widget.accounts
                  .where((Account a) => !a.isLiability)
                  .toList()
                  .isEmpty
              ? null
              : widget.accounts
                  .firstWhere((Account a) => !a.isLiability)
                  .id);
      if (widget.presetToAccountId != null) {
        _name.text = '还款';
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final int? cents = parseYuanToCents(_amount.text);
    final String name = _name.text.trim();
    if (name.isEmpty) {
      _toast('给这条规则起个名字');
      return;
    }
    if (cents == null || cents <= 0) {
      _toast('请输入金额');
      return;
    }
    if (_fromId == null) {
      _toast('请选择扣款账户');
      return;
    }
    if (_toId != null && _toId == _fromId) {
      _toast('扣款账户和还款账户不能相同');
      return;
    }

    setState(() => _saving = true);
    await widget.repo.saveRecurringRule(
      id: widget.rule?.id,
      name: name,
      amount: cents,
      dayOfMonth: _day,
      fromAccountId: _fromId!,
      toAccountId: _toId,
      categoryId: _toId == null ? _categoryId : null,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    await widget.repo.runDueRecurringRules();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Account> assets =
        widget.accounts.where((Account a) => !a.isLiability).toList();
    final List<Account> liabilities =
        widget.accounts.where((Account a) => a.isLiability).toList();
    final List<TxnCategory> expenseTops = widget.categories
        .where((TxnCategory c) => c.kind == 'expense' && c.parentId == null)
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.rule == null ? '新增定期扣款' : '编辑定期扣款'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          _label('名称'),
          TextField(
            controller: _name,
            maxLength: 20,
            decoration: const InputDecoration(
              hintText: '例如：房贷、房租、会员费',
              counterText: '',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),
          _label('金额'),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              prefixText: '¥ ',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),
          _label('每月几号扣'),
          _dropdown<int>(
            value: _day,
            items: <DropdownMenuItem<int>>[
              for (int i = 1; i <= 28; i++)
                DropdownMenuItem<int>(value: i, child: Text('$i 号')),
            ],
            onChanged: (int? v) => setState(() => _day = v ?? _day),
          ),
          const SizedBox(height: 16),
          _label('从哪个账户扣'),
          _dropdown<int?>(
            value: assets.any((Account a) => a.id == _fromId) ? _fromId : null,
            items: <DropdownMenuItem<int?>>[
              for (final Account a in assets)
                DropdownMenuItem<int?>(value: a.id, child: Text(a.name)),
            ],
            onChanged: (int? v) => setState(() => _fromId = v),
          ),
          const SizedBox(height: 16),
          _label('还款到哪个贷款账户（不选则记成一笔支出）'),
          _dropdown<int?>(
            value: _toId,
            items: <DropdownMenuItem<int?>>[
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('不还款，直接记支出'),
              ),
              for (final Account a in liabilities)
                DropdownMenuItem<int?>(value: a.id, child: Text(a.name)),
            ],
            onChanged: (int? v) => setState(() => _toId = v),
          ),
          if (_toId == null) ...<Widget>[
            const SizedBox(height: 16),
            _label('计入哪个分类'),
            _dropdown<int?>(
              value: expenseTops.any((TxnCategory c) => c.id == _categoryId)
                  ? _categoryId
                  : null,
              items: <DropdownMenuItem<int?>>[
                for (final TxnCategory c in expenseTops)
                  DropdownMenuItem<int?>(value: c.id, child: Text(c.name)),
              ],
              onChanged: (int? v) => setState(() => _categoryId = v),
            ),
          ],
          const SizedBox(height: 16),
          _label('备注（可选）'),
          TextField(
            controller: _note,
            maxLength: 30,
            decoration: const InputDecoration(
              counterText: '',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '保存中…' : '保存'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Xm.ink3),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        hint: const Text('请选择', style: TextStyle(fontSize: 14)),
        items: items,
        onChanged: onChanged,
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
