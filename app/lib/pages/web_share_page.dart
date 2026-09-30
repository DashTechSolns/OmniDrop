import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/state/server/web_share_state.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:localsend_app/util/native/file_picker.dart';
import 'package:localsend_app/widget/dialogs/add_file_dialog.dart';
import 'package:localsend_app/widget/dialogs/pin_dialog.dart';
import 'package:localsend_app/widget/dialogs/qr_dialog.dart';
import 'package:localsend_app/widget/animated_press.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:localsend_isolates/util/sleep.dart';
import 'package:localsend_isolates/util/file_size_helper.dart';
import 'package:logging/logging.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';
import 'package:url_launcher/url_launcher.dart';

final _logger = Logger('WebSharePage');

enum _ServerState { initializing, running, error, stopping }

/// Shares a link with web browsers, in one of two modes:
/// - send: offers [WebSharePage.files] for download.
/// - receive: serves the upload page so browsers can upload files to this device.
///   Incoming requests are not listed here because they open the receive page
///   like any other incoming request.
class WebSharePage extends StatefulWidget {
  /// The files offered for download (share via link).
  /// `null` serves the upload page instead (receive via link).
  final List<CrossFile>? files;
  final bool showQrOnStart;

  const WebSharePage({this.files, this.showQrOnStart = false});

  @override
  State<WebSharePage> createState() => _WebSharePageState();
}

class _WebSharePageState extends State<WebSharePage> with Refena {
  _ServerState _stateEnum = _ServerState.initializing;
  bool _encrypted = false;
  String? _initializedError;
  bool _initialQrOpened = false;
  late List<CrossFile> _stagedFiles = [...?widget.files];

