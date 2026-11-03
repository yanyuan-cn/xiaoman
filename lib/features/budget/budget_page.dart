import 'package:flutter/material.dart';

import '../../core/budget_period.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../state/data_bus.dart';

class BudgetPage extends StatefulWidget {
  const BudgetPage({super.key, required this.repo});

  final Repo repo;

  @override
  State<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends State<BudgetPage> {
  final TextEditingController _total = TextEditingController();
  final TextEditingController _food = TextEditingController();
  final TextEditingController _shop = TextEditingController();

  String _type = 'month';
  int _startDay = 1;
  int? _foodId;
  int? _shopId;
  bool _loading = true;
  bool _saving = false;

  int _spentTotal = 0;
  int _spentFood = 0;
  int _spentShop = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _total.dispose();
    _food.dispose();
    _shop.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final String? type = await widget.repo.getSetting('budget_type');
    final String? day = await widget.repo.getSetting('budget_start_day');
    final List<BudgetRule> rules = await widget.repo.budgets();
    final List<TxnCategory> cats = await widget.repo.categories();

    int? foodId;
    int? shopId;
    for (final TxnCategory c in cats) {
      if (c.kind != 'expense' || c.parentId != null) continue;
      if (c.name == '食品餐饮') foodId = c.id;
      if (c.name == '购物消费') shopId = c.id;
    }

    final String t = (type == null || type.isEmpty) ? 'month' : type;
    final int raw = int.tryParse(day ?? '') ?? 1;
    final int d = raw < 1 ? 1 : (raw > 28 ? 28 : raw);
    final BudgetPeriod period = budgetPeriodOf(t, d);

    int amountOf(String scope, int? categoryId) {
      for (final BudgetRule r in rules) {
        if (r.scope == scope && r.categoryId == categoryId) return r.amount;
      }
      return 0;
    }

    final int spentTotal = await widget.repo.budgetSpent(
      from: period.start,
      to: period.end,
    );
    final int spentFood = foodId == null
        ? 0
        : await widget.repo.budgetSpent(
            from: period.start,
            to: period.end,
            parentCategoryId: foodId,
          );
    final int spentShop = shopId == null
        ? 0
        : await widget.repo.budgetSpent(
            from: period.start,
            to: period.end,
            parentCategoryId: shopId,
          );

    if (!mounted) return;
    setState(() {
      _type = t;
      _startDay = d;
      _foodId = foodId;
      _shopId = shopId;
      final int total = amountOf('all', null);
      final int food = foodId == null ? 0 : amountOf('category', foodId);
      final int shop = shopId == null ? 0 : amountOf('category', shopId);
      _total.text = total == 0 ? '' : formatCentsPlain(total);
      _food.text = food == 0 ? '' : formatCentsPlain(food);
      _shop.text = shop == 0 ? '' : formatCentsPlain(shop);
      _spentTotal = spentTotal;
      _spentFood = spentFood;
      _spentShop = spentShop;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.repo.setSetting('budget_type', _type);
    await widget.repo.setSetting('budget_start_day', '$_startDay');

    final int total = parseYuanToCents(_total.text) ?? 0;
    await widget.repo.saveBudget(scope: 'all', amount: total);

    if (_foodId != null) {
      await widget.repo.saveBudget(
        scope: 'category',
        categoryId: _foodId,
        amount: parseYuanToCents(_food.text) ?? 0,
      );
    }
    if (_shopId != null) {
      await widget.repo.saveBudget(
        scope: 'category',
        categoryId: _shopId,
        amount: parseYuanToCents(_shop.text) ?? 0,
      );
    }

    DataBus.instance.bump();
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('预算已保存'), duration: Duration(seconds: 2)),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('预算')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: <Widget>[
                _periodCard(),
                const SizedBox(height: 16),
                _budgetCard(),
                const SizedBox(height: 20),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? '保存中…' : '保存'),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '金额留空或填 0 表示不设这项预算。',
                  style: TextStyle(fontSize: 12, color: Colors.black38),
                ),
              ],
            ),
    );
  }

  Widget _periodCard() {
    final BudgetPeriod p = budgetPeriodOf(_type, _startDay);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('重置周期',
              style: TextStyle(fontSize: 12, color: Colors.black45)),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const <ButtonSegment<String>>[
              ButtonSegment<String>(value: 'month', label: Text('每月')),
              ButtonSegment<String>(value: 'week', label: Text('每周')),
            ],
            selected: <String>{_type},
            onSelectionChanged: (Set<String> s) =>
                setState(() => _type = s.first),
          ),
          if (_type == 'month') ...<Widget>[
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                const Text('每月', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: _startDay,
                  underline: const SizedBox.shrink(),
                  items: <DropdownMenuItem<int>>[
                    for (int i = 1; i <= 28; i++)
                      DropdownMenuItem<int>(value: i, child: Text('$i 号')),
                  ],
                  onChanged: (int? v) =>
                      setState(() => _startDay = v ?? _startDay),
                ),
                const SizedBox(width: 8),
                const Text('重置', style: TextStyle(fontSize: 13)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '本期：${budgetPeriodLabel(p, _type)}',
              style: const TextStyle(fontSize: 11, color: Colors.black38),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '每周一重置 · 本期：${budgetPeriodLabel(p, _type)}',
                style: const TextStyle(fontSize: 11, color: Colors.black38),
              ),
            ),
        ],
      ),
    );
  }

  Widget _budgetCard() {
    final BudgetPeriod p = budgetPeriodOf(_type, _startDay);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: <Widget>[
          _amountRow('总预算', _total, _spentTotal, true),
          const Divider(height: 1),
          _amountRow('餐饮', _food, _spentFood, _foodId != null),
          const Divider(height: 1),
          _amountRow('购物', _shop, _spentShop, _shopId != null),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 8),
            child: Text(
              '本期已用：${budgetPeriodLabel(p, _type)}',
              style: const TextStyle(fontSize: 11, color: Colors.black38),
            ),
          ),
        ],
      ),
    );
  }

  Widget _amountRow(
    String label,
    TextEditingController ctl,
    int spent,
    bool enabled,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: enabled ? Colors.black87 : Colors.black26,
              ),
            ),
          ),
          const Text('¥', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: ctl,
              enabled: enabled,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                isDense: true,
                hintText: enabled ? '不设' : '分类不存在',
                border: InputBorder.none,
              ),
            ),
          ),
          Text(
            '已用 ${formatCents(spent)}',
            style: const TextStyle(fontSize: 11, color: Colors.black38),
          ),
        ],
      ),
    );
  }
}
