import 'dart:convert';

import 'package:charset/charset.dart' show gbk;

/// 把账单文件字节解码成文本。
///
/// 顺序：BOM 优先（UTF-8 / UTF-16 LE / UTF-16 BE），否则先按 UTF-8 **严格**解码，
/// 失败再退回 GBK（支付宝、微信、多数银行导出的中文 CSV 都是 GBK）。
///
/// GBK 是 GB18030 的子集，常见汉字都能覆盖；纯 GB18030 生僻字会退化成替换符，
/// 这里不做进一步区分——记账场景用不到那部分字符。
String decodeText(List<int> bytes) {
  if (bytes.isEmpty) return '';

  // UTF-8 BOM
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }

  // UTF-16 LE BOM: FF FE
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _utf16(bytes.sublist(2), littleEndian: true);
  }

  // UTF-16 BE BOM: FE FF
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _utf16(bytes.sublist(2), littleEndian: false);
  }

  try {
    return utf8.decode(bytes);
  } on FormatException {
    try {
      return gbk.decode(bytes);
    } catch (_) {
      // GBK 也解不动（半截字节/二进制），给一个能读的兜底，至少不崩。
      return utf8.decode(bytes, allowMalformed: true);
    }
  }
}

String _utf16(List<int> bytes, {required bool littleEndian}) {
  final List<int> units = <int>[];
  for (int i = 0; i + 1 < bytes.length; i += 2) {
    units.add(littleEndian
        ? (bytes[i] | (bytes[i + 1] << 8))
        : ((bytes[i] << 8) | bytes[i + 1]));
  }
  return String.fromCharCodes(units);
}

/// 文件是不是「看起来像」账单文本（用于导入前的粗略校验）。
bool looksLikeText(List<int> bytes) {
  if (bytes.isEmpty) return false;
  int control = 0;
  for (final int b in bytes.take(512)) {
    if (b == 0) return false; // 含 NUL 基本是二进制
    if (b < 0x09) control++;
  }
  return control < 4;
}
