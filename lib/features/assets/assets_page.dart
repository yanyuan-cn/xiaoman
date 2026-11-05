import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../state/data_bus.dart';
import '../../ui/components.dart';
import '../../ui/motion.dart';
import '../account/account_detail_page.dart';

class AssetsPage extends StatefulWidget {
  const AssetsPage({super.key, required this.repo});

  final Repo repo;

  @override
  State<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends State<AssetsPage> {
  List<Account> _accounts = const <Account>[];
  Map<int, int> _deltas = const <int, int>{};
  bool _loading = true;

  final Map<int, GlobalKey> _rowKeys = <int, GlobalKey>{};
  final GlobalKey _addKey = GlobalKey();

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
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _deltas = deltas;
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
      appBar: AppBar(
        title: const Text('资产'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: XmIconButton(
              key: _addKey,
              icon: Icons.add_rounded,
              tooltip: '新增账户',
              filled: true,
              onTap: () => _openAccount(null),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.zero,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 18),
                    child: _netCard(net, totalAsset, totalLiability),
                  ),
                  XmSectionTitle('资产', subtitle: '${assets.length} 个账户'),
                  if (assets.isEmpty)
                    _emptyHint('还没有资产账户')
                  else
                    _accountCard(assets),
                  const SizedBox(height: 18),
                  XmSectionTitle('负债', subtitle: '${liabilities.length} 个账户'),
                  if (liabilities.isEmpty)
                    _emptyHint('还没有负债项目')
                  else
                    _accountCard(liabilities),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 96),
                    child: Text(
                      '余额 = 期初余额 + 收入 − 支出；负债记为负数，还款会减少欠款',
                      style: Xm.text(11, FontWeight.w400, color: Xm.ink3),
                    ),
                  ),
                ],
              ),
            ),
    );
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
                                  style: Xm.body,
                                ),
                              ),
                              if (note != null) ...<Widget>[
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    note,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Xm.text(11.5, FontWeight.w400,
                                        color: Xm.ink3),
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
