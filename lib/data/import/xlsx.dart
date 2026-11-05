import 'dart:typed_data';

import 'package:excel/excel.dart';

/// 读 .xlsx（Excel 2007+）的第一张非空工作表，转成和 CSV 一样的
/// `[[单元格, 单元格, ...], ...]`，后面的解析流程完全复用。
///
/// 只支持 xlsx：老的 .xls 是二进制格式，解析库普遍不支持，
/// 这条路径读不出来就返回 null，让上层提示用户另存为 xlsx 或 CSV。
List<List<String>>? readXlsxRows(Uint8List bytes) {
  try {
    final Excel ex = Excel.decodeBytes(bytes);
    for (final String name in ex.tables.keys) {
      final Sheet? sheet = ex.tables[name];
      if (sheet == null) continue;

      final List<List<String>> rows = <List<String>>[];
      for (final List<Data?> row in sheet.rows) {
        rows.add(<String>[for (final Data? cell in row) _cellText(cell)]);
      }
      while (rows.isNotEmpty &&
          rows.last.every((String c) => c.trim().isEmpty)) {
        rows.removeLast();
      }
      final bool hasContent = rows.any(
          (List<String> r) => r.any((String c) => c.trim().isNotEmpty));
      if (hasContent) return rows;
    }
    return null;
  } catch (_) {
    return null;
  }
}

String _cellText(Data? data) {
  final CellValue? v = data?.value;
  if (v == null) return '';
  if (v is TextCellValue) return v.value.toString();
  if (v is IntCellValue) return v.value.toString();
  if (v is DoubleCellValue) {
    final double d = v.value;
    // 金额在 Excel 里常常是 25.0 这种，去掉无意义的小数点
    if (d == d.roundToDouble() && d.abs() < 1e15) {
      return d.toInt().toString();
    }
    return d.toString();
  }
  if (v is BoolCellValue) return v.value ? 'TRUE' : 'FALSE';
  if (v is DateCellValue) {
    return '${_pad(v.year, 4)}-${_pad(v.month, 2)}-${_pad(v.day, 2)}';
  }
  if (v is DateTimeCellValue) {
    return '${_pad(v.year, 4)}-${_pad(v.month, 2)}-${_pad(v.day, 2)}'
        ' ${_pad(v.hour, 2)}:${_pad(v.minute, 2)}:${_pad(v.second, 2)}';
  }
  // 公式单元格没有缓存值，取不到就读成空
  if (v is FormulaCellValue) return '';
  return v.toString();
}

String _pad(int v, int width) => v.toString().padLeft(width, '0');

/// 是不是 xlsx：zip 文件头是 `PK\x03\x04`。
bool looksLikeXlsx(Uint8List bytes) {
  if (bytes.length < 4) return false;
  return bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04;
}
