import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

const _crashReportTimeout = Duration(seconds: 10);
Future<void> _writeQueue = Future<void>.value();

String sanitizeCrashText(String text) {
  final redacted = text
      .replaceAllMapped(
        RegExp(
          r'''["']?\b([\w.-]*(?:password|passwd|token|pin))["']?\s*(?:[:=]\s*|\s+(?:is\s*)?[:=]?\s*)(?:"[^"]*"|'[^']*'|[^\s,;&]+)''',
          caseSensitive: false,
        ),
        (match) => '${match[1]}=[REDACTED]',
      )
      .replaceAll(
        RegExp(r'\bBearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
        'Bearer [REDACTED]',
      );
  return redacted;
}

Future<void> writeLastCrashReport({required Object error, required StackTrace stackTrace}) {
  final report = [
    'Time: ${DateTime.now().toIso8601String()}',
    'Error: ${sanitizeCrashText(error.toString())}',
    'Stack trace:',
    sanitizeCrashText(stackTrace.toString()),
  ].join('\n');
  _writeQueue = _writeQueue.then((_) => _writeReport(report));
  return _writeQueue;
}

Future<void> _writeReport(String report) async {
  try {
    final directory = await getApplicationSupportDirectory().timeout(_crashReportTimeout);
    await directory.create(recursive: true).timeout(_crashReportTimeout);
    final file = File('${directory.path}${Platform.pathSeparator}last_crash.txt');
    await file.writeAsString(report, flush: true).timeout(_crashReportTimeout);
  } catch (error, stackTrace) {
    debugPrint('Failed to write last crash report: $error\n$stackTrace');
  }
}

Future<String?> readLastCrashReport() async {
  final directory = await getApplicationSupportDirectory().timeout(_crashReportTimeout);
  final file = File('${directory.path}${Platform.pathSeparator}last_crash.txt');
  if (!await file.exists().timeout(_crashReportTimeout)) return null;
  return file.readAsString().timeout(_crashReportTimeout);
}