  bool get _sendMode => widget.files != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _init(encrypted: false);
    });
  }

  void _init({required bool encrypted}) async {
    final settings = ref.read(settingsProvider);
    setState(() {
      _stateEnum = _ServerState.initializing;
      _encrypted = encrypted;
      _initializedError = null;
    });
    await sleepAsync(500);
    try {
      final files = _stagedFiles;

      // The pin of a previous web share session is kept;
      // receive mode initially uses the receive pin from settings.
      final previousWeb = ref.read(serverProvider)?.web;
      final webPin = previousWeb != null ? previousWeb.pin : (files == null ? settings.receivePin : null);

      if (_sendMode) {
        // The auto accept setting of a previous web download state is kept.
        await ref
            .notifier(serverProvider)
            .restartServerWithWebDownload(
              alias: settings.alias,
              port: settings.port,
              https: _encrypted,
              files: files,
              pin: webPin,
            );
      } else {
        await ref
            .notifier(serverProvider)
            .restartServer(
              alias: settings.alias,
              port: settings.port,
              https: _encrypted,
              web: WebShareUpload(pin: webPin),
            );
      }
      setState(() {
        _stateEnum = _ServerState.running;
      });
      if (widget.showQrOnStart && !_initialQrOpened) {
        _initialQrOpened = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final localIps = ref.read(localIpProvider).localIps;
          final serverState = ref.read(serverProvider);
          if (localIps.isEmpty || serverState == null) return;
          final url = '${_encrypted ? 'https' : 'http'}://${localIps.first}:${serverState.port}';
          final pin = serverState.web?.pin;
          final urlWithPin = pin == null ? url : '$url/?pin=${Uri.encodeQueryComponent(pin)}';
          unawaited(
            showDialog<void>(
              context: context,
              builder: (_) => QrDialog(
                data: urlWithPin,
                label: url,
                listenIncomingWebDownloadRequests: _sendMode,
                pin: pin,
              ),
            ),
          );
        });
      }
    } catch (e) {
      if (context.mounted) {
        setState(() {
          _stateEnum = _ServerState.error;
          _initializedError = e.toString();
        });
      }
    }
  }

  /// Web share uses unencrypted http by default, so we need to revert to the previous state.
  Future<void> _revertServerState() async {
    await ref.notifier(serverProvider).restartServerFromSettings();
  }

  Future<void> _addStagedFiles() async {
    final options = FilePickerOption.getOptionsForPlatform();
    if (options.length == 1) {
      await ref.global.dispatchAsync(PickFileAction(option: options.first, context: context));
    } else {
      await AddFileDialog.open(context: context, options: options);
    }
    if (!mounted) return;
    setState(() => _stagedFiles = [...ref.read(selectedSendingFilesProvider)]);
    if (_sendMode) await _init(encrypted: _encrypted);
  }

  Future<void> _clearStagedFiles() async {
    ref.redux(selectedSendingFilesProvider).dispatch(ClearSelectionAction());
    setState(() => _stagedFiles = []);
    if (_sendMode) await _init(encrypted: _encrypted);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (_, _) async {
        if (_stateEnum == _ServerState.initializing || _stateEnum == _ServerState.stopping) {
          return;
        }

        setState(() {
          _stateEnum = _ServerState.stopping;
        });
        await sleepAsync(250);
        try {
          // Also needed in the error state: the failed restart already stopped the old server.
          await _revertServerState();
        } catch (e) {
          _logger.warning('Failed to restore the server', e);
        }
        await sleepAsync(250);

        if (context.mounted) {
          context.pop();
        }
      },
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_sendMode ? t.webSharePage.title : t.webReceivePage.title),
        ),
        body: Builder(
          builder: (context) {
            if (_stateEnum != _ServerState.running) {
              return Column(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (_stateEnum == _ServerState.initializing || _stateEnum == _ServerState.stopping) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    Center(
                      child: Text(
                        _stateEnum == _ServerState.initializing ? t.webSharePage.loading : t.webSharePage.stopping,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ] else if (_initializedError != null) ...[
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 10),
                    Center(
                      child: Text(t.webSharePage.error, style: Theme.of(context).textTheme.titleLarge),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: SelectableText(_initializedError!, style: Theme.of(context).textTheme.bodyMedium),
                    ),
                  ],
                ],
              );
            }

            final serverState = context.watch(serverProvider);
            final webDownloadState = serverState?.webDownloadState;
            if (serverState == null || (_sendMode && webDownloadState == null)) {
              // the server is restarting (e.g. because the pin changed)
              return const Center(child: CircularProgressIndicator());
            }
            final networkState = context.watch(localIpProvider);
            final settings = context.watch(settingsProvider);
            final pin = serverState.web?.pin;

            final firstIp = networkState.localIps.isEmpty ? null : networkState.localIps.first;
            final localUrl = firstIp == null ? null : '${_encrypted ? 'https' : 'http'}://$firstIp:${serverState.port}';
            final shareUrl = localUrl == null || pin == null ? localUrl : '$localUrl/?pin=${Uri.encodeQueryComponent(pin)}';
            final clients = webDownloadState?.sessions.values.toList() ?? const [];

            return ResponsiveListView(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 20),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const _PulsingStatusDot(),
                            const SizedBox(width: 10),
                            Expanded(child: Text('WebDrop is online', style: Theme.of(context).textTheme.titleLarge)),
                            Text('ACTIVE', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.tertiary)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (shareUrl != null) ...[
                          Center(
                            child: Container(
                              width: 196,
                              height: 196,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: PrettyQrView.data(
                                errorCorrectLevel: QrErrorCorrectLevel.Q,
                                data: shareUrl,
                                decoration: PrettyQrDecoration(
                                  shape: PrettyQrSmoothSymbol(color: Theme.of(context).colorScheme.onSurface),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text('Local URL', style: Theme.of(context).textTheme.labelLarge),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(child: SelectableText(localUrl!, maxLines: 2)),
                              Tooltip(
                                message: 'Copy URL',
                                child: IconButton(
                                  onPressed: () async {
                                    await Clipboard.setData(ClipboardData(text: shareUrl));
                                    if (context.mounted && checkPlatformIsDesktop()) context.showSnackBar(t.general.copiedToClipboard);
                                  },
                                  icon: const Icon(Icons.content_copy),
                                ),
                              ),
                              Tooltip(
                                message: 'Open WebDrop',
                                child: IconButton(
                                  onPressed: () async => await launchUrl(Uri.parse(shareUrl), mode: LaunchMode.externalApplication),
                                  icon: const Icon(Icons.open_in_new),
                                ),
                              ),
                            ],
                          ),
                        ] else
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text('No local network address is available yet.'),
                          ),
                        const Divider(height: 24),
                        Text('Connected Browser Clients (${clients.length})', style: Theme.of(context).textTheme.titleMedium),
                        if (clients.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 8, bottom: 8),
                            child: Text('No browser clients connected.'),
                          )
                        else
                          ...clients.map((session) {
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.laptop_chromebook_outlined),
                              title: Text(session.deviceInfo, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(session.ip),
                              trailing: session.pending
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Decline',
                                          onPressed: () => ref.notifier(serverProvider).declineWebDownloadRequest(session.sessionId),
                                          icon: const Icon(Icons.close),
                                        ),
                                        IconButton(
                                          tooltip: 'Accept',
                                          onPressed: () => ref.notifier(serverProvider).acceptWebDownloadRequest(session.sessionId),
                                          icon: const Icon(Icons.check_circle_outline),
                                        ),
                                      ],
                                    )
                                  : Text(t.general.accepted),
                            );
                          }),
                        const Divider(height: 24),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Pairing PIN Protection'),
                          value: pin != null,
                          onChanged: (value) async {
                            if (pin != null) {
                              await ref.notifier(serverProvider).setWebPin(null);
                            } else {
                              final newPin = await showDialog<String>(
                                context: context,
                                builder: (_) => const PinDialog(obscureText: false, generateRandom: true),
                              );
                              if (newPin != null && newPin.isNotEmpty) await ref.notifier(serverProvider).setWebPin(newPin);
                            }
                          },
                        ),
                        if (pin != null)
                          Text(t.webSharePage.pinHint(pin: pin), style: TextStyle(color: Theme.of(context).colorScheme.warning)),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(t.webSharePage.encryption),
                          subtitle: _encrypted ? Text(t.webSharePage.encryptionHint) : null,
                          value: _encrypted,
                          onChanged: (value) => _init(encrypted: value),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(t.webSharePage.autoAccept),
                          value: webDownloadState?.autoAccept ?? settings.receiveViaLinkAutoAccept,
                          onChanged: (value) async {
                            if (webDownloadState != null) {
                              ref.notifier(serverProvider).setWebDownloadAutoAccept(value);
                            } else {
                              await ref.notifier(settingsProvider).setReceiveViaLinkAutoAccept(value);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                if (_sendMode) ...[
                  const SizedBox(height: 14),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Staged Files (${_stagedFiles.length})', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 4),
                          const Text('Available to connected browser clients'),
                          if (_stagedFiles.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 18),
                              child: Text('No files staged. Browser clients can still send files to this device.'),
                            )
                          else
                            ..._stagedFiles.map(
                              (file) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.insert_drive_file_outlined),
                                title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text(file.size.asReadableFileSize),
                              ),
                            ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              AnimatedPress(
                                child: FilledButton.icon(
                                  onPressed: _addStagedFiles,
                                  icon: const Icon(Icons.add),
                                  label: const Text('+ Add Files'),
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: _stagedFiles.isEmpty ? null : _clearStagedFiles,
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Clear staged files'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PulsingStatusDot extends StatefulWidget {
  const _PulsingStatusDot();

  @override
  State<_PulsingStatusDot> createState() => _PulsingStatusDotState();
}

class _PulsingStatusDotState extends State<_PulsingStatusDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.tertiary;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Container(
        width: 13,
        height: 13,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.25 + _controller.value * 0.45), blurRadius: 4 + _controller.value * 7)],
        ),
      ),
    );
  }
}
