import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 一套调色板。浅色是设计规范原值，深色是同色相压暗后的对应值。
class XmPalette {
  const XmPalette({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.line,
    required this.brand,
    required this.brandD,
    required this.brandL,
    required this.brandLL,
    required this.gold,
    required this.goldL,
    required this.expense,
    required this.income,
    required this.warn,
  });

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color line;
  final Color brand;
  final Color brandD;
  final Color brandL;
  final Color brandLL;
  final Color gold;
  final Color goldL;
  final Color expense;
  final Color income;
  final Color warn;

  static const XmPalette light = XmPalette(
    bg: Color(0xFFF4F6F2),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFFAFBF8),
    ink: Color(0xFF12211A),
    ink2: Color(0xFF5B6B62),
    ink3: Color(0xFF9AA8A0),
    line: Color(0xFFE8EDE7),
    brand: Color(0xFF2F6B4F),
    brandD: Color(0xFF1F4C37),
    brandL: Color(0xFFDCEBE1),
    brandLL: Color(0xFFEFF6F1),
    gold: Color(0xFFB08442),
    goldL: Color(0xFFF3E9D8),
    expense: Color(0xFFC0392B),
    income: Color(0xFF2F6B4F),
    warn: Color(0xFFC0563E),
  );

  static const XmPalette dark = XmPalette(
    bg: Color(0xFF0E1613),
    surface: Color(0xFF16211C),
    surface2: Color(0xFF1B2721),
    ink: Color(0xFFE9F0EA),
    ink2: Color(0xFFA8B6AD),
    ink3: Color(0xFF71827A),
    line: Color(0xFF243029),
    brand: Color(0xFF62B48C),
    brandD: Color(0xFF2F6B4F),
    brandL: Color(0xFF1E3A2C),
    brandLL: Color(0xFF172A20),
    gold: Color(0xFFC99C58),
    goldL: Color(0xFF2A2318),
    expense: Color(0xFFE4776A),
    income: Color(0xFF6DBB91),
    warn: Color(0xFFE08A72),
  );
}

/// 设计 Token：小满「Quiet Ledger」。
///
/// 颜色是 **getter**，读当前调色板（`Xm.setDark`）；圆角/字号/渐变是常量。
/// 约定：绿色是品牌色，不是"成功"语义色；红色只给支出与负值。
class Xm {
  Xm._();

  static XmPalette _p = XmPalette.light;
  static bool _dark = false;

  static bool get isDark => _dark;

  static void setDark(bool value) {
    _dark = value;
    _p = value ? XmPalette.dark : XmPalette.light;
  }

  // ---------------- 色彩（随主题切换） ----------------
  static Color get bg => _p.bg;
  static Color get surface => _p.surface;
  static Color get surface2 => _p.surface2;
  static Color get ink => _p.ink;
  static Color get ink2 => _p.ink2;
  static Color get ink3 => _p.ink3;
  static Color get line => _p.line;
  static Color get brand => _p.brand;
  static Color get brandD => _p.brandD;
  static Color get brandL => _p.brandL;
  static Color get brandLL => _p.brandLL;
  static Color get gold => _p.gold;
  static Color get goldL => _p.goldL;
  static Color get expense => _p.expense;
  static Color get income => _p.income;

  /// 深绿卡上的关键数字（预算剩余、结余）—— 深浅色都用这个金色
  static const Color goldOnDark = Color(0xFFF0D7A6);

  /// 超支 / 负值 / 危险操作。比 [expense] 更暗一点，用在浅底上不刺眼。
  static Color get warn => _p.warn;

  /// 分类色板：分类首字方块按 id 取色，同一个分类永远同一个颜色。
  /// 前三个是主色（赭石 / 褐 / 灰蓝），后面是备用。
  static List<Color> get catPalette => _dark
      ? const <Color>[
          Color(0xFFD08C52),
          Color(0xFFA98063),
          Color(0xFF6E92AE),
          Color(0xFF8FA391),
          Color(0xFFBE86A0),
          Color(0xFF9AA69F),
        ]
      : const <Color>[
          Color(0xFFC4783E),
          Color(0xFF8C6A4F),
          Color(0xFF5A7D9A),
          Color(0xFF7B8F7C),
          Color(0xFFA8748A),
          Color(0xFF8A9690),
        ];

