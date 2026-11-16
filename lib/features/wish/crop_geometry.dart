import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

/// 裁切框手柄编号，按 3×3 网格从上到下、从左到右排：
///
/// ```
/// 0 左上   1 上边   2 右上
/// 3 左边   4 框内   5 右边
/// 6 左下   7 下边   8 右下
/// ```
///
/// 编号 = (hy + 1) * 3 + (hx + 1)，hy = -1/0/+1 表示拖上/不动/拖下。
/// -1 表示没落在框上（这时候拖动是平移/缩放图片）。
const int kCropHandleNone = -1;

/// 框内（整体移动）
const int kCropHandleMove = 4;

int cropHandleHorizontal(int mode) => (mode % 3) - 1;

int cropHandleVertical(int mode) => (mode ~/ 3) - 1;

/// 判断点 [p] 落在哪个手柄上。四角优先于四边，四边优先于框内。
int cropHandleAt(
  Rect frame,
  Offset p, {
  double corner = 30,
  double edge = 16,
}) {
  if (frame.width <= 0 || frame.height <= 0) return kCropHandleNone;

  bool near(Offset a) => (p - a).distance <= corner;
  if (near(frame.topLeft)) return 0;
  if (near(frame.topRight)) return 2;
  if (near(frame.bottomLeft)) return 6;
  if (near(frame.bottomRight)) return 8;

  final bool xBetween =
      p.dx > frame.left + corner && p.dx < frame.right - corner;
  final bool yBetween =
      p.dy > frame.top + corner && p.dy < frame.bottom - corner;

  if ((p.dy - frame.top).abs() <= edge && xBetween) return 1;
  if ((p.dy - frame.bottom).abs() <= edge && xBetween) return 7;
  if ((p.dx - frame.left).abs() <= edge && yBetween) return 3;
  if ((p.dx - frame.right).abs() <= edge && yBetween) return 5;
  if (frame.contains(p)) return kCropHandleMove;
  return kCropHandleNone;
}

/// 按手柄方向改裁切框，结果永远落在 `[0, imageWidth] × [0, imageHeight]` 里。
///
/// [delta] 是**图片坐标**（源像素）里的位移。整体移动时框的大小不变。
Rect dragCropRect({
  required Rect sel,
  required Offset delta,
  required int mode,
  required double imageWidth,
  required double imageHeight,
  required double minSize,
}) {
  final double safeMin = math.max(minSize, 1);
  final int hx = cropHandleHorizontal(mode);
  final int hy = cropHandleVertical(mode);

  double l = sel.left;
  double t = sel.top;
  double r = sel.right;
  double b = sel.bottom;

  if (hx == 0 && hy == 0) {
    final double w = r - l;
    final double h = b - t;
    l = (l + delta.dx).clamp(0.0, math.max(0.0, imageWidth - w));
    t = (t + delta.dy).clamp(0.0, math.max(0.0, imageHeight - h));
    r = l + w;
    b = t + h;
  } else {
    if (hx < 0) {
      l = (l + delta.dx).clamp(0.0, math.max(0.0, r - safeMin));
    }
    if (hx > 0) {
      r = (r + delta.dx).clamp(math.min(imageWidth, l + safeMin), imageWidth);
    }
    if (hy < 0) {
      t = (t + delta.dy).clamp(0.0, math.max(0.0, b - safeMin));
    }
    if (hy > 0) {
      b = (b + delta.dy).clamp(math.min(imageHeight, t + safeMin), imageHeight);
    }
  }
  return Rect.fromLTRB(l, t, r, b);
}

/// 图片比视口小的方向居中，比视口大的方向夹住不让拖出空白
Offset clampImageOffset({
  required Offset offset,
  required Size imageSize,
  required Size viewport,
}) {
  double x = offset.dx;
  double y = offset.dy;
  if (imageSize.width <= viewport.width) {
    x = (viewport.width - imageSize.width) / 2;
  } else {
    x = x.clamp(viewport.width - imageSize.width, 0.0);
  }
  if (imageSize.height <= viewport.height) {
    y = (viewport.height - imageSize.height) / 2;
  } else {
    y = y.clamp(viewport.height - imageSize.height, 0.0);
  }
  return Offset(x, y);
}

/// 缩放之后把选区夹回图片范围内
Rect clampSelectionToImage(
  Rect sel,
  double imageWidth,
  double imageHeight,
) {
  final double l = sel.left.clamp(0.0, math.max(0.0, imageWidth - 1));
  final double t = sel.top.clamp(0.0, math.max(0.0, imageHeight - 1));
  return Rect.fromLTRB(
    l,
    t,
    sel.right.clamp(l + 1, math.max(l + 1, imageWidth)),
    sel.bottom.clamp(t + 1, math.max(t + 1, imageHeight)),
  );
}
