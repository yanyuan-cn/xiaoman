import 'dart:async';

import 'package:flutter/services.dart';

/// 每日记账提醒。
///
/// 全部由原生实现（AlarmManager + NotificationManager，见
/// `scripts/android/Reminder.kt`）：不引插件、不改 gradle，也不依赖精确闹钟
/// 之外的东西。这里只负责把设置传下去。
class DailyReminder {
  DailyReminder._();

  static const MethodChannel _ch = MethodChannel('xiaoman/reminder');

  static const Duration _timeout = Duration(seconds: 4);

  static Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _ch.invokeMethod<T>(method, args).timeout(_timeout);
    } catch (_) {
      return null;
    }
  }

  static Future<ReminderConfig> load() async {
    final Map<Object?, Object?>? raw =
        await _call<Map<Object?, Object?>>('get');
    if (raw == null) return const ReminderConfig();
    return ReminderConfig(
      enabled: raw['enabled'] == true,
      hour: (raw['hour'] as num?)?.toInt() ?? 21,
      minute: (raw['minute'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<bool> save(ReminderConfig c) async {
    final bool? ok = await _call<bool>('set', <String, Object?>{
      'enabled': c.enabled,
      'hour': c.hour,
      'minute': c.minute,
    });
    return ok ?? false;
  }

  /// 系统层通知是否被允许（Android 13+ 需要用户授权）
  static Future<bool> notificationsEnabled() async =>
      (await _call<bool>('notificationsEnabled')) ?? true;

  static Future<void> requestNotifications() =>
      _call<void>('requestNotifications');

  /// Android 12+ 的「精确闹钟」权限，没有的话提醒会晚几分钟
  static Future<bool> canExactAlarm() async =>
      (await _call<bool>('canExactAlarm')) ?? true;

  static Future<void> openExactAlarmSettings() =>
      _call<void>('openExactAlarmSettings');

  /// 立刻发一条，用来验证通知链是否通
  static Future<void> testNow() => _call<void>('test');
}

class ReminderConfig {
  const ReminderConfig({
    this.enabled = false,
    this.hour = 21,
    this.minute = 0,
  });

  final bool enabled;
  final int hour;
  final int minute;

  ReminderConfig copyWith({bool? enabled, int? hour, int? minute}) =>
      ReminderConfig(
        enabled: enabled ?? this.enabled,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
      );

  String get label {
    final String h = hour.toString().padLeft(2, '0');
    final String m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
