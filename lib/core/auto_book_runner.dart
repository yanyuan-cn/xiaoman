import 'package:flutter/foundation.dart';

import '../data/import/auto_parse.dart';
import '../data/models.dart';
import '../data/repo.dart';
import 'auto_book.dart';

/// 把「悬浮窗里已经点过记下」的账单真正写进数据库。
///
/// 触发时机：App 启动、App 回到前台、进入自动记账页。
/// 之前只在冷启动时写，所以从微信切回来点「记下」后看不到记录——这是根因。
class AutoBookRunner {
  AutoBookRunner._();

  static bool _running = false;

  /// 返回这次新增的条数。
  static Future<int> flush(Repo repo) async {
    if (_running) return 0;
    _running = true;
    try {
      final List<AutoBill> confirmed = await AutoBook.confirmedBills();
      if (confirmed.isEmpty) return 0;

      final List<Account> accounts = await repo.accounts();
      if (accounts.isEmpty) return 0;
      final int accountId = accounts.first.id;

      int added = 0;
      for (final AutoBill b in confirmed) {
        if (await repo.hasExternalId(b.dedupeKey)) continue;
        await repo.addTxn(
          kind: b.kind,
          amount: b.amountCents,
          occurredAt: b.at,
          accountId: accountId,
          note: b.note,
          merchant: b.merchant,
          source: 'auto_access',
          externalId: b.dedupeKey,
          inBudget: true,
        );
        added++;
      }
      // 写完之后把 confirmed / ignored 从队列里摘掉，保留还没确认的
      await AutoBook.pruneHandled();
      if (added > 0) {
        debugPrint('auto book: flushed $added confirmed bills');
      }
      return added;
    } catch (_) {
      // 写库失败不能影响页面加载/启动流程
      return 0;
    } finally {
      _running = false;
    }
  }
}
