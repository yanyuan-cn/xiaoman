import 'dart:async';
import 'dart:convert' show ByteConversionSink;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'update_service.dart';

/// APK 下载器。
///
/// 三条策略，都是针对「国内直连 GitHub 只有几十 KB/s」这件事：
///  1. **测速换源**：下载 3 秒后算平均速度，低于 [minSpeed] 就主动放弃、
///     换下一个地址。以前只有报错才换，慢就一直磨到底。
///  2. **空闲超时**：12 秒没有新数据就判失败换源，避免卡住不动。
///  3. **流式校验**：SHA-256 边读边算，不再把 60MB 一次性读进内存
///     （以前会在 100% 处卡一下）。
class ApkUpdater {
  /// 低于这个速度就换源（字节/秒）。
  static const int minSpeed = 150 * 1024;

  /// 下载多久之后开始判断速度。
  static const Duration probeAfter = Duration(seconds: 3);

  /// 多久没收到数据算卡死。
  static const Duration idleTimeout = Duration(seconds: 12);

  /// 建立连接的超时。
  static const Duration connectTimeout = Duration(seconds: 10);

  /// 依次尝试每个地址；太慢的会被主动放弃。
  ///
  /// [onSwitch] 会在每次换地址时回调，界面上可以显示「正在换线路」。
  static Future<String> download(
    UpdateInfo info, {
    void Function(int received, int? total)? onProgress,
    void Function(String url, int index)? onSwitch,
  }) async {
    if (info.apkUrls.isEmpty) {
      throw UpdateException('没有下载地址');
    }
    Object? lastError;
    for (int i = 0; i < info.apkUrls.length; i++) {
      final String url = info.apkUrls[i];
      try {
        onSwitch?.call(url, i);
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
    IOSink? sink;
    File? file;
    try {
      final http.Request req = http.Request('GET', Uri.parse(url));
      final http.StreamedResponse res =
          await client.send(req).timeout(connectTimeout);
      if (res.statusCode != 200 && res.statusCode != 206) {
        throw UpdateException('HTTP ${res.statusCode}');
      }

      final Directory dir = await getTemporaryDirectory();
      file = File('${dir.path}/xiaoman-$version.apk');
      if (await file.exists()) {
        await file.delete();
      }
      sink = file.openWrite();

      final int? total = res.contentLength;
      final Stopwatch sw = Stopwatch()..start();
      int received = 0;

      try {
        // timeout() 作用在"两个事件之间"：超过 idleTimeout 没数据就抛
        await for (final List<int> chunk in res.stream.timeout(idleTimeout)) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);

          if (sw.elapsed >= probeAfter && received > 0) {
            final double speed = received / (sw.elapsedMilliseconds / 1000);
            final bool incomplete = total != null && received < total;
            if (incomplete && speed < minSpeed) {
              throw UpdateException(
                  '这条线路只有 ${(speed / 1024).round()} KB/s，换下一个');
            }
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
        sink = null;
      }

      if (total != null && received != total) {
        throw UpdateException('只下到 $received / $total 字节');
      }
      return file.path;
    } catch (e) {
      // 半截文件留着没用，也别让它占空间
      try {
        await sink?.close();
      } catch (_) {}
      if (file != null && await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  /// 流式计算 SHA-256：60MB 也只占一个缓冲区，不会卡在 100%。
  static Future<String> sha256Of(String path) async {
    final _DigestSink sink = _DigestSink();
    final ByteConversionSink input = sha256.startChunkedConversion(sink);
    await for (final List<int> chunk in File(path).openRead()) {
      input.add(chunk);
    }
    input.close();
    final Digest? digest = sink.value;
    if (digest == null) throw StateError('哈希计算失败');
    return digest.toString();
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
