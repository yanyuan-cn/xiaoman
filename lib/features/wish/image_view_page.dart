import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'crop_page.dart';

/// 全屏看想买的图片，可以双指放大，也可以直接重新裁切。
///
/// 返回：新图片路径（重新裁切过）或 null（只是看了看）。
Future<String?> showWishImageView(
  BuildContext context,
  String path,
) {
  return Navigator.of(context).push<String>(
    PageRouteBuilder<String>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (BuildContext c, Animation<double> a, Animation<double> s) =>
          _WishImageView(path: path),
      transitionsBuilder: (BuildContext c, Animation<double> a,
              Animation<double> s, Widget child) =>
          FadeTransition(opacity: a, child: child),
    ),
  );
}

class _WishImageView extends StatefulWidget {
  const _WishImageView({required this.path});

  final String path;

  @override
  State<_WishImageView> createState() => _WishImageViewState();
}

class _WishImageViewState extends State<_WishImageView> {
  late String _path = widget.path;
  bool _busy = false;

  Future<void> _recrop() async {
    setState(() => _busy = true);
    // 从原图重新裁（不是在这张裁好的图上再裁），原图副本由 recropImage 保管
    final String? next = await recropImage(context, _path);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (next != null) _path = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final File file = File(_path);
    return Scaffold(
      backgroundColor: const Color(0xFF0C1411),
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: file.existsSync()
                      ? Image.file(file, fit: BoxFit.contain)
                      : const Icon(Icons.broken_image_outlined,
                          color: Colors.white38, size: 48),
                ),
              ),
            ),
            Positioned(
              left: 8,
              top: 4,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(
                  _path == widget.path ? null : _path,
                ),
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 22),
              ),
            ),
            Positioned(
              left: 16,
              bottom: 24,
              child: IgnorePointer(
                child: Text(
                  '原图已保留，可反复重裁',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 11.5,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 20,
              child: Material(
                color: Xm.gold,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _busy ? null : _recrop,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 11),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.crop_rounded,
                            size: 17, color: Colors.white),
                        const SizedBox(width: 7),
                        Text(_busy ? '处理中…' : '重新裁切',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
