import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/display.dart';
import 'core/storage.dart';
import 'data/db.dart';
import 'data/repo.dart';
import 'features/home/root_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final Repo repo = Repo(await openLedgerDb());
  await cleanUpdateCache();
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
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3F7D58)),
        scaffoldBackgroundColor: const Color(0xFFF4F6F4),
      ),
      home: RootPage(repo: repo),
    );
  }
}
