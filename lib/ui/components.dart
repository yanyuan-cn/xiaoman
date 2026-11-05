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
                style: TextStyle(
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
                      ? LinearGradient(
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
      child: Divider(height: 0.6, thickness: 0.6, color: Xm.line),
    );
  }
}

/// 撤销提示：浮动、缩小、上移，避免挡住底部导航；6 秒后自动消失。
void showUndoSnack(
  BuildContext context, {
  required String message,
  required VoidCallback onUndo,
  String label = '撤销',
}) {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message, style: const TextStyle(fontSize: 13)),
      duration: const Duration(seconds: 6),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      action: SnackBarAction(label: label, onPressed: onUndo),
    ),
  );
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
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Xm.brand,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 统一界面语言（v2.0）
//
// 之前的问题：记账面板用 SegmentedButton + ChoiceChip + OutlineInputBorder，
// 资产/详情页用 AppBar + 裸 Container，首页用自绘 FAB —— 三套语言拼在一起
// 就显得割裂。下面这组组件是唯一的一套，新页面都用它们拼。
// ---------------------------------------------------------------------------

/// 圆形图标按钮：所有页面右上角的操作都用它，尺寸/底色一致。
class XmIconButton extends StatelessWidget {
  const XmIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.filled = false,
    this.size = 38,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool filled;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Widget button = Material(
      color: filled ? Xm.brandLL : Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: 19, color: Xm.ink2),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// 二级页面骨架：返回键 + 大标题 + 右侧操作，风格和记账面板的头部一致。
///
/// 用它替换 `Scaffold(appBar: AppBar(...))`，二级页和面板就不会一个像
/// Material 默认页、一个像自绘面板。
class XmPageScaffold extends StatelessWidget {
  const XmPageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.actions = const <Widget>[],
    this.bottomBar,
    this.showBack = true,
    this.padding = EdgeInsets.zero,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget> actions;
  final Widget? bottomBar;
  final bool showBack;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final double top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: Xm.bg,
      body: Column(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(10, top + 6, 10, 6),
            child: Row(
              children: <Widget>[
                if (showBack)
                  XmIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    tooltip: '返回',
                    onTap: () => Navigator.of(context).maybePop(),
                  )
                else
                  const SizedBox(width: 8),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Xm.text(19, FontWeight.w700, spacing: -0.4),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Xm.captionS,
                          ),
                        ),
                    ],
                  ),
                ),
                ...actions,
              ],
            ),
          ),
          Expanded(child: Padding(padding: padding, child: body)),
          if (bottomBar != null) bottomBar!,
        ],
      ),
    );
  }
}

