import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

/// 设计 Token：小满「Quiet Ledger」。
///
/// 全部数值来自《小满设计规范》§2，改这里就能全站生效。
/// 约定：绿色是品牌色，不是"成功"语义色；红色只给支出与负值。
class Xm {
  Xm._();

  // ---------------- 色彩（§2.1） ----------------
  static const Color bg = Color(0xFFF4F6F2);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surface2 = Color(0xFFFAFBF8);
  static const Color ink = Color(0xFF12211A);
  static const Color ink2 = Color(0xFF5B6B62);
  static const Color ink3 = Color(0xFF9AA8A0);
  static const Color line = Color(0xFFE8EDE7);

  static const Color brand = Color(0xFF2F6B4F);
  static const Color brandD = Color(0xFF1F4C37);
  static const Color brandL = Color(0xFFDCEBE1);
  static const Color brandLL = Color(0xFFEFF6F1);

  static const Color gold = Color(0xFFB08442);
  static const Color goldL = Color(0xFFF3E9D8);

  /// 支出金额、负余额。**仅此用途**（§0.3）。
  static const Color expense = Color(0xFFC0392B);
  static const Color income = Color(0xFF2F6B4F);

  /// 深绿卡上的关键数字（预算剩余、结余）
  static const Color goldOnDark = Color(0xFFF0D7A6);

  // 深色卡内的文字透明度阶梯（§2.1）
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
  static const EdgeInsets pagePadding = EdgeInsets.fromLTRB(16, 8, 16, 96);

  // ---------------- 渐变（§2.1，三张主色卡参数不同，别混用） ----------------

  /// A. 首页概览卡：右上高光 + 左下暗角 + 152° 三段渐变
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment(-0.47, -0.88),
    end: Alignment(0.47, 0.88),
    colors: <Color>[Color(0xFF37765A), Color(0xFF2B6249), Color(0xFF204E3A)],
    stops: <double>[0, 0.52, 1],
  );

  /// B. 资产净值卡：少一层暗角，155°
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

  // ---------------- 阴影（§2.5，只有三档） ----------------
  static const List<BoxShadow> cardShadow = <BoxShadow>[
    BoxShadow(color: Color(0x0A12211A), blurRadius: 2, offset: Offset(0, 1)),
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
  static TextStyle _s(
    double size,
    FontWeight weight, {
    double spacing = 0,
    Color color = ink,
    double height = 1.2,
    bool tabular = false,
  }) =>
      TextStyle(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: spacing,
        color: color,
        height: height,
        fontFeatures: tabular ? tnum : null,
      );

  /// 公开版：页面里需要微调字号时用，避免各自写 TextStyle。
  static TextStyle text(
    double size,
    FontWeight weight, {
    double spacing = 0,
    Color color = ink,
    double height = 1.2,
    bool tabular = false,
  }) =>
      _s(size, weight,
          spacing: spacing,
          color: color,
          height: height,
          tabular: tabular);

  static final TextStyle display = _s(36, FontWeight.w700,
      spacing: -1.6, color: Colors.white, height: 1, tabular: true);
  static final TextStyle amountXL = _s(34, FontWeight.w700,
      spacing: -1.2, height: 1, tabular: true);
  static final TextStyle amountL = _s(25, FontWeight.w700, spacing: -0.3);
  static final TextStyle amountM = _s(24, FontWeight.w700,
      spacing: -0.7, height: 1, tabular: true);
  static final TextStyle amountS = _s(23, FontWeight.w600,
      spacing: -0.7, color: Colors.white, height: 1, tabular: true);
  static final TextStyle amountXS = _s(18, FontWeight.w700,
      spacing: -0.3, color: goldOnDark, height: 1, tabular: true);

  static final TextStyle bodyL = _s(17, FontWeight.w600, spacing: 0.2);
  static final TextStyle bodyM = _s(16, FontWeight.w600,
      spacing: -0.4, height: 1.5, tabular: true);
  static final TextStyle body = _s(15, FontWeight.w600, spacing: -0.1, height: 1.4);
  static final TextStyle bodyS = _s(13.5, FontWeight.w600, spacing: 0.2);
  static final TextStyle captionL = _s(13, FontWeight.w600, height: 1.4);
  static final TextStyle caption = _s(12, FontWeight.w400,
      spacing: 0.4, color: ink3, height: 1.4);
  static final TextStyle captionS = _s(11.5, FontWeight.w400,
      spacing: 0.3, color: ink3, height: 1.4);
  static final TextStyle micro = _s(10.5, FontWeight.w600,
      spacing: 0.3, color: ink3, height: 1.4);

  /// 深色卡片上的标签 / 说明
  static final TextStyle onDarkLabelStyle =
      _s(11.5, FontWeight.w400, spacing: 0.6, color: onDarkLabel);

  // ---------------- ThemeData ----------------
  static ThemeData theme() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: Brightness.light,
    ).copyWith(
      primary: brand,
      surface: surface,
      onSurface: ink,
      error: expense,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: amountL,
        iconTheme: const IconThemeData(color: ink2, size: 20),
        actionsIconTheme: const IconThemeData(color: ink2, size: 20),
      ),
      dividerTheme: const DividerThemeData(color: line, thickness: 0.6, space: 1),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rCard),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: _s(13.5, FontWeight.w500, color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titleTextStyle: _s(17, FontWeight.w700),
        contentTextStyle: _s(13.5, FontWeight.w400, height: 1.6, color: ink2),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(rButton)),
          textStyle: _s(15, FontWeight.w600, spacing: 0.4),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ink2,
          textStyle: _s(14, FontWeight.w500),
        ),
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: body,
        subtitleTextStyle: captionS,
        iconColor: brand,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: brand,
        linearTrackColor: Color(0xFFEFF3EE),
      ),
      splashColor: const Color(0x0F12211A),
      highlightColor: const Color(0x0812211A),
    );
  }
}
