import 'dart:io';

import 'package:open_filex/open_filex.dart';

import '../data/apk_updater.dart';
import '../data/repo.dart';
import '../data/update_service.dart';
import 'version.dart';

/// 用户在设置里手动填的下载地址（优先用）
const String kApkUrlOverride = 'apk_url';

/// 后台更新：启动时静默检查，有新版本就下载好，用户点一下即可安装。
///
/// 只做「下载 + 记住路径」，安装必须由用户点头（系统安装器的要求）。
class BackgroundUpdate {
  BackgroundUpdate._();

  static const String _kAuto = 'bg_update_auto';
  static const String _kRecord = 'bg_update_record';

  /// 是否允许后台自动下载（默认开）。
  static Future<bool> autoDownloadEnabled(Repo repo) async =>
      (await repo.getSetting(_kAuto)) != 'off';

  static Future<void> setAutoDownload(Repo repo, bool on) =>
      repo.setSetting(_kAuto, on ? 'on' : 'off');

  /// 背景检查：有新版本就下好放缓存里。永不抛异常，失败就当无事发生。
  static Future<bool> check(Repo repo) async {
    try {
      UpdateInfo info = await UpdateService.fetchLatest();
      if (info.versionCode <= kAppBuild) {
        await repo.setSetting(_kRecord, '');
        return false;
      }

      // 手动指定的下载地址排最前面
      final String manual = (await repo.getSetting(kApkUrlOverride) ?? '').trim();
      if (manual.isNotEmpty) {
        info = info.withApkUrls(<String>[
          manual,
          for (final String u in info.apkUrls)
            if (u != manual) u,
        ]);
      }

      // 已经下好同一个版本就不重复下载
      final PendingApk? existing = await pending(repo);
      if (existing != null &&
          existing.versionCode == info.versionCode &&
          existing.path != null &&
          await File(existing.path!).exists()) {
        return true;
      }

      if (!await autoDownloadEnabled(repo)) {
        // 只记住「有新版本」，不下载
        await repo.setSetting(
            _kRecord, '${info.versionCode}|${info.versionName}|');
        return true;
      }

      final String path = await ApkUpdater.download(info);
      if (info.sha256.isNotEmpty) {
        final String actual = await ApkUpdater.sha256Of(path);
        if (actual.toLowerCase() != info.sha256.toLowerCase()) {
          try {
            await File(path).delete();
          } catch (_) {}
          await repo.setSetting(
              _kRecord, '${info.versionCode}|${info.versionName}|');
          return true;
        }
      }
      await repo.setSetting(
          _kRecord, '${info.versionCode}|${info.versionName}|$path');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 读回上次的结果：有 versionCode 说明发现过新版本，有 path 说明已经下好。
  static Future<PendingApk?> pending(Repo repo) async {
    final String? raw = await repo.getSetting(_kRecord);
    if (raw == null || raw.isEmpty) return null;
    final List<String> parts = raw.split('|');
    if (parts.length < 2) return null;
    final int code = int.tryParse(parts[0]) ?? 0;
    if (code <= kAppBuild) return null;
    return PendingApk(
      versionCode: code,
      versionName: parts[1],
      path: parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null,
    );
  }

  /// 调起系统安装器。返回错误文案，null 表示已调起。
  static Future<String?> install(PendingApk apk) async {
    final String? path = apk.path;
    if (path == null) return '安装包还没下载好';
    if (!await File(path).exists()) return '安装包已被清理，请重新检查更新';
    final OpenResult res = await OpenFilex.open(path);
    return res.type == ResultType.done ? null : '打不开安装程序：${res.message}';
  }

  /// 清掉记录（安装或用户忽略后调用）。
  static Future<void> clear(Repo repo) => repo.setSetting(_kRecord, '');
}

class PendingApk {
  const PendingApk({
    required this.versionCode,
    required this.versionName,
    this.path,
  });

  final int versionCode;
  final String versionName;

  /// 已下载的 APK 路径；null 表示只发现了新版本、还没下载。
  final String? path;

  bool get downloaded => path != null;
}
