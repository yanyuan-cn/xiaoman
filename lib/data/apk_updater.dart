import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'update_service.dart';

class ApkUpdater {
  /// 下载 APK 到应用缓存目录，返回文件路径。
  static Future<String> download(
    UpdateInfo info, {
    void Function(int received, int? total)? onProgress,
  }) async {
    if (info.apkUrl.isEmpty) {
      throw UpdateException('没有下载地址');
    }
    final http.Client client = http.Client();
    try {
      final http.Request req = http.Request('GET', Uri.parse(info.apkUrl));
      final http.StreamedResponse res =
          await client.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        throw UpdateException('下载失败：HTTP ${res.statusCode}');
      }
      final Directory dir = await getTemporaryDirectory();
      final File file =
          File('${dir.path}/xiaoman-${info.versionName}.apk');
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
    } on UpdateException {
      rethrow;
    } catch (e) {
      throw UpdateException('下载中断：$e');
    } finally {
      client.close();
    }
  }

  static Future<String> sha256Of(String path) async {
    final File file = File(path);
    final List<int> bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }
}