/// 底部面板头部：一根把手 + 标题 + 右侧按钮。
class XmSheetHeader extends StatelessWidget {
  const XmSheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onClose,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Center(
          child: Container(
            width: 38,
            height: 4.5,
            margin: const EdgeInsets.only(top: 8, bottom: 10),
            decoration: BoxDecoration(
              color: Xm.isDark ? const Color(0xFF33443B) : const Color(0xFFD8E0DA),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 6),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title,
                        style: Xm.text(18, FontWeight.w700, spacing: -0.4)),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle!, style: Xm.captionS),
                      ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
              if (onClose != null)
                XmIconButton(
                  icon: Icons.close_rounded,
                  tooltip: '关闭',
                  onTap: onClose,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 分段选择：支出 / 收入 / 转账。滑块是一个元素在移动，不是三块各自变色。
class XmSegmented<T> extends StatelessWidget {
  const XmSegmented({
    super.key,
    required this.values,
    required this.labels,
    required this.value,
    required this.onChanged,
    this.height = 38,
  });

  final List<T> values;
  final List<String> labels;
  final T value;
  final ValueChanged<T> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final int index = values.indexOf(value).clamp(0, values.length - 1);
    return Container(
      height: height,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Xm.isDark ? Xm.surface2 : const Color(0xFFEDF1EC),
        borderRadius: BorderRadius.circular(Xm.rSeg),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final double slot = c.maxWidth / values.length;
          return Stack(
            children: <Widget>[
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: XmEase.e2,
                left: slot * index,
                top: 0,
                width: slot,
                height: c.maxHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Xm.surface,
                    borderRadius: BorderRadius.circular(Xm.rSegItem),
                    boxShadow: Xm.cardShadow,
                  ),
                ),
              ),
              Row(
                children: <Widget>[
                  for (int i = 0; i < values.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(values[i]),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: Xm.text(
                              14,
                              i == index ? FontWeight.w700 : FontWeight.w500,
                              color: i == index ? Xm.ink : Xm.ink3,
                            ),
                            child: Text(labels[i]),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 可选标签（分类、账户、状态都用同一个）。选中是品牌绿实心。
class XmChoice extends StatelessWidget {
  const XmChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.leading,
    this.dense = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? leading;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 11 : 14,
          vertical: dense ? 6 : 8.5,
        ),
        decoration: BoxDecoration(
          color: selected ? Xm.brand : Xm.surface,
          borderRadius: BorderRadius.circular(dense ? 9 : 12),
          border: Border.all(
            color: selected ? Colors.transparent : Xm.line,
            width: 1,
          ),
        ),
        child: Text(
          leading == null ? label : '$leading $label',
          style: Xm.text(
            dense ? 12.5 : 13.5,
            selected ? FontWeight.w600 : FontWeight.w500,
            color: selected
                ? (Xm.isDark ? const Color(0xFF08120D) : Colors.white)
                : Xm.ink2,
          ),
        ),
      ),
    );
  }
}

/// 统一的输入框：到底部面板和二级页里长得一样。
class XmField extends StatelessWidget {
  const XmField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.maxLength,
    this.keyboardType,
    this.helper,
    this.onChanged,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final int? maxLength;
  final TextInputType? keyboardType;
  final String? helper;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text(label!,
                style: Xm.text(12, FontWeight.w500, color: Xm.ink3)),
          ),
        Container(
          decoration: BoxDecoration(
            color: Xm.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Xm.line),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            controller: controller,
            maxLength: maxLength,
            keyboardType: keyboardType,
            onChanged: onChanged,
            textInputAction: textInputAction,
            style: Xm.text(14.5, FontWeight.w500, height: 1.3),
            decoration: InputDecoration(
              counterText: '',
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 13),
              hintText: hint,
              hintStyle: Xm.text(14, FontWeight.w400, color: Xm.ink3),
            ),
          ),
        ),
        if (helper != null)
          Padding(
            padding: const EdgeInsets.only(left: 2, top: 5),
            child: Text(helper!,
                style: Xm.text(11.5, FontWeight.w400, color: Xm.ink3)),
          ),
      ],
    );
  }
}

/// 首页二级菜单：横向滚动的分类标签。
class XmScrollTabs extends StatelessWidget {
  const XmScrollTabs({
    super.key,
    required this.items,
    required this.index,
    required this.onTap,
  });

  final List<String> items;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (BuildContext _, int __) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int i) {
          final bool selected = i == index;
          return Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: selected ? Xm.ink : Xm.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? Colors.transparent : Xm.line,
                  ),
                ),
                child: Text(
                  items[i],
                  style: Xm.text(
                    13,
                    selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? Xm.bg : Xm.ink2,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 列表行里的情绪 / 状态小标记。
class XmMoodBadge extends StatelessWidget {
  const XmMoodBadge(this.emoji, {super.key, this.label});

  final String emoji;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: label == null ? 5 : 7, vertical: 2),
      decoration: BoxDecoration(
        color: Xm.isDark ? Xm.surface2 : const Color(0xFFF1F4EF),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label == null ? emoji : '$emoji $label',
        style: Xm.text(11, FontWeight.w500, color: Xm.ink3, height: 1.3),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 页面骨架与「可展开」结构（v2.1）
//
// 视觉稿的核心是两层：顶部的「额度卡」和下面的「分类卡」都可以原地展开，
// 展开的内容属于同一个页面，不跳转。用 [XmExpandable] 统一这个动作。
// ---------------------------------------------------------------------------

/// 带 kicker 的页面头：一行小字 + 一行大标题 + 右侧圆角方块按钮。
class XmHeader extends StatelessWidget {
  const XmHeader({
    super.key,
    required this.title,
    this.kicker,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(20, 2, 20, 6),
  });

  final String title;
  final String? kicker;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (kicker != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      kicker!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Xm.text(12, FontWeight.w400,
                          spacing: 0.4, color: Xm.ink3),
                    ),
                  ),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Xm.text(24, FontWeight.w700,
                      spacing: -0.4, height: 1.15),
                ),
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 10),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// 头部右侧的圆角方块按钮（视觉稿里的 .avbtn）。
class XmAvatarButton extends StatelessWidget {
  const XmAvatarButton({
    super.key,
    this.label,
    this.icon,
    this.onTap,
    this.tooltip,
    this.inverted = false,
  });

  final String? label;
  final IconData? icon;
  final VoidCallback? onTap;
  final String? tooltip;

  /// true = 放在深绿卡上（半透明白）
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    final Widget box = Material(
      color: inverted
          ? Colors.white.withValues(alpha: 0.16)
          : Xm.brandLL,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Center(
            child: icon != null
                ? Icon(icon,
                    size: 19,
                    color: inverted ? Colors.white : Xm.brand)
                : Text(
                    label ?? '',
                    style: Xm.text(15, FontWeight.w600,
                        color: inverted ? Colors.white : Xm.brand),
                  ),
          ),
        ),
      ),
    );
    if (tooltip == null) return box;
    return Tooltip(message: tooltip!, child: box);
  }
}

