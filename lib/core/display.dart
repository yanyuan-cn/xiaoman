import 'package:flutter_displaymode/flutter_displaymode.dart';

/// 申请当前设备支持的最高刷新率。
/// 部分机型受系统白名单限制，这里失败也不影响使用。
Future<void> applyHighRefreshRate() async {
  try {
    await FlutterDisplayMode.setHighRefreshRate();
  } catch (_) {
    // 忽略：不支持或系统限制
  }
}
