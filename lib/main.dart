import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/display.dart';
import 'core/storage.dart';
import 'core/theme.dart';
import 'data/db.dart';
import 'data/repo.dart';
import 'features/home/root_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final Repo repo = Repo(await openLedgerDb());
  await cleanUpdateCache();
  try {
    await repo.runDueRecurringRules();
  } catch (_) {
    // 自动记账失败不影响启动。
  }
  await applyHighRefreshRate();
  runApp(XiaomanApp(repo: repo));
}

class XiaomanApp extends StatelessWidget {
  const XiaomanApp({super.key, required this.repo});

  final Repo repo;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '小满',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const <Locale>[Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: Xm.theme(),
      home: RootPage(repo: repo),
    );
  }
}
