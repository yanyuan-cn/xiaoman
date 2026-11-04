import 'package:flutter/material.dart';

import '../../core/theme.dart';

import '../../data/models.dart';
import '../../data/repo.dart';
import '../../state/data_bus.dart';

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key, required this.repo});

  final Repo repo;

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  String _kind = 'expense';
  List<TxnCategory> _all = const <TxnCategory>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<TxnCategory> cats = await widget.repo.categories();
    if (!mounted) return;
    setState(() {
      _all = cats;
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
    await widget.repo.addCategory(
        name: name, kind: _kind, parentId: parent.id);
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
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('隐藏「${c.name}」'),
        content: Text(used == 0
            ? '这个分类会从选择列表里消失，历史流水不受影响。'
            : '这个分类下有 $used 条流水，隐藏后旧流水仍显示原分类，但新记账时选不到了。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('隐藏'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.repo.archiveCategory(c.id);
    await _load();
    DataBus.instance.bump();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('分类管理'),
        actions: <Widget>[
          IconButton(
            tooltip: '新建一级分类',
            onPressed: _addTop,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment<String>(value: 'expense', label: Text('支出')),
                ButtonSegment<String>(value: 'income', label: Text('收入')),
              ],
              selected: <String>{_kind},
              onSelectionChanged: (Set<String> s) =>
                  setState(() => _kind = s.first),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    children: <Widget>[
                      for (final TxnCategory top in _tops) _section(top),
                      const SizedBox(height: 8),
                      Text('隐藏的分类不会出现，但历史流水仍保留原分类。',
                          style:
                              TextStyle(fontSize: 11, color: Xm.ink3)),
                    ],
                  ),
          ),
        ],
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
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(top.name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500)),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz, size: 20),
                onSelected: (String v) {
                  if (v == 'add') _addChild(top);
                  if (v == 'rename') _rename(top);
                  if (v == 'archive') _archive(top);
                },
                itemBuilder: (BuildContext ctx) =>
                    const <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(value: 'add', child: Text('新建二级分类')),
                  PopupMenuItem<String>(value: 'rename', child: Text('重命名')),
                  PopupMenuItem<String>(value: 'archive', child: Text('隐藏')),
                ],
              ),
            ],
          ),
          if (kids.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 2, bottom: 6),
              child: Text('没有二级分类',
                  style: TextStyle(fontSize: 11, color: Xm.ink3)),
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
                        color: const Color(0xFFEAF2ED),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(c.name,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF2F5F44))),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
