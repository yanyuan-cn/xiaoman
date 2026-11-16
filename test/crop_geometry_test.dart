import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoman/features/wish/crop_geometry.dart';

void main() {
  // 视口里的框：左上 (100,100)，右下 (300,250)
  const Rect frame = Rect.fromLTRB(100, 100, 300, 250);

  group('手柄命中', () {
    test('四个角', () {
      expect(cropHandleAt(frame, const Offset(100, 100)), 0);
      expect(cropHandleAt(frame, const Offset(300, 100)), 2);
      expect(cropHandleAt(frame, const Offset(100, 250)), 6);
      expect(cropHandleAt(frame, const Offset(300, 250)), 8);
    });

    test('四条边（避开角）', () {
      expect(cropHandleAt(frame, const Offset(200, 101)), 1);
      expect(cropHandleAt(frame, const Offset(200, 249)), 7);
      expect(cropHandleAt(frame, const Offset(101, 180)), 3);
      expect(cropHandleAt(frame, const Offset(299, 180)), 5);
    });

    test('框内是整体移动，框外是平移图片', () {
      expect(cropHandleAt(frame, const Offset(200, 180)), kCropHandleMove);
      expect(cropHandleAt(frame, const Offset(20, 20)), kCropHandleNone);
    });

    test('角附近不会被误判成边', () {
      // 距左上角 20px 的位置，仍算拖角
      expect(cropHandleAt(frame, const Offset(114, 114)), 0);
    });
  });

  group('拖动改框', () {
    const Rect sel = Rect.fromLTRB(100, 100, 500, 400);

    Rect drag(int mode, Offset delta) => dragCropRect(
          sel: sel,
          delta: delta,
          mode: mode,
          imageWidth: 1000,
          imageHeight: 800,
          minSize: 20,
        );

    test('拖右下角同时改宽高', () {
      final Rect r = drag(8, const Offset(50, 40));
      expect(r.left, 100);
      expect(r.top, 100);
      expect(r.right, 550);
      expect(r.bottom, 440);
    });

    test('拖左上角不动右下角', () {
      final Rect r = drag(0, const Offset(50, 40));
      expect(r.left, 150);
      expect(r.top, 140);
      expect(r.right, 500);
      expect(r.bottom, 400);
    });

    test('只有一条边变', () {
      expect(drag(3, const Offset(30, 0)).left, 130);
      expect(drag(3, const Offset(30, 0)).right, 500);
      expect(drag(1, const Offset(0, -30)).top, 70);
      expect(drag(1, const Offset(0, -30)).bottom, 400);
    });

    test('整体移动保持尺寸', () {
      final Rect r = drag(kCropHandleMove, const Offset(-60, 25));
      expect(r.left, 40);
      expect(r.top, 125);
      expect(r.width, sel.width);
      expect(r.height, sel.height);
    });

    test('整体移动不会越出图片', () {
      final Rect r = drag(kCropHandleMove, const Offset(-9999, -9999));
      expect(r.left, 0);
      expect(r.top, 0);
      expect(r.width, sel.width);
      final Rect r2 = drag(kCropHandleMove, const Offset(9999, 9999));
      expect(r2.right, 1000);
      expect(r2.bottom, 800);
    });

    test('拖过头会被图片边界夹住', () {
      final Rect r = drag(8, const Offset(9999, 9999));
      expect(r.right, 1000);
      expect(r.bottom, 800);
      final Rect r2 = drag(0, const Offset(-9999, -9999));
      expect(r2.left, 0);
      expect(r2.top, 0);
    });

    test('不会缩到比 minSize 还小', () {
      final Rect r = drag(8, const Offset(-9999, -9999));
      expect(r.width, greaterThanOrEqualTo(20));
      expect(r.height, greaterThanOrEqualTo(20));
    });
  });

  group('图片偏移夹取', () {
    const Size viewport = Size(400, 600);

    test('图比视口小时居中', () {
      final Offset o = clampImageOffset(
        offset: const Offset(999, -999),
        imageSize: const Size(200, 300),
        viewport: viewport,
      );
      expect(o, const Offset(100, 150));
    });

    test('图比视口大时夹在边界内', () {
      final Offset o = clampImageOffset(
        offset: const Offset(50, 50),
        imageSize: const Size(800, 1200),
        viewport: viewport,
      );
      expect(o, Offset.zero);
      final Offset o2 = clampImageOffset(
        offset: const Offset(-9999, -9999),
        imageSize: const Size(800, 1200),
        viewport: viewport,
      );
      expect(o2, const Offset(-400, -600));
    });
  });

  test('选区缩回图片范围', () {
    final Rect r = clampSelectionToImage(
      const Rect.fromLTRB(-20, -10, 1200, 900),
      1000,
      800,
    );
    expect(r, const Rect.fromLTRB(0, 0, 1000, 800));
  });
}
