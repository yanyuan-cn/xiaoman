import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/version.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.notes,
    this.apkUrl = '',
    this.sha256 = '',
    this.pageUrl = kReleasePageUrl,
  });

  final int versionCode;
  final String versionName;
  final String notes;

  /// APK 直链，为空时退回打开下载页
  final String apkUrl;

  /// APK 的 SHA-256（可选，用于校验）
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
  /// 读取仓库里的 version.json，返回远端版本信息。
  static Future<UpdateInfo> fetchLatest() async {
    http.Response res;
    try {
      res = await http
          .get(Uri.parse(kUpdateManifestUrl))
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      throw UpdateException('连不上服务器');
    }
    if (res.statusCode != 200) {
      throw UpdateException('服务器返回 ${res.statusCode}');
    }
    try {
      final String body = utf8.decode(res.bodyBytes);
      final Object? decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('不是 JSON 对象');
      }
      return UpdateInfo(
        versionCode: (decoded['versionCode'] as num?)?.toInt() ?? 0,
        versionName: (decoded['versionName'] as String?) ?? '未知',
        notes: (decoded['notes'] as String?) ?? '',
        apkUrl: (decoded['apkUrl'] as String?) ?? '',
        sha256: (decoded['sha256'] as String?) ?? '',
        pageUrl: (decoded['url'] as String?) ?? kReleasePageUrl,
      );
    } catch (e) {
      throw UpdateException('版本信息格式不对');
    }
  }
}
