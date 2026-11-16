import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/theme.dart';

/// 裁切结果：把原图里的一块矩形区域另存成新文件。
///
/// 不引第三方裁切库（要改 gradle、加 Activity），这里用 InteractiveViewer
/// 做手势，再用 dart:ui 的 drawImageRect 真正裁出像素。
Future<String?> cropImageToFile(
  BuildContext context,
  String srcPath, {
  double aspect = 4 / 3,
}) {
  return Navigator.of(context).push<String>(
    PageRouteBuilder<String>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (BuildContext c, Animation<double> a, Animation<double> s) =>
          _CropPage(srcPath: srcPath, aspect: aspect),
      transitionsBuilder: (BuildContext c, Animation<double> a,
              Animation<double> s, Widget child) =>
          FadeTransition(opacity: a, child: child),
    ),
  );
}

class _CropPage extends StatefulWidget {
  const _CropPage({required this.srcPath, required this.aspect});

  final String srcPath;
  final double aspect;

  @override
  State<_CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<_CropPage> {
  final GlobalKey _viewportKey = GlobalKey();
  final TransformationController _tc = TransformationController();

  ui.Image? _image;
  Size _displaySize = Size.zero;
  Rect _frame = Rect.zero;
  bool _transformInited = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  Future<void> _decode() async {
    try {
      final Uint8List bytes = await File(widget.srcPath).readAsBytes();
      final ui.Image img = await decodeImageFromList(bytes);
      if (!mounted) return;
      setState(() => _image = img);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '这张图打不开：$e');
    }
  }

  /// 视口和图片尺寸确定后，把图片按「铺满裁切框」放好，并居中。
  ///
  /// 只改普通字段，不动 [TransformationController]——那个会通知监听者，
  /// 在 build 期间调用会触发 setState during build。初始位移放到下一帧做。
  void _layout(Size viewport) {
    final ui.Image? img = _image;
    if (img == null) return;

    const double inset = 20;
    final double fw = viewport.width - inset * 2;
    final double fh = math.min(fw / widget.aspect, viewport.height - 160);
    _frame = Rect.fromCenter(
      center: Offset(viewport.width / 2, viewport.height / 2),
      width: fw,
      height: math.max(fh, 80),
    );

    final double scale = math.max(
      _frame.width / img.width,
      _frame.height / img.height,
    );
    _displaySize = Size(img.width * scale, img.height * scale);

    if (!_transformInited) {
      _transformInited = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _displaySize == Size.zero) return;
        _tc.value = Matrix4.translationValues(
          _frame.center.dx - _displaySize.width / 2,
          _frame.center.dy - _displaySize.height / 2,
          0,
        );
      });
    }
  }

  /// 把视口里的裁切框映射回原图像素，再真的裁出来
  Future<void> _apply() async {
    final ui.Image? img = _image;
    if (img == null || _busy) return;
    setState(() => _busy = true);
    try {
      final Matrix4 inv = Matrix4.inverted(_tc.value);
      // 视口坐标 -> 子控件（显示尺寸）坐标
      final Offset tl = MatrixUtils.transformPoint(inv, _frame.topLeft);
      final Offset br = MatrixUtils.transformPoint(inv, _frame.bottomRight);

      final double sx = img.width / _displaySize.width;
      final double sy = img.height / _displaySize.height;

      final double left = (tl.dx * sx).clamp(0.0, img.width.toDouble());
      final double top = (tl.dy * sy).clamp(0.0, img.height.toDouble());
      final double right = (br.dx * sx).clamp(0.0, img.width.toDouble());
      final double bottom = (br.dy * sy).clamp(0.0, img.height.toDouble());

      final double w = right - left;
      final double h = bottom - top;
      if (w < 8 || h < 8) {
        setState(() => _busy = false);
        _snack('裁出来的图太小了，换个位置试试');
        return;
      }

      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(left, top, w, h),
        Rect.fromLTWH(0, 0, w, h),
        Paint()..filterQuality = FilterQuality.high,
      );
      final ui.Image out = await recorder
          .endRecording()
          .toImage(w.round().clamp(1, 4096), h.round().clamp(1, 4096));
      final ByteData? data =
          await out.toByteData(format: ui.ImageByteFormat.png);
      out.dispose();
      if (data == null) throw StateError('编码失败');

      final Directory dir = await getApplicationDocumentsDirectory();
      final Directory wishDir = Directory('${dir.path}/wishes');
      if (!wishDir.existsSync()) wishDir.createSync(recursive: true);
      final String dest =
          '${wishDir.path}/${DateTime.now().millisecondsSinceEpoch}_c.png';
      await File(dest).writeAsBytes(data.buffer.asUint8List());

      if (!mounted) return;
      Navigator.of(context).pop(dest);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('裁切失败：$e');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C1411),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
              child: Row(
                children: <Widget>[
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 22),
                  ),
                  const Spacer(),
                  const Text('调整裁切范围',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  TextButton(
                    onPressed: _busy ? null : _apply,
                    child: Text(_busy ? '处理中…' : '使用',
                        style: TextStyle(
                            color: Xm.goldOnDark,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            Expanded(child: _editor()),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
              child: Text(
                '双指缩放、拖动调整位置。只保留框内的部分。',
                style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.white.withValues(alpha: 0.55)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _editor() {
    if (_error != null) {
      return Center(
        child: Text(_error!,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
      );
    }
    if (_image == null) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white54));
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final Size viewport = Size(c.maxWidth, c.maxHeight);
        _layout(viewport);

        return ClipRect(
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: InteractiveViewer(
                  key: _viewportKey,
                  transformationController: _tc,
                  constrained: false,
                  boundaryMargin: const EdgeInsets.all(0),
                  minScale: 0.5,
                  maxScale: 6,
                  child: SizedBox(
                    width: _displaySize.width,
                    height: _displaySize.height,
                    child: RawImage(image: _image, fit: BoxFit.fill),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _CropMaskPainter(frame: _frame),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 半透明遮罩 + 亮框，把裁切区域圈出来
class _CropMaskPainter extends CustomPainter {
  _CropMaskPainter({required this.frame});

  final Rect frame;

  @override
  void paint(Canvas canvas, Size size) {
    final Path all = Path()
      ..addRect(Offset.zero & size)
      ..addRect(frame)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(all, Paint()..color = const Color(0xB3000000));

    canvas.drawRect(
      frame,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.9),
    );

    // 三分线，方便对齐
    final Paint grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = Colors.white.withValues(alpha: 0.22);
    for (int i = 1; i < 3; i++) {
      final double dx = frame.left + frame.width * i / 3;
      final double dy = frame.top + frame.height * i / 3;
      canvas.drawLine(Offset(dx, frame.top), Offset(dx, frame.bottom), grid);
      canvas.drawLine(Offset(frame.left, dy), Offset(frame.right, dy), grid);
    }
  }

  @override
  bool shouldRepaint(covariant _CropMaskPainter old) => old.frame != frame;
}
