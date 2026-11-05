import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoman/data/import/draft.dart';
import 'package:xiaoman/data/import/xlsx.dart';

/// 用 excel 包现造一个 xlsx，再走「读回来 → 识别」的完整链路，
/// 这样测的是真实文件，不是手写二维数组。
Uint8List _book(List<List<Object?>> rows) {
  final Excel ex = Excel.createExcel();
  final String sheet = ex.getDefaultSheet() ?? 'Sheet1';
  final Sheet sh = ex[sheet];
  for (int r = 0; r < rows.length; r++) {
    for (int c = 0; c < rows[r].length; c++) {
      final Object? v = rows[r][c];
      if (v == null) continue;
      final CellIndex idx = CellIndex.indexByColumnRow(
        columnIndex: c,
        rowIndex: r,
      );
      if (v is int) {
        sh.cell(idx).value = IntCellValue(v);
      } else if (v is double) {
        sh.cell(idx).value = DoubleCellValue(v);
      } else {
        sh.cell(idx).value = TextCellValue(v.toString());
      }
    }
  }
  return Uint8List.fromList(ex.encode()!);
}

void main() {
  test('xlsx 文件头能被认出来', () {
    final Uint8List bytes = _book(<List<Object?>>[
      <Object?>['a'],
    ]);
    expect(looksLikeXlsx(bytes), isTrue);
    expect(looksLikeXlsx(Uint8List.fromList(<int>[1, 2, 3, 4])), isFalse);
  });

  test('其他记账 App 的表：读出二维表并识别', () {
    final Uint8List bytes = _book(<List<Object?>>[
      <Object?>['日期', '金额', '收支类型', '类别', '账户', '备注', '二级分类'],
      <Object?>['2026-03-01', 25.5, '支出', '食品餐饮', '支付宝', '午饭', '午餐'],
      <Object?>['2026-03-02', 12, '收入', '工资', '银行卡', '', ''],
    ]);

    final List<List<String>>? rows = readXlsxRows(bytes);
    expect(rows, isNotNull);
    expect(rows!.length, 3);

    final ImportParse? p = parseRows(rows);
    expect(p, isNotNull);
    expect(p!.format, ImportFormat.migration);
    expect(p.rows.length, 2);

    final DraftTxn first = p.rows.first;
    expect(first.kind, 'expense');
    expect(first.amountCents, 2550);
    expect(first.occurredAt.year, 2026);
    expect(first.occurredAt.month, 3);
    expect(first.occurredAt.day, 1);
    expect(first.note, '午饭');
    expect(first.subCategory, '午餐');
    expect(first.accountName, '支付宝');

    // 整数金额不应该变成 12.0 之后解析失败
    expect(p.rows[1].amountCents, 1200);
    expect(p.rows[1].kind, 'income');
  });

  test('微信格式的表也能识别', () {
    final Uint8List bytes = _book(<List<Object?>>[
      <Object?>['交易时间', '交易类型', '交易对方', '商品', '收/支', '金额(元)', '支付方式', '当前状态', '交易单号'],
      <Object?>[
        '2026-03-05 12:30:00',
        '商户消费',
        '美团',
        '午餐',
        '支出',
        38.8,
        '零钱',
        '支付成功',
        'WX001',
      ],
    ]);

    final ImportParse? p = parseRows(readXlsxRows(bytes)!);
    expect(p, isNotNull);
    expect(p!.format, ImportFormat.wechat);
    expect(p.rows.single.amountCents, 3880);
    expect(p.rows.single.externalId, 'WX001');
    expect(p.rows.single.merchant, '美团');
  });

  test('空表 / 坏文件返回 null，不抛异常', () {
    final Uint8List empty = _book(<List<Object?>>[
      <Object?>['', ''],
    ]);
    expect(readXlsxRows(empty), isNull);
    expect(readXlsxRows(Uint8List.fromList(<int>[1, 2, 3, 4, 5])), isNull);
  });

  test('认不出的表头返回 null', () {
    final Uint8List bytes = _book(<List<Object?>>[
      <Object?>['姓名', '电话'],
      <Object?>['张三', '13800000000'],
    ]);
    final List<List<String>> rows = readXlsxRows(bytes)!;
    expect(parseRows(rows), isNull);
  });
}