  /// 按 id 稳定取色。
  static Color catColor(int? id) {
    final List<Color> p = catPalette;
    if (id == null) return p[5];
    return p[(id - 1) % p.length];
  }

  /// 「值不值」三档的取色（背景 / 文字）。
  static const List<Color> worthBg = <Color>[
    Color(0xFFE5F0E9),
    Color(0xFFEDEFF0),
    Color(0xFFFBEBE6),
  ];
  static const List<Color> worthInk = <Color>[
    Color(0xFF1F4C37),
    Color(0xFF4A5A62),
    Color(0xFFA8432C),
  ];

  // 深色卡内的文字透明度阶梯（卡片本身在两种模式下都是墨绿）
  static const Color onDarkLabel = Color(0x9EFFFFFF); // .62
  static const Color onDarkNote = Color(0x8CFFFFFF); // .55
  static const Color onDarkStrong = Color(0xF0FFFFFF); // .94
  static const Color onDarkLine = Color(0x21FFFFFF); // .13

  // ---------------- 圆角（§2.4） ----------------
  static const double rHero = 26;
  static const double rCard = 22;
  static const double rProfile = 20;
  static const double rIconLg = 13;
  static const double rIconSm = 11;
  static const double rChip = 11;
  static const double rSeg = 12;
  static const double rSegItem = 9;
  static const double rBar = 3;
  static const double rButton = 16;

  // ---------------- 间距（§2.3） ----------------
  static const double gutter = 16;

  // ---------------- 渐变（§2.1，三张主色卡参数不同，别混用） ----------------

