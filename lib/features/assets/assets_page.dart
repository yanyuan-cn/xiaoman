import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../state/data_bus.dart';
import '../../ui/components.dart';
import '../../ui/confetti.dart';
import '../../ui/motion.dart';
import '../account/account_detail_page.dart';
import '../wish/wish_detail_page.dart';

class AssetsPage extends StatefulWidget {
  const AssetsPage({super.key, required this.repo});

  final Repo repo;

  @override
  State<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends State<AssetsPage> {
  static const String kSectionOrderKey = 'assets_section_order';
  static const List<String> kDefaultOrder = <String>[
    'assets',
    'liabilities',
    'wishes',
  ];

  List<Account> _accounts = const <Account>[];
  Map<int, int> _deltas = const <int, int>{};
  List<Wish> _wishes = const <Wish>[];
  List<String> _order = List<String>.of(kDefaultOrder);
  bool _loading = true;

  final Map<int, GlobalKey> _rowKeys = <int, GlobalKey>{};
  final Map<int, GlobalKey> _wishKeys = <int, GlobalKey>{};
  final GlobalKey _addKey = GlobalKey();
  final GlobalKey _addWishKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    DataBus.instance.addListener(_reload);
    _load();
  }

  @override
  void dispose() {
    DataBus.instance.removeListener(_reload);
    super.dispose();
  }

  void _reload() => _load();

