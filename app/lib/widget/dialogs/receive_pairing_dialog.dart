import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/model/send_mode.dart';
import 'package:localsend_app/pages/tabs/send_tab_vm.dart';
import 'package:localsend_app/widget/list_tile/device_list_tile.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> showReceivePairingDialog(BuildContext context) async {
  await showDialog<void>(context: context, builder: (_) => _ReceivePairingDialog(parentContext: context));
}

class _ReceivePairingDialog extends StatefulWidget {
  final BuildContext parentContext;

  const _ReceivePairingDialog({required this.parentContext});

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

    final uri = Uri.tryParse(value);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
      setState(() => _scanMessage = 'That QR code is not a WebDrop link.');
      return;
    }

    _handledCode = true;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (mounted) Navigator.of(context).pop();
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
              Text('Scan a WebDrop QR code to open its transfer page.', style: Theme.of(context).textTheme.bodyMedium),
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
              const SizedBox(height: 12),
              Consumer(
                builder: (context, ref) {
                  final vm = ref.watch(sendTabVmProvider);
                  return ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    title: const Text('Nearby devices'),
                    subtitle: Text('${vm.nearbyDevices.length} found'),
                    children: [
                      Wrap(
                        spacing: 4,
                        children: [
                          Tooltip(
                            message: 'Send to an address',
                            child: IconButton(
                              onPressed: () async {
                                Navigator.of(context).pop();
                                await vm.onTapAddress(widget.parentContext);
                              },
                              icon: const Icon(Icons.ads_click),
                            ),
                          ),
                          Tooltip(
                            message: 'Send to a favorite',
                            child: IconButton(
                              onPressed: () async {
                                Navigator.of(context).pop();
                                await vm.onTapFavorite(widget.parentContext);
                              },
                              icon: const Icon(Icons.favorite_outline),
                            ),
                          ),
                          PopupMenuButton<SendMode>(
                            tooltip: 'Send mode',
                            onSelected: (mode) async {
                              Navigator.of(context).pop();
                              await vm.onTapSendMode(widget.parentContext, mode);
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: SendMode.single, child: Text('Single recipient')),
                              PopupMenuItem(value: SendMode.multiple, child: Text('Multiple recipients')),
                              PopupMenuItem(value: SendMode.link, child: Text('WebDrop link')),
                            ],
                            child: const Padding(
                              padding: EdgeInsets.all(12),
                              child: Icon(Icons.settings_outlined),
                            ),
                          ),
                        ],
                      ),
                      if (vm.nearbyDevices.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Align(alignment: Alignment.centerLeft, child: Text('No nearby devices found yet.')),
                        )
                      else
                        ...vm.nearbyDevices.map((device) {
                          return DeviceListTile(
                            device: device,
                            onTap: () async {
                              Navigator.of(context).pop();
                              if (vm.sendMode == SendMode.multiple) {
                                await vm.onTapDeviceMultiSend(widget.parentContext, device);
                              } else {
                                await vm.onTapDevice(widget.parentContext, device);
                              }
                            },
                          );
                        }),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
    );
  }
}