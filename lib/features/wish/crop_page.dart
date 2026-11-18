import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/theme.dart';
import 'crop_geometry.dart';

/// 图片库的命名约定（都在 `<应用文档>/wishes` 里）：
///
/// * `<ts>_o.jpg`  —— 用户选的原图副本，保留完整画面，随时可以重新裁
/// * `<ts>_c.png`  —— 裁好之后真正显示的那张
///
/// 保留原图是关键：重新裁切必须从原图开始，不能在裁过的图上面再裁一次，
/// 否则每改一次都会丢掉一圈像素。
const String _kCropTail = '_c.png';
const String _kOrigTail = '_o.';
const List<String> _kImageExts = <String>['jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif'];

/// 计划图片的存放目录
Future<Directory> wishImageDir() async {
  final Directory docs = await getApplicationDocumentsDirectory();
  final Directory dir = Directory('${docs.path}/wishes');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir;
}

int _lastSeparator(String path) =>
    math.max(path.lastIndexOf('/'), path.lastIndexOf(r'\'));

/// `<ts>_c.png` -> `<ts>`；不是这个命名就返回 null
String? wishImageBase(String cropPath) => cropPath.endsWith(_kCropTail)
    ? cropPath.substring(0, cropPath.length - _kCropTail.length)
    : null;

/// 把用户选的原图原样拷进应用目录，返回 `<ts>_o.<ext>`。
///
/// 只是拷贝，不解码不重新压缩，所以画质无损、大图也不会卡。
Future<String> importOriginalImage(String srcPath) async {
  final Directory dir = await wishImageDir();
  String ext = 'jpg';
  final int dot = srcPath.lastIndexOf('.');
  final int sep = _lastSeparator(srcPath);
  if (dot > sep) {
    final String raw = srcPath.substring(dot + 1).toLowerCase();
    if (_kImageExts.contains(raw)) ext = raw;
  }
  final String ts = DateTime.now().millisecondsSinceEpoch.toString();
  final String dest = '${dir.path}/$ts$_kOrigTail$ext';
  await File(srcPath).copy(dest);
  return dest;
}

/// 由裁好图的路径推回原图副本；找不到（老数据）就返回它自己
Future<String> originalOf(String cropPath) async {
  final String? base = wishImageBase(cropPath);
  if (base == null) return cropPath;
  for (final String ext in _kImageExts) {
    final String candidate = '$base$_kOrigTail$ext';
    if (File(candidate).existsSync()) return candidate;
  }
  return cropPath;
}

/// 删掉一组图片（裁好的那张 + 配对的原图副本）
Future<void> deleteWishImage(String cropPath) async {
  final String? base = wishImageBase(cropPath);
  final List<String> targets = <String>[cropPath];
  if (base != null) {
    for (final String ext in _kImageExts) {
      targets.add('$base$_kOrigTail$ext');
    }
  }
  for (final String p in targets) {
    final File f = File(p);
    if (f.existsSync()) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
  }
}

/// 打开裁切界面，返回裁好的新文件路径；用户取消返回 null。
///
/// [srcPath] 应该是原图。输出固定是新名字 `<ts>_c.png`（不复用旧文件名），
/// 这样图片缓存不会拿到旧像素。
Future<String?> cropImageToFile(BuildContext context, String srcPath) {
  return Navigator.of(context).push<String>(
    PageRouteBuilder<String>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (BuildContext c, Animation<double> a, Animation<double> s) =>
          _CropPage(srcPath: srcPath),
      transitionsBuilder: (BuildContext c, Animation<double> a,
              Animation<double> s, Widget child) =>
          FadeTransition(opacity: a, child: child),
    ),
  );
}

/// 选完图后的完整流程：把原图拷进应用目录 → 裁 → 把原图副本改名到结果旁边。
///
/// 返回裁好的图；用户取消裁切返回 null（这时刚拷进来的原图也会被删掉）。
Future<String?> pickAndCrop(BuildContext context, String srcPath) async {
  final String original = await importOriginalImage(srcPath);
  final String? cropped = await cropImageToFile(context, original);
  if (cropped == null) {
    await deleteWishImage(original);
    return null;
  }
  final String? base = wishImageBase(cropped);
  if (base != null) {
    final String ext = original.contains('.') ? original.split('.').last : 'jpg';
    try {
      final File o = File(original);
      if (o.existsSync()) o.renameSync('$base$_kOrigTail$ext');
    } catch (_) {}
  }
  return cropped;
}

/// 拿**原图**重新裁一次，返回新的裁好图路径。
///
/// 裁完会把原图副本改名到新的时间戳上（两组文件名保持配对），
/// 并删掉旧的裁好图，避免目录里堆垃圾。
Future<String?> recropImage(BuildContext context, String cropPath) async {
  final String src = await originalOf(cropPath);
  final bool fromOriginal = src != cropPath;
  final String srcExt = src.contains('.') ? src.split('.').last : 'jpg';

  final String? fresh = await cropImageToFile(context, src);
  if (fresh == null) return null;

  if (fromOriginal) {
    final String? freshBase = wishImageBase(fresh);
    if (freshBase != null) {
      try {
        File(src).renameSync('$freshBase$_kOrigTail$srcExt');
      } catch (_) {}
    }
  }
  if (cropPath != fresh) {
    try {
      final File old = File(cropPath);
      if (old.existsSync()) old.deleteSync();
    } catch (_) {}
  }
  return fresh;
}

/// 大图先缩到能放下的尺寸再解码，避免 8000×6000 的照片直接把内存撑爆。
Future<ui.Image> _decodeCapped(Uint8List bytes) async {
  const int maxSide = 4096;
  try {
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
      bytes,
    );
    final ui.ImageDescriptor desc = await ui.ImageDescriptor.encoded(buffer);
    final int w = desc.width;
    final int h = desc.height;
    final int longSide = math.max(w, h);
    final ui.Codec codec = longSide > maxSide
        ? await desc.instantiateCodec(
            targetWidth: math.max(1, (w * maxSide / longSide).round()),
            targetHeight: math.max(1, (h * maxSide / longSide).round()),
          )
        : await desc.instantiateCodec();
    final ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  } catch (_) {
    return decodeImageFromList(bytes);
  }
}