  Future<void> _load() async {
    final List<Account> accounts = await widget.repo.accounts();
    final Map<int, int> deltas = await widget.repo.accountDeltas();
    final List<Wish> wishes = await widget.repo.wishes();
    final String? rawOrder = await widget.repo.getSetting(kSectionOrderKey);
    final List<String> order = <String>[];
    if (rawOrder != null && rawOrder.trim().isNotEmpty) {
      for (final String id in rawOrder.split(',')) {
        if (kDefaultOrder.contains(id) && !order.contains(id)) order.add(id);
      }
    }
    for (final String id in kDefaultOrder) {
      if (!order.contains(id)) order.add(id);
    }
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _deltas = deltas;
      _wishes = wishes;
      _order = order;
      _loading = false;
    });
  }

  int _balance(Account a) => a.initialBalance + (_deltas[a.id] ?? 0);

  /// 账户详情从被点的那一行放大出来；新增账户从右上角的 ＋ 放大出来。
  Future<void> _openAccount(Account? account) async {
    final Rect? from = account == null
        ? xmGlobalRect(_addKey)
        : xmGlobalRect(_rowKeys[account.id]);
    final bool? changed = await Navigator.of(context).push<bool>(
      XmExpandRoute<bool>(
        from: from,
        builder: (BuildContext _) =>
            AccountDetailPage(repo: widget.repo, account: account),
      ),
    );
    if (changed == true) DataBus.instance.bump();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final List<Account> assets = <Account>[];
    final List<Account> liabilities = <Account>[];
    int totalAsset = 0;
    int totalLiability = 0;
    int net = 0;

    for (final Account a in _accounts) {
      final int b = _balance(a);
      if (a.isLiability) {
        liabilities.add(a);
        if (a.includeInTotal) totalLiability += -b;
      } else {
        assets.add(a);
        if (a.includeInTotal) totalAsset += b;
      }
      if (a.includeInTotal) net += b;
    }

    return Scaffold(
      backgroundColor: Xm.bg,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.zero,
                children: <Widget>[
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        20, MediaQuery.paddingOf(context).top + 8, 16, 12),
                    child: XmHeader(
                      padding: EdgeInsets.zero,
                      kicker: '共 ${assets.length + liabilities.length} 个账户',
                      title: '我的家底',
                      trailing: XmAvatarButton(
                        key: _addKey,
                        icon: Icons.add_rounded,
                        tooltip: '新增账户',
                        onTap: () => _openAccount(null),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                    child: _netCard(net, totalAsset, totalLiability),
                  ),
                  for (final String id in _order)
                    ..._sectionWidgets(
                      id,
                      assets: assets,
                      liabilities: liabilities,
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 4, 22, 96),
                    child: Text(
                      '长按板块标题可以调整三个板块的先后顺序',
                      style: Xm.text(11, FontWeight.w400, color: Xm.ink3),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  /// 三个大板块：资产 / 负债 / 想买，按用户排的顺序拼出来。
  List<Widget> _sectionWidgets(
    String id, {
    required List<Account> assets,
    required List<Account> liabilities,
  }) {
    switch (id) {
      case 'assets':
        return <Widget>[
          _sectionTitle('资产', '${assets.length} 个账户'),
          if (assets.isEmpty)
            _emptyHint('还没有资产账户')
          else
            _accountCard(assets),
          const SizedBox(height: 18),
        ];
      case 'liabilities':
        return <Widget>[
          _sectionTitle('负债', '${liabilities.length} 个账户'),
          if (liabilities.isEmpty)
            _emptyHint('还没有负债项目')
          else
            _accountCard(liabilities),
          const SizedBox(height: 18),
        ];
      default:
        return <Widget>[
          _wishSection(),
          const SizedBox(height: 4),
        ];
    }
  }

  Widget _sectionTitle(String title, String subtitle) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: _openSectionSort,
      child: XmSectionTitle(title, subtitle: subtitle),
    );
  }

  Future<void> _openSectionSort() async {
    final List<String> working = List<String>.of(_order);
    const Map<String, String> names = <String, String>{
      'assets': '资产',
      'liabilities': '负债',
      'wishes': '想买',
    };

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Xm.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx2, StateSetter setSheet) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  XmSheetHeader(
                    title: '板块顺序',
                    subtitle: '按住一行上下拖动',
                    onClose: () => Navigator.of(ctx2).pop(),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 56.0 * working.length,
                    child: ReorderableListView.builder(
                      itemCount: working.length,
                      onReorder: (int oldIndex, int newIndex) async {
                        setSheet(() {
                          if (newIndex > oldIndex) newIndex -= 1;
                          working.insert(newIndex, working.removeAt(oldIndex));
                        });
                        await _saveSectionOrder(working);
                      },
                      itemBuilder: (BuildContext c, int i) {
                        final String id = working[i];
                        return Container(
                          key: ValueKey<String>(id),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                          decoration: BoxDecoration(
                            color: Xm.isDark ? Xm.surface2 : Xm.bg,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: <Widget>[
                              Icon(Icons.drag_indicator_rounded,
                                  size: 20, color: Xm.ink3),
                              const SizedBox(width: 10),
                              Text(names[id] ?? id,
                                  style: Xm.text(15, FontWeight.w600)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _saveSectionOrder(List<String> order) async {
    setState(() => _order = List<String>.of(order));
    await widget.repo.setSetting(kSectionOrderKey, order.join(','));
  }

  Widget _netCard(int net, int asset, int liability) {
    return XmHeroCard(
      variant: XmHeroVariant.assets,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '净资产',
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 0.6,
              color: Xm.onDarkLabel,
            ),
          ),
          const SizedBox(height: 10),
          // 36dp 金额必须给足高度，否则会被卡片裁切
          SizedBox(
            height: 40,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: XmAmount(
                  text: formatCents(net),
                  style: Xm.display.copyWith(
                    color: net < 0 ? const Color(0xFFFFC9C2) : Colors.white,
                  ),
                  currencyScale: 0.58,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              _foot('总资产', asset),
              const SizedBox(width: 22),
              _foot('总负债', liability),
            ],
          ),
        ],
      ),
    );
  }

  Widget _foot(String label, int value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            color: Xm.onDarkNote,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '¥${formatCents(value)}',
          style: Xm.text(14, FontWeight.w600,
              spacing: -0.2, color: Colors.white, tabular: true),
        ),
      ],
    );
  }

  Widget _emptyHint(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 6),
      child: Text(text, style: Xm.text(12, FontWeight.w400, color: Xm.ink3)),
    );
  }

  Widget _accountCard(List<Account> list) {
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < list.length; i++) {
      rows.add(XmSwipeDelete(
        onDelete: () => _deleteAccount(list[i]),
        child: _row(list[i], first: i == 0),
      ));
    }
    return XmCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      radius: 18,
      child: Column(children: rows),
    );
  }

  // ---------------- 想买 ----------------

  Widget _wishSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        XmSect(
          '想买',
          action: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openWish(null),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('+ 添加',
                  style: Xm.text(11.5, FontWeight.w500, color: Xm.ink3)),
            ),
          ),
        ),
        if (_wishes.isEmpty)
          _emptyHint('还没有想买的东西，点「+ 添加」记一个')
        else
          XmCard(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            radius: 18,
            child: Column(
              children: <Widget>[
                for (int i = 0; i < _wishes.length; i++)
                  _wishRow(_wishes[i], first: i == 0),
              ],
            ),
          ),
      ],
    );
  }

  Widget _wishRow(Wish w, {bool first = false}) {
    final GlobalKey key = _wishKeys.putIfAbsent(w.id, () => GlobalKey());
    final int? days = w.daysLeft;
    final String sub = days == null
        ? '还没定日子'
        : (days < 0
            ? '过了 ${-days} 天'
            : (days == 0 ? '就是今天' : '还有 $days 天'));

    return XmSwipeActions(
      actions: <XmSwipeAction>[
        XmSwipeAction(
          label: '已买',
          icon: Icons.check_rounded,
          color: Xm.brand,
          onTap: () => _markBought(w),
        ),
        XmSwipeAction(
          label: '取消',
          icon: Icons.close_rounded,
          color: Xm.ink3,
          onTap: () => _cancelWish(w),
        ),
      ],
      child: Material(
        key: key,
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openWish(w),
          child: Column(
            children: <Widget>[
              if (!first) const XmDivider(indent: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Row(
                  children: <Widget>[
                    _wishThumb(w),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(w.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Xm.text(15, FontWeight.w600,
                                  spacing: -0.1)),
                          const SizedBox(height: 3),
                          Text(
                            w.targetAt == null
                                ? sub
                                : '$sub · ${fmtMonthDay(w.targetAt!)}',
                            style: Xm.text(11.5, FontWeight.w400,
                                color: days != null && days <= 0
                                    ? Xm.warn
                                    : Xm.ink3),
                          ),
                          if (w.targetAt != null) ...<Widget>[
                            const SizedBox(height: 7),
                            _wishProgress(w),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      w.price > 0 ? '¥${formatCents(w.price)}' : '未定价',
                      style: Xm.text(16, FontWeight.w700,
                          spacing: -0.4,
                          tabular: true,
                          color: w.price > 0 ? Xm.ink : Xm.ink3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 离预计购买日期还有多久：充裕绿、快到了黄、到点或超期红。
  Widget _wishProgress(Wish w) {
    final DateTime created = w.createdAt;
    final DateTime target = w.targetAt!;
    final double totalSec = target.difference(created).inSeconds.toDouble();
    final double usedSec =
        DateTime.now().difference(created).inSeconds.toDouble();
    final double frac =
        totalSec <= 0 ? 1.0 : (usedSec / totalSec).clamp(0.0, 1.0);
    final int? days = w.daysLeft;

    final Color color = (days != null && days <= 0)
        ? Xm.warn
        : (days != null && days <= 7)
            ? const Color(0xFFD9A64B)
            : const Color(0xFF3E9A6E);

    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 4,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: ColoredBox(
                color: Xm.isDark ? Xm.surface2 : const Color(0xFFEDF1ED),
              ),
            ),
            FractionallySizedBox(
              widthFactor: frac,
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    );
  }

  /// 右滑「已买」：标记完成 + 撒彩带，可以撤销。
  Future<void> _markBought(Wish w) async {
    await widget.repo.setWishBought(w.id, true);
    await _load();
    DataBus.instance.bump();
    if (!mounted) return;
    await showConfetti(context, message: '「${w.name}」到手了 🎉');
    if (!mounted) return;
    showUndoSnack(
      context,
      message: '已标记「${w.name}」为已买',
      onUndo: () async {
        await widget.repo.setWishBought(w.id, false);
        await _load();
        DataBus.instance.bump();
      },
    );
  }

  /// 右滑「取消」：从想买里删掉，先确认一下（删了没法撤销）。
  Future<void> _cancelWish(Wish w) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('不想买「${w.name}」了？'),
        content: const Text('会从想买清单里删掉，不影响任何账目。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('再想想'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删掉'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final String? img = w.imagePath;
    await widget.repo.deleteWish(w.id);
    if (img != null) {
      final File f = File(img);
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
    await _load();
    DataBus.instance.bump();
    if (!mounted) return;
    _toast('已从想买里删掉');
  }

  Widget _wishThumb(Wish w) {
    final File? file = w.imagePath == null ? null : File(w.imagePath!);
    if (file != null && file.existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Image.file(
          file,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
              _wishPlaceholder(),
        ),
      );
    }
    return _wishPlaceholder();
  }

  Widget _wishPlaceholder() {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Xm.brandLL,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(Icons.card_giftcard_rounded, size: 19, color: Xm.brand),
    );
  }

  Future<void> _openWish(Wish? wish) async {
    final Rect? from = wish == null
        ? xmGlobalRect(_addWishKey)
        : xmGlobalRect(_wishKeys[wish.id]);
    final bool? changed = await Navigator.of(context).push<bool>(
      XmExpandRoute<bool>(
        from: from,
        builder: (BuildContext _) =>
            WishDetailPage(repo: widget.repo, wish: wish),
      ),
    );
    if (changed == true) {
      await _load();
      DataBus.instance.bump();
    }
  }

  // ---------------- 拖动排序 ----------------

  Future<void> _openSortSheet(bool liability) async {
    final List<Account> list = <Account>[
      for (final Account a in _accounts)
        if (a.isLiability == liability) a,
    ];
    if (list.length < 2) {
      _toast(liability ? '负债账户至少两个才能排序' : '资产账户至少两个才能排序');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Xm.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext ctx2, StateSetter setSheet) {
            return SizedBox(
              height: MediaQuery.sizeOf(ctx2).height * 0.72,
              child: Column(
                children: <Widget>[
                  XmSheetHeader(
                    title: liability ? '负债账户排序' : '资产账户排序',
                    subtitle: '按住一行上下拖动，松手就保存',
                    onClose: () => Navigator.of(ctx2).pop(),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                      itemCount: list.length,
                      onReorder: (int oldIndex, int newIndex) async {
                        setSheet(() {
                          if (newIndex > oldIndex) newIndex -= 1;
                          list.insert(newIndex, list.removeAt(oldIndex));
                        });
                        await widget.repo
                            .reorderAccounts(<int>[
                              for (final Account a in list) a.id,
                            ]);
                        await _load();
                      },
                      itemBuilder: (BuildContext c, int i) {
                        final Account a = list[i];
                        return Container(
                          key: ValueKey<int>(a.id),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: Xm.isDark ? Xm.surface2 : Xm.bg,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: <Widget>[
                              Icon(Icons.drag_indicator_rounded,
                                  size: 20, color: Xm.ink3),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(a.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Xm.text(14.5, FontWeight.w500)),
                              ),
                              Text('¥${formatCents(_balance(a))}',
                                  style: Xm.text(13.5, FontWeight.w600,
                                      tabular: true, color: Xm.ink2)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    await _load();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
      ));
  }

  /// 删除账户（归档，可撤销）。有流水时先确认，避免一键把账户名变成「未知」。
  Future<void> _deleteAccount(Account a) async {
    final int count = await widget.repo.accountTxnCount(a.id);
    if (count > 0) {
      if (!mounted) return;
      final bool? ok = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('删除账户'),
          content: Text(
            '「${a.name}」下还有 $count 笔流水。删除后账户不再显示，'
            '这些流水会保留但账户名显示为「未知」。\n\n要继续吗？',
          ),
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
    }

    await widget.repo.archiveAccount(a.id);
    await _load();
    DataBus.instance.bump();
    if (!mounted) return;
    showUndoSnack(
      context,
      message: '已删除「${a.name}」',
      onUndo: () async {
        await widget.repo.restoreAccount(a.id);
        await _load();
        DataBus.instance.bump();
      },
    );
  }

  Widget _row(Account a, {bool first = false}) {
    final GlobalKey key = _rowKeys.putIfAbsent(a.id, () => GlobalKey());
    final int balance = _balance(a);
    final int shown = a.isLiability ? -balance : balance;
    final String typeLabel = Account.typeLabel(a.type);
    final String? note = (a.note ?? '').trim().isEmpty ? null : a.note!.trim();

    return Material(
      key: key,
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openAccount(a),
        onLongPress: () => _openSortSheet(a.isLiability),
        child: Column(
          children: <Widget>[
            if (!first) const XmDivider(indent: 63),
            SizedBox(
              height: 66,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: <Widget>[
                    XmIconBlock.icon(
                      a.isLiability
                          ? Icons.credit_card_off_outlined
                          : Icons.account_balance_wallet_outlined,
                      size: 36,
                      iconSize: 18,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Flexible(
                                child: Text(
                                  a.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Xm.text(15, FontWeight.w600,
                                      spacing: -0.1),
                                ),
                              ),
                              if (note != null) ...<Widget>[
                                const SizedBox(width: 7),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: Xm.isDark
                                        ? Xm.goldL
                                        : const Color(0xFFF3E9D8),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    note,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Xm.text(10, FontWeight.w600,
                                        color: Xm.gold, height: 1.2),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            a.includeInTotal ? typeLabel : '$typeLabel · 不计入总资产',
                            style: Xm.text(11.5, FontWeight.w400, color: Xm.ink3),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Text(
                          '¥${formatCents(shown)}',
                          style: Xm.bodyM.copyWith(
                            color: shown < 0 ? Xm.expense : Xm.ink,
                          ),
                        ),
                        if (a.isLiability)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text('待还',
                                style: Xm.text(10.5, FontWeight.w400,
                                    color: Xm.ink3)),
                          ),
                      ],
                    ),
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
