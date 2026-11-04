import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';

import '../../data/import/decode.dart';
import '../../data/import/draft.dart';
import '../../data/models.dart';
import '../../data/repo.dart';

class ImportPage extends StatefulWidget {
  const ImportPage({super.key, required this.repo});

  final Repo repo;

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  List<Account> _accounts = const <Account>[];
  List<TxnCategory> _categories = const <TxnCategory>[];
  bool _busy = false;
  String? _error;
  String? _fileName;
  ImportParse? _parse;
  Map<String, int?> _accountMap = <String, int?>{};
  ImportResult? _result;
  bool _excludeBudget = false;

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    final List<Account> accounts = await widget.repo.accounts();
    final List<TxnCategory> categories = await widget.repo.categories();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _categories = categories;
    });
  }

  int? _guessAccount(String name) {
    if (name.isEmpty) return null;
    for (final Account a in _accounts) {
      if (a.name == name) return a.id;
    }
    for (final Account a in _accounts) {
      if (a.name.contains(name) || name.contains(a.name)) return a.id;
    }
    return null;
  }

  T? _firstWhere<T>(Iterable<T> items, bool Function(T) test) {
    for (final T it in items) {
      if (test(it)) return it;
    }
    return null;
  }

  int _matchCategory(DraftTxn d) {
    final String? sub = d.subCategory;
    if (d.kind == 'income') {
      if (sub != null && sub.isNotEmpty) {
        final TxnCategory? hit = _firstWhere<TxnCategory>(
          _categories,
          (TxnCategory c) => c.kind == 'income' && c.name == sub,
        );
        if (hit != null) return hit.id;
      }
      final TxnCategory? byName = _firstWhere<TxnCategory>(
        _categories,
        (TxnCategory c) => c.kind == 'income' && c.name == d.categoryName,
      );
      if (byName != null) return byName.id;
      return _fallbackCategory('income');
    }

    final TxnCategory? parent = _firstWhere<TxnCategory>(
      _categories,
      (TxnCategory c) =>
          c.kind == 'expense' && c.parentId == null && c.name == d.categoryName,
    );
    if (parent == null) return _fallbackCategory('expense');
    if (sub != null && sub.isNotEmpty) {
      final TxnCategory? child = _firstWhere<TxnCategory>(
        _categories,
        (TxnCategory c) => c.parentId == parent.id && c.name == sub,
      );
      if (child != null) return child.id;
    }
    return parent.id;
  }

  int _fallbackCategory(String kind) {
    final String wanted = kind == 'income' ? '其他收入' : '其他';
    for (final TxnCategory c in _categories) {
      if (c.kind == kind && c.name == wanted && c.parentId == null) return c.id;
    }
    for (final TxnCategory c in _categories) {
      if (c.kind == kind && c.parentId == null) return c.id;
    }
    return _categories.isEmpty ? 0 : _categories.first.id;
  }

  Future<void> _pickFile() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final List<PlatformFile>? files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['csv', 'txt'],
      );
      if (files == null || files.isEmpty) {
        setState(() => _busy = false);
        return;
      }
      final PlatformFile file = files.first;
      final Uint8List bytes = await file.readAsBytes();

      final String text = decodeText(bytes);

      final ImportParse? parsed = parseAny(text);
      if (parsed == null) {
        setState(() {
          _busy = false;
          _error = '认不出这个文件。支持支付宝账单、微信账单、其他记账 App 导出的 CSV。';
        });
        return;
      }

      final Map<String, int?> map = <String, int?>{};
      for (final String name in parsed.accountCounts.keys) {
        map[name] = _guessAccount(name);
      }
      setState(() {
        _busy = false;
        _fileName = file.name;
        _parse = parsed;
        _accountMap = map;
        _result = null;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '读取失败：$e';
      });
    }
  }

  Future<void> _runImport() async {
    final ImportParse? parsed = _parse;
    if (parsed == null) return;

    final List<ImportItem> items = <ImportItem>[];
    for (final DraftTxn d in parsed.rows) {
      final int? accId = _accountMap[d.accountName];
      if (accId == null) continue;
      items.add(ImportItem(
        kind: d.kind,
        amount: d.amountCents,
        occurredAt: d.occurredAt,
        accountId: accId,
        categoryId: _matchCategory(d),
        note: d.note,
        merchant: d.merchant,
        externalId: d.externalId,
        inBudget: !_excludeBudget,
      ));
    }
    if (items.isEmpty) {
      setState(() => _error = '没有可以导入的记录');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final String source = parsed.format == ImportFormat.alipay
        ? 'alipay'
        : (parsed.format == ImportFormat.wechat ? 'wechat' : 'migration');
    final ImportResult r = await widget.repo.importItems(
      items,
      source: source,
      fileName: _fileName,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = r;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入账单')),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_result != null) return _doneView();
    if (_parse == null) return _pickView();
    return _previewView();
  }

  Widget _pickView() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Icon(Icons.upload_file, size: 64, color: Xm.ink3),
        const SizedBox(height: 16),
        const Text(
          '导入账单',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          '支持三种来源，选文件后自动识别：\n'
          '· 支付宝账单（CSV）\n'
          '· 微信账单（解压后的 CSV）\n'
          '· 其他记账 App 导出的 CSV',
          style: TextStyle(fontSize: 13, color: Xm.ink3, height: 1.6),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy ? null : _pickFile,
          icon: const Icon(Icons.folder_open),
          label: Text(_busy ? '读取中…' : '选择 CSV 文件'),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 16),
          _errorBox(_error!),
        ],
      ],
    );
  }

  Widget _previewView() {
    final ImportParse p = _parse!;
    final bool ready = _accounts.isNotEmpty &&
        _accountMap.values.every((int? v) => v != null);

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2ED),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(_fileName ?? '未命名文件',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('识别为：${p.formatLabel}',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF3F7D58))),
                    const SizedBox(height: 6),
                    Text(
                      '共 ${p.total} 行 · 可导入 ${p.rows.length} 行'
                      '${p.skipped > 0 ? ' · 跳过 ${p.skipped} 行（无法识别）' : ''}',
                      style: TextStyle(fontSize: 12, color: Xm.ink3),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text('账户对应',
                  style: TextStyle(fontSize: 12, color: Xm.ink3)),
              const SizedBox(height: 8),
              for (final String name in p.accountCounts.keys)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          name.isEmpty ? '（原文件未填账户）' : name,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      Text('${p.accountCounts[name]} 笔',
                          style: TextStyle(
                              fontSize: 12, color: Xm.ink3)),
                      const SizedBox(width: 10),
                      DropdownButton<int>(
                        value: _accountMap[name],
                        hint: const Text('选择'),
                        underline: const SizedBox.shrink(),
                        items: <DropdownMenuItem<int>>[
                          for (final Account a in _accounts)
                            DropdownMenuItem<int>(
                              value: a.id,
                              child: Text(a.name),
                            ),
                        ],
                        onChanged: (int? v) =>
                            setState(() => _accountMap[name] = v),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              CheckboxListTile(
                value: _excludeBudget,
                onChanged: (bool? v) =>
                    setState(() => _excludeBudget = v ?? false),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('历史账单不计入预算',
                    style: TextStyle(fontSize: 14)),
                subtitle: Text('导入前的旧账不占本月预算额度',
                    style: TextStyle(fontSize: 11, color: Xm.ink3)),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                _errorBox(_error!),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: (_busy || !ready) ? null : _runImport,
              child: Text(_busy
                  ? '导入中…'
                  : ready
                      ? '导入 ${p.rows.length} 笔'
                      : '请先把账户都选好'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _doneView() {
    final ImportResult r = _result!;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        const Icon(Icons.check_circle, size: 64, color: Color(0xFF3F7D58)),
        const SizedBox(height: 16),
        Text('导入完成',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Text('新增 ${r.inserted} 笔',
            style: TextStyle(fontSize: 15, color: Xm.ink)),
        if (r.skipped > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('跳过 ${r.skipped} 笔（已存在）',
                style: TextStyle(fontSize: 13, color: Xm.ink3)),
          ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => setState(() {
            _parse = null;
            _result = null;
            _fileName = null;
            _accountMap = <String, int?>{};
          }),
          child: const Text('再导入一个文件'),
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('完成'),
        ),
        const SizedBox(height: 18),
        Text(
          '导错了可以在首页右上角菜单里「撤销上次导入」。',
          style: TextStyle(fontSize: 12, color: Xm.ink3),
        ),
      ],
    );
  }

  Widget _errorBox(String msg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEDEA),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(msg,
          style: const TextStyle(fontSize: 12, color: Color(0xFFB3261E))),
    );
  }
}
