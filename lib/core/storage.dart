import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

Future<int> _dirSize(Directory dir) async {
  if (!await dir.exists()) return 0;
  int total = 0;
  try {
    await for (final FileSystemEntity e in dir.list(recursive: true)) {
      if (e is File) {
        try {
          total += await e.length();
        } catch (_) {}
      }
    }
  } catch (_) {}
  return total;
}

/// 缓存目录大小（更新下载的 APK 也在这里）
Future<int> cacheBytes() async {
  try {
    return await _dirSize(await getTemporaryDirectory());
  } catch (_) {
    return 0;
  }
}

/// 数据库文件大小
Future<int> databaseBytes() async {
  try {
    final String dir = await getDatabasesPath();
    return await _dirSize(Directory(dir));
  } catch (_) {
    return 0;
  }
}

/// 清空缓存目录，返回释放的字节数
Future<int> clearCache() async {
  int freed = 0;
  try {
    final Directory dir = await getTemporaryDirectory();
    if (!await dir.exists()) return 0;
    await for (final FileSystemEntity e in dir.list()) {
      try {
        if (e is File) {
          freed += await e.length();
          await e.delete();
        } else if (e is Directory) {
          freed += await _dirSize(e);
          await e.delete(recursive: true);
        }
      } catch (_) {}
    }
  } catch (_) {}
  return freed;
}

/// 启动时清掉更新下载残留的安装包
Future<void> cleanUpdateCache() async {
  try {
    final Directory dir = await getTemporaryDirectory();
    if (!await dir.exists()) return;
    await for (final FileSystemEntity e in dir.list()) {
      if (e is File && e.path.toLowerCase().endsWith('.apk')) {
        try {
          await e.delete();
        } catch (_) {}
      }
    }
  } catch (_) {}
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
}

/// 数据库文件名（用于展示）
String get dbFileName => p.basename('xiaoman.db');
