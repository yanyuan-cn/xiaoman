import '../../core/money.dart';
import 'csv.dart';

enum ImportFormat { migration, alipay, wechat }

class DraftTxn {
  const DraftTxn({
    required this.kind,
    required this.amountCents,
    required this.occurredAt,
    required this.categoryName,
    required this.accountName,
    this.subCategory,
    this.note,
    this.merchant,
    this.externalId,
  });

  final String kind;
  final int amountCents;
  final DateTime occurredAt;
  final String categoryName;
  final String accountName;
  final String? subCategory;
  final String? note;
  final String? merchant;
  final String? externalId;
}

class ImportParse {
  const ImportParse({
    required this.rows,
    required this.total,
    required this.skipped,
    required this.accountCounts,
    required this.format,
  });

  final List<DraftTxn> rows;
  final int total;
  final int skipped;
  final Map<String, int> accountCounts;
  final ImportFormat format;

  String get formatLabel {
    switch (format) {
      case ImportFormat.alipay:
        return '支付宝账单';
      case ImportFormat.wechat:
        return '微信账单';
      case ImportFormat.migration:
        return '其他记账 App';
    }
  }
}

/// 平台分类 / 交易类型 -> 小满的分类（一级名）
const Map<String, String> _aliases = <String, String>{
  '餐饮美食': '食品餐饮',
  '食品餐饮': '食品餐饮',
  '交通出行': '出行交通',
  '出行交通': '出行交通',
  '日用百货': '购物消费',
  '服饰装扮': '购物消费',
  '数码电器': '购物消费',
  '美容美发': '购物消费',
  '母婴亲子': '购物消费',
  '宠物': '购物消费',
  '住房物业': '居家生活',
  '生活服务': '居家生活',
  '充值缴费': '居家生活',
  '文化休闲': '休闲娱乐',
  '运动户外': '休闲娱乐',
  '医疗健康': '健康医疗',
  '教育培训': '文化教育',
  '转账红包': '送礼人情',
  '人情往来': '送礼人情',
  '投资理财': '其他',
  '保险': '其他',
  '信用借还': '其他',
  '商户消费': '其他',
  '扫二维码付款': '其他',
  '转账': '送礼人情',
  '红包': '送礼人情',
  '群收款': '送礼人情',
};

String mapCategory(String raw) => _aliases[raw] ?? raw;

/// 自动识别格式并解析，认不出返回 null
ImportParse? parseAny(String text) {
  final List<List<String>> raw = parseCsv(text);
  if (raw.isEmpty) return null;
  return _parseAlipay(raw) ?? _parseWechat(raw) ?? _parseMigration(raw);
}

int _findHeader(
  List<List<String>> rows,
  bool Function(List<String> cells) test,
) {
  for (int i = 0; i < rows.length && i < 30; i++) {
    final List<String> cells =
        rows[i].map((String c) => c.trim()).toList(growable: false);
    if (test(cells)) return i;
  }
  return -1;
}

Map<String, int> _colIndex(List<String> header) {
  final Map<String, int> map = <String, int>{};
  for (int i = 0; i < header.length; i++) {
    map[header[i].trim()] = i;
  }
  return map;
}

String _cell(List<String> r, Map<String, int> idx, String name) {
  final int? i = idx[name];
  if (i == null || i >= r.length) return '';
  return r[i].trim();
}

int? _parseAmount(String raw) {
  final String s = raw
      .replaceAll('¥', '')
      .replaceAll('￥', '')
      .replaceAll(',', '')
      .replaceAll(' ', '')
      .replaceAll('+', '')
      .replaceAll('-', '');
  if (s.isEmpty) return null;
  return parseYuanToCents(s);
}

ImportParse? _build(
  List<List<String>> raw,
  int headerIndex,
  ImportFormat format,
  DraftTxn? Function(List<String> row, Map<String, int> idx) convert,
) {
  final List<String> header =
      raw[headerIndex].map((String c) => c.trim()).toList(growable: false);
  final Map<String, int> idx = _colIndex(header);

  final List<DraftTxn> rows = <DraftTxn>[];
  final Map<String, int> accountCounts = <String, int>{};
  int total = 0;
  int skipped = 0;

  for (int i = headerIndex + 1; i < raw.length; i++) {
    final List<String> r = raw[i];
    if (r.every((String c) => c.trim().isEmpty)) continue;
    total++;
    final DraftTxn? d = convert(r, idx);
    if (d == null) {
      skipped++;
      continue;
    }
    rows.add(d);
    accountCounts[d.accountName] = (accountCounts[d.accountName] ?? 0) + 1;
  }

  return ImportParse(
    rows: rows,
    total: total,
    skipped: skipped,
    accountCounts: accountCounts,
    format: format,
  );
}

