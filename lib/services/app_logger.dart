import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Simple file-based logger. Writes timestamped lines to a rotating log file
/// in the app's documents directory. Call [AppLogger.log], [AppLogger.error],
/// or [AppLogger.api] anywhere in the app.
class AppLogger {
  AppLogger._();

  static File? _logFile;
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dateStr = _dateString();
      _logFile = File('${dir.path}/guideme_$dateStr.log');
      _initialized = true;
      log('─── App started ───');
    } catch (e) {
      debugPrint('[AppLogger] init failed: $e');
    }
  }

  static void log(String message) => _write('INFO ', message);

  static void error(String message, [Object? err, StackTrace? stack]) {
    _write('ERROR', message);
    if (err != null) _write('ERROR', '  $err');
    if (stack != null) _write('ERROR', '  ${stack.toString().split('\n').take(3).join(' | ')}');
  }

  static void api(String method, String path, int statusCode) {
    _write('API  ', '$method $path → $statusCode');
  }

  static void _write(String level, String message) {
    final entry = '[${_timestamp()}] $level  $message\n';
    debugPrint(entry.trimRight());
    _logFile?.writeAsStringSync(entry, mode: FileMode.append, flush: true);
  }

  static String _timestamp() {
    final n = DateTime.now();
    return '${_pad(n.hour)}:${_pad(n.minute)}:${_pad(n.second)}.${n.millisecond.toString().padLeft(3, '0')}';
  }

  static String _dateString() {
    final n = DateTime.now();
    return '${n.year}-${_pad(n.month)}-${_pad(n.day)}';
  }

  static String _pad(int v) => v.toString().padLeft(2, '0');

  /// Returns the path to today's log file, or null if not initialized.
  static String? get logFilePath => _logFile?.path;
}
