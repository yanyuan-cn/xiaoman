import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/repo.dart';
import '../../ui/components.dart';
import '../assets/assets_page.dart';
import '../ledger/ledger_page.dart';
import '../profile/profile_page.dart';
import '../stats/stats_page.dart';

/// 四页骨架 + 自定义 TabBar（§4.0 / §6.2 C10）。
///
/// 页面用 Stack + 位移/透明度切换，而不是整页翻走：
/// 非活动页停在 ±22% 处并淡出，保留各自的滚动位置与状态。
class RootPage extends StatefulWidget {
  const RootPage({super.key, required this.repo});

  final Repo repo;

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage>
    with SingleTickerProviderStateMixin {
  int _index = 0;

  /// 只给「新页面」做一次轻微的淡入 + 上浮。
  ///
  /// 之前是四个页面同时做 AnimatedOpacity/AnimatedSlide：旧页一边淡出一边还在
  /// 绘制，于是出现残影，而且四个页面每帧都在走动画，低端机直接掉帧。
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );

  late final Animation<double> _fade = CurvedAnimation(
    parent: _enter,
    curve: Curves.easeOut,
  );

  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0.04, 0),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _enter, curve: XmEase.e2));

  static const List<_TabSpec> _tabs = <_TabSpec>[
    _TabSpec('首页', Icons.home_outlined, Icons.home),
    _TabSpec('资产', Icons.account_balance_wallet_outlined,
        Icons.account_balance_wallet),
    _TabSpec('统计', Icons.pie_chart_outline, Icons.pie_chart),
    _TabSpec('我的', Icons.person_outline, Icons.person),
  ];

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  void _select(int i) {
    if (i == _index) return;
    setState(() => _index = i);
    // 切换瞬间把旧页隐藏、新页从 0 开始淡入，不再有两页叠加
    _enter.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = <Widget>[
      LedgerPage(repo: widget.repo),
      AssetsPage(repo: widget.repo),
      StatsPage(repo: widget.repo),
      ProfilePage(repo: widget.repo),
    ];

    return Scaffold(
      backgroundColor: Xm.bg,
      body: Stack(
        children: <Widget>[
          for (int i = 0; i < pages.length; i++)
            // Offstage 保留页面状态，但不布局不绘制：不参与渲染就没有残影和开销
            Offstage(
              offstage: i != _index,
              child: TickerMode(
                enabled: i == _index,
                child: FadeTransition(
                  opacity: i == _index ? _fade : const AlwaysStoppedAnimation<double>(1),
                  child: SlideTransition(
                    position: i == _index ? _slide : const AlwaysStoppedAnimation<Offset>(Offset.zero),
                    child: ColoredBox(color: Xm.bg, child: pages[i]),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _TabBar(
              index: _index,
              tabs: _tabs,
              onTap: _select,
            ),
          ),
        ],
      ),
    );
  }
}

class _TabSpec {
  const _TabSpec(this.label, this.icon, this.activeIcon);

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.index,
    required this.tabs,
    required this.onTap,
  });

  final int index;
  final List<_TabSpec> tabs;
  final ValueChanged<int> onTap;

  /// 图标盒子、间隙、文字行高的固定值：滑块和图标共用同一套垂直基准，
  /// 否则滑块会像早先那样偏上（图标中心 ≠ 滑块中心）。
  static const double iconBox = 30;
  static const double gap = 4;
  static const double labelH = 14;
  static const double barH = 80;
  static const double topPad = (barH - (iconBox + gap + labelH)) / 2;

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.paddingOf(context).bottom;
    // 这里原本是 BackdropFilter 毛玻璃，是中低端机上切页掉帧的主要来源：
    // 每一帧都要把整条栏后面的内容重新模糊一遍。改成不透明底色 + 细边，
    // 视觉差别很小，但少了一整层离屏渲染。
    return RepaintBoundary(
      child: Container(
        padding: EdgeInsets.only(bottom: bottomInset),
        decoration: BoxDecoration(
          color: Xm.isDark ? const Color(0xF2121A16) : const Color(0xF2FAFBF9),
          border: Border(
            top: BorderSide(
              color:
                  Xm.isDark ? const Color(0x14FFFFFF) : const Color(0x0F12211A),
              width: 1,
            ),
          ),
        ),
        child: SizedBox(
          height: barH,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final double slot = c.maxWidth / tabs.length;
              const double pillW = 52;
              return Stack(
                children: <Widget>[
                  // 滑块是**一个**元素在四个位置间移动（§6.2 C10）
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 360),
                    curve: XmEase.e2,
                    left: slot * index + (slot - pillW) / 2,
                    top: topPad,
                    width: pillW,
                    height: iconBox,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Xm.brandL,
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),
                  Row(
                    children: <Widget>[
                      for (int i = 0; i < tabs.length; i++)
                        Expanded(
                          child: _TabItem(
                            spec: tabs[i],
                            selected: i == index,
                            onTap: () => onTap(i),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  final _TabSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = selected ? Xm.brand : Xm.ink3;
    return Semantics(
      button: true,
      selected: selected,
      label: spec.label,
      child: InkResponse(
        onTap: onTap,
        radius: 44,
        containedInkWell: false,
        child: Padding(
          padding: const EdgeInsets.only(top: _TabBar.topPad),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              // 图标在 30dp 的盒子里居中 —— 滑块也是 30dp、同一 top，天然对齐
              SizedBox(
                height: _TabBar.iconBox,
                child: Center(
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 340),
                    curve: XmEase.e4,
                    offset: selected ? const Offset(0, -0.06) : Offset.zero,
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 340),
                      curve: XmEase.e4,
                      scale: selected ? 1.06 : 1,
                      child: Icon(
                        selected ? spec.activeIcon : spec.icon,
                        size: 22,
                        color: color,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: _TabBar.gap),
              Text(
                spec.label,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.2,
                  letterSpacing: 0.3,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
