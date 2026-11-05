import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_icon.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../../core/theme_mode.dart';
import '../../core/version.dart';
import '../../data/models.dart';
import '../../data/apk_updater.dart';
import '../../data/repo.dart';
import '../../data/update_service.dart';
import '../../state/data_bus.dart';
import '../../ui/components.dart';
import '../autobook/autobook_page.dart';
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
    _loadIcon();
  }

  String _iconId = AppIcon.d1;

  /// 外观模式：跟随系统 / 浅色 / 深色
  Future<void> _pickThemeMode() async {
    XmThemeMode selected = ThemeController.instance.mode;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setInner) => AlertDialog(
          title: const Text('外观模式'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final XmThemeMode m in XmThemeMode.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _iconOption(
                    ctx: ctx,
                    setInner: setInner,
                    id: m.storage,
                    selected: selected.storage,
                    title: m.label,
                    subtitle: switch (m) {
                      XmThemeMode.system => '跟着手机的深色模式走',
                      XmThemeMode.light => '米白底，白天看清爽',
                      XmThemeMode.dark => '深绿底，夜里不刺眼',
                    },
                    onPick: () => selected = m,
                  ),
                ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('应用'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    ThemeController.instance.setMode(selected);
    await widget.repo.setSetting('theme_mode', selected.storage);
    if (mounted) setState(() {});
  }

  Future<void> _loadIcon() async {
    final String id = await AppIcon.current();
    if (!mounted) return;
    setState(() => _iconId = id);
  }

  /// 切换桌面图标：只换图标，不动数据。
  Future<void> _pickIcon() async {
    String selected = _iconId;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setInner) => AlertDialog(
          title: const Text('应用图标'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _iconOption(
                ctx: ctx,
                setInner: setInner,
                id: AppIcon.d1,
                selected: selected,
                title: '墨绿满未满',
                subtitle: '深色底、哑光金环，识别度更高（默认）',
                onPick: () => selected = AppIcon.d1,
              ),
              const SizedBox(height: 6),
              _iconOption(
                ctx: ctx,
                setInner: setInner,
                id: AppIcon.d3,
                selected: selected,
                title: '米白方孔钱',
                subtitle: '米白底、深墨棕外圆内方，更文雅',
                onPick: () => selected = AppIcon.d3,
              ),
              Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  '切换后桌面图标会重新加载，可能需要几秒；部分启动器要回到桌面才刷新。',
                  style: TextStyle(fontSize: 11.5, height: 1.5, color: Xm.ink3),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('应用'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final bool done = await AppIcon.apply(selected);
    if (!mounted) return;
    setState(() => _iconId = selected);
    _toast(done ? '已切换图标，回桌面看一眼' : '切换失败，请重试');
  }

  Widget _iconOption({
    required BuildContext ctx,
    required StateSetter setInner,
    required String id,
    required String selected,
    required String title,
    required String subtitle,
    required VoidCallback onPick,
  }) {
    final bool active = selected == id;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setInner(onPick),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? Xm.brandLL : Xm.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? Xm.brand.withValues(alpha: 0.4) : Xm.line,
            width: 1,
          ),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(fontSize: 11, color: Xm.ink3)),
                ],
              ),
            ),
            Icon(
              active ? Icons.check_circle : Icons.circle_outlined,
              size: 20,
              color: active ? Xm.brand : Xm.ink3,
            ),
          ],
        ),
      ),
    );
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
            Text(
              '填 version.json 的地址。留空则使用内置的多个地址自动尝试。',
              style: TextStyle(fontSize: 12, color: Xm.ink3, height: 1.5),
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
              style: TextStyle(fontSize: 12, color: Xm.ink3),
            ),
            const SizedBox(height: 10),
            Text(
              '缓存里主要是更新时下载的安装包，清理不会影响账目。',
              style: TextStyle(fontSize: 11, color: Xm.ink3),
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
          Text(value, style: TextStyle(fontSize: 13, color: Xm.ink3)),
        ],
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _openAutoBook() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => AutoBookPage(repo: widget.repo),
      ),
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
    try {
      final Map<String, Object?> body = await widget.repo.exportBackup();
      final String text = const JsonEncoder.withIndent('  ').convert(
        <String, Object?>{
          'app': kAppName,
          'format': 2,
          'version': kAppVersion,
          'exportedAt': DateTime.now().toIso8601String(),
          ...body,
        },
      );
      final bool ok = await _saveBackup('小满-备份-${_stamp()}.json', text);
      if (!mounted) return;
      _toast(ok ? '已导出' : '已取消');
    } catch (e) {
      if (!mounted) return;
      _toast('导出失败：$e');
    }
  }

  /// 从 JSON 备份恢复：先确认，再自动导出当前数据，最后整库覆盖。
  Future<void> _restoreBackup() async {
    try {
      final List<PlatformFile> picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['json'],
      );
      if (picked.isEmpty) return;

      final Uint8List bytes = await picked.first.xFile.readAsBytes();
      if (bytes.isEmpty) {
        _toast('读不到文件内容');
        return;
      }

      final String text =
          utf8.decode(bytes, allowMalformed: true).replaceFirst('\uFEFF', '');
      final Object? decoded = jsonDecode(text);
      if (decoded is! Map) {
        _toast('这不是有效的备份文件');
        return;
      }
      final Map<String, Object?> data = Map<String, Object?>.from(decoded);
      int n(String key) {
        final Object? v = data[key];
        return v is List ? v.length : 0;
      }

      if (n('accounts') == 0 && n('txns') == 0) {
        _toast('这个文件里没有可恢复的数据');
        return;
      }

      if (!mounted) return;
      final bool? ok = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('从备份恢复'),
          content: Text(
            '将恢复：账户 ${n('accounts')}、分类 ${n('categories')}、'
            '流水 ${n('txns')}。\n\n'
            '当前所有数据会被清空覆盖，无法撤销。\n'
            '恢复前会先自动导出一份当前数据到你自己选的位置。\n\n'
            '继续吗？',
            style: const TextStyle(fontSize: 13, height: 1.6),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB3261E)),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('覆盖并恢复'),
            ),
          ],
        ),
      );
      if (ok != true) return;

      // 恢复前先给当前数据留一份，防止选错文件后无处可退。
      final Map<String, Object?> current = await widget.repo.exportBackup();
      final bool saved = await _saveBackup(
        '小满-恢复前-${_stamp()}.json',
        const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          'app': kAppName,
          'format': 2,
          'version': kAppVersion,
          'exportedAt': DateTime.now().toIso8601String(),
          ...current,
        }),
      );
      if (!saved) {
        _toast('已取消：没能先备份当前数据');
        return;
      }

      final BackupSummary r = await widget.repo.importBackup(data);
      DataBus.instance.bump();
      await _loadSettings();
      await _loadStorage();
      if (!mounted) return;
      _toast('已恢复：账户 ${r.accounts}、分类 ${r.categories}、'
          '流水 ${r.txns}${r.full ? '' : '（旧版备份，部分字段缺失）'}');
    } catch (e) {
      if (!mounted) return;
      _toast('恢复失败：$e');
    }
  }

  Future<bool> _saveBackup(String fileName, String content) async {
    try {
      final Uri? uri = await FilePicker.saveFile(
        fileName: fileName,
        bytes: Uint8List.fromList(utf8.encode(content)),
        mimeType: 'application/json',
      );
      return uri != null;
    } catch (e) {
      _toast('导出失败：$e');
      return false;
    }
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
                style: TextStyle(fontSize: 12, color: Xm.ink3),
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
        padding: EdgeInsets.zero,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
            child: _profileCard(),
          ),
          const XmSectionTitle('数据', group: true),
          _menuCard(<Widget>[
            _tile(Icons.upload_file_outlined, '导入账单', _openImport, first: true),
            _tile(Icons.auto_awesome_outlined, '自动记账', _openAutoBook),
            _tile(Icons.pie_chart_outline, '预算', _openBudget),
            _tile(Icons.event_repeat_outlined, '定期扣款', _openRecurring),
            _tile(Icons.undo_rounded, '撤销上次导入', _undoImport),
            _tile(Icons.category_outlined, '分类管理', _openCategories),
            _tile(Icons.file_download_outlined, '导出流水 CSV', _exportCsv),
            _tile(Icons.backup_outlined, '备份为 JSON', _exportJson),
            _tile(Icons.settings_backup_restore, '从备份恢复', _restoreBackup),
            _tile(Icons.cleaning_services_outlined, '存储占用', _showStorage),
          ]),
          const SizedBox(height: 14),
          const XmSectionTitle('关于', group: true),
          _menuCard(<Widget>[
            _tile(
              Icons.system_update_alt,
              _checking ? '正在检查…' : '检查更新',
              _checking ? null : _checkUpdate,
              first: true,
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
          ]),
          const SizedBox(height: 14),
          const XmSectionTitle('外观', group: true),
          _menuCard(<Widget>[
            _tile(
              Icons.brightness_6_outlined,
              '外观模式',
              _pickThemeMode,
              first: true,
              subtitle: ThemeController.instance.mode.label,
            ),
            _tile(
              Icons.apps_rounded,
              '应用图标',
              _pickIcon,
              subtitle: _iconId == AppIcon.d3 ? '米白方孔钱（浅色）' : '墨绿满未满（深色）',
            ),
          ]),
          const SizedBox(height: 20),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.shield_outlined, size: 13, color: Xm.ink3),
                SizedBox(width: 5),
                Text('数据只保存在本机，不联网上传',
                    style: TextStyle(
                        fontSize: 11.5, letterSpacing: 0.3, color: Xm.ink3)),
              ],
            ),
          ),
          const SizedBox(height: 96),
        ],
      ),
    );
  }

  /// 头像卡（§4.4）：用名字首字，不用默认人头图标。
  Widget _profileCard() {
    return XmHeroCard(
      variant: XmHeroVariant.profile,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.18), width: 1),
            ),
            child: const Text(
              '满',
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w500, color: Colors.white),
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(kAppName,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    color: Colors.white,
                  )),
              const SizedBox(height: 5),
              Text('版本 $kAppVersion ($kAppBuild)',
                  style: const TextStyle(
                    fontSize: 11.5,
                    letterSpacing: 0.3,
                    color: Xm.onDarkLabel,
                  )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _menuCard(List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: XmCard(child: Column(children: rows)),
    );
  }

  Widget _tile(IconData icon, String title, VoidCallback? onTap,
      {String? subtitle, bool first = false}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: <Widget>[
            if (!first) const XmDivider(indent: 52),
            SizedBox(
              height: subtitle == null ? 56 : 65,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: <Widget>[
                    Icon(icon, size: 24, color: Xm.brand),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Xm.text(15, FontWeight.w500,
                                  spacing: -0.1, color: Xm.ink)),
                          if (subtitle != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11.5, color: Xm.ink3),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        size: 16, color: Color(0xFFC4CEC7)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
