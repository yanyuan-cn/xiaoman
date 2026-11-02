/// 金额统一用「分」存成 int，避免浮点误差。

/// 把用户输入的元字符串解析成「分」。
/// 支持 12 / 12.3 / 12.34 / 1,234.56；非法输入返回 null。
int? parseYuanToCents(String raw) {
  final String s = raw.trim().replaceAll(',', '');
  if (s.isEmpty || s == '.') return null;
  if (!RegExp(r'^\d*\.?\d*$').hasMatch(s)) return null;

  String intPart = s;
  String frac = '';
  final int dot = s.indexOf('.');
  if (dot >= 0) {
    intPart = s.substring(0, dot);
    frac = s.substring(dot + 1);
    if (frac.length > 2) frac = frac.substring(0, 2);
  }
  if (intPart.isEmpty) intPart = '0';
  final int? yuan = int.tryParse(intPart);
  if (yuan == null) return null;
  return yuan * 100 + int.parse(frac.padRight(2, '0'));
}

/// 1,234.56
String formatCents(int cents) {
  final String sign = cents < 0 ? '-' : '';
  final int a = cents.abs();
  final String yuan = (a ~/ 100).toString();
  final String frac = (a % 100).toString().padLeft(2, '0');
  final String grouped =
      yuan.replaceAllMapped(RegExp(r'\d(?=(\d{3})+$)'), (Match m) => '${m[0]},');
  return '$sign$grouped.$frac';
}

/// 12 / 12.5 / 12.34（不带千分位，给输入框回填用）
String formatCentsPlain(int cents) {
  final int a = cents.abs();
  final String s = a % 100 == 0
      ? '${a ~/ 100}'
      : '${a ~/ 100}.${(a % 100).toString().padLeft(2, '0')}';
  return cents < 0 ? '-$s' : s;
}
