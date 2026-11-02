import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoman/core/money.dart';

void main() {
  test('解析元 -> 分', () {
    expect(parseYuanToCents('12'), 1200);
    expect(parseYuanToCents('12.3'), 1230);
    expect(parseYuanToCents('12.34'), 1234);
    expect(parseYuanToCents('0.07'), 7);
    expect(parseYuanToCents('1,234.56'), 123456);
    expect(parseYuanToCents('12.345'), 1234);
    expect(parseYuanToCents(''), isNull);
    expect(parseYuanToCents('.'), isNull);
    expect(parseYuanToCents('abc'), isNull);
  });

  test('分 -> 显示', () {
    expect(formatCents(123456), '1,234.56');
    expect(formatCents(7), '0.07');
    expect(formatCents(-500), '-5.00');
    expect(formatCents(100000000), '1,000,000.00');
    expect(formatCentsPlain(1200), '12');
    expect(formatCentsPlain(1250), '12.50');
  });
}
