import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// 撒彩带：庆祝「已买」这种小成就。
///
/// 不引第三方库，纯 CustomPainter + 一条 AnimationController：
/// 60 片纸屑从顶部往下落，边落边转，1.8 秒后自动移除。
Future<void> showConfetti(
  BuildContext context, {
  String? message,
}) async {
  final OverlayState? overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (BuildContext _) => _ConfettiLayer(
      message: message,
      onDone: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _ConfettiLayer extends StatefulWidget {
  const _ConfettiLayer({this.message, required this.onDone});

  final String? message;
  final VoidCallback onDone;

  @override
  State<_ConfettiLayer> createState() => _ConfettiLayerState();
}

class _ConfettiLayerState extends State<_ConfettiLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  late final List<_Piece> _pieces;

  @override
  void initState() {
    super.initState();
    final math.Random rnd = math.Random();
    const List<Color> palette = <Color>[
      Color(0xFF3A7C5F),
      Color(0xFFD9AF6C),
      Color(0xFFE07A6E),
      Color(0xFF5A7D9A),
      Color(0xFFC4783E),
      Color(0xFFF0D7A6),
    ];
    _pieces = List<_Piece>.generate(64, (int i) {
      return _Piece(
        x: rnd.nextDouble(),
        delay: rnd.nextDouble() * 0.25,
        speed: 0.75 + rnd.nextDouble() * 0.5,
        drift: (rnd.nextDouble() - 0.5) * 0.35,
        spin: (rnd.nextDouble() - 0.5) * 10,
        size: 6 + rnd.nextDouble() * 6,
        color: palette[rnd.nextInt(palette.length)],
        round: rnd.nextBool(),
      );
    });
    _c.addStatusListener((AnimationStatus s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (BuildContext context, Widget? _) {
          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: CustomPaint(
                  painter: _ConfettiPainter(
                    pieces: _pieces,
                    t: _c.value,
                  ),
                ),
              ),
              if (widget.message != null)
                Positioned(
                  left: 0,
                  right: 0,
                  top: MediaQuery.sizeOf(context).height * 0.36,
                  child: Opacity(
                    opacity: (_c.value * 2.4).clamp(0.0, 1.0) *
                        (1 - ((_c.value - 0.65) / 0.35).clamp(0.0, 1.0)),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 10),
                        decoration: BoxDecoration(
                          color: Xm.isDark
                              ? const Color(0xF01B2721)
                              : const Color(0xF0FFFFFF),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: Xm.heroShadow,
                        ),
                        child: Text(
                          widget.message!,
                          style: Xm.text(16, FontWeight.w700, spacing: 0.2),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Piece {
  const _Piece({
    required this.x,
    required this.delay,
    required this.speed,
    required this.drift,
    required this.spin,
    required this.size,
    required this.color,
    required this.round,
  });

  final double x;
  final double delay;
  final double speed;
  final double drift;
  final double spin;
  final double size;
  final Color color;
  final bool round;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.pieces, required this.t});

  final List<_Piece> pieces;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint();
    for (final _Piece p in pieces) {
      final double local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final double y = -40 + (size.height + 80) * local * p.speed;
      final double x = (p.x + p.drift * local) * size.width;
      final double angle = p.spin * local * math.pi;
      // 最后 25% 淡出
      final double opacity = local > 0.75 ? (1 - (local - 0.75) / 0.25) : 1.0;
      paint.color = p.color.withValues(alpha: opacity.clamp(0.0, 1.0));

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRect(
          Rect.fromCenter(
              center: Offset.zero, width: p.size, height: p.size * 0.6),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}
