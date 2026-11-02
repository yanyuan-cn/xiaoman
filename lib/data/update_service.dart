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
}

class UpdateException implements Exception {
  UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

class UpdateService {
  /// 依次尝试多个清单地址，返回第一个成功的结果。
  static Uri _stamped(String url) {
    final Uri u = Uri.parse(url);
    final Map<String, String> q = Map<String, String>.from(u.queryParameters);
    q['t'] = DateTime.now().millisecondsSinceEpoch.toString();
    return u.replace(queryParameters: q);
  }

  static Future<UpdateInfo> fetchLatest({String? overrideUrl}) async {
    final List<String> urls = <String>[
      if (overrideUrl != null && overrideUrl.trim().isNotEmpty)
        overrideUrl.trim(),
      ...kUpdateManifestUrls,
    ];
    for (final String url in urls) {
      try {
        final http.Response res =
            await http.get(_stamped(url)).timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) continue;
        final String body = utf8.decode(res.bodyBytes);
        final Object? decoded = jsonDecode(body);
        if (decoded is! Map<String, dynamic>) continue;
        return _parse(decoded);
      } catch (_) {
        continue;
      }
    }
    throw UpdateException('连接失败，已尝试 ${urls.length} 个地址');
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
