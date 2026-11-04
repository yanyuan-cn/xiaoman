import 'package:flutter/services.dart';

/// 桌面图标切换：D1「墨绿满未满」深色版 / D3「米白方孔钱」浅色版。
///
/// Android 侧用两个 activity-alias 实现（见 scripts/init_android.ps1 与
/// scripts/android/MainActivity.kt），切换后系统会重新加载桌面图标。
class AppIcon {
  AppIcon._();

  static const MethodChannel _channel = MethodChannel('xiaoman/icon');

  static const String d1 = 'd1';
  static const String d3 = 'd3';

  static Future<String> current() async {
    try {
      final String? id = await _channel.invokeMethod<String>('get');
      return (id == d3) ? d3 : d1;
    } catch (_) {
      // 非 Android 或通道不可用时静默降级
      return d1;
    }
  }

  static Future<bool> apply(String id) async {
    try {
      await _channel.invokeMethod<bool>('set', <String, Object?>{'id': id});
      return true;
    } catch (_) {
      return false;
    }
  }
}
