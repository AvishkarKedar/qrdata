import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Lightweight local logger. Writes timestamped lines to a text file in the
/// app's documents directory so crashes/errors can be inspected after the
/// fact without wiring up a third-party crash-reporting account or API key.
class AppLogger {
  static const _fileName = 'qrdata_log.txt';
  static const _maxBytes = 512 * 1024; // rotate at 512KB to avoid unbounded growth

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<void> log(String message, {String level = 'INFO'}) async {
    try {
      final file = await _file();
      final line = '${DateTime.now().toIso8601String()} [$level] $message\n';
      final exists = await file.exists();
      if (exists && await file.length() > _maxBytes) {
        await file.writeAsString(line, flush: true);
      } else {
        await file.writeAsString(line, mode: FileMode.append, flush: true);
      }
    } catch (_) {
      // Logging must never crash the app.
    }
  }

  static Future<String> readAll() async {
    final file = await _file();
    if (!await file.exists()) return '(no log entries yet)';
    return file.readAsString();
  }

  static Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.writeAsString('', flush: true);
  }
}
