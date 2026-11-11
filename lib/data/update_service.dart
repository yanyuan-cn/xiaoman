import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/version.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.notes,
    this.apkUrls = const <String>[],
    this.sha256 = '',
    this.pageUrl = kReleasePageUrl,
  });

  final int versionCode;
  final String versionName;
  final String notes;

  /// APK 下载地址（已展开镜像），为空时退回打开下载页
  final List<String> apkUrls;

  /// APK 的 SHA-256（可选）
  final String sha256;

  /// 发布页 / 下载页
  final String pageUrl;

  /// 换一组下载地址（用户手动指定时用），其余字段不变。
  UpdateInfo withApkUrls(List<String> urls) => UpdateInfo(
        versionCode: versionCode,
        versionName: versionName,
        notes: notes,
        apkUrls: urls,
        sha256: sha256,
        pageUrl: pageUrl,
      );
}

class UpdateException implements Exception {
  UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

class UpdateService {
  /// 取**所有**清单里版本号最高的那个，而不是第一个能连上的。
  ///
  /// 原因：GitHub Pages 可能因为缓存/构建失败返回旧内容，而镜像（jsdelivr、
  /// ghproxy）读的是仓库里的最新文件。只看第一个成功的源会被旧内容卡住。
  static Uri _stamped(String url) {
    final Uri u = Uri.parse(url);
    final Map<String, String> q = Map<String, String>.from(u.queryParameters);
    q['t'] = DateTime.now().millisecondsSinceEpoch.toString();
    return u.replace(queryParameters: q);
  }

  static Future<UpdateInfo> fetchLatest({String? overrideUrl}) async {
    // 用户自己指定了源，就只认它（他要的就是这个地址的内容）
    final String custom = (overrideUrl ?? '').trim();
    if (custom.isNotEmpty) {
      final UpdateInfo? one = await _tryOne(custom);
      if (one != null) return one;
      throw UpdateException('自定义更新源连接失败：$custom');
    }

    final List<UpdateInfo?> results =
        await Future.wait(kUpdateManifestUrls.map(_tryOne));
    final List<UpdateInfo> ok = results.whereType<UpdateInfo>().toList();
    if (ok.isEmpty) {
      throw UpdateException('连接失败，已尝试 ${kUpdateManifestUrls.length} 个地址');
    }
    ok.sort((UpdateInfo a, UpdateInfo b) => b.versionCode.compareTo(a.versionCode));
    return ok.first;
  }

  static Future<UpdateInfo?> _tryOne(String url) async {
    try {
      final http.Response res =
          await http.get(_stamped(url)).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final Object? decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map<String, dynamic>) return null;
      return _parse(decoded);
    } catch (_) {
      return null;
    }
  }

  static UpdateInfo _parse(Map<String, dynamic> m) {
    final List<String> urls = <String>[];
    final Object? list = m['apkUrls'];
    if (list is List) {
      for (final Object? item in list) {
        if (item is String && item.isNotEmpty) urls.add(item);
      }
    }
    final String single = (m['apkUrl'] as String?) ?? '';
    if (urls.isEmpty && single.isNotEmpty) urls.add(single);

    final List<String> expanded = <String>[];
    for (final String u in urls) {
      for (final String prefix in kApkMirrorPrefixes) {
        expanded.add('$prefix$u');
      }
    }

    return UpdateInfo(
      versionCode: (m['versionCode'] as num?)?.toInt() ?? 0,
      versionName: (m['versionName'] as String?) ?? '未知',
      notes: (m['notes'] as String?) ?? '',
      apkUrls: expanded,
      sha256: (m['sha256'] as String?) ?? '',
      pageUrl: (m['url'] as String?) ?? kReleasePageUrl,
    );
  }
}
