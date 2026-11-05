import 'package:flutter/material.dart';

import '../../core/auto_book.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/import/auto_parse.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../state/data_bus.dart';
import '../../ui/components.dart';

/// 自动记账：开关、授权状态、教程，以及待确认账单的处理入口。
class AutoBookPage extends StatefulWidget {
  const AutoBookPage({super.key, required this.repo});

  final Repo repo;

  @override
  State<AutoBookPage> createState() => _AutoBookPageState();
}

class _AutoBookPageState extends State<AutoBookPage> {
  bool _notifSwitch = true;
  bool _smsSwitch = true;
  bool _accessSwitch = true;
  bool _notifAccess = false;
  bool _smsPermission = false;
  bool _accessEnabled = false;
  bool _overlayOk = false;
  int _pending = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bool n = await AutoBook.switchOn(AutoBook.switchNotif);
    final bool s = await AutoBook.switchOn(AutoBook.switchSms);
    final bool a = await AutoBook.switchOn(AutoBook.switchAccess);
    final bool na = await AutoBook.hasNotificationAccess();
    final bool sp = await AutoBook.hasSmsPermission();
    final bool ae = await AutoBook.accessibilityEnabled();
    final bool ov = await AutoBook.hasOverlayPermission();
    final List<AutoBill> bills = await AutoBook.pendingBills();
    if (!mounted) return;
    setState(() {
      _notifSwitch = n;
      _smsSwitch = s;
      _accessSwitch = a;
      _notifAccess = na;
      _smsPermission = sp;
      _accessEnabled = ae;
      _overlayOk = ov;
      _pending = bills.length;
      _loading = false;
    });
  }

  Future<void> _openPending() async {
    final List<AutoBill> bills = await AutoBook.pendingBills();
    if (!mounted) return;
    if (bills.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有待处理的账单')),
      );
      return;
    }
    final List<Account> accounts = await widget.repo.accounts();
    if (!mounted) return;
    final bool? done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x6B0A120E),
      builder: (BuildContext _) =>
          _PendingSheet(repo: widget.repo, bills: bills, accounts: accounts),
    );
    if (done == true) {
      DataBus.instance.bump();
      await _load();
    }
  }

  Future<void> _toggle(String key, bool on) async {
    await AutoBook.setSwitch(key, on);
    if (!mounted) return;
    setState(() {
      if (key == AutoBook.switchNotif) {
        _notifSwitch = on;
      } else if (key == AutoBook.switchSms) {
        _smsSwitch = on;
      } else {
        _accessSwitch = on;
      }
    });
    if (on) {
      // 打开开关时顺手把权限检查一遍
      if (key == AutoBook.switchNotif && !_notifAccess) {
        await AutoBook.openNotificationSettings();
      }
      if (key == AutoBook.switchSms && !_smsPermission) {
        await AutoBook.requestSmsPermission();
      }
      if (key == AutoBook.switchAccess && !_accessEnabled) {
        await AutoBook.openAccessibilitySettings();
      }
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('自动记账')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: <Widget>[
                _intro(),
                const SizedBox(height: 16),
                _switchCard(
                  icon: Icons.notifications_active_outlined,
                  title: '通知自动记账',
                  subtitle: '读取支付宝、微信、银行的付款通知',
                  value: _notifSwitch,
                  granted: _notifAccess,
                  grantedText: '已授权通知读取',
                  deniedText: '需要「通知使用权」才能读付款通知',
                  onChanged: (bool v) => _toggle(AutoBook.switchNotif, v),
                  onGrant: () async {
                    await AutoBook.openNotificationSettings();
                    await Future<void>.delayed(const Duration(seconds: 1));
                    await _load();
                  },
                  grantLabel: '去授权',
                ),
                const SizedBox(height: 10),
                _switchCard(
                  icon: Icons.sms_outlined,
                  title: '短信自动记账',
                  subtitle: '解析银行扣款 / 入账短信',
                  value: _smsSwitch,
                  granted: _smsPermission,
                  grantedText: '已允许读取短信',
                  deniedText: '需要短信权限才能解析',
                  onChanged: (bool v) => _toggle(AutoBook.switchSms, v),
                  onGrant: () async {
                    await AutoBook.requestSmsPermission();
                    await Future<void>.delayed(const Duration(seconds: 1));
                    await _load();
                  },
                  grantLabel: '去授权',
                ),
                const SizedBox(height: 10),
                _switchCard(
                  icon: Icons.visibility_outlined,
                  title: '屏幕识别（微信 / 支付宝）',
                  subtitle: '微信支付不发通知，只能读支付成功页',
                  value: _accessSwitch,
                  granted: _accessEnabled,
                  grantedText: '无障碍已开启',
                  deniedText: '需要「无障碍」权限才能读支付页',
                  onChanged: (bool v) => _toggle(AutoBook.switchAccess, v),
                  onGrant: () async {
                    await AutoBook.openAccessibilitySettings();
                    await Future<void>.delayed(const Duration(seconds: 1));
                    await _load();
                  },
                  grantLabel: '去开启',
                ),
                const SizedBox(height: 10),
                _overlayCard(),
                const SizedBox(height: 16),
                _pendingCard(),
                const SizedBox(height: 16),
                _tutorial(),
              ],
            ),
    );
  }

  Widget _intro() {
    return XmHeroCard(
      variant: XmHeroVariant.profile,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.auto_awesome_outlined,
                  size: 18, color: Xm.goldOnDark),
              const SizedBox(width: 7),
              Text('自动记账', style: Xm.text(15, FontWeight.w600, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '微信支付完成后不发通知，所以主要靠「屏幕识别」：支付成功页出现后'
            '延迟约 1.6 秒弹个小窗，点「记下」就入账。通知和短信作为兜底。'
            '所有解析都在本机完成，不会上传任何内容。',
            style: Xm.text(12, FontWeight.w400,
                color: Xm.onDarkNote, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _switchCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required bool granted,
    required String grantedText,
    required String deniedText,
    required ValueChanged<bool> onChanged,
    required VoidCallback onGrant,
    required String grantLabel,
  }) {
    return XmCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              XmIconBlock.icon(icon, size: 34, iconSize: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: Xm.body),
                    const SizedBox(height: 2),
                    Text(subtitle, style: Xm.captionS),
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeTrackColor: Xm.brand,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Icon(
                granted ? Icons.check_circle : Icons.error_outline,
                size: 14,
                color: granted ? Xm.brand : Xm.gold,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  granted ? grantedText : deniedText,
                  style: Xm.text(11.5, FontWeight.w400,
                      color: granted ? Xm.ink3 : Xm.ink2),
                ),
              ),
              if (!granted)
                TextButton(
                  onPressed: onGrant,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 30),
                  ),
                  child: Text(grantLabel,
                      style: TextStyle(fontSize: 12, color: Xm.brand)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _overlayCard() {
    return XmCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: <Widget>[
          Icon(
            _overlayOk ? Icons.check_circle : Icons.error_outline,
            size: 15,
            color: _overlayOk ? Xm.brand : Xm.gold,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _overlayOk
                  ? '悬浮窗已授权：识别后约 1.6 秒弹出确认窗'
                  : '悬浮窗未授权：识别到只进队列，打开小满时再确认',
              style: Xm.text(11.5, FontWeight.w400,
                  color: _overlayOk ? Xm.ink3 : Xm.ink2),
            ),
          ),
          if (!_overlayOk)
            TextButton(
              onPressed: () async {
                await AutoBook.openOverlaySettings();
                await Future<void>.delayed(const Duration(seconds: 1));
                await _load();
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 30),
              ),
              child: Text('去授权',
                  style: TextStyle(fontSize: 12, color: Xm.brand)),
            ),
        ],
      ),
    );
  }

  Widget _pendingCard() {
    return XmCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: <Widget>[
          XmIconBlock.icon(Icons.inbox_outlined, size: 34, iconSize: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('待确认账单', style: Xm.body),
                const SizedBox(height: 2),
                Text(
                  _pending == 0 ? '暂时没有' : '$_pending 条待处理',
                  style: Xm.captionS,
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: _pending == 0 ? null : _openPending,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text('处理'),
          ),
        ],
      ),
    );
  }

  Widget _tutorial() {
    return XmCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('怎么开启', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          _step('1', '「屏幕识别」是主力：微信支付成功后不发通知，只能读支付页。点「去开启」，在无障碍列表里找到「小满 · 自动记账」打开。'),
          _step('2', '再点悬浮窗的「去授权」，允许「显示在其他应用上层」，这样付完款才弹确认窗。'),
          _step('3', '付款完成后约 1.6 秒会弹出小窗（刻意延迟，避免支付刚结束就被判定异常），点「记下」直接入账，「忽略」丢掉。'),
          _step('4', '「通知自动记账」和「短信自动记账」是兜底：微信/支付宝没弹窗、或者走银行短信时靠它们。'),
          _step('5', '没给悬浮窗权限也能用：识别到的账单会攒在「待确认账单」里，打开小满时再处理。'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Xm.surface2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('说明',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(
                  '· 识别范围：微信、支付宝的支付成功页，以及从它们切回商户 App 后 25 秒内的页面\n'
                  '· 只认「支付成功/付款成功/交易成功」+ 金额，验证码、额度提醒会被丢弃\n'
                  '· 同一条内容 90 秒内不会重复弹窗\n'
                  '· 无障碍服务可能被系统清理，发现不弹了就来这一页看状态、重新开启\n'
                  '· 所有内容只在本机处理，不会上传',
                  style: Xm.text(11.5, FontWeight.w400,
                      color: Xm.ink3, height: 1.7),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _step(String n, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(top: 1),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Xm.brandLL,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(n,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Xm.brand)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: Xm.text(12, FontWeight.w400,
                    color: Xm.ink2, height: 1.6)),
          ),
        ],
      ),
    );
  }
}

