import 'dart:convert';

import 'package:charset/charset.dart' show gbk;

/// 把文件字节解码成文本。
/// 先按 UTF-8 严格解码；失败说明是 GBK（支付宝账单常见），退回 GBK。
String decodeText(List<int> bytes) {
  if (bytes.isEmpty) return '';
  // UTF-8 BOM
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  // UTF-16 BOM
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return String.fromCharCodes(bytes.sublist(2));
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    try {
      return gbk.decode(bytes);
    } catch (_) {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }
}
