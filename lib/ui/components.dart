import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// 动效曲线库（§5.2）：只有五条，不要临时造新曲线。
class XmEase {
  XmEase._();

  static const Cubic e1 = Cubic(0.22, 1, 0.36, 1); // 入场
  static const Cubic e2 = Cubic(0.32, 0.72, 0, 1); // 位移
  static const Cubic e3 = Cubic(0.34, 1.28, 0.64, 1); // 弹性（Tab 滑块）
  static const Cubic e4 = Cubic(0.34, 1.4, 0.64, 1); // 微弹
  static const Cubic e5 = Cubic(0.34, 1.2, 0.64, 1); // 提示
}

/// 标准白卡：圆角 22、几乎看不见的阴影（§2.5）。
class XmCard extends StatelessWidget {
  const XmCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = Xm.rCard,
    this.margin = EdgeInsets.zero,
    this.clip = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final EdgeInsetsGeometry margin;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: Xm.surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: Xm.cardShadow,
      ),
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      child: Padding(padding: padding, child: child),
    );
  }
}

/// 主色卡：首页概览用 [variant] A，资产净值用 B，我的页用 C（§2.1）。
enum XmHeroVariant { home, assets, profile }

class XmHeroCard extends StatelessWidget {
  const XmHeroCard({
    super.key,
    required this.child,
    this.variant = XmHeroVariant.home,
    this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 17),
    this.margin = EdgeInsets.zero,
    this.radius = Xm.rHero,
  });

  final Widget child;
  final XmHeroVariant variant;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final LinearGradient gradient = switch (variant) {
      XmHeroVariant.home => Xm.heroGradient,
      XmHeroVariant.assets => Xm.assetGradient,
      XmHeroVariant.profile => Xm.profileGradient,
    };
    // 右上角的"光源"高光：去掉就变成普通色块了。
    final Alignment light = variant == XmHeroVariant.profile
        ? const Alignment(0.76, -0.4)
        : const Alignment(0.76, -0.36);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: Xm.heroShadow,
        gradient: gradient,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: light,
                  radius: 1.2,
                  colors: <Color>[
                    Colors.white.withValues(alpha: 0.20),
                    Colors.transparent,
                  ],
                  stops: const <double>[0, 0.62],
                ),
              ),
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// 金额文本：货币符号是主数字的 0.6 倍，且与数字基线对齐（§6.2 C04）。
class XmAmount extends StatelessWidget {
  const XmAmount({
    super.key,
    required this.text,
    this.style,
    this.currency = '¥',
    this.showCurrency = true,
    this.currencyScale = 0.6,
  });

  final String text;
  final TextStyle? style;
  final String currency;
  final bool showCurrency;
  final double currencyScale;

  @override
  Widget build(BuildContext context) {
    final TextStyle base = style ?? Xm.bodyM;
    final TextStyle cur = base.copyWith(
      fontSize: (base.fontSize ?? 16) * currencyScale,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    );
    if (!showCurrency) return Text(text, style: base, maxLines: 1);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Text(currency, style: cur),
        Text(text, style: base, maxLines: 1, softWrap: false),
      ],
    );
  }
}

/// 分类首字方块（列表左侧，§4.1）。
class XmIconBlock {
  const XmIconBlock._();

  static Widget char(String text, {double size = 38, double radius = Xm.rIconLg}) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Xm.brandLL,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        text.isEmpty ? '·' : text.substring(0, 1),
        style: TextStyle(
          fontSize: size * 0.34,
          fontWeight: FontWeight.w600,
          color: Xm.brand,
        ),
      ),
    );
  }

  static Widget icon(IconData icon,
      {double size = 34, double radius = Xm.rIconSm, double iconSize = 18}) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Xm.brandLL,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(icon, size: iconSize, color: Xm.brand),
    );
  }
}

/// 分组标题（§4.3 / §4.4 两种规格）。
class XmSectionTitle extends StatelessWidget {
  const XmSectionTitle(this.text, {super.key, this.subtitle, this.group = false});

  final String text;

  /// 右侧的计数，如「5 个账户」
  final String? subtitle;

  /// true = 我的页的索引标签（更小、字距更大）
  final bool group;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: group
          ? const EdgeInsets.fromLTRB(24, 0, 24, 7)
          : const EdgeInsets.fromLTRB(22, 6, 22, 12),
      child: Row(
        children: <Widget>[
          Text(
            text,
            style: TextStyle(
              fontSize: group ? 12 : 12.5,
              fontWeight: FontWeight.w500,
              letterSpacing: group ? 1 : 0.5,
              color: Xm.ink3,
            ),
          ),
          if (subtitle != null) ...<Widget>[
            const SizedBox(width: 6),
            Text('· $subtitle',
                style: const TextStyle(
                    fontSize: 12, color: Xm.ink3, letterSpacing: 0.5)),
          ],
        ],
      ),
    );
  }
}

/// 细进度条（§4.1 预算条 / 分类余额条）。
class XmProgressBar extends StatelessWidget {
  const XmProgressBar({
    super.key,
    required this.value,
    this.height = 6,
    this.track = const Color(0x29FFFFFF),
    this.fill,
    this.overdue = false,
  });

  final double value;
  final double height;
  final Color track;
  final Gradient? fill;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final double v = value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: ColoredBox(color: track)),
            FractionallySizedBox(
              widthFactor: v,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: overdue
                      ? const LinearGradient(
                          colors: <Color>[Color(0xFFE07A6E), Xm.expense])
                      : (fill ?? Xm.barGold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 入场动画：上浮 + 淡入，按 index 交错（§5.4.1）。
///
/// 只对前 8 条生效，再多的直接显示——列表长了不会拖累首帧（§5.5）。
class XmEntrance extends StatefulWidget {
  const XmEntrance({
    super.key,
    required this.child,
    this.index = 0,
    this.step = 45,
    this.base = 60,
    this.duration = 500,
    this.offsetY = 14,
  });

  final Widget child;
  final int index;
  final int step;
  final int base;
  final int duration;
  final double offsetY;

  @override
  State<XmEntrance> createState() => _XmEntranceState();
}

class _XmEntranceState extends State<XmEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.duration),
  );
  Timer? _timer;
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_reduced) {
      _c.value = 1;
      return;
    }
    if (_c.value == 0 && _c.isDismissed && _timer == null) {
      final int delay = widget.base + (widget.index.clamp(0, 8)) * widget.step;
      if (delay <= 0) {
        _c.forward();
      } else {
        _timer = Timer(Duration(milliseconds: delay), () {
          if (mounted) _c.forward();
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Animation<double> curved =
        CurvedAnimation(parent: _c, curve: XmEase.e1);
    return AnimatedBuilder(
      animation: curved,
      builder: (BuildContext context, Widget? child) {
        final double t = curved.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, widget.offsetY * (1 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// 分割线：视觉 0.6dp，左内缩可避开图标（§2.7）。
class XmDivider extends StatelessWidget {
  const XmDivider({super.key, this.indent = 16, this.endIndent = 16});

  final double indent;
  final double endIndent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.only(start: indent, end: endIndent),
      child: const Divider(height: 0.6, thickness: 0.6, color: Xm.line),
    );
  }
}

/// 小标签（如期间的「本月」状态指示，§4.1）。
class XmTag extends StatelessWidget {
  const XmTag(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: Xm.brandLL,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Xm.brand,
        ),
      ),
    );
  }
}
