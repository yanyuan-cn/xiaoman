import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/background_update.dart';
import 'core/display.dart';
import 'core/storage.dart';
import 'core/theme.dart';
import 'core/theme_mode.dart';
import 'data/db.dart';
import 'data/repo.dart';
import 'features/home/root_page.dart';
import 'state/data_bus.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final Repo repo = Repo(await openLedgerDb());
  ThemeController.instance
      .setMode(ThemeController.parse(await repo.getSetting('theme_mode')));
  await cleanUpdateCache();
  try {
    await repo.runDueRecurringRules();
  } catch (_) {
    // 定期扣款失败不影响启动。
  }
  await applyHighRefreshRate();
  runApp(XiaomanApp(repo: repo));
  // 后台静默检查更新：不阻塞启动，失败也无感
  BackgroundUpdate.check(repo);
}

class XiaomanApp extends StatefulWidget {
  const XiaomanApp({super.key, required this.repo});

  final Repo repo;

  @override
  State<XiaomanApp> createState() => _XiaomanAppState();
}

class _XiaomanAppState extends State<XiaomanApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ThemeController.instance.addListener(_onThemeChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 回到前台时刷新一次数据，避免跨天（比如凌晨记账）后首页还是昨天的
    if (state == AppLifecycleState.resumed) DataBus.instance.bump();
  }

  @override
  void dispose() {
    ThemeController.instance.removeListener(_onThemeChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangePlatformBrightness() {
    // 「跟随系统」时，系统切换深浅色要立刻生效
    if (mounted && ThemeController.instance.mode == XmThemeMode.system) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final XmThemeMode mode = ThemeController.instance.mode;
    final bool platformDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    Xm.setDark(mode == XmThemeMode.dark ||
        (mode == XmThemeMode.system && platformDark));

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
      home: RootPage(repo: widget.repo),
    );
  }
}
