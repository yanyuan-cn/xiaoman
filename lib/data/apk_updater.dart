import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'update_service.dart';

class ApkUpdater {
  /// 依次尝试每个下载地址，成功即返回本地路径。
  static Future<String> download(
    UpdateInfo info, {
    void Function(int received, int? total)? onProgress,
  }) async {
    if (info.apkUrls.isEmpty) {
      throw UpdateException('没有下载地址');
    }
    Object? lastError;
    for (final String url in info.apkUrls) {
      try {
        return await _downloadOne(url, info.versionName, onProgress);
      } catch (e) {
        lastError = e;
      }
    }
    throw UpdateException('下载失败：$lastError');
  }

  static Future<String> _downloadOne(
    String url,
    String version,
    void Function(int received, int? total)? onProgress,
  ) async {
    final http.Client client = http.Client();
    try {
      final http.Request req = http.Request('GET', Uri.parse(url));
      final http.StreamedResponse res =
          await client.send(req).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        throw UpdateException('HTTP ${res.statusCode}');
      }
      final Directory dir = await getTemporaryDirectory();
      final File file = File('${dir.path}/xiaoman-$version.apk');
      if (await file.exists()) {
        await file.delete();
      }
      final IOSink sink = file.openWrite();
      int received = 0;
      final int? total = res.contentLength;
      await for (final List<int> chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      return file.path;
    } finally {
      client.close();
    }
  }

  static Future<String> sha256Of(String path) async {
    final List<int> bytes = await File(path).readAsBytes();
    return sha256.convert(bytes).toString();
  }
}
