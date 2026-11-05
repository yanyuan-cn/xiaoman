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

  static const String switchNotif = 'switch_notif';
  static const String switchSms = 'switch_sms';

  /// 读取队列里尚未处理的原文，并解析成候选账单。
  static Future<List<AutoBill>> pendingBills() async {
    final List<_RawItem> items = await _pendingRaw();
    final List<AutoBill> out = <AutoBill>[];
    for (final _RawItem it in items) {
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
}

class _RawItem {
  const _RawItem({required this.source, required this.raw, required this.at});

  final String source;
  final String raw;
  final DateTime at;

  factory _RawItem.fromJson(Map<String, Object?> m) => _RawItem(
        source: (m['source'] as String?) ?? 'notification',
        raw: (m['raw'] as String?) ?? '',
        at: DateTime.fromMillisecondsSinceEpoch(
            ((m['at'] as num?)?.toInt()) ?? 0),
      );
}
