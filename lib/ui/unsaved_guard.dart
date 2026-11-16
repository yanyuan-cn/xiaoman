import 'package:flutter/material.dart';

import '../core/theme.dart';

/// 返回时有未保存修改就拦一下。
///
/// 用法：页面自己维护一个 `_dirty`（和初始值比），把它传给 [XmUnsavedScope]。
Future<bool> confirmDiscard(
  BuildContext context, {
  String title = '放弃这次修改？',
  String content = '刚才改的内容还没保存，返回就没了。',
  String discardLabel = '不保存',
}) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('继续编辑'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(discardLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// 把子页面包一层，返回手势/返回键在 dirty 时先弹确认。
class XmUnsavedScope extends StatelessWidget {
  const XmUnsavedScope({
    super.key,
    required this.dirty,
    required this.child,
  });

  final bool dirty;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !dirty,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        final bool discard = await confirmDiscard(context);
        if (!discard || !context.mounted) return;
        Navigator.of(context).pop(result);
      },
      child: child,
    );
  }
}

/// 顶部「保存」按钮旁边那种小圆按钮，统一尺寸。
class XmSaveButton extends StatelessWidget {
  const XmSaveButton({
    super.key,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: FilledButton(
        onPressed: busy ? null : onTap,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11)),
        ),
        child: Text(busy ? '保存中' : label,
            style: Xm.text(13.5, FontWeight.w600)),
      ),
    );
  }
}