/// 原地展开 / 收起：高度从 0 到内容高度，同时淡入。
///
/// 展开时子组件仍然完整布局（只是被裁掉），所以宽高不会在动画中间跳变，
/// 这是它比 AnimatedCrossFade 稳的地方。
class XmExpandable extends StatelessWidget {
  const XmExpandable({
    super.key,
    required this.expanded,
    required this.child,
    this.duration = const Duration(milliseconds: 380),
  });

  final bool expanded;
  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final bool reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced) {
      return expanded
          ? child
          : const SizedBox(width: double.infinity, height: 0);
    }
    return AnimatedAlign(
      alignment: Alignment.topCenter,
      heightFactor: expanded ? 1 : 0,
      duration: duration,
      curve: XmEase.e2,
      child: ClipRect(
        child: AnimatedOpacity(
          opacity: expanded ? 1 : 0,
          duration: duration,
          curve: Curves.easeOut,
          child: child,
        ),
      ),
    );
  }
}

/// 展开指示箭头：展开时转 180°。
class XmChevron extends StatelessWidget {
  const XmChevron({super.key, required this.expanded, this.size = 14, this.color});

  final bool expanded;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: expanded ? 0.5 : 0,
      duration: const Duration(milliseconds: 340),
      curve: XmEase.e2,
      child: Icon(
        Icons.keyboard_arrow_down_rounded,
        size: size + 3,
        color: color ?? const Color(0xFFC4CEC7),
      ),
    );
  }
}

/// 分类首字方块（彩色，带一道斜向高光）。
class XmColorBlock extends StatelessWidget {
  const XmColorBlock(
    this.text, {
    super.key,
    required this.color,
    this.size = 34,
    this.radius = 12,
    this.fontSize,
  });

  final String text;
  final Color color;
  final double size;
  final double radius;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: const Alignment(-0.6, -1),
                  end: const Alignment(0.3, 0.45),
                  colors: <Color>[
                    Colors.white.withValues(alpha: 0.28),
                    Colors.transparent,
                  ],
                  stops: const <double>[0, 0.55],
                ),
              ),
            ),
          ),
          Center(
            child: Text(
              text.isEmpty ? '·' : text.substring(0, 1),
              style: Xm.text(fontSize ?? 13, FontWeight.w600,
                  color: Colors.white, height: 1),
            ),
          ),
        ],
      ),
    );
  }
}

/// 分区标题：左边粗一点，右边灰色的补充说明。
class XmSect extends StatelessWidget {
  const XmSect(this.title, {super.key, this.trailing, this.action});

  final String title;
  final String? trailing;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 5),
      child: Row(
        children: <Widget>[
          Text(title,
              style: Xm.text(12, FontWeight.w600, spacing: 0.2, color: Xm.ink)),
          const Spacer(),
          if (action != null) action!
          else if (trailing != null)
            Text(trailing!,
                style: Xm.text(11.5, FontWeight.w400,
                    spacing: 0.2, color: Xm.ink3)),
        ],
      ),
    );
  }
}

