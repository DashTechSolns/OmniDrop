import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/config/crash_report.dart';

/// Shows a self-contained app if initialization fails.
void showInitErrorApp({
  required Object error,
  required StackTrace stackTrace,
}) {
  runApp(CrashScreen(error: error, stackTrace: stackTrace));
}

class CrashScreen extends StatelessWidget {
  final Object error;
  final StackTrace stackTrace;

  const CrashScreen({
    required this.error,
    required this.stackTrace,
  });

  @override
  Widget build(BuildContext context) {
    final details = [
      'Error: ${sanitizeCrashText(error.toString())}',
      '',
      sanitizeCrashText(stackTrace.toString()),
    ].join('\n');
    return MaterialApp(
      title: 'OmniDrop: Error',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('OmniDrop failed to start')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Expanded(child: SingleChildScrollView(child: SelectableText(details))),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => Clipboard.setData(ClipboardData(text: details)),
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
