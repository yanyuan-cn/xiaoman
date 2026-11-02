import '../../core/money.dart';
import 'csv.dart';

class DraftTxn {
  const DraftTxn({
    required this.kind,
    required this.amountCents,
    required this.occurredAt,
    required this.categoryName,
    required this.accountName,
    this.subCategory,
    this.note,
  });

  final String kind;
  final int amountCents;
  final DateTime occurredAt;
  final String categoryName;
  final String accountName;
  final String? subCategory;
  final String? note;
}

class MigrationParse {
  const MigrationParse({
    required this.rows,
    required this.total,
    required this.skipped,
    required this.accountCounts,
  });

  final List<DraftTxn> rows;
  final int total;
  final int skipped;
  final Map<String, int> accountCounts;
}

/// 解析「其他记账 App」导出的 CSV，认不出表头时返回 null。
MigrationParse? parseMigrationCsv(String text) {
  final List<List<String>> raw = parseCsv(text);
  if (raw.isEmpty) return null;

  int headerIndex = -1;
  for (int i = 0; i < raw.length && i < 10; i++) {
    final List<String> cells = raw[i].map((String c) => c.trim()).toList();
    if (cells.contains('日期') && cells.contains('金额')) {
      headerIndex = i;
      break;
    }
  }
  if (headerIndex < 0) return null;

  final List<String> header =
      raw[headerIndex].map((String c) => c.trim()).toList();
  int col(String name) => header.indexOf(name);

  final int dateCol = col('日期');
  final int kindCol = col('收支类型');
  final int amountCol = col('金额');
  final int categoryCol = col('类别');
  final int subCol = col('二级分类');
  final int accountCol = col('账户');
  final int noteCol = col('备注');

  final List<DraftTxn> rows = <DraftTxn>[];
  final Map<String, int> accountCounts = <String, int>{};
  int total = 0;
  int skipped = 0;

  String cell(List<String> r, int i) => (i >= 0 && i < r.length) ? r[i].trim() : '';

  for (int i = headerIndex + 1; i < raw.length; i++) {
    final List<String> r = raw[i];
    if (r.every((String c) => c.trim().isEmpty)) continue;
    total++;

    final String kindRaw = cell(r, kindCol);
    final String kind = kindRaw == '支出' ? 'expense' : (kindRaw == '收入' ? 'income' : '');
    if (kind.isEmpty) {
      skipped++;
      continue;
    }

    final String amountRaw = cell(r, amountCol)
        .replaceAll('¥', '')
        .replaceAll('￥', '')
        .replaceAll(',', '')
        .replaceAll(' ', '')
        .replaceAll('-', '');
    final int? cents = parseYuanToCents(amountRaw);
    if (cents == null || cents <= 0) {
      skipped++;
      continue;
    }

    final DateTime? when = _parseDate(cell(r, dateCol));
    if (when == null) {
      skipped++;
      continue;
    }

    final String account = cell(r, accountCol);
    accountCounts[account] = (accountCounts[account] ?? 0) + 1;

    final String note = cell(r, noteCol);
    final String sub = cell(r, subCol);
    rows.add(DraftTxn(
      kind: kind,
      amountCents: cents,
      occurredAt: when,
      categoryName: cell(r, categoryCol),
      accountName: account,
      subCategory: sub.isEmpty ? null : sub,
      note: note.isEmpty ? null : note,
    ));
  }

  return MigrationParse(
    rows: rows,
    total: total,
    skipped: skipped,
    accountCounts: accountCounts,
  );
}

DateTime? _parseDate(String raw) {
  final String s = raw.trim().replaceAll('/', '-');
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}
