import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../state/data_bus.dart';
import '../../ui/components.dart';

/// 分类管理：记账分类 + 账户类型两个页签。
///
/// 账户类型以前是写死的五个，现在和分类一样可以增删改；改名会连带
/// 更新所有用到它的账户（见 `Repo.renameAccountType`）。
class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key, required this.repo});

  final Repo repo;

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  String _tab = 'cat';
  String _kind = 'expense';
  List<TxnCategory> _all = const <TxnCategory>[];
  List<AccountType> _types = const <AccountType>[];
  Map<String, int> _typeUsage = <String, int>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<TxnCategory> cats = await widget.repo.categories();
    final List<AccountType> types = await widget.repo.accountTypes();
    final Map<String, int> usage = <String, int>{};
    for (final AccountType t in types) {
      usage[t.name] = await widget.repo.accountTypeUsage(t.name);
    }
    if (!mounted) return;
    setState(() {
      _all = cats;
      _types = types;
      _typeUsage = usage;
      _loading = false;
    });
  }

  List<TxnCategory> get _tops => _all
      .where((TxnCategory c) => c.kind == _kind && c.parentId == null)
      .toList(growable: false);

  List<TxnCategory> _children(int parentId) => _all
      .where((TxnCategory c) => c.parentId == parentId)
      .toList(growable: false);

  Future<String?> _prompt(String title, String initial) async {
    final TextEditingController ctl = TextEditingController(text: initial);
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          autofocus: true,
          maxLength: 12,
          decoration: const InputDecoration(hintText: '名称', counterText: ''),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctl.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    ctl.dispose();
    return (result == null || result.isEmpty) ? null : result;
  }

  // ---------------- 记账分类 ----------------

  Future<void> _addTop() async {
    final String? name = await _prompt('新建一级分类', '');
    if (name == null) return;
    await widget.repo.addCategory(name: name, kind: _kind);
    await _load();
    DataBus.instance.bump();
  }

  Future<void> _addChild(TxnCategory parent) async {
    final String? name = await _prompt('在「${parent.name}」下新建二级分类', '');
    if (name == null) return;
    await widget.repo.addCategory(name: name, kind: _kind, parentId: parent.id);
    await _load();
    DataBus.instance.bump();
  }

  Future<void> _rename(TxnCategory c) async {
    final String? name = await _prompt('重命名', c.name);
    if (name == null) return;
    await widget.repo.renameCategory(c.id, name);
    await _load();
    DataBus.instance.bump();
  }

  Future<void> _archive(TxnCategory c) async {
    final int used = await widget.repo.categoryUsage(c.id);
    if (!mounted) return;
    final bool? ok = await _confirm(
      '隐藏「${c.name}」',
      used == 0
          ? '这个分类会从选择列表里消失，历史流水不受影响。'
          : '这个分类下有 $used 条流水，隐藏后旧流水仍显示原分类，但新记账时选不到了。',
      '隐藏',
    );
    if (ok != true) return;
    await widget.repo.archiveCategory(c.id);
    await _load();
    DataBus.instance.bump();
  }

  // ---------------- 账户类型 ----------------

  Future<void> _addType() async {
    final String? name = await _prompt('新建账户类型', '');
    if (name == null) return;
    if (_types.any((AccountType t) => t.name == name)) {
      _toast('已经有「$name」了');
      return;
    }
    await widget.repo.addAccountType(name);
    await _load();
    DataBus.instance.bump();
  }

  Future<void> _renameType(AccountType t) async {
    final String? name = await _prompt('重命名账户类型', t.name);
    if (name == null || name == t.name) return;
    if (_types.any((AccountType x) => x.name == name)) {
      _toast('已经有「$name」了');
      return;
    }
    await widget.repo.renameAccountType(t.id, name);
    await _load();
    DataBus.instance.bump();
  }

  Future<void> _archiveType(AccountType t) async {
    final int used = _typeUsage[t.name] ?? 0;
    final bool? ok = await _confirm(
      '隐藏「${t.name}」',
      used == 0
          ? '这个类型会从选择列表里消失，已有的账户不受影响。'
          : '还有 $used 个账户在用「${t.name}」，隐藏后它们仍显示这个类型，但新建账户时选不到了。',
      '隐藏',
    );
    if (ok != true) return;
    await widget.repo.archiveAccountType(t.id);
    await _load();
    DataBus.instance.bump();
  }

  Future<bool?> _confirm(String title, String content, String action) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return XmPageScaffold(
      title: '分类管理',
      subtitle: _tab == 'cat'
          ? '记账时选的分类，${_tops.length} 个一级'
          : '账户的类型，${_types.length} 个',
      actions: <Widget>[
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: XmAvatarButton(
            icon: Icons.add_rounded,
            tooltip: _tab == 'cat' ? '新建一级分类' : '新建账户类型',
            onTap: _tab == 'cat' ? _addTop : _addType,
          ),
        ),
      ],
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: XmSegmented<String>(
              values: const <String>['cat', 'type'],
              labels: const <String>['记账分类', '账户类型'],
              value: _tab,
              onChanged: (String v) => setState(() => _tab = v),
            ),
          ),
          if (_tab == 'cat')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: XmSegmented<String>(
                values: const <String>['expense', 'income'],
                labels: const <String>['支出', '收入'],
                value: _kind,
                height: 34,
                onChanged: (String v) => setState(() => _kind = v),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    children: _tab == 'cat' ? _catList() : _typeList(),
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _catList() {
    return <Widget>[
      for (final TxnCategory top in _tops) _section(top),
      const SizedBox(height: 8),
      Text('隐藏的分类不会出现，但历史流水仍保留原分类。',
          style: Xm.text(11, FontWeight.w400, color: Xm.ink3)),
    ];
  }

  List<Widget> _typeList() {
    return <Widget>[
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Xm.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: Xm.cardShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: <Widget>[
            for (int i = 0; i < _types.length; i++)
              _typeRow(_types[i], first: i == 0),
            if (_types.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text('还没有账户类型',
                    style: Xm.text(12, FontWeight.w400, color: Xm.ink3)),
              ),
          ],
        ),
      ),
      Text('点一行改名，右边可以隐藏。改名字会连带把所有用到它的账户一起改。',
          style: Xm.text(11, FontWeight.w400, color: Xm.ink3)),
    ];
  }

  Widget _typeRow(AccountType t, {bool first = false}) {
    final int used = _typeUsage[t.name] ?? 0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _renameType(t),
        child: Column(
          children: <Widget>[
            if (!first) const XmDivider(indent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Xm.brandLL,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(Icons.account_balance_wallet_outlined,
                        size: 17, color: Xm.brand),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(t.name,
                            style: Xm.text(15, FontWeight.w500,
                                spacing: -0.1)),
                        const SizedBox(height: 2),
                        Text(
                          used == 0 ? '还没有账户用这个类型' : '$used 个账户在用',
                          style: Xm.text(11.5, FontWeight.w400,
                              color: Xm.ink3),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz_rounded, size: 20),
                    onSelected: (String v) {
                      if (v == 'rename') _renameType(t);
                      if (v == 'archive') _archiveType(t);
                    },
                    itemBuilder: (BuildContext ctx) =>
                        const <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                          value: 'rename', child: Text('重命名')),
                      PopupMenuItem<String>(
                          value: 'archive', child: Text('隐藏')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(TxnCategory top) {
    final List<TxnCategory> kids = _children(top.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 12),
      decoration: BoxDecoration(
        color: Xm.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: Xm.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(top.name,
                    style: Xm.text(15, FontWeight.w600, spacing: -0.1)),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz_rounded, size: 20),
                onSelected: (String v) {
                  if (v == 'add') _addChild(top);
                  if (v == 'rename') _rename(top);
                  if (v == 'archive') _archive(top);
                },
                itemBuilder: (BuildContext ctx) =>
                    const <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                      value: 'add', child: Text('新建二级分类')),
                  PopupMenuItem<String>(value: 'rename', child: Text('重命名')),
                  PopupMenuItem<String>(value: 'archive', child: Text('隐藏')),
                ],
              ),
            ],
          ),
          if (kids.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 6),
              child: Text('没有二级分类',
                  style: Xm.text(11, FontWeight.w400, color: Xm.ink3)),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final TxnCategory c in kids)
                  InkWell(
                    onTap: () => _rename(c),
                    onLongPress: () => _archive(c),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Xm.brandLL,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(c.name,
                          style: Xm.text(12, FontWeight.w500,
                              color: Xm.brand)),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
