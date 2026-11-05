import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// 全局动效层：所有「二级界面」都从被点的那一行里长出来。
///
/// 做法是容器的做派（Material container transform）：一个圆角面从源矩形
/// 长到目标矩形，内容随后淡入。这样不用对页面做非等比缩放，文字不会在
/// 动画中间被拉扁，低端机也不过是画一个矩形 + 一层透明度。

/// 取某个 widget 在屏幕上的矩形；拿不到就返回 null。
Rect? xmGlobalRect(GlobalKey? key) {
  final BuildContext? ctx = key?.currentContext;
  if (ctx == null) return null;
  final RenderObject? ro = ctx.findRenderObject();
  if (ro is! RenderBox || !ro.hasSize) return null;
  final Offset topLeft = ro.localToGlobal(Offset.zero);
  return topLeft & ro.size;
}

/// 单一转场：圆角面从 [begin] 长到 [end]，内容在中段淡入。
///
/// 反着播就是「缩回那一行」，不需要第二套代码。
class XmExpandTransition extends StatelessWidget {
  const XmExpandTransition({
    super.key,
    required this.animation,
    required this.begin,
    required this.end,
    required this.child,
    this.beginRadius = 18,
    this.endRadius = 0,
    this.surface,
    this.scrim = true,
  });

  final Animation<double> animation;

  /// 起始矩形（被点的行在屏幕上的位置）。
  final Rect begin;

  /// 结束矩形（整屏，或底部面板的矩形）。
  final Rect end;

  final Widget child;
  final double beginRadius;
  final double endRadius;

  /// 长出来的那层底色；默认用卡片色。
  final Color? surface;

  /// 是否在背后压一层很淡的遮罩，让"从列表里长出来"更有层次。
  final bool scrim;

  @override
  Widget build(BuildContext context) {
    final bool reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced) return child;

    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? _) {
        final double raw = animation.value;
        final double t = Curves.easeOutCubic.transform(raw);
        final Rect rect = Rect.lerp(begin, end, t) ?? end;
        final double radius =
            lerpDouble(beginRadius, endRadius, t) ?? endRadius;
        // 内容晚一点出现：先看到"面"在长，再看到内容，符合容器变换的节奏。
        final double content = ((raw - 0.28) / 0.72).clamp(0.0, 1.0);
        final double curved = Curves.easeOutCubic.transform(content);

        return Stack(
          children: <Widget>[
            if (scrim)
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.16 * (1 - t)),
                  ),
                ),
              ),
            Positioned.fromRect(
              rect: rect,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: surface ?? Xm.surface,
                    borderRadius: BorderRadius.circular(radius),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                ignoring: raw < 0.9,
                child: Opacity(
                  opacity: curved,
                  child: Transform.scale(
                    scale: 0.985 + 0.015 * curved,
                    child: child,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 「从这一行放大进来」的页面路由。
///
/// 用法：
/// ```dart
/// final Rect? from = xmGlobalRect(rowKey);
/// Navigator.of(context).push(XmExpandRoute<void>(from: from, builder: ...));
/// ```
class XmExpandRoute<T> extends PageRouteBuilder<T> {
  XmExpandRoute({
    required WidgetBuilder builder,
    Rect? from,
    RouteSettings? settings,
  }) : super(
          settings: settings,
          pageBuilder: (BuildContext context, Animation<double> a,
                  Animation<double> s) =>
              builder(context),
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 240),
          transitionsBuilder: (BuildContext context, Animation<double> a,
              Animation<double> s, Widget child) {
            final Size size = MediaQuery.sizeOf(context);
            // 没有来源行的页面（搜索、导入、预算…）用轻量的上浮淡入，
            // 不要硬套"从中间放大"，那样反而奇怪。
            if (from == null) {
              return FadeTransition(
                opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.03),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
                  child: child,
                ),
              );
            }
            return XmExpandTransition(
              animation: a,
              begin: from!,
              end: Offset.zero & size,
              child: child,
            );
          },
        );
}

/// 底部面板：也从触发它的那条「记账条」长出来，而不是从屏幕底部滑上来。
///
/// [heightFactor] 是面板占屏幕高度的比例，必须和面板自身高度一致，
/// 否则动画终点和实际高度对不上，会看到一次跳变。
Future<T?> showXmExpandSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Rect? from,
  double heightFactor = 0.86,
  Color barrierColor = const Color(0x6B0A120E),
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: barrierColor,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (BuildContext context, Animation<double> a,
        Animation<double> s) {
      // 面板本身没有 Scaffold，需要一层 Material 给 InkWell / 输入框用。
      return Material(
        type: MaterialType.transparency,
        child: builder(context),
      );
    },
    transitionBuilder: (BuildContext context, Animation<double> a,
        Animation<double> s, Widget child) {
      final Size size = MediaQuery.sizeOf(context);
      final double h = size.height * heightFactor;
      return XmExpandTransition(
        animation: a,
        begin: from ??
            Rect.fromLTWH(
                16, size.height - h - 40, size.width - 32, 56),
        end: Rect.fromLTWH(0, size.height - h, size.width, h),
        beginRadius: 18,
        endRadius: 26,
        scrim: false,
        child: child,
      );
    },
  );
}
