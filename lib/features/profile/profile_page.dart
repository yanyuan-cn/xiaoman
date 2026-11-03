import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/storage.dart';
import '../../core/version.dart';
import '../../data/models.dart';
import '../../data/apk_updater.dart';
import '../../data/repo.dart';
import '../../data/update_service.dart';
import '../../state/data_bus.dart';
import '../budget/budget_page.dart';
import '../categories/categories_page.dart';
import '../import/import_page.dart';
import '../recurring/recurring_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.repo});

  final Repo repo;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _checking = false;
  int _cacheBytes = 0;
  int _dbBytes = 0;
  Map<String, int> _stats = const <String, int>{};
  String? _updateUrl;

  @override
  void initState() {
    super.initState();
    _loadStorage();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final String? url = await widget.repo.getSetting('update_url');
    if (!mounted) return;
    setState(() => _updateUrl = url);
  }

  Future<void> _editUpdateUrl() async {
    final TextEditingController ctl =
        TextEditingController(text: _updateUrl ?? '');
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('更新源'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '填 version.json 的地址。留空则使用内置的多个地址自动尝试。',
              style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.5),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctl,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                hintText: 'https://example.com/version.json',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (result == null) return;
    await widget.repo.setSetting('update_url', result);
    await _loadSettings();
    if (!mounted) return;
    _toast(result.isEmpty ? '已恢复默认更新源' : '已保存自定义更新源');
  }

  Future<void> _loadStorage() async {
    final int cache = await cacheBytes();
    final int db = await databaseBytes();
    final Map<String, int> stats = await widget.repo.storageStats();
    if (!mounted) return;
    setState(() {
      _cacheBytes = cache;
      _dbBytes = db;
      _stats = stats;
    });
  }

  Future<void> _showStorage() async {
    await _loadStorage();
    if (!mounted) return;
    final bool? cleared = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('存储占用'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _storageRow('数据库', formatBytes(_dbBytes)),
            _storageRow('缓存', formatBytes(_cacheBytes)),
            const SizedBox(height: 10),
            Text(
              '${_stats['txns'] ?? 0} 条流水 · ${_stats['categories'] ?? 0} 个分类 · ${_stats['accounts'] ?? 0} 个账户',
              style: const TextStyle(fontSize: 12, color: Colors.black45),
            ),
            const SizedBox(height: 10),
            const Text(
              '缓存里主要是更新时下载的安装包，清理不会影响账目。',
              style: TextStyle(fontSize: 11, color: Colors.black38),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清理缓存'),
          ),
        ],
      ),
    );
    if (cleared != true) return;
    final int freed = await clearCache();
    await _loadStorage();
    if (!mounted) return;
    _toast('已清理 ${formatBytes(freed)}');
  }

  Widget _storageRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          SizedBox(width: 64, child: Text(label, style: const TextStyle(fontSize: 13))),
          Text(value, style: const TextStyle(fontSize: 13, color: Colors.black54)),
        ],
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _openImport() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => ImportPage(repo: widget.repo),
      ),
    );
    DataBus.instance.bump();
  }

  Future<void> _openCategories() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => CategoriesPage(repo: widget.repo),
      ),
    );
  }

  Future<void> _openBudget() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext _) => BudgetPage(repo: widget.repo),
      ),
    );
    DataBus.instance.bump();
  }

  Future<void> _openRecurring() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => RecurringPage(repo: widget.repo),
      ),
    );
    DataBus.instance.bump();
  }

  Future<void> _undoImport() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('撤销上次导入'),
        content: const Text('会删除最近一次导入的全部记录，手工记的不受影响。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('撤销'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final int n = await widget.repo.undoLastImport();
    DataBus.instance.bump();
    if (!mounted) return;
    _toast(n == 0 ? '没有可撤销的导入' : '已撤销 $n 笔');
  }

  String _q(String? v) {
    final String s = v ?? '';
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  Future<void> _exportCsv() async {
    final List<Txn> txns = await widget.repo.allTxns();
    final List<Account> accounts = await widget.repo.accounts();
    final List<TxnCategory> cats = await widget.repo.categories();
    final Map<int, Account> am = <int, Account>{
      for (final Account a in accounts) a.id: a
    };
    final Map<int, TxnCategory> cm = <int, TxnCategory>{
      for (final TxnCategory c in cats) c.id: c
    };

    final StringBuffer sb = StringBuffer('\uFEFF');
    sb.writeln('日期,类型,金额,分类,二级分类,账户,备注');
    for (final Txn t in txns) {
      final TxnCategory? c = t.categoryId == null ? null : cm[t.categoryId];
      final TxnCategory? parent =
          (c == null || c.parentId == null) ? null : cm[c.parentId!];
      final String type = t.isExpense ? '支出' : '收入';
      sb.writeln(<String>[
        _q('${t.occurredAt.year}-${_two(t.occurredAt.month)}-${_two(t.occurredAt.day)} '
            '${_two(t.occurredAt.hour)}:${_two(t.occurredAt.minute)}'),
        _q(type),
        _q((t.amount / 100).toStringAsFixed(2)),
        _q(parent?.name ?? c?.name ?? '未分类'),
        _q(parent == null ? '' : c!.name),
        _q(am[t.accountId]?.name ?? ''),
        _q(t.note ?? ''),
      ].join(','));
    }

    await _save('小满-流水-${_stamp()}.csv', sb.toString(), 'text/csv');
  }

  Future<void> _exportJson() async {
    final List<Txn> txns = await widget.repo.allTxns();
    final List<Account> accounts = await widget.repo.accounts();
    final List<TxnCategory> cats = await widget.repo.categories();
    final Map<String, Object?> data = <String, Object?>{
      'app': kAppName,
      'version': kAppVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'accounts': <Map<String, Object?>>[
        for (final Account a in accounts)
          <String, Object?>{
            'id': a.id,
            'name': a.name,
            'type': a.type,
            'initialBalance': a.initialBalance,
          },
      ],
      'categories': <Map<String, Object?>>[
        for (final TxnCategory c in cats)
          <String, Object?>{
            'id': c.id,
            'name': c.name,
            'kind': c.kind,
            'parentId': c.parentId,
          },
      ],
      'txns': <Map<String, Object?>>[
        for (final Txn t in txns)
          <String, Object?>{
            'kind': t.kind,
            'amount': t.amount,
            'occurredAt': t.occurredAt.toIso8601String(),
            'accountId': t.accountId,
            'categoryId': t.categoryId,
            'note': t.note,
            'source': t.source,
          },
      ],
    };
    await _save(
      '小满-备份-${_stamp()}.json',
      JsonEncoder.withIndent('  ').convert(data),
      'application/json',
    );
  }

  Future<void> _save(String fileName, String content, String mime) async {
    try {
      final Uri? uri = await FilePicker.saveFile(
        fileName: fileName,
        bytes: Uint8List.fromList(utf8.encode(content)),
        mimeType: mime,
      );
      if (!mounted) return;
      _toast(uri == null ? '已取消' : '已导出');
    } catch (e) {
      if (!mounted) return;
      _toast('导出失败：$e');
    }
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  String _stamp() {
    final DateTime n = DateTime.now();
    return '${n.year}${_two(n.month)}${_two(n.day)}-${_two(n.hour)}${_two(n.minute)}';
  }

  Future<void> _checkUpdate() async {
    setState(() => _checking = true);
    try {
      final UpdateInfo info =
          await UpdateService.fetchLatest(overrideUrl: _updateUrl);
      if (!mounted) return;
      setState(() => _checking = false);
      if (info.versionCode > kAppBuild) {
        await showDialog<void>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: Text('发现新版本 ${info.versionName}'),
            content: SingleChildScrollView(
              child: Text(
                info.notes.isEmpty ? '有新版本可用。' : info.notes,
                style: const TextStyle(fontSize: 13, height: 1.6),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _openUrl(info.pageUrl);
                },
                child: const Text('去网页下载'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _startUpdate(info);
                },
                child: const Text('立即更新'),
              ),
            ],
          ),
        );
      } else {
        _toast('已是最新版本 $kAppVersion');
      }
    } on UpdateException catch (e) {
      if (!mounted) return;
      setState(() => _checking = false);
      _toast('检查失败：${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _checking = false);
      _toast('检查失败：$e');
    }
  }


  Future<void> _startUpdate(UpdateInfo info) async {
    if (info.apkUrls.isEmpty) {
      await _openUrl(info.pageUrl);
      return;
    }

    final ValueNotifier<double> progress = ValueNotifier<double>(0);
    final ValueNotifier<String> status = ValueNotifier<String>('正在连接…');

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('更新到 ${info.versionName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (BuildContext _, double v, Widget? __) =>
                  LinearProgressIndicator(value: v <= 0 ? null : v),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<String>(
              valueListenable: status,
              builder: (BuildContext _, String s, Widget? __) => Text(
                s,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );

    try {
      final String path = await ApkUpdater.download(
        info,
        onProgress: (int received, int? total) {
          if (total != null && total > 0) {
            progress.value = received / total;
            status.value =
                '${(received / 1048576).toStringAsFixed(1)} / ${(total / 1048576).toStringAsFixed(1)} MB';
          } else {
            status.value = '${(received / 1048576).toStringAsFixed(1)} MB';
          }
        },
      );

      if (info.sha256.isNotEmpty) {
        status.value = '正在校验文件…';
        final String actual = await ApkUpdater.sha256Of(path);
        if (actual.toLowerCase() != info.sha256.toLowerCase()) {
          throw UpdateException('文件校验失败，已停止安装');
        }
      }

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      final OpenResult res = await OpenFilex.open(path);
      if (res.type != ResultType.done) {
        _toast('打不开安装程序：${res.message}');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _toast('更新失败：$e');
    }
  }

  Future<void> _openUrl(String url) async {
    final Uri uri = Uri.parse(url);
    final bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) _toast('打不开链接，地址：$url');
  }

  void _showChangelog() {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('更新日志'),
        content: SingleChildScrollView(
          child: Text(kChangelog,
              style: const TextStyle(fontSize: 13, height: 1.7)),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF3F7D58),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: <Widget>[
                const CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.white24,
                  child: Text('满',
                      style: TextStyle(color: Colors.white, fontSize: 18)),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(kAppName,
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                    const SizedBox(height: 4),
                    Text('版本 $kAppVersion ($kAppBuild)',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white70)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _section('数据'),
          _tile(Icons.upload_file, '导入账单', _openImport),
          _tile(Icons.pie_chart_outline, '预算', _openBudget),
          _tile(Icons.event_repeat, '定期扣款', _openRecurring),
          _tile(Icons.undo, '撤销上次导入', _undoImport),
          _tile(Icons.category_outlined, '分类管理', _openCategories),
          _tile(Icons.file_download_outlined, '导出流水 CSV', _exportCsv),
          _tile(Icons.backup_outlined, '备份为 JSON', _exportJson),
          _tile(Icons.cleaning_services_outlined, '存储占用', _showStorage),
          const SizedBox(height: 12),
          _section('关于'),
          _tile(
            Icons.system_update_alt,
            _checking ? '正在检查…' : '检查更新',
            _checking ? null : _checkUpdate,
          ),
          _tile(
            Icons.cloud_outlined,
            '更新源',
            _editUpdateUrl,
            subtitle: (_updateUrl == null || _updateUrl!.isEmpty)
                ? '默认（自动尝试多个地址）'
                : _updateUrl!,
          ),
          _tile(Icons.article_outlined, '更新日志', _showChangelog),
          _tile(Icons.info_outline, '开源地址', () => _openUrl(kRepoUrl)),
          const SizedBox(height: 18),
          const Center(
            child: Text('数据只保存在本机，不联网上传',
                style: TextStyle(fontSize: 11, color: Colors.black38)),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(title,
          style: const TextStyle(fontSize: 12, color: Colors.black45)),
    );
  }

  Widget _tile(IconData icon, String title, VoidCallback? onTap,
      {String? subtitle}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      color: Colors.white,
      child: ListTile(
        leading: Icon(icon, size: 20, color: const Color(0xFF3F7D58)),
        title: Text(title, style: const TextStyle(fontSize: 15)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.black38)),
        trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.black26),
        onTap: onTap,
      ),
    );
  }
}