  /// A. 首页概览卡
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment(-0.47, -0.88),
    end: Alignment(0.47, 0.88),
    colors: <Color>[Color(0xFF37765A), Color(0xFF2B6249), Color(0xFF204E3A)],
    stops: <double>[0, 0.52, 1],
  );

  /// B. 资产净值卡
  static const LinearGradient assetGradient = LinearGradient(
    begin: Alignment(-0.42, -0.91),
    end: Alignment(0.42, 0.91),
    colors: <Color>[Color(0xFF37765A), Color(0xFF2B6249), Color(0xFF1F4C37)],
    stops: <double>[0, 0.55, 1],
  );

  /// C. 我的页头像卡
  static const LinearGradient profileGradient = LinearGradient(
    begin: Alignment(-0.42, -0.91),
    end: Alignment(0.42, 0.91),
    colors: <Color>[Color(0xFF3A7A5D), Color(0xFF255039)],
  );

  /// D. 主按钮 / FAB
  static const LinearGradient buttonGradient = LinearGradient(
    begin: Alignment(-0.5, -0.87),
    end: Alignment(0.5, 0.87),
    colors: <Color>[Color(0xFF3A7C5F), Color(0xFF235440)],
  );

  /// 进度条填充（金）
  static const LinearGradient barGold = LinearGradient(
    colors: <Color>[Color(0xFFF2DCB0), Color(0xFFD9AF6C)],
  );

  /// 深绿卡上的进度条：比 [barGold] 更亮更黄一点，在深底上看得清
  static const LinearGradient barGoldOnDark = LinearGradient(
    colors: <Color>[Color(0xFFFFE7BE), Color(0xFFE9B96F)],
  );

  // ---------------- 阴影（§2.5，只有三档） ----------------
  static List<BoxShadow> get cardShadow => <BoxShadow>[
        BoxShadow(
          color: _dark ? const Color(0x40000000) : const Color(0x0A12211A),
          blurRadius: _dark ? 2 : 2,
          offset: const Offset(0, 1),
        ),
      ];

  static const List<BoxShadow> heroShadow = <BoxShadow>[
    BoxShadow(
        color: Color(0x731F4C37), blurRadius: 30, spreadRadius: -12,
        offset: Offset(0, 12)),
    BoxShadow(color: Color(0x241F4C37), blurRadius: 6, offset: Offset(0, 2)),
  ];

  static const List<BoxShadow> fabShadow = <BoxShadow>[
    BoxShadow(
        color: Color(0x8C1F4C37), blurRadius: 24, spreadRadius: -8,
        offset: Offset(0, 10)),
    BoxShadow(color: Color(0x331F4C37), blurRadius: 6, offset: Offset(0, 2)),
  ];

  // ---------------- 字体（§2.2） ----------------

  /// 金额专用：等宽数字，否则滚动时会左右跳（§0.3 硬约束）。
  static List<FontFeature> get tnum => const <FontFeature>[
        FontFeature.tabularFigures(),
      ];

  /// 临时造一个文本样式（规范里没收录的字号/颜色组合用它）。
  static TextStyle text(
    double size,
    FontWeight weight, {
    double spacing = 0,
    Color? color,
    double height = 1.2,
    bool tabular = false,
  }) =>
      TextStyle(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: spacing,
        color: color ?? ink,
        height: height,
        fontFeatures: tabular ? tnum : null,
      );

  static TextStyle get display => text(36, FontWeight.w700,
      spacing: -1.6, color: Colors.white, height: 1, tabular: true);
  static TextStyle get amountXL => text(34, FontWeight.w700,
      spacing: -1.2, height: 1, tabular: true);
  static TextStyle get amountL =>
      text(25, FontWeight.w700, spacing: -0.3);
  static TextStyle get amountM => text(24, FontWeight.w700,
      spacing: -0.7, height: 1, tabular: true);
  static TextStyle get amountS => text(23, FontWeight.w600,
      spacing: -0.7, color: Colors.white, height: 1, tabular: true);
  static TextStyle get amountXS => text(18, FontWeight.w700,
      spacing: -0.3, color: goldOnDark, height: 1, tabular: true);

  static TextStyle get bodyL => text(17, FontWeight.w600, spacing: 0.2);
  static TextStyle get bodyM => text(16, FontWeight.w600,
      spacing: -0.4, height: 1.5, tabular: true);
  static TextStyle get body =>
      text(15, FontWeight.w600, spacing: -0.1, height: 1.4);
  static TextStyle get bodyS => text(13.5, FontWeight.w600, spacing: 0.2);
  static TextStyle get captionL => text(13, FontWeight.w600, height: 1.4);
  static TextStyle get caption =>
      text(12, FontWeight.w400, spacing: 0.4, color: ink3, height: 1.4);
  static TextStyle get captionS =>
      text(11.5, FontWeight.w400, spacing: 0.3, color: ink3, height: 1.4);
  static TextStyle get micro => text(10.5, FontWeight.w600,
      spacing: 0.3, color: ink3, height: 1.4);

  /// 深色卡片上的标签 / 说明
  static TextStyle get onDarkLabelStyle =>
      text(11.5, FontWeight.w400, spacing: 0.6, color: onDarkLabel);

  // ---------------- ThemeData ----------------
  static ThemeData theme() {
    final bool dark = _dark;
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: dark ? Brightness.dark : Brightness.light,
    ).copyWith(
      primary: brand,
      surface: surface,
      onSurface: ink,
      error: expense,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text(19, FontWeight.w700, spacing: -0.4),
        iconTheme: IconThemeData(color: ink2, size: 20),
        actionsIconTheme: IconThemeData(color: ink2, size: 20),
        systemOverlayStyle: dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      dividerTheme: DividerThemeData(color: line, thickness: 0.6, space: 1),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rCard),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? surface2 : ink,
        contentTextStyle: text(13.5, FontWeight.w500,
            color: dark ? ink : Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titleTextStyle: text(17, FontWeight.w700),
        contentTextStyle: text(13.5, FontWeight.w400, height: 1.6, color: ink2),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: dark ? const Color(0xFF08120D) : Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(rButton)),
          textStyle: text(15, FontWeight.w600, spacing: 0.4,
              color: dark ? const Color(0xFF08120D) : Colors.white),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ink2,
          textStyle: text(14, FontWeight.w500, color: ink2),
        ),
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: body,
        subtitleTextStyle: captionS,
        iconColor: brand,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: brand,
        linearTrackColor: dark ? surface2 : const Color(0xFFEFF3EE),
      ),
      splashColor: dark ? const Color(0x14FFFFFF) : const Color(0x0F12211A),
      highlightColor: dark ? const Color(0x0AFFFFFF) : const Color(0x0812211A),
    );
  }
}
