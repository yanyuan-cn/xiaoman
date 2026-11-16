import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../ui/components.dart';
import '../../ui/unsaved_guard.dart';
import 'crop_page.dart';
import 'image_view_page.dart';

/// 想买清单的详情 / 新建页。
///
/// 字段：名称、价格、预计购买日期、备注、图片。图片会复制到应用私有目录，
/// 这样原相册里的图删掉也不影响这里。
class WishDetailPage extends StatefulWidget {
  const WishDetailPage({super.key, required this.repo, this.wish});

  final Repo repo;
  final Wish? wish;

  @override
  State<WishDetailPage> createState() => _WishDetailPageState();
}

class _WishDetailPageState extends State<WishDetailPage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _price = TextEditingController();
  final TextEditingController _note = TextEditingController();

  DateTime? _target;
  String? _imagePath;
  bool _saving = false;
  bool _saved = false;
  bool _loadingImage = false;

  bool get _isEditing => widget.wish != null;

  /// 和进来时的状态比，有改动就拦一下返回
  bool get _dirty {
    if (_saved) return false;
    final Wish? w = widget.wish;
    if (w == null) {
      return _name.text.trim().isNotEmpty ||
          _price.text.trim().isNotEmpty ||
          _note.text.trim().isNotEmpty ||
          _target != null ||
          _imagePath != null;
    }
    return _name.text.trim() != w.name ||
        _price.text.trim() != (w.price > 0 ? formatCentsPlain(w.price) : '') ||
        _note.text.trim() != (w.note ?? '') ||
        _target?.millisecondsSinceEpoch != w.targetAt?.millisecondsSinceEpoch ||
        _imagePath != w.imagePath;
  }

  @override
  void initState() {
    super.initState();
    final Wish? w = widget.wish;
    if (w != null) {
      _name.text = w.name;
      _price.text = w.price > 0 ? formatCentsPlain(w.price) : '';
      _note.text = w.note ?? '';
      _target = w.targetAt;
      _imagePath = w.imagePath;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _note.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
      ));
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _target ?? now.add(const Duration(days: 30)),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 20),
    );
    if (picked == null) return;
    setState(() => _target = DateTime(picked.year, picked.month, picked.day, 12));
  }

  /// 选图 → 原图拷进应用目录 → 自己框一块 → 只留框内的部分
  Future<void> _pickImage() async {
    setState(() => _loadingImage = true);
    try {
      final List<PlatformFile>? files =
          await FilePicker.pickFiles(type: FileType.image);
      if (files == null || files.isEmpty) {
        setState(() => _loadingImage = false);
        return;
      }
      final PlatformFile f = files.first;
      final String? srcPath = f.path;
      if (srcPath == null) {
        setState(() => _loadingImage = false);
        _toast('读不到这张图');
        return;
      }

      if (!mounted) return;
      setState(() => _loadingImage = false);
      // pickAndCrop 会把原图留在应用目录里，之后「重新裁切」用得到
      final String? cropped = await pickAndCrop(context, srcPath);
      if (!mounted || cropped == null) return;

      // 换图时把旧的一组（裁好的 + 原图副本）删掉
      final String? old = _imagePath;
      if (old != null && old != cropped) await deleteWishImage(old);
      if (!mounted) return;
      setState(() => _imagePath = cropped);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingImage = false);
      _toast('选图失败：$e');
    }
  }

  /// 点图片：全屏看，顺便可以重新裁
  Future<void> _viewImage() async {
    final String? path = _imagePath;
    if (path == null) {
      await _pickImage();
      return;
    }
    final String? next = await showWishImageView(context, path);
    if (!mounted || next == null || next == path) return;
    // 重裁时旧文件已经由 recropImage 清掉了，这里只换路径
    setState(() => _imagePath = next);
  }

  Future<void> _removeImage() async {
    final String? old = _imagePath;
    setState(() => _imagePath = null);
    if (old != null) await deleteWishImage(old);
  }

  Future<void> _save() async {
    final String name = _name.text.trim();
    if (name.isEmpty) {
      _toast('给它起个名字');
      return;
    }
    final int? cents = parseYuanToCents(_price.text.trim());
    setState(() => _saving = true);
    final String note = _note.text.trim();

    if (_isEditing) {
      await widget.repo.updateWish(
        id: widget.wish!.id,
        name: name,
        price: cents ?? 0,
        targetAt: _target,
        note: note.isEmpty ? null : note,
        imagePath: _imagePath,
      );
    } else {
      await widget.repo.addWish(
        name: name,
        price: cents ?? 0,
        targetAt: _target,
        note: note.isEmpty ? null : note,
        imagePath: _imagePath,
      );
    }
    if (!mounted) return;
    _saved = true;
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('从想买里删掉'),
        content: const Text('只是删掉这条记录，不影响任何账目。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final String? old = _imagePath;
    await widget.repo.deleteWish(widget.wish!.id);
    if (old != null) await deleteWishImage(old);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return XmUnsavedScope(
      dirty: _dirty,
      child: XmPageScaffold(
      title: _isEditing ? '想买的东西' : '添加想买',
      subtitle: _isEditing ? '记录了就不容易忘' : '先记下来，再慢慢决定',
      actions: <Widget>[
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: SizedBox(
            height: 36,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11)),
              ),
              child: Text(_saving ? '保存中' : '保存'),
            ),
          ),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: <Widget>[
          _imageCard(),
          const SizedBox(height: 16),
          XmField(
            controller: _name,
            label: '名称',
            hint: '例如：降噪耳机、露营帐篷',
            maxLength: 24,
          ),
          const SizedBox(height: 14),
          XmField(
            controller: _price,
            label: '价格',
            hint: '大概多少（可以之后再改）',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 14),
          _dateRow(),
          const SizedBox(height: 14),
          XmField(
            controller: _note,
            label: '备注',
            hint: '为什么想买 / 买了用在哪儿（可选）',
            maxLength: 60,
          ),
          if (_isEditing) ...<Widget>[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text(
                '添加于 ${fmtDate(widget.wish!.createdAt)}',
                style: Xm.text(11.5, FontWeight.w400, color: Xm.ink3),
              ),
            ),
            const SizedBox(height: 26),
            SizedBox(
              height: 48,
              child: Material(
                color: Xm.isDark
                    ? const Color(0xFF3A221F)
                    : const Color(0xFFFCF2EF),
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _delete,
                  child: Center(
                    child: Text('删掉这条',
                        style: Xm.text(14, FontWeight.w600,
                            spacing: 0.2, color: Xm.warn)),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }

  Widget _imageCard() {
    final File? file = _imagePath == null ? null : File(_imagePath!);
    final bool hasImage = file != null && file.existsSync();

    return GestureDetector(
      onTap: _loadingImage ? null : _viewImage,
      child: Container(
        height: 168,
        decoration: BoxDecoration(
          color: Xm.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Xm.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: <Widget>[
            if (hasImage)
              Positioned.fill(
                child: Image.file(file, fit: BoxFit.cover),
              )
            else
              Positioned.fill(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      _loadingImage
                          ? Icons.hourglass_empty_rounded
                          : Icons.add_photo_alternate_outlined,
                      size: 30,
                      color: Xm.ink3,
                    ),
                    const SizedBox(height: 8),
                    Text(_loadingImage ? '正在读取…' : '添一张图片',
                        style: Xm.text(12, FontWeight.w400, color: Xm.ink3)),
                  ],
                ),
              ),
            if (hasImage)
              Positioned(
                right: 10,
                top: 10,
                child: GestureDetector(
                  onTap: _removeImage,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded,
                        size: 16, color: Colors.white),
                  ),
                ),
              ),
            if (hasImage)
              Positioned(
                left: 10,
                bottom: 10,
                child: GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text('换一张',
                        style: Xm.text(11.5, FontWeight.w500,
                            color: Colors.white)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _dateRow() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _pickDate,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: Xm.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Xm.line),
        ),
        child: Row(
          children: <Widget>[
            Text('预计购买',
                style: Xm.text(13.5, FontWeight.w500, color: Xm.ink2)),
            const Spacer(),
            Text(
              _target == null ? '还没定' : fmtDate(_target!),
              style: Xm.text(13.5, FontWeight.w500,
                  color: _target == null ? Xm.ink3 : Xm.ink,
                  tabular: true),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 18, color: Xm.ink3),
          ],
        ),
      ),
    );
  }
}