class _CropPage extends StatefulWidget {
  const _CropPage({required this.srcPath});

  final String srcPath;

  @override
  State<_CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<_CropPage> {
  ui.Image? _image;
  String? _error;
  bool _busy = false;

  /// 视口（可编辑区域）尺寸
  Size _vp = Size.zero;

  /// 1 个源像素对应多少视口像素（zoom = 1 时）
  double _fit = 0;

  /// 用户双指缩放倍数
  double _zoom = 1;

  /// 图片左上角在视口里的位置
  Offset _offset = Offset.zero;

  /// 裁切框，**源图像素坐标**（不是屏幕坐标，这样缩放/平移都不影响结果）
  Rect _sel = Rect.zero;

  // 手势临时量
  int _modeAtStart = kCropHandleNone; // -1 平移图片；0..8 见 cropHandleAt
  int _pointers = 0;
  Offset _startFocal = Offset.zero;
  Offset _offsetAtStart = Offset.zero;
  double _zoomAtStart = 1;
  Rect _selAtStart = Rect.zero;
  bool _active = false;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    try {
      final Uint8List bytes = await File(widget.srcPath).readAsBytes();
      final ui.Image img = await _decodeCapped(bytes);
      if (!mounted) return;
      setState(() => _image = img);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '这张图打不开：$e');
    }
  }

  // ── 几何 ────────────────────────────────────────────────────────────────

  static const double _pad = 24;

  double get _ds => _fit * _zoom;

  Size get _displaySize {
    final ui.Image? img = _image;
    if (img == null) return Size.zero;
    return Size(img.width * _ds, img.height * _ds);
  }

  Rect get _imageRectVp {
    final Size d = _displaySize;
    return Rect.fromLTWH(_offset.dx, _offset.dy, d.width, d.height);
  }

  Rect get _selVp {
    final double d = _ds;
    return Rect.fromLTWH(
      _offset.dx + _sel.left * d,
      _offset.dy + _sel.top * d,
      _sel.width * d,
      _sel.height * d,
    );
  }

  /// 视口尺寸变化时重新算缩放；只在第一次把裁切框设成整张图
  void _layout(Size vp) {
    final ui.Image? img = _image;
    if (img == null) return;
    if (vp == _vp && _fit > 0) return;
    final bool first = _fit <= 0;
    _vp = vp;
    final double s = math.min(
      (vp.width - _pad * 2) / img.width,
      (vp.height - _pad * 2) / img.height,
    );
    _fit = s > 0 ? s : 0.01;
    _zoom = 1;
    if (first) {
      _sel = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    }
    _offset = Offset(
      (vp.width - img.width * _ds) / 2,
      (vp.height - img.height * _ds) / 2,
    );
    _clampOffset();
  }

  void _clampOffset() {
    _offset = clampImageOffset(
      offset: _offset,
      imageSize: _displaySize,
      viewport: _vp,
    );
  }

  /// 显示尺寸变了（缩放）之后，保持裁切框还在图里
  void _keepSelInImage() {
    final ui.Image? img = _image;
    if (img == null) return;
    _sel = clampSelectionToImage(
      _sel,
      img.width.toDouble(),
      img.height.toDouble(),
    );
  }

  // ── 手势 ────────────────────────────────────────────────────────────────

  static const double _hitCorner = 30;
  static const double _hitEdge = 16;

  int _hitMode(Offset p) => cropHandleAt(
        _selVp,
        p,
        corner: _hitCorner,
        edge: _hitEdge,
      );

  void _onScaleStart(ScaleStartDetails d) {
    _selAtStart = _sel;
    _offsetAtStart = _offset;
    _zoomAtStart = _zoom;
    _startFocal = d.localFocalPoint;
    _pointers = d.pointerCount;
    _modeAtStart = d.pointerCount > 1 ? -1 : _hitMode(d.localFocalPoint);
    setState(() => _active = true);
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final ui.Image? img = _image;
    if (img == null) return;

    // 手指加减了（单指 <-> 双指）：重新起算，避免画面突然跳一下
    if (d.pointerCount != _pointers) {
      _pointers = d.pointerCount;
      _startFocal = d.localFocalPoint;
      _offsetAtStart = _offset;
      _zoomAtStart = _zoom;
      if (d.pointerCount > 1) _modeAtStart = kCropHandleNone;
    }

    final bool multi = d.pointerCount > 1;
    if (!multi && _modeAtStart >= 0) {
      _applyDrag(_modeAtStart, d.localFocalPoint - _startFocal);
    } else {
      // 单指从框外开始 / 双指：平移 + 缩放图片
      final double newZoom = (_zoomAtStart * d.scale).clamp(1.0, 6.0);
      final double dsAtStart = _fit * _zoomAtStart;
      final Offset imgPoint = (_startFocal - _offsetAtStart) / dsAtStart;
      final double newDs = _fit * newZoom;
      _zoom = newZoom;
      _offset = d.localFocalPoint - imgPoint * newDs;
      _clampOffset();
      _keepSelInImage();
    }
    setState(() {});
  }

  void _onScaleEnd(ScaleEndDetails d) {
    setState(() => _active = false);
  }

  /// 按 [mode] 的方向改裁切框；[deltaVp] 是视口位移
  void _applyDrag(int mode, Offset deltaVp) {
    final ui.Image? img = _image;
    if (img == null) return;
    final double d = _ds;
    if (d <= 0) return;
    _sel = dragCropRect(
      sel: _selAtStart,
      delta: deltaVp / d,
      mode: mode,
      imageWidth: img.width.toDouble(),
      imageHeight: img.height.toDouble(),
      minSize: math.max(26 / d, 1.0),
    );
  }

  void _resetSelection() {
    final ui.Image? img = _image;
    if (img == null) return;
    setState(() {
      _sel = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    });
  }

  // ── 真正裁像素 ──────────────────────────────────────────────────────────

  Future<void> _apply() async {
    final ui.Image? img = _image;
    if (img == null || _busy) return;
    setState(() => _busy = true);
    try {
      final double w = img.width.toDouble();
      final double h = img.height.toDouble();
      final Rect raw = _sel;
      final double left = raw.left.clamp(0.0, math.max(0.0, w - 1));
      final double top = raw.top.clamp(0.0, math.max(0.0, h - 1));
      final double right = raw.right.clamp(left + 1, w);
      final double bottom = raw.bottom.clamp(top + 1, h);
      final double sw = right - left;
      final double sh = bottom - top;

      if (sw < 8 || sh < 8) {
        setState(() => _busy = false);
        _snack('框太小了，拉大一点再试');
        return;
      }

      // 输出最多 2048 长边，够看也省内存
      const double maxSide = 2048;
      final double longSide = math.max(sw, sh);
      final double k = longSide > maxSide ? maxSide / longSide : 1.0;
      final int ow = math.max(1, (sw * k).round());
      final int oh = math.max(1, (sh * k).round());

      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(left, top, sw, sh),
        Rect.fromLTWH(0, 0, ow.toDouble(), oh.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final ui.Image out = await recorder.endRecording().toImage(ow, oh);
      final ByteData? data =
          await out.toByteData(format: ui.ImageByteFormat.png);
      out.dispose();
      if (data == null) throw StateError('编码失败');

      final Directory dir = await wishImageDir();
      final String ts = DateTime.now().millisecondsSinceEpoch.toString();
      final String dest = '${dir.path}/$ts$_kCropTail';
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
    final ui.Image? img = _image;
    return Scaffold(
      backgroundColor: const Color(0xFF0C1411),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
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
                    onPressed: img == null || _busy ? null : _resetSelection,
                    child: Text('全选',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 13.5)),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _apply,
                    child: Text(_busy ? '处理中…' : '使用',
                        style: const TextStyle(
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
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '拖角或边调整范围 · 拖框内移动框 · 框外拖动/双指缩放图片',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.white.withValues(alpha: 0.55)),
                    ),
                  ),
                  if (img != null) ...<Widget>[
                    const SizedBox(width: 10),
                    Text(
                      '${_sel.width.round()} × ${_sel.height.round()}',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.white.withValues(alpha: 0.4),
                          fontFeatures: const <ui.FontFeature>[
                            ui.FontFeature.tabularFigures(),
                          ]),
                    ),
                  ],
                ],
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ),
      );
    }
    if (_image == null) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white54));
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final Size vp = Size(c.maxWidth, c.maxHeight);
        _layout(vp);

        return ClipRect(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: <Widget>[
                Positioned.fromRect(
                  rect: _imageRectVp,
                  child: RawImage(
                    image: _image,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _CropPainter(sel: _selVp, active: _active),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 半透明遮罩 + 亮框 + 角标，把裁切区域圈出来
class _CropPainter extends CustomPainter {
  _CropPainter({required this.sel, required this.active});

  final Rect sel;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    if (sel.width <= 0 || sel.height <= 0) return;

    final Path mask = Path()
      ..addRect(Offset.zero & size)
      ..addRect(sel)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(mask, Paint()..color = const Color(0xA6000000));

    canvas.drawRect(
      sel,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 2.0 : 1.3
        ..color = Colors.white.withValues(alpha: active ? 1 : 0.88),
    );

    // 三分线，方便对齐
    final Paint grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = Colors.white.withValues(alpha: 0.2);
    for (int i = 1; i < 3; i++) {
      final double dx = sel.left + sel.width * i / 3;
      final double dy = sel.top + sel.height * i / 3;
      canvas.drawLine(Offset(dx, sel.top), Offset(dx, sel.bottom), grid);
      canvas.drawLine(Offset(sel.left, dy), Offset(sel.right, dy), grid);
    }

    // 四个角的粗短角标，明确告诉人「这儿能拖」
    const double arm = 18;
    final Paint bracket = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    void corner(Offset o, double sx, double sy) {
      canvas.drawLine(o, o + Offset(arm * sx, 0), bracket);
      canvas.drawLine(o, o + Offset(0, arm * sy), bracket);
      canvas.drawCircle(
        o,
        5,
        Paint()..color = Xm.gold,
      );
    }

    corner(sel.topLeft, 1, 1);
    corner(sel.topRight, -1, 1);
    corner(sel.bottomLeft, 1, -1);
    corner(sel.bottomRight, -1, -1);
  }

  @override
  bool shouldRepaint(covariant _CropPainter old) =>
      old.sel != sel || old.active != active;
}
