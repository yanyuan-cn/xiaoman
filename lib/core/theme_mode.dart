import 'package:flutter/foundation.dart';

enum XmThemeMode { system, light, dark }

extension XmThemeModeLabel on XmThemeMode {
  String get label => switch (this) {
        XmThemeMode.system => '跟随系统',
        XmThemeMode.light => '浅色',
        XmThemeMode.dark => '深色',
      };

  String get storage => switch (this) {
        XmThemeMode.system => 'system',
        XmThemeMode.light => 'light',
        XmThemeMode.dark => 'dark',
      };
}

/// 外观模式的单一数据源：页面改它，根部重建并重设调色板。
class ThemeController extends ChangeNotifier {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  XmThemeMode _mode = XmThemeMode.system;

  XmThemeMode get mode => _mode;

  void setMode(XmThemeMode mode) {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
  }

  static XmThemeMode parse(String? value) => switch (value) {
        'light' => XmThemeMode.light,
        'dark' => XmThemeMode.dark,
        _ => XmThemeMode.system,
      };
}
