import 'dart:convert';

import 'package:flutter/services.dart';

import '../data/import/auto_parse.dart';

/// 自动记账的原生桥。
///
/// 原生侧只负责「抓文本」（通知监听 / 短信广播），所有判断都在 Dart 里做，
/// 这样规则集中、可测试。
class AutoBook {
  AutoBook._();

  static const MethodChannel _ch = MethodChannel('xiaoman/autobook');

  static const String switchMaster = 'switch_master';
  static const String switchNotif = 'switch_notif';
  static const String switchSms = 'switch_sms';
  static const String switchAccess = 'switch_access';

  /// 丢掉已经处理过的队列条目（confirmed / ignored），保留待确认的。
  static Future<void> pruneHandled() async {
    try {
      await _ch.invokeMethod<bool>('pruneHandled');
    } catch (_) {}
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

  static Future<int> pendingCount() async => (await _pendingRaw()).length;

  static Future<void> clearPending() async {
    try {
      await _ch.invokeMethod<bool>('clearPending');
    } catch (_) {
      // 桌面/测试环境没有原生实现，忽略
    }
  }

  static Future<List<_RawItem>> _pendingRaw() async {
    try {
      final String? json = await _ch.invokeMethod<String>('getPending');
      if (json == null || json.isEmpty) return const <_RawItem>[];
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

  // ---------------- 开关与权限 ----------------

  static Future<bool> switchOn(String key) async {
    try {
      return await _ch.invokeMethod<bool>('getSwitch', <String, Object?>{
            'key': key,
          }) ??
          true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setSwitch(String key, bool on) async {
    try {
      await _ch.invokeMethod<bool>('setSwitch', <String, Object?>{
        'key': key,
        'on': on,
      });
    } catch (_) {}
  }

  static Future<bool> hasNotificationAccess() async {
    try {
      return await _ch.invokeMethod<bool>('notificationAccess') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openNotificationSettings() async {
    try {
      await _ch.invokeMethod<bool>('openNotificationSettings');
    } catch (_) {}
  }

  static Future<bool> hasSmsPermission() async {
    try {
      return await _ch.invokeMethod<bool>('hasSmsPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestSmsPermission() async {
    try {
      await _ch.invokeMethod<bool>('requestSmsPermission');
    } catch (_) {}
  }

  static Future<void> openAppSettings() async {
    try {
      await _ch.invokeMethod<bool>('openAppSettings');
    } catch (_) {}
  }

  /// 无障碍服务（读屏识别）是否已启用。
  static Future<bool> accessibilityEnabled() async {
    try {
      return await _ch.invokeMethod<bool>('accessibilityEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openAccessibilitySettings() async {
    try {
      await _ch.invokeMethod<bool>('openAccessibilitySettings');
    } catch (_) {}
  }

  /// 悬浮窗权限（延迟弹窗用；没有就退回「只进队列」）。
  static Future<bool> hasOverlayPermission() async {
    try {
      return await _ch.invokeMethod<bool>('hasOverlayPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openOverlaySettings() async {
    try {
      await _ch.invokeMethod<bool>('openOverlaySettings');
    } catch (_) {}
  }
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
