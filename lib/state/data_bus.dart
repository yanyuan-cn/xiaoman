import 'package:flutter/foundation.dart';

/// 数据变更广播：导入、撤销、记账后通知各页刷新
class DataBus extends ChangeNotifier {
  DataBus._();

  static final DataBus instance = DataBus._();

  void bump() => notifyListeners();
}