/// 待确认账单的处理面板。
class _PendingSheet extends StatefulWidget {
  const _PendingSheet({
    required this.repo,
    required this.bills,
    required this.accounts,
  });

  final Repo repo;
  final List<AutoBill> bills;
  final List<Account> accounts;

  @override
  State<_PendingSheet> createState() => _PendingSheetState();
}

class _PendingSheetState extends State<_PendingSheet> {
  late final List<bool> _checked =
      List<bool>.filled(widget.bills.length, true);
  late int _accountId =
      widget.accounts.isEmpty ? 0 : widget.accounts.first.id;
  bool _saving = false;

  Future<void> _confirm() async {
    if (_saving) return;
    setState(() => _saving = true);

    int added = 0;
    for (int i = 0; i < widget.bills.length; i++) {
      if (!_checked[i]) continue;
      final AutoBill b = widget.bills[i];
      if (await widget.repo.hasExternalId(b.dedupeKey)) continue;
      await widget.repo.addTxn(
        kind: b.kind,
        amount: b.amountCents,
        occurredAt: b.at,
        accountId: _accountId,
        note: b.note,
        merchant: b.merchant,
        source: b.source == 'sms' ? 'auto_sms' : 'auto_notify',
        externalId: b.dedupeKey,
        inBudget: true,
      );
      added++;
    }
    await AutoBook.clearPending();
    if (!mounted) return;
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(added == 0 ? '没有新增（可能已入过账）' : '已入账 $added 笔')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double h = MediaQuery.sizeOf(context).height * 0.78;
    return SizedBox(
      height: h,
      child: Container(
        decoration: BoxDecoration(
          color: Xm.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: <Widget>[
            const SizedBox(height: 8),
            Container(
              width: 38,
              height: 4.5,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Xm.line,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: <Widget>[
                  Text('待确认 ${widget.bills.length} 笔', style: Xm.bodyL),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text('取消',
                        style: TextStyle(fontSize: 13, color: Xm.ink3)),
                  ),
                ],
              ),
            ),
            if (widget.accounts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SizedBox(
                  height: 34,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.accounts.length,
                    separatorBuilder: (BuildContext _, int __) =>
                        const SizedBox(width: 8),
                    itemBuilder: (BuildContext context, int i) {
                      final Account a = widget.accounts[i];
                      final bool active = a.id == _accountId;
                      return GestureDetector(
                        onTap: () => setState(() => _accountId = a.id),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: active ? Xm.brand : Xm.surface2,
                            borderRadius: BorderRadius.circular(Xm.rChip),
                            border: Border.all(
                                color: active ? Xm.brand : Xm.line),
                          ),
                          child: Text(
                            a.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: active ? Colors.white : Xm.ink2,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: widget.bills.length,
                separatorBuilder: (BuildContext _, int __) => const XmDivider(),
                itemBuilder: (BuildContext context, int i) {
                  final AutoBill b = widget.bills[i];
                  return CheckboxListTile(
                    value: _checked[i],
                    onChanged: (bool? v) =>
                        setState(() => _checked[i] = v ?? false),
                    activeColor: Xm.brand,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            b.merchant ?? (b.source == 'sms' ? '短信' : '通知'),
                            style: Xm.body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${b.kind == 'income' ? '+' : '-'}${formatCents(b.amountCents)}',
                          style: Xm.bodyM.copyWith(
                            color: b.kind == 'income' ? Xm.income : Xm.ink,
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      '${_time(b.at)} · ${b.source == 'sms' ? '短信' : '通知'} · ${b.note ?? ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Xm.captionS,
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed:
                      _saving || widget.accounts.isEmpty ? null : _confirm,
                  child: Text(_saving ? '入账中…' : '确认入账'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _time(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
