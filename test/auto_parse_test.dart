import 'package:flutter_test/flutter_test.dart';

import 'package:xiaoman/data/import/auto_parse.dart';

DateTime _at() => DateTime(2026, 11, 5, 8, 12);

AutoBill? _p(String raw, {String source = 'notification'}) =>
    parseAutoBill(source: source, raw: raw, at: _at());

void main() {
  test('支付宝付款通知', () {
    final AutoBill? b = _p('支付宝 支付成功 ¥12.50');
    expect(b, isNotNull);
    expect(b!.kind, 'expense');
    expect(b.amountCents, 1250);
    expect(b.merchant, '支付宝');
  });

  test('微信支付凭证', () {
    final AutoBill? b = _p('微信支付凭证 你已支付88.00元');
    expect(b, isNotNull);
    expect(b!.kind, 'expense');
    expect(b.amountCents, 8800);
    expect(b.merchant, '微信');
  });

  test('银行短信（人民币）', () {
    final AutoBill? b = _p(
      '【招商银行】您尾号1234的储蓄卡11月05日08:12消费人民币36.80元，余额1000.00元',
      source: 'sms',
    );
    expect(b, isNotNull);
    expect(b!.kind, 'expense');
    expect(b.amountCents, 3680);
    expect(b.merchant, '招商银行');
  });

  test('收款到账算收入', () {
    final AutoBill? b = _p('支付宝 收款到账¥100.00');
    expect(b, isNotNull);
    expect(b!.kind, 'income');
    expect(b.amountCents, 10000);
  });

  test('退款算收入', () {
    final AutoBill? b = _p('微信支付 退款到账 ¥9.90');
    expect(b, isNotNull);
    expect(b!.kind, 'income');
    expect(b.amountCents, 990);
  });

  test('验证码不记账', () {
    expect(_p('验证码 123456，您正在支付 ¥1.00'), isNull);
  });

  test('额度提醒不记账', () {
    expect(_p('您的信用卡额度已提升至50000元'), isNull);
  });

  test('没有金额不记账', () {
    expect(_p('你的快递已签收'), isNull);
  });

  test('没有金额关键词不记账', () {
    expect(_p('今天天气不错 ¥12.50'), isNull);
  });

  test('同一段文本的 dedupeKey 稳定', () {
    final AutoBill? a = _p('支付宝 支付成功 ¥12.50');
    final AutoBill? b = _p('支付宝 支付成功 ¥12.50');
    expect(a!.dedupeKey, b!.dedupeKey);
    expect(a.dedupeKey, startsWith('auto:'));
  });

  test('不同金额产生不同 dedupeKey', () {
    final AutoBill? a = _p('支付宝 支付成功 ¥12.50');
    final AutoBill? b = _p('支付宝 支付成功 ¥12.51');
    expect(a!.dedupeKey, isNot(b!.dedupeKey));
  });
}
