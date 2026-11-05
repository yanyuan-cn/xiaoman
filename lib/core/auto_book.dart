import 'dart:convert';

import 'package:flutter/services.dart';

import '../data/import/auto_parse.dart';

/// 自动记账的原生桥。
///
/// 原生侧只负责「抓文本」（无障碍 / 通知 / 短信），所有判断都在 Dart 里做。
///
/// 所有调用都加了超时：之前页面卡在转圈，就是因为某个 channel 调用没有返回、
/// 也没有被 catch，`_load()` 永远走不到 setState。
class AutoBook {
  AutoBook._();

  static const MethodChannel _ch = MethodChannel('xiaoman/autobook');

  static const String switchMaster = 'switch_master';
  static const String switchNotif = 'switch_notif';
  static const String switchSms = 'switch_sms';
  static const String switchAccess = 'switch_access';

  static const Duration _timeout = Duration(seconds: 4);

  static Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _ch.invokeMethod<T>(method, args).timeout(_timeout);
    } catch (_) {
      return null;
    }
  }

  /// 队列里「待确认」的账单。
  static Future<List<AutoBill>> pendingBills() async {
    final List<_RawItem> items = await _pendingRaw();
    final List<AutoBill> out = <AutoBill>[];
    for (final _RawItem it in items) {
      if (it.decision != 'pending') continue;
      final AutoBill? b =
          parseAutoBill(source: it.source, raw: it.raw, at: it.at);
      if (b != null) out.add(b);
    }
    return out;
  }

  /// 用户在悬浮窗里点了「记下」的账单，直接入账不用再问。
  static Future<List<AutoBill>> confirmedBills() async {
    final List<_RawItem> items = await _pendingRaw();
    final List<AutoBill> out = <AutoBill>[];
    for (final _RawItem it in items) {
      if (it.decision != 'confirmed') continue;
      final AutoBill? b =
          parseAutoBill(source: it.source, raw: it.raw, at: it.at);
      if (b != null) out.add(b);
    }
    return out;
  }

  static Future<List<_RawItem>> _pendingRaw() async {
    final String? json = await _call<String>('getPending');
    if (json == null || json.isEmpty) return const <_RawItem>[];
    try {
      final Object? decoded = jsonDecode(json);
      if (decoded is! List) return const <_RawItem>[];
      return <_RawItem>[
        for (final Object? e in decoded)
          if (e is Map) _RawItem.fromJson(Map<String, Object?>.from(e)),
      ];
    } catch (_) {
      return const <_RawItem>[];
    }
  }

  static Future<void> clearPending() => _call<bool>('clearPending');

  /// 丢掉已经处理过的队列条目（confirmed / ignored），保留待确认的。
  static Future<void> pruneHandled() => _call<bool>('pruneHandled');

  // ---------------- 开关与权限 ----------------

  static Future<bool> switchOn(String key) async {
    final bool? v = await _call<bool>('getSwitch', <String, Object?>{'key': key});
    return v ?? true;
  }

  static Future<void> setSwitch(String key, bool on) =>
      _call<bool>('setSwitch', <String, Object?>{'key': key, 'on': on});

  static Future<bool> hasNotificationAccess() async =>
      await _call<bool>('notificationAccess') ?? false;

  static Future<void> openNotificationSettings() =>
      _call<bool>('openNotificationSettings');

  static Future<bool> hasSmsPermission() async =>
      await _call<bool>('hasSmsPermission') ?? false;

  static Future<void> requestSmsPermission() =>
      _call<bool>('requestSmsPermission');

  static Future<void> openAppSettings() => _call<bool>('openAppSettings');

  /// 无障碍服务（读屏识别）是否已启用。
  static Future<bool> accessibilityEnabled() async =>
      await _call<bool>('accessibilityEnabled') ?? false;

  static Future<void> openAccessibilitySettings() =>
      _call<bool>('openAccessibilitySettings');

  /// 悬浮窗权限（延迟弹窗用；没有就退回「只进队列」）。
  static Future<bool> hasOverlayPermission() async =>
      await _call<bool>('hasOverlayPermission') ?? false;

  static Future<void> openOverlaySettings() =>
      _call<bool>('openOverlaySettings');
}

class _RawItem {
  const _RawItem({
    required this.source,
    required this.raw,
    required this.at,
    required this.decision,
  });

  final String source;
  final String raw;
  final DateTime at;

  /// pending / confirmed / ignored
  final String decision;

  factory _RawItem.fromJson(Map<String, Object?> m) => _RawItem(
        source: (m['source'] as String?) ?? 'notification',
        raw: (m['raw'] as String?) ?? '',
        at: DateTime.fromMillisecondsSinceEpoch(
            ((m['at'] as num?)?.toInt()) ?? 0),
        decision: (m['decision'] as String?) ?? 'pending',
      );
}
