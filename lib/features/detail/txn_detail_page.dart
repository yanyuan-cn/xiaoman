import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../state/data_bus.dart';
import '../../ui/components.dart';
import '../../ui/motion.dart';
import '../record/record_page.dart';

/// 账单详情：金额在中间，下面依次是明细、值不值、当时在干嘛。
///
/// 从列表那一行放大进来；值不值 / 场景直接在页面上改，改完立刻落库。
class TxnDetailPage extends StatefulWidget {
  const TxnDetailPage({super.key, required this.repo, required this.txn});

  final Repo repo;
  final Txn txn;

  @override
  State<TxnDetailPage> createState() => _TxnDetailPageState();
}

class _TxnDetailPageState extends State<TxnDetailPage> {
  Map<int, Account> _accounts = const <int, Account>{};
  Map<int, TxnCategory> _categories = const <int, TxnCategory>{};
  late bool _inBudget = widget.txn.inBudget;
  late int _mood = widget.txn.mood;
  late String? _scene = widget.txn.workState;
  List<Txn> _sameMerchant = const <Txn>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<Account> accounts = await widget.repo.accounts();
    final List<TxnCategory> cats = await widget.repo.categories();
    List<Txn> same = const <Txn>[];
    final String? merchant = widget.txn.merchant;
    if ((merchant ?? '').isNotEmpty) {
      final List<Txn> found =
          await widget.repo.searchTxns(keyword: merchant, limit: 4);
      same = <Txn>[
        for (final Txn t in found)
          if (t.id != widget.txn.id) t,
      ].take(3).toList(growable: false);
    }
    if (!mounted) return;
    setState(() {
      _accounts = <int, Account>{for (final Account a in accounts) a.id: a};
      _categories = <int, TxnCategory>{for (final TxnCategory c in cats) c.id: c};
      _sameMerchant = same;
    });
  }

  Txn get _t => widget.txn;

  String get _categoryText {
    final TxnCategory? c =
        _t.categoryId == null ? null : _categories[_t.categoryId];
    if (c == null) return '未分类';
    if (c.parentId == null) return c.name;
    final TxnCategory? p = _categories[c.parentId];
    return p == null ? c.name : '${p.name} · ${c.name}';
  }

  int get _iconCategoryId {
    final TxnCategory? c =
        _t.categoryId == null ? null : _categories[_t.categoryId];
    return c?.parentId ?? c?.id ?? 0;
  }

  String get _accountText => _accounts[_t.accountId]?.name ?? '未知账户';

  String get _toAccountText => _accounts[_t.toAccountId]?.name ?? '未知账户';

  String _fullTime(DateTime d) =>
      '${fmtDate(d)} ${two(d.hour)}:${two(d.minute)}';

  Future<void> _setMood(int v) async {
    setState(() => _mood = v);
    await widget.repo.setTxnMood(_t.id, v);
    DataBus.instance.bump();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(v == 0
            ? '已清除标记'
            : '已标记为「${XmMood.fromCode(v).label}」'),
        duration: const Duration(seconds: 2),
      ));
  }

  Future<void> _setScene(String? v) async {
    setState(() => _scene = v);
    await widget.repo.setTxnWorkState(_t.id, v);
    DataBus.instance.bump();
  }

  Future<void> _edit() async {
    final bool? ok = await showXmExpandSheet<bool>(
      context: context,
      heightFactor: RecordPage.heightFactor,
      builder: (BuildContext _) => RecordPage(repo: widget.repo, editing: _t),
    );
    if (ok == true) {
      DataBus.instance.bump();
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  Future<void> _delete() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('删除这笔'),
        content: const Text('删除后可以点「撤销」找回（3 秒内）。'),
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
    await widget.repo.softDelete(_t.id);
    DataBus.instance.bump();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final bool isTransfer = _t.isTransfer;
    final String sign = isTransfer ? '' : (_t.isExpense ? '−' : '+');
    final Color iconColor = Xm.catColor(_iconCategoryId);

    return Scaffold(
      backgroundColor: Xm.bg,
      body: Column(
        children: <Widget>[
          // 顶栏：返回 / 标题 / 更多
          Padding(
            padding: EdgeInsets.fromLTRB(
                10, MediaQuery.paddingOf(context).top + 6, 10, 0),
            child: SizedBox(
              height: 52,
              child: Row(
                children: <Widget>[
                  XmIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    tooltip: '返回',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: Center(
                      child: Text('账单详情',
                          style: Xm.text(15, FontWeight.w600, spacing: 0.2)),
                    ),
                  ),
                  XmIconButton(
                    icon: Icons.edit_outlined,
                    tooltip: '编辑',
                    onTap: _edit,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
              children: <Widget>[
                _hero(iconColor, sign, isTransfer),
                _kvCard(isTransfer),
                _worthCard(),
                _itemsCard(),
                if (_sameMerchant.isNotEmpty) _sameCard(),
              ],
            ),
          ),
          _footer(),
        ],
      ),
    );
  }

  Widget _hero(Color iconColor, String sign, bool isTransfer) {
    final String glyph = isTransfer
        ? '转'
        : (_categories[_t.categoryId]?.name ?? '·');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
      child: Column(
        children: <Widget>[
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(19),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: const Color(0x4712211A),
                  blurRadius: 20,
                  spreadRadius: -8,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: XmColorBlock(glyph, color: iconColor, size: 56, radius: 19, fontSize: 19),
          ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text('$sign¥',
                    style: Xm.text(22, FontWeight.w500,
                        color: Xm.ink.withValues(alpha: 0.55))),
                const SizedBox(width: 2),
                Text(
                  formatCents(_t.amount),
                  style: Xm.text(40, FontWeight.w700,
                      spacing: -1.8, height: 1, tabular: true),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            (_t.merchant ?? '').isNotEmpty
                ? _t.merchant!
                : (isTransfer ? '账户转账' : _categoryText),
            style: Xm.text(14, FontWeight.w400,
                spacing: 0.1, color: Xm.ink2),
          ),
        ],
      ),
    );
  }

  Widget _kvCard(bool isTransfer) {
    return _card(<Widget>[
      _kv('分类', isTransfer ? '转账' : _categoryText),
      _kv('账户', _accountText),
      if (isTransfer) _kv('转入', _toAccountText),
      _kv('时间', _fullTime(_t.occurredAt)),
      if ((_t.note ?? '').isNotEmpty) _kv('备注', _t.note!),
      if (!isTransfer)
        Row(
          children: <Widget>[
            Text('计入预算',
                style: Xm.text(13.5, FontWeight.w400, color: Xm.ink2)),
            const Spacer(),
            Switch(
              value: _inBudget,
              onChanged: (bool v) => _setInBudget(v),
            ),
          ],
        ),
    ]);
  }

  Future<void> _setInBudget(bool value) async {
    await widget.repo.setTxnInBudget(_t.id, value);
    if (!mounted) return;
    setState(() => _inBudget = value);
    DataBus.instance.bump();
  }

  Widget _worthCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: Xm.surface,
        borderRadius: BorderRadius.circular(Xm.rCard),
        boxShadow: Xm.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('这笔值不值？',
                  style: Xm.text(12.5, FontWeight.w600, spacing: 0)),
              const SizedBox(width: 6),
              Text('只有你自己看得到',
                  style: Xm.text(12, FontWeight.w400, color: Xm.ink3)),
            ],
          ),
          const SizedBox(height: 12),
          XmWorthPicker(value: _mood, onChanged: _setMood),
          const SizedBox(height: 20),
          Text('当时在干嘛', style: Xm.text(12.5, FontWeight.w600)),
          const SizedBox(height: 12),
          XmSceneChips(
            options: XmWorkState.presets,
            value: _scene,
            onChanged: _setScene,
          ),
        ],
      ),
    );
  }

  /// 明细：目前一笔账只有一个金额，显示「实付」。
  Widget _itemsCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Xm.surface,
        borderRadius: BorderRadius.circular(Xm.rCard),
        boxShadow: Xm.cardShadow,
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('明细', style: Xm.text(13.5, FontWeight.w600)),
              const SizedBox(width: 7),
              Text('1 项', style: Xm.text(11, FontWeight.w500, color: Xm.ink3)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(_categoryText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Xm.text(13, FontWeight.w400, color: Xm.ink2)),
              ),
              Text('${_t.isExpense ? '−' : '+'}¥${formatCents(_t.amount)}',
                  style: Xm.text(13, FontWeight.w500, tabular: true)),
            ],
          ),
          const SizedBox(height: 11),
          Container(
            padding: const EdgeInsets.only(top: 11),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Xm.line, width: 0.6)),
            ),
            child: Row(
              children: <Widget>[
                Text('实付',
                    style: Xm.text(13, FontWeight.w400, color: Xm.ink2)),
                const Spacer(),
                Text('¥${formatCents(_t.amount)}',
                    style: Xm.text(16, FontWeight.w700,
                        spacing: -0.4, tabular: true)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sameCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const XmSect('同一家店最近'),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: Xm.surface,
            borderRadius: BorderRadius.circular(Xm.rCard),
            boxShadow: Xm.cardShadow,
          ),
          child: Column(
            children: <Widget>[
              for (int i = 0; i < _sameMerchant.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    border: i == 0
                        ? null
                        : Border(top: BorderSide(color: Xm.line, width: 0.6)),
                  ),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 60,
                        child: Text(
                          fmtShortDay(_sameMerchant[i].occurredAt),
                          style: Xm.text(11.5, FontWeight.w400,
                              color: Xm.ink3),
                        ),
                      ),
                      Expanded(
                        child: Text(_categoryText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Xm.text(12.5, FontWeight.w400,
                                color: Xm.ink2)),
                      ),
                      Text('¥${formatCents(_sameMerchant[i].amount)}',
                          style: Xm.text(13, FontWeight.w600,
                              spacing: -0.2, tabular: true)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _footer() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, 20 + MediaQuery.paddingOf(context).bottom),
      color: Xm.bg,
      child: SizedBox(
        height: 50,
        width: double.infinity,
        child: Material(
          color: Xm.isDark ? const Color(0xFF3A221F) : const Color(0xFFFCF2EF),
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _delete,
            child: Center(
              child: Text('删除这笔',
                  style: Xm.text(14.5, FontWeight.w600,
                      spacing: 0.2, color: Xm.warn)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Xm.surface,
        borderRadius: BorderRadius.circular(Xm.rCard),
        boxShadow: Xm.cardShadow,
      ),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < children.length; i++)
            Container(
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : Border(top: BorderSide(color: Xm.line, width: 0.6)),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: children[i],
            ),
        ],
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: Xm.text(13.5, FontWeight.w400, color: Xm.ink2)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(value,
              textAlign: TextAlign.right,
              style: Xm.text(13.5, FontWeight.w500, height: 1.4)),
        ),
      ],
    );
  }
}
