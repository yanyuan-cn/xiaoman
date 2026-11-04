import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:charset/charset.dart' show gbk;

import 'package:xiaoman/data/import/decode.dart';

void main() {
  const String sample = '日期,金额,备注\n2026-11-02,20.00,早餐';

  test('UTF-8 无 BOM', () {
    expect(decodeText(utf8.encode(sample)), sample);
  });

  test('UTF-8 带 BOM', () {
    final List<int> bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(sample)];
    expect(decodeText(bytes), sample);
  });

  test('GBK（支付宝/银行常见）', () {
    // 手工构造 GBK 字节，避免依赖编码器实现
    final List<int> bytes = gbk.encode(sample);
    expect(decodeText(bytes), sample);
  });

  test('UTF-16 LE 带 BOM', () {
    final List<int> units = sample.codeUnits;
    final List<int> bytes = <int>[0xFF, 0xFE];
    for (final int u in units) {
      bytes..add(u & 0xFF)..add((u >> 8) & 0xFF);
    }
    expect(decodeText(bytes), sample);
  });

  test('UTF-16 BE 带 BOM', () {
    final List<int> units = sample.codeUnits;
    final List<int> bytes = <int>[0xFE, 0xFF];
    for (final int u in units) {
      bytes..add((u >> 8) & 0xFF)..add(u & 0xFF);
    }
    expect(decodeText(bytes), sample);
  });

  test('空文件', () {
    expect(decodeText(const <int>[]), '');
  });

  test('二进制不会崩', () {
    // 含 NUL 的随机字节：只要不抛异常即可
    expect(() => decodeText(<int>[0x00, 0x01, 0x02, 0xFF]), returnsNormally);
    expect(looksLikeText(<int>[0x00, 0x01]), isFalse);
    expect(looksLikeText(gbk.encode(sample)), isTrue);
  });
}