/// 值不值：三档（值得 / 一般 / 后悔）。再点一下取消。
class XmWorthPicker extends StatelessWidget {
  const XmWorthPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// 0 未标，1 值得，2 一般，3 后悔（与 [XmMood.code] 一致）。
  final int value;
  final ValueChanged<int> onChanged;

  static const List<List<String>> _labels = <List<String>>[
    <String>['😊', '值得'],
    <String>['😐', '一般'],
    <String>['😞', '后悔'],
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (int i = 0; i < 3; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(value == i + 1 ? 0 : i + 1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 11),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: value == i + 1
                      ? (Xm.isDark
                          ? Xm.surface2
                          : Xm.worthBg[i])
                      : (Xm.isDark ? Xm.surface2 : const Color(0xFFF2F4F0)),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: value == i + 1
                        ? (Xm.isDark ? Xm.ink3 : Xm.worthInk[i]).withValues(alpha: 0.35)
                        : Colors.transparent,
                    width: 1.4,
                  ),
                ),
                child: Text(
                  '${_labels[i][0]} ${_labels[i][1]}',
                  style: Xm.text(
                    13.5,
                    FontWeight.w600,
                    spacing: 0.2,
                    color: value == i + 1
                        ? (Xm.isDark ? Xm.ink : Xm.worthInk[i])
                        : Xm.ink2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 场景 chips（当时在干嘛）。单选，再点取消。
class XmSceneChips extends StatelessWidget {
  const XmSceneChips({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<String> options;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final String s in options)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(value == s ? null : s),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 190),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              decoration: BoxDecoration(
                color: value == s ? Xm.brandLL : (Xm.isDark ? Xm.surface2 : const Color(0xFFF4F6F2)),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: value == s
                      ? Xm.brand.withValues(alpha: 0.22)
                      : Colors.transparent,
                ),
              ),
              child: Text(
                s,
                style: Xm.text(
                  12.5,
                  value == s ? FontWeight.w600 : FontWeight.w500,
                  color: value == s ? Xm.brand : Xm.ink2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}


/// 左滑露出「删除」按钮（不是直接滑走，避免误删）。
///
/// 点删除后由调用方负责真正的删除与撤销提示；这里只负责收起。
class XmSwipeDelete extends StatefulWidget {
  const XmSwipeDelete({
    super.key,
    required this.child,
    required this.onDelete,
    this.actionWidth = 84,
    this.label = '删除',
  });

  final Widget child;
  final Future<void> Function() onDelete;
  final double actionWidth;
  final String label;

  @override
  State<XmSwipeDelete> createState() => _XmSwipeDeleteState();
}

class _XmSwipeDeleteState extends State<XmSwipeDelete>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  )..addListener(() => setState(() => _offset = _anim.value));

  late Animation<double> _anim = const AlwaysStoppedAnimation<double>(0);
  double _offset = 0;
  bool _busy = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _snap(double to) {
    _anim = Tween<double>(begin: _offset, end: to).animate(
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic),
    );
    _c.forward(from: 0);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_c.isAnimating) _c.stop();
    setState(() {
      _offset = (_offset + d.delta.dx).clamp(-widget.actionWidth, 0.0);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    final bool open = _offset < -widget.actionWidth * 0.45;
    _snap(open ? -widget.actionWidth : 0);
  }

  Future<void> _delete() async {
    if (_busy) return;
    _busy = true;
    _snap(0);
    await widget.onDelete();
    _busy = false;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: widget.actionWidth,
                child: Material(
                  color: Xm.isDark
                      ? const Color(0xFF3A221F)
                      : const Color(0xFFF6E7E4),
                  child: InkWell(
                    onTap: _delete,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(Icons.delete_outline_rounded,
                            size: 20, color: Xm.expense),
                        const SizedBox(height: 2),
                        Text(
                          widget.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Xm.expense,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          GestureDetector(
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            onTap: _offset == 0 ? null : () => _snap(0),
            child: Transform.translate(
              offset: Offset(_offset, 0),
              // 滑开时用白色垫底，避免透出下面的删除按钮
              child: ColoredBox(color: Xm.surface, child: widget.child),
            ),
          ),
        ],
      ),
    );
  }
}

