import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localsend_app/config/crash_report.dart';
import 'package:localsend_app/pages/transfer/transfer_dock.dart';
import 'package:localsend_app/pages/transfer/transfer_dock_visibility.dart';
import 'package:localsend_app/pages/transfer/transfer_progress_page.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

final _logger = Logger('TransferDock');

class TransferDockOverlay extends StatefulWidget {
  const TransferDockOverlay({super.key});

  @override
  State<TransferDockOverlay> createState() => _TransferDockOverlayState();
}

class _TransferDockOverlayState extends State<TransferDockOverlay> with Refena {
  static const _refreshInterval = Duration(milliseconds: 100);
  Timer? _timer;
  final ValueNotifier<_DockState> _dockState = ValueNotifier(const _DockState.hidden());
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _refresh();
        _timer = Timer.periodic(_refreshInterval, (_) => _refreshSafely());
        setState(() => _ready = true);
      } catch (error, stackTrace) {
        _logger.warning(
          'Failed to initialize transfer dock; continuing without it: ${sanitizeCrashText(error.toString())}',
          sanitizeCrashText(stackTrace.toString()),
        );
        setState(() => _failed = true);
      }
    });
  }

  void _refreshSafely() {
    try {
      _refresh();
    } catch (error, stackTrace) {
      _logger.warning(
        'Transfer dock refresh failed; disabling it: ${sanitizeCrashText(error.toString())}',
        sanitizeCrashText(stackTrace.toString()),
      );
      _timer?.cancel();
      if (mounted) setState(() => _failed = true);
    }
  }

  void _refresh() {
    final selectedFiles = ref.read(selectedSendingFilesProvider);
    final sendSessions = ref.read(sendProvider).values.toList();
    final receiveSession = ref.read(serverProvider)?.session;
    final active = sendSessions.any((session) => session.status == SessionStatus.sending) || receiveSession?.status == SessionStatus.sending;
    final sessionPresent =
        sendSessions.any(
          (session) =>
              session.status == SessionStatus.waiting ||
              session.status == SessionStatus.sending ||
              session.status == SessionStatus.finishedWithErrors ||
              session.status == SessionStatus.finished,
        ) ||
        receiveSession != null;
    final count = selectedFiles.isNotEmpty
        ? selectedFiles.length
        : receiveSession?.files.length ?? (sendSessions.isEmpty ? 0 : sendSessions.first.files.length);

    _dockState.value = _DockState(
      visible: selectedFiles.isNotEmpty || sessionPresent,
      active: active,
      count: count,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _dockState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _failed) return const SizedBox.shrink();

    return ValueListenableBuilder(
      valueListenable: _dockState,
      builder: (context, state, _) {
        return ValueListenableBuilder(
          valueListenable: transferProgressPageVisibility,
          builder: (context, progressPageCount, _) {
            final hidden = !state.visible || progressPageCount > 0;
            return SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 600;
                  return Offstage(
                    offstage: hidden,
                    child: TickerMode(
                      enabled: !hidden && state.active,
                      child: TransferDock(
                        key: const ValueKey('transfer-dock'),
                        count: state.count,
                        active: !hidden && state.active,
                        bottomClearance: isMobile ? 86 : 12,
                        onTap: () {
                          if (state.active || ref.read(serverProvider)?.session != null || ref.read(sendProvider).isNotEmpty) {
                            unawaited(
                              Routerino.context.push(
                                () => const TransferProgressPage(),
                                transition: RouterinoTransition.fade(),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _DockState {
  final bool visible;
  final bool active;
  final int count;

  const _DockState({required this.visible, required this.active, required this.count});

  const _DockState.hidden() : visible = false, active = false, count = 0;
}
