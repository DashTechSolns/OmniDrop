import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/pages/pairing/pairing_page.dart';
import 'package:localsend_app/util/qr_payload_parser.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> showReceivePairingDialog(BuildContext context, {bool allowWebDropLinks = false}) async {
  await showDialog<void>(
    context: context,
    builder: (_) => PairingReceiveDialog(allowWebDropLinks: allowWebDropLinks),
  );
}

class _ReceivePairingDialog extends StatefulWidget {
  final bool allowWebDropLinks;

  const _ReceivePairingDialog({required this.allowWebDropLinks});

  @override
  State<_ReceivePairingDialog> createState() => _ReceivePairingDialogState();
}

class _ReceivePairingDialogState extends State<_ReceivePairingDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _scanLine = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
  bool _handledCode = false;
  String? _scanMessage;

  @override
  void dispose() {
    _scanLine.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handledCode) return;
    final value = capture.barcodes.map((barcode) => barcode.rawValue).whereType<String>().firstOrNull;
    if (value == null) return;

    final parsed = parseQrPayload(value);
    if (parsed case ParsedPairQr()) {
      _handledCode = true;
      setState(() => _scanMessage = 'This OmniDrop pairing code cannot be joined while no sender session is active.');
      return;
    }
    if (parsed case ParsedWebDropQr(:final uri)) {
      if (!widget.allowWebDropLinks) {
        setState(() => _scanMessage = 'Not an OmniDrop code.');
        return;
      }
      final openLink = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Open this link in browser?'),
          content: Text(uri.toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Open')),
          ],
        ),
      );
      if (openLink == true) {
        _handledCode = true;
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (mounted) Navigator.of(context).pop();
      }
      return;
    }
    setState(() => _scanMessage = 'Not an OmniDrop code.');
  }

  @override
  Widget build(BuildContext context) {
    final cameraUnavailable = !kIsWeb && (defaultTargetPlatform == TargetPlatform.linux || defaultTargetPlatform == TargetPlatform.windows);
    return AlertDialog(
      title: const Text('Receive'),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.allowWebDropLinks ? 'Scan an OmniDrop code or WebDrop link.' : 'Scan an OmniDrop pairing code.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              if (cameraUnavailable)
                Container(
                  height: 230,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text('Camera QR scanning is unavailable on this platform.'),
                )
              else
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 230,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        MobileScanner(onDetect: _onDetect),
                        IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                        AnimatedBuilder(
                          animation: _scanLine,
                          builder: (context, _) => Positioned(
                            top: 16 + (_scanLine.value * 198),
                            left: 18,
                            right: 18,
                            child: Container(
                              height: 2,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                boxShadow: [
                                  BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6), blurRadius: 8),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_scanMessage != null) ...[
                const SizedBox(height: 8),
                Text(_scanMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
    );
  }
}