String _kindOf(String raw) {
  if (raw.contains('支出') || raw == '支') return 'expense';
  if (raw.contains('收入') || raw == '收') return 'income';
  return '';
}

ImportParse? _parseAlipay(List<List<String>> raw) {
  final int h = _findHeader(
    raw,
    (List<String> c) =>
        c.contains('交易时间') && c.contains('金额') && c.contains('交易订单号'),
  );
  if (h < 0) return null;

  return _build(raw, h, ImportFormat.alipay,
      (List<String> r, Map<String, int> idx) {
    final String kind = _kindOf(_cell(r, idx, '收/支'));
    if (kind.isEmpty) return null;

    final String status = _cell(r, idx, '交易状态');
    if (status.contains('关闭') || status.contains('失败')) return null;

    final int? cents = _parseAmount(_cell(r, idx, '金额'));
    if (cents == null || cents <= 0) return null;

    final DateTime? when = DateTime.tryParse(_cell(r, idx, '交易时间'));
    if (when == null) return null;

    final String merchant = _cell(r, idx, '交易对方');
    final String desc = _cell(r, idx, '商品说明');
    final String note = merchant.isNotEmpty ? merchant : desc;

    final String orderNo = _cell(r, idx, '交易订单号');
    return DraftTxn(
      kind: kind,
      amountCents: cents,
      occurredAt: when,
      categoryName: mapCategory(_cell(r, idx, '交易分类')),
      accountName: _cell(r, idx, '收/付款方式'),
      note: note.isEmpty ? null : note,
      merchant: merchant.isEmpty ? null : merchant,
      externalId: orderNo.isEmpty ? null : orderNo,
    );
  });
}

ImportParse? _parseWechat(List<List<String>> raw) {
  final int h = _findHeader(
    raw,
    (List<String> c) =>
        c.contains('交易时间') && c.contains('金额(元)') && c.contains('当前状态'),
  );
  if (h < 0) return null;

  return _build(raw, h, ImportFormat.wechat,
      (List<String> r, Map<String, int> idx) {
    final String kind = _kindOf(_cell(r, idx, '收/支'));
    if (kind.isEmpty) return null;

    final String status = _cell(r, idx, '当前状态');
    if (status.contains('全额退款') || status.contains('已退还')) return null;

    final int? cents = _parseAmount(_cell(r, idx, '金额(元)'));
    if (cents == null || cents <= 0) return null;

    final DateTime? when = DateTime.tryParse(_cell(r, idx, '交易时间'));
    if (when == null) return null;

    final String merchant = _cell(r, idx, '交易对方');
    final String goods = _cell(r, idx, '商品');
    final String note = goods.isNotEmpty ? goods : merchant;

    final String orderNo = _cell(r, idx, '交易单号');
    return DraftTxn(
      kind: kind,
      amountCents: cents,
      occurredAt: when,
      categoryName: mapCategory(_cell(r, idx, '交易类型')),
      accountName: _cell(r, idx, '支付方式'),
      note: note.isEmpty ? null : note,
      merchant: merchant.isEmpty ? null : merchant,
      externalId: orderNo.isEmpty ? null : orderNo,
    );
  });
}

ImportParse? _parseMigration(List<List<String>> raw) {
  final int h = _findHeader(
    raw,
    (List<String> c) =>
        c.contains('日期') && c.contains('金额') && c.contains('收支类型'),
  );
  if (h < 0) return null;

  return _build(raw, h, ImportFormat.migration,
      (List<String> r, Map<String, int> idx) {
    final String kind = _cell(r, idx, '收支类型') == '支出'
        ? 'expense'
        : (_cell(r, idx, '收支类型') == '收入' ? 'income' : '');
    if (kind.isEmpty) return null;

    final int? cents = _parseAmount(_cell(r, idx, '金额'));
    if (cents == null || cents <= 0) return null;

    final String rawDate = _cell(r, idx, '日期').replaceAll('/', '-');
    final DateTime? when = DateTime.tryParse(rawDate);
    if (when == null) return null;

    final String sub = _cell(r, idx, '二级分类');
    final String note = _cell(r, idx, '备注');

    return DraftTxn(
      kind: kind,
      amountCents: cents,
      occurredAt: when,
      categoryName: mapCategory(_cell(r, idx, '类别')),
      accountName: _cell(r, idx, '账户'),
      subCategory: sub.isEmpty ? null : sub,
      note: note.isEmpty ? null : note,
    );
  });
}
