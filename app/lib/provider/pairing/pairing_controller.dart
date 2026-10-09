import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/http_provider.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/scan_facade.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/native/channel/android_channel.dart' as android_channel;
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/qr_payload_parser.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/http.dart';
import 'package:localsend_isolates/rust/api/model.dart' as rust_model;
import 'package:localsend_isolates/rust/api/pairing.dart';
import 'package:localsend_isolates/util/rust.dart';
import 'package:refena_flutter/refena_flutter.dart';

String _safePairingError(Object error) {
  return error.toString().replaceAll(
    RegExp(r'(pin|token|password)\s*[:=]\s*[^,\s]+', caseSensitive: false),
    r'$1=[redacted]',
  );
}

bool _isPairingPinError(Object error) => error.toString().toLowerCase().contains('pin');

final pairingControllerProvider = NotifierProvider<PairingController, PairingState>((ref) => PairingController());
final pairingConnectionProvider = NotifierProvider<PairingConnectionController, PairingConnectionState>(
  (ref) => PairingConnectionController(),
);

enum PairingMode { qr, sameNetwork }

enum PairingRole { sender, receiver }

class PairingConnectionState {
  final PairingRole? role;
  final String? sessionToken;
  final List<PairingDeviceInfo> peers;
  final int activeTransferCount;
  final Set<String> lastSelectedFingerprints;

  const PairingConnectionState({
    this.role,
    this.sessionToken,
    this.peers = const [],
    this.activeTransferCount = 0,
    this.lastSelectedFingerprints = const {},
  });

  bool get isConnected => peers.isNotEmpty;
}

class PairingConnectionController extends Notifier<PairingConnectionState> {
  @override
  PairingConnectionState init() => const PairingConnectionState();

  void connect({required PairingRole role, required String? sessionToken, required List<PairingDeviceInfo> peers}) {
    final peerFingerprints = peers.map((peer) => peer.fingerprint).toSet();
    final remembered = state.sessionToken == sessionToken ? state.lastSelectedFingerprints : const <String>{};
    state = PairingConnectionState(
      role: role,
      sessionToken: sessionToken,
      peers: List.unmodifiable(peers),
      activeTransferCount: state.sessionToken == sessionToken ? state.activeTransferCount : 0,
      lastSelectedFingerprints: remembered.intersection(peerFingerprints),
    );
  }

  void updatePeers(List<PairingDeviceInfo> peers) {
    if (!state.isConnected) return;
    final peerFingerprints = peers.map((peer) => peer.fingerprint).toSet();
    state = PairingConnectionState(
      role: state.role,
      sessionToken: state.sessionToken,
      peers: List.unmodifiable(peers),
      activeTransferCount: state.activeTransferCount,
      lastSelectedFingerprints: state.lastSelectedFingerprints.intersection(peerFingerprints),
    );
  }

  void setActiveTransferCount(int count) {
    final safeCount = count < 0 ? 0 : count;
    if (safeCount == state.activeTransferCount) return;
    state = PairingConnectionState(
      role: state.role,
      sessionToken: state.sessionToken,
      peers: state.peers,
      activeTransferCount: safeCount,
      lastSelectedFingerprints: state.lastSelectedFingerprints,
    );
  }

  void rememberSelection(Set<String> fingerprints) {
    final peerFingerprints = state.peers.map((peer) => peer.fingerprint).toSet();
    state = PairingConnectionState(
      role: state.role,
      sessionToken: state.sessionToken,
      peers: state.peers,
      activeTransferCount: state.activeTransferCount,
      lastSelectedFingerprints: fingerprints.intersection(peerFingerprints),
    );
  }

  void clear() {
    state = const PairingConnectionState();
  }
}

enum PairingPhase {
  idle,
  startingSession,
  startingHotspot,
  sessionReady,
  peerJoined,
  closedForSelection,
  transferring,
  stopped,
  enablingWifi,
  scanning,
  connecting,
  joining,
  waitingForPin,
  joined,
  failed,
  manualGuide,
}

class PairingOptions {
  final PairingMode mode;
  final bool multiRecipient;
  final bool pinEnabled;
  final String? pin;
  final bool encrypted;

  const PairingOptions({
    required this.mode,
    required this.multiRecipient,
    required this.pinEnabled,
    required this.pin,
    required this.encrypted,
  });

  String? get validatedPin {
    if (!pinEnabled) return null;
    if (pin == null || !RegExp(r'^\d{6}$').hasMatch(pin!)) {
      throw const FormatException('PIN must be exactly six digits.');
    }
    return pin;
  }

  HttpServerPairingTask toSessionTask({required PairingDeviceInfo sender, required int avatarIndex}) {
    return HttpServerPairingTask(
      operation: HttpServerPairingOperation.create,
      sender: sender,
      discoverable: mode == PairingMode.sameNetwork,
      avatarIndex: avatarIndex,
      pin: validatedPin,
      multiRecipient: multiRecipient,
    );
  }
}

class PairingNearbyOffer {
  final Device device;
  final PairingSendOffer offer;

  const PairingNearbyOffer({required this.device, required this.offer});
}

class PairingLogEntry {
  final DateTime timestamp;
  final String step;
  final String message;

  const PairingLogEntry({required this.timestamp, required this.step, required this.message});
}

class PairingState {
  final PairingPhase phase;
  final PairingRole? role;
  final PairingMode? mode;
  final String? sessionToken;
  final String? qrPayload;
  final String? pin;
  final bool pinRequired;
  final bool multiRecipient;
  final bool encrypted;
  final DateTime? expiresAt;
  final String? ssid;
  final String? password;
  final List<PairingDeviceInfo> peers;
  final List<PairingNearbyOffer> offers;
  final String? failureReason;
  final String? controlEvent;
  final bool? wifiEnabled;
  final List<PairingLogEntry> dartLog;
  final bool canUse5GMode;

  const PairingState({
    required this.phase,
    this.role,
    this.mode,
    this.sessionToken,
    this.qrPayload,
    this.pin,
    this.pinRequired = false,
    this.multiRecipient = false,
    this.encrypted = true,
    this.expiresAt,
    this.ssid,
    this.password,
    this.peers = const [],
    this.offers = const [],
    this.failureReason,
    this.controlEvent,
    this.wifiEnabled,
    this.dartLog = const [],
    this.canUse5GMode = false,
  });

  static const _unset = Object();

  PairingState copyWith({
    PairingPhase? phase,
    Object? role = _unset,
    Object? mode = _unset,
    Object? sessionToken = _unset,
    Object? qrPayload = _unset,
    Object? pin = _unset,
    bool? pinRequired,
    bool? multiRecipient,
    bool? encrypted,
    Object? expiresAt = _unset,
    Object? ssid = _unset,
    Object? password = _unset,
    List<PairingDeviceInfo>? peers,
    List<PairingNearbyOffer>? offers,
    Object? failureReason = _unset,
    Object? controlEvent = _unset,
    Object? wifiEnabled = _unset,
    List<PairingLogEntry>? dartLog,
    bool? canUse5GMode,
  }) {
    return PairingState(
      phase: phase ?? this.phase,
      role: identical(role, _unset) ? this.role : role as PairingRole?,
      mode: identical(mode, _unset) ? this.mode : mode as PairingMode?,
      sessionToken: identical(sessionToken, _unset) ? this.sessionToken : sessionToken as String?,
      qrPayload: identical(qrPayload, _unset) ? this.qrPayload : qrPayload as String?,
      pin: identical(pin, _unset) ? this.pin : pin as String?,
      pinRequired: pinRequired ?? this.pinRequired,
      multiRecipient: multiRecipient ?? this.multiRecipient,
      encrypted: encrypted ?? this.encrypted,
      expiresAt: identical(expiresAt, _unset) ? this.expiresAt : expiresAt as DateTime?,
      ssid: identical(ssid, _unset) ? this.ssid : ssid as String?,
      password: identical(password, _unset) ? this.password : password as String?,
      peers: peers ?? this.peers,
      offers: offers ?? this.offers,
      failureReason: identical(failureReason, _unset) ? this.failureReason : failureReason as String?,
      controlEvent: identical(controlEvent, _unset) ? this.controlEvent : controlEvent as String?,
      wifiEnabled: identical(wifiEnabled, _unset) ? this.wifiEnabled : wifiEnabled as bool?,
      dartLog: dartLog ?? this.dartLog,
      canUse5GMode: canUse5GMode ?? this.canUse5GMode,
    );
  }
}

class PairingController extends Notifier<PairingState> {
  static const sessionLifetime = Duration(minutes: 2);

  android_channel.AndroidLocalOnlyHotspot? _hotspot;
  Timer? _expiryTimer;
  StreamSubscription<void>? _disconnectSubscription;
  final List<StreamSubscription<HttpServerEvent>> _sessionSubscriptions = [];
  PairQrPayload? _lastQrPayload;
  PairingNearbyOffer? _lastNearbyOffer;
  bool _stopping = false;

  @override
  PairingState init() => const PairingState(phase: PairingPhase.idle);

  void _log(String step, String message) {
    final entries = [...state.dartLog, PairingLogEntry(timestamp: DateTime.now(), step: step, message: message)];
    state = state.copyWith(dartLog: entries.length > 500 ? entries.sublist(entries.length - 500) : entries);
  }

  static bool isValidPin(String? pin) => pin != null && RegExp(r'^\d{6}$').hasMatch(pin);

  String suggestPin() => generatePairingPin();

  Future<void> startSender(PairingOptions options) async {
    if (state.sessionToken != null || state.phase == PairingPhase.startingHotspot || state.phase == PairingPhase.startingSession) return;
    final pin = options.validatedPin;
    state = PairingState(
      phase: options.mode == PairingMode.qr ? PairingPhase.startingHotspot : PairingPhase.startingSession,
      role: PairingRole.sender,
      mode: options.mode,
      pin: pin,
      pinRequired: options.pinEnabled,
      multiRecipient: options.multiRecipient,
      encrypted: options.encrypted,
      dartLog: state.dartLog,
    );
    _log('sender_start', 'Starting pairing session');

    try {
      if (checkPlatform([TargetPlatform.android])) {
        state = state.copyWith(canUse5GMode: await android_channel.canRequest5GHzAndroid());
      }
      if (options.mode == PairingMode.qr) {
        if (!checkPlatform([TargetPlatform.android])) throw StateError('QR pairing hotspot is available on Android only.');
        _hotspot = await android_channel.startLocalOnlyHotspotAndroid();
        await _listenForNativeDisconnect();
        _log('hotspot_started', 'Pairing hotspot started');
      }

      await ref.notifier(settingsProvider).setHttps(options.encrypted);
      final settings = ref.read(settingsProvider);
      final existingServer = ref.read(serverProvider);
      if (existingServer == null) {
        await ref
            .notifier(serverProvider)
            .startServer(
              alias: settings.alias,
              port: settings.port,
              https: options.encrypted,
            );
      } else if (existingServer.https != options.encrypted) {
        if (existingServer.session != null) {
          throw StateError('Encryption cannot be changed while a transfer is active.');
        }
        await ref
            .notifier(serverProvider)
            .restartServer(
              alias: existingServer.alias,
              port: existingServer.port,
              https: options.encrypted,
              web: existingServer.web,
            );
      }

      final localDevice = ref.read(deviceFullInfoProvider);
      final hostIp = _hotspot?.hostIp ?? ref.read(localIpProvider).localIps.firstOrNull;
      if (hostIp == null || hostIp.isEmpty || localDevice.port < 1) throw StateError('No usable local host address is available.');
      final sender = PairingDeviceInfo(
        fingerprint: localDevice.fingerprint,
        alias: localDevice.alias,
        version: localDevice.version,
        deviceModel: localDevice.deviceModel,
        deviceType: localDevice.deviceType.toRust(),
        ip: hostIp,
        port: localDevice.port,
        protocol: localDevice.https ? rust_model.ProtocolType.https : rust_model.ProtocolType.http,
        hasWebInterface: localDevice.download,
      );
      _log('sender_server_ready', 'HTTP server ready at ${sender.ip}:${sender.port} (${sender.protocol.name})');
      final createStream = ref
          .redux(parentIsolateProvider)
          .dispatchTakeResult(
            IsolateHttpServerPairingAction(
              task: options.toSessionTask(sender: sender, avatarIndex: ref.read(persistenceProvider).getProfileAvatar() % 6),
            ),
          );
      final created =
          (await createStream.firstWhere((event) => event is HttpServerPairingEvent && event.sessionToken != null)) as HttpServerPairingEvent;
      final token = created.sessionToken!;
      final expiry = DateTime.now().add(sessionLifetime);
      final qrPayload = options.mode == PairingMode.qr
          ? Uri(
              scheme: 'omnidrop',
              host: 'pair',
              queryParameters: {
                'alias': localDevice.alias,
                'ssid': _hotspot!.ssid,
                'password': _hotspot!.password,
                'ip': hostIp,
                'port': localDevice.port.toString(),
                'https': localDevice.https.toString(),
                'fp': localDevice.fingerprint,
                'token': token,
                'pin': options.pinEnabled.toString(),
                'exp': expiry.millisecondsSinceEpoch.toString(),
              },
            ).toString()
          : null;

      state = state.copyWith(
        phase: PairingPhase.sessionReady,
        sessionToken: token,
        qrPayload: qrPayload,
        expiresAt: expiry,
        ssid: _hotspot?.ssid,
        password: _hotspot?.password,
      );
      _log('session_ready', 'Pairing session is ready');
      _listenToSession(token);
      _expiryTimer = Timer(sessionLifetime, () {
        if (state.peers.isEmpty) unawaited(stop(expired: true));
      });
    } catch (error) {
      _log('sender_failed', 'Pairing session could not be started');
      await _cleanupFailedStart();
      state = state.copyWith(phase: PairingPhase.failed, failureReason: error.toString());
      rethrow;
    }
  }

  void _listenToSession(String token) {
    final peers = ref
        .redux(parentIsolateProvider)
        .dispatchTakeResult(
          IsolateHttpServerPairingAction(
            task: HttpServerPairingTask(operation: HttpServerPairingOperation.listen, sessionToken: token),
          ),
        );
    _sessionSubscriptions.add(
      peers.listen(
        (event) {
          if (event is! HttpServerPairingEvent || event.event == null || event.event is! RsPairingEvent_DeviceJoined) return;
          final pairingEvent = event.event! as RsPairingEvent_DeviceJoined;
          final device = pairingEvent.device.device;
          final updated = [...state.peers.where((peer) => peer.fingerprint != device.fingerprint), device];
          _expiryTimer?.cancel();
          _expiryTimer = null;
          state = state.copyWith(
            phase: state.phase == PairingPhase.closedForSelection ? PairingPhase.closedForSelection : PairingPhase.peerJoined,
            peers: updated,
          );
          ref.notifier(pairingConnectionProvider).connect(role: PairingRole.sender, sessionToken: token, peers: updated);
          unawaited(_keepPairingServiceAlive());
          _log('peer_joined', 'A receiver joined the pairing session');
        },
        onError: (Object error) {
          state = state.copyWith(phase: PairingPhase.failed, failureReason: error.toString());
        },
      ),
    );
    final controls = ref
        .redux(parentIsolateProvider)
        .dispatchTakeResult(
          IsolateHttpServerPairingAction(
            task: HttpServerPairingTask(operation: HttpServerPairingOperation.listenControl, sessionToken: token),
          ),
        );
    _sessionSubscriptions.add(
      controls.listen(
        (event) {
          if (event is HttpServerPairingEvent && event.controlEvent != null) unawaited(handleControlEvent(event.controlEvent!));
        },
        onError: (Object error) {
          state = state.copyWith(phase: PairingPhase.failed, failureReason: error.toString());
        },
      ),
    );
  }

  Future<void> handleControlEvent(String event) async {
    _log('control_event', 'Pairing control event received');
    switch (event) {
      case 'paired':
        _expiryTimer?.cancel();
        _expiryTimer = null;
        state = state.copyWith(
          phase: state.multiRecipient ? PairingPhase.peerJoined : PairingPhase.closedForSelection,
          controlEvent: event,
        );
        if (!state.multiRecipient) await _finalizeSelection();
      case 'lockedOut':
        state = state.copyWith(
          phase: PairingPhase.failed,
          failureReason: 'Pairing is locked after too many incorrect PIN attempts.',
          controlEvent: event,
        );
      case 'finalized':
        state = state.copyWith(phase: PairingPhase.closedForSelection, controlEvent: event);
    }
  }

  Future<void> _finalizeSelection() async {
    final token = state.sessionToken;
    if (token == null) return;
    try {
      final events = ref
          .redux(parentIsolateProvider)
          .dispatchTakeResult(
            IsolateHttpServerPairingAction(
              task: HttpServerPairingTask(operation: HttpServerPairingOperation.finalize, sessionToken: token),
            ),
          );
      final result = (await events.firstWhere((event) => event is HttpServerPairingEvent && event.snapshot != null)) as HttpServerPairingEvent;
      state = state.copyWith(
        phase: PairingPhase.closedForSelection,
        peers: result.snapshot!.joinedDevices.map((joined) => joined.device).toList(),
      );
      ref.notifier(pairingConnectionProvider).updatePeers(state.peers);
    } catch (error) {
      state = state.copyWith(phase: PairingPhase.failed, failureReason: error.toString());
    }
  }

  void setTransferring(bool transferring) {
    if (state.role != PairingRole.sender || state.sessionToken == null) return;
    state = state.copyWith(
      phase: transferring
          ? PairingPhase.transferring
          : state.controlEvent == 'paired' && !state.multiRecipient
          ? PairingPhase.closedForSelection
          : PairingPhase.peerJoined,
    );
  }

  Future<void> stop({bool expired = false, bool disconnected = false}) async {
    if (_stopping) return;
    if (expired && state.peers.isNotEmpty) return;
    _stopping = true;
    final previousState = state;
    _log(
      expired
          ? 'session_expired'
          : disconnected
          ? 'native_disconnect'
          : 'user_stop',
      'Pairing session stopped',
    );
    _expiryTimer?.cancel();
    _expiryTimer = null;
    await _disconnectSubscription?.cancel();
    _disconnectSubscription = null;
    Object? failure;
    final token = state.sessionToken;
    if (token != null) {
      try {
        await ref
            .redux(parentIsolateProvider)
            .dispatchTakeResult(
              IsolateHttpServerPairingAction(
                task: HttpServerPairingTask(operation: HttpServerPairingOperation.invalidate, sessionToken: token),
              ),
            )
            .drain<void>();
      } catch (error) {
        failure = error;
      }
    }
    if (previousState.role == PairingRole.receiver && previousState.ssid != null && checkPlatform([TargetPlatform.android])) {
      try {
        await android_channel.disconnectFromWifiHotspotAndroid();
      } catch (error) {
        failure ??= error;
      }
    }
    for (final subscription in _sessionSubscriptions) {
      await subscription.cancel();
    }
    _sessionSubscriptions.clear();
    final shouldStopHotspot = _hotspot != null && !disconnected;
    _hotspot = null;
    if (shouldStopHotspot) {
      try {
        await android_channel.stopLocalOnlyHotspotAndroid();
      } catch (error) {
        failure ??= error;
      }
    }
    if (checkPlatform([TargetPlatform.android]) && !shouldStopHotspot && (!disconnected || previousState.role == PairingRole.receiver)) {
      try {
        await android_channel.stopPairingKeepAliveAndroid();
      } catch (error) {
        failure ??= error;
      }
    }
    state = state.copyWith(
      phase: failure == null ? (expired ? PairingPhase.stopped : PairingPhase.idle) : PairingPhase.failed,
      sessionToken: null,
      qrPayload: null,
      ssid: null,
      password: null,
      expiresAt: null,
      peers: const [],
      role: null,
      mode: null,
      pin: null,
      pinRequired: false,
      failureReason: failure?.toString() ?? (expired ? 'Pairing session expired.' : null),
    );
    _lastQrPayload = null;
    _lastNearbyOffer = null;
    ref.notifier(pairingConnectionProvider).clear();
    _stopping = false;
  }

  Future<void> _cleanupFailedStart() async {
    await _disconnectSubscription?.cancel();
    _disconnectSubscription = null;
    final token = state.sessionToken;
    if (token != null) {
      await ref
          .redux(parentIsolateProvider)
          .dispatchTakeResult(
            IsolateHttpServerPairingAction(
              task: HttpServerPairingTask(operation: HttpServerPairingOperation.invalidate, sessionToken: token),
            ),
          )
          .drain<void>();
    }
    if (_hotspot != null) {
      _hotspot = null;
      await android_channel.stopLocalOnlyHotspotAndroid();
    }
  }

  Future<void> enterReceiver() async {
    if (state.role == PairingRole.sender && state.sessionToken != null) {
      state = state.copyWith(phase: PairingPhase.failed, failureReason: 'Stop the active sender session before starting receiver pairing.');
      return;
    }
    _lastQrPayload = null;
    _lastNearbyOffer = null;
    state = PairingState(
      phase: PairingPhase.enablingWifi,
      role: PairingRole.receiver,
      dartLog: state.dartLog,
      canUse5GMode: state.canUse5GMode,
    );
    _log('receive_enter', 'Receiver pairing opened');
    if (!checkPlatform([TargetPlatform.android])) {
      state = state.copyWith(phase: PairingPhase.scanning, wifiEnabled: null);
      return;
    }
    try {
      await _listenForNativeDisconnect();
      final result = await android_channel.enableWifiAndroid();
      if (!result.success) {
        state = state.copyWith(
          phase: PairingPhase.failed,
          wifiEnabled: false,
          failureReason: result.message ?? 'Wi-Fi could not be enabled (${result.path}).',
        );
        _log('wifi_enable_failed', 'Wi-Fi could not be enabled');
      } else {
        state = state.copyWith(phase: PairingPhase.scanning, wifiEnabled: true, failureReason: null);
        _log('wifi_enabled', 'Wi-Fi is enabled');
      }
    } catch (error) {
      state = state.copyWith(phase: PairingPhase.failed, wifiEnabled: false, failureReason: error.toString());
      _log('wifi_enable_failed', 'Wi-Fi could not be enabled');
    }
  }

  Future<void> receiveQr(PairQrPayload payload) async {
    _lastQrPayload = payload;
    state = state.copyWith(
      phase: PairingPhase.connecting,
      role: PairingRole.receiver,
      mode: PairingMode.qr,
      ssid: payload.ssid,
      password: payload.password,
      pinRequired: payload.pinRequired,
      failureReason: null,
    );
    _log('qr_scanned', 'Pairing QR code scanned');
    if (checkPlatform([TargetPlatform.android])) {
      try {
        final result = await android_channel.connectToWifiHotspotAndroid(ssid: payload.ssid, password: payload.password);
        if (!result.succeeded) {
          state = state.copyWith(
            phase: PairingPhase.manualGuide,
            failureReason: 'Automatic Wi-Fi connection failed (${result.code}): ${result.message}',
          );
          _log('wifi_connect_failed', 'Automatic Wi-Fi connection failed');
          return;
        }
      } catch (error) {
        state = state.copyWith(phase: PairingPhase.manualGuide, failureReason: error.toString());
        _log('wifi_connect_failed', 'Automatic Wi-Fi connection failed');
        return;
      }
    } else {
      state = state.copyWith(phase: PairingPhase.manualGuide, failureReason: 'Connect to the sender Wi-Fi network manually to continue.');
      _log('manual_wifi_guide', 'Manual Wi-Fi connection is required');
      return;
    }
    if (payload.pinRequired) {
      state = state.copyWith(phase: PairingPhase.waitingForPin);
      return;
    }
    await _joinQr(payload);
  }

  Future<void> continueAfterManualWifi() async {
    final payload = _lastQrPayload;
    if (payload == null) {
      state = state.copyWith(phase: PairingPhase.failed, failureReason: 'The pairing QR code is no longer available.');
      return;
    }
    if (payload.pinRequired) {
      state = state.copyWith(phase: PairingPhase.waitingForPin);
    } else {
      await _joinQr(payload);
    }
  }

  Future<void> submitPin(String pin) async {
    if (!isValidPin(pin)) {
      state = state.copyWith(phase: PairingPhase.failed, failureReason: 'PIN must be exactly six digits.');
      return;
    }
    final payload = _lastQrPayload;
    final offer = _lastNearbyOffer;
    if (payload != null) {
      await _joinQr(payload, pin: pin);
    } else if (offer != null) {
      await _joinNearby(offer, pin: pin);
    }
  }

  Future<void> retry() async {
    if (_lastQrPayload case final payload?) {
      await receiveQr(payload);
      return;
    }
    if (_lastNearbyOffer case final offer?) {
      await _joinNearby(offer);
      return;
    }
    await enterReceiver();
  }

  Future<void> _joinQr(PairQrPayload payload, {String? pin}) async {
    state = state.copyWith(phase: PairingPhase.joining, failureReason: null);
    _log('join_started', 'Joining pairing session');
    try {
      final localDevice = await _ensureLocalServer();
      final request = _joinRequest(payload.sessionToken, localDevice);
      final response = await ref
          .read(httpProvider)
          .pinnedTo(payload.fingerprint, timeout: const Duration(seconds: 3))
          .joinPairingWithPin(
            protocol: payload.https ? rust_model.ProtocolType.https : rust_model.ProtocolType.http,
            ip: payload.ip,
            port: payload.port,
            request: request,
            pin: pin,
          );
      if (!response.success) throw StateError('The pairing session was rejected by the sender.');
      state = state.copyWith(phase: PairingPhase.joined, failureReason: null);
      ref.notifier(pairingConnectionProvider).connect(role: PairingRole.receiver, sessionToken: payload.sessionToken, peers: [response.sender]);
      await _keepPairingServiceAlive();
      _log(
        'join_result',
        'POST ${_joinUrl(payload.https, payload.ip, payload.port)} -> HTTP 200; ${pin == null ? 'PIN not required' : 'PIN accepted'}',
      );
      _log('join_succeeded', 'Joined pairing session');
    } catch (error) {
      final status = error is RsHttpClientError_StatusCode ? error.status : null;
      final pinRequired = status == 403 && (payload.pinRequired || _isPairingPinError(error));
      _log(
        'join_result',
        'POST ${_joinUrl(payload.https, payload.ip, payload.port)} -> HTTP ${status ?? 'error'}: ${_safePairingError(error)}${pinRequired ? '; PIN rejected or required' : ''}',
      );
      state = state.copyWith(
        phase: pinRequired ? PairingPhase.waitingForPin : PairingPhase.failed,
        pinRequired: pinRequired || payload.pinRequired,
        failureReason: pinRequired
            ? 'A six-digit PIN is required or incorrect.'
            : status == 429
            ? 'Pairing is locked after too many incorrect PIN attempts.'
            : error.toString(),
      );
      _log('join_failed', 'Could not join pairing session');
    }
  }

  Future<void> scanNearbyOffers() async {
    final wifiFailure = state.wifiEnabled == false ? state.failureReason : null;
    state = state.copyWith(
      phase: PairingPhase.scanning,
      role: PairingRole.receiver,
      mode: PairingMode.sameNetwork,
      offers: const [],
      failureReason: wifiFailure,
    );
    _log('nearby_scan_started', 'Searching for nearby pairing offers');
    try {
      ref.redux(nearbyDevicesProvider).dispatch(ClearFoundDevicesAction());
      await ref.global.dispatchAsync(StartSmartScan());
      final discoveredDevices = ref.read(nearbyDevicesProvider).devices.values.toList();
      for (final device in discoveredDevices) {
        final ip = device.ip ?? 'unknown IP';
        final protocol = device.https ? rust_model.ProtocolType.https : rust_model.ProtocolType.http;
        _log('device_found', 'Found ${device.alias} at $ip:${device.port} (${protocol.name})');
      }
      final devices = discoveredDevices.where((device) => device.ip != null && device.port > 0).toList();
      final offers = <PairingNearbyOffer>[];
      for (final device in devices) {
        final protocol = device.https ? rust_model.ProtocolType.https : rust_model.ProtocolType.http;
        final url = _sendOfferUrl(device.https, device.ip!, device.port);
        try {
          final offer = await ref
              .read(httpProvider)
              .pinnedTo(device.fingerprint, timeout: const Duration(milliseconds: 900))
              .sendOffer(
                protocol: protocol,
                ip: device.ip!,
                port: device.port,
              );
          if (offer != null && offer.expiresAtMs.toInt() > DateTime.now().millisecondsSinceEpoch) {
            offers.add(PairingNearbyOffer(device: device, offer: offer));
            _log('send_offer_result', 'GET $url -> HTTP 200; active offer found');
          } else if (offer == null) {
            _log('send_offer_result', 'GET $url -> HTTP 404; no active offer');
          } else {
            _log('send_offer_result', 'GET $url -> HTTP 200; expired offer ignored');
          }
        } catch (error) {
          final status = error is RsHttpClientError_StatusCode ? error.status : null;
          _log('send_offer_error', 'GET $url -> HTTP ${status ?? 'error'}: ${_safePairingError(error)}');
        }
      }
      state = state.copyWith(phase: PairingPhase.scanning, offers: offers);
      if (offers.isEmpty && wifiFailure == null) {
        state = state.copyWith(failureReason: 'No active pairing offers were found.');
      }
    } catch (error) {
      state = state.copyWith(phase: PairingPhase.failed, failureReason: error.toString());
      _log('nearby_scan_failed', 'Could not search for nearby pairing offers');
    }
  }

  Future<void> joinNearby(PairingNearbyOffer offer) async {
    _lastNearbyOffer = offer;
    await _joinNearby(offer);
  }

  Future<void> _joinNearby(PairingNearbyOffer item, {String? pin}) async {
    state = state.copyWith(phase: PairingPhase.joining, role: PairingRole.receiver, mode: PairingMode.sameNetwork, failureReason: null);
    _log('nearby_join_started', 'Joining nearby pairing offer');
    try {
      final localDevice = await _ensureLocalServer();
      final request = _joinRequest(item.offer.joinToken, localDevice);
      final response = await ref
          .read(httpProvider)
          .pinnedTo(item.device.fingerprint, timeout: const Duration(seconds: 3))
          .joinPairingWithPin(
            protocol: item.device.https ? rust_model.ProtocolType.https : rust_model.ProtocolType.http,
            ip: item.device.ip!,
            port: item.device.port,
            request: request,
            pin: pin,
          );
      if (!response.success) throw StateError('The pairing session was rejected by the sender.');
      state = state.copyWith(phase: PairingPhase.joined);
      ref.notifier(pairingConnectionProvider).connect(role: PairingRole.receiver, sessionToken: item.offer.joinToken, peers: [response.sender]);
      await _keepPairingServiceAlive();
      _log(
        'join_result',
        'POST ${_joinUrl(item.device.https, item.device.ip!, item.device.port)} -> HTTP 200; ${pin == null ? 'PIN not required' : 'PIN accepted'}',
      );
      _log('nearby_join_succeeded', 'Joined nearby pairing session');
    } catch (error) {
      final status = error is RsHttpClientError_StatusCode ? error.status : null;
      final pinRequired = status == 403 && _isPairingPinError(error);
      _log(
        'join_result',
        'POST ${_joinUrl(item.device.https, item.device.ip!, item.device.port)} -> HTTP ${status ?? 'error'}: ${_safePairingError(error)}${pinRequired ? '; PIN rejected or required' : ''}',
      );
      state = state.copyWith(
        phase: pinRequired ? PairingPhase.waitingForPin : PairingPhase.failed,
        pinRequired: pinRequired,
        failureReason: pinRequired
            ? 'A six-digit PIN is required or incorrect.'
            : status == 429
            ? 'Pairing is locked after too many incorrect PIN attempts.'
            : error.toString(),
      );
      _log('nearby_join_failed', 'Could not join nearby pairing offer');
    }
  }

  PairingJoinRequest _joinRequest(String sessionToken, Device localDevice) {
    return PairingJoinRequest(
      sessionToken: sessionToken,
      fingerprint: localDevice.fingerprint,
      alias: localDevice.alias,
      version: localDevice.version,
      deviceModel: localDevice.deviceModel,
      deviceType: localDevice.deviceType.toRust(),
      port: localDevice.port,
      protocol: localDevice.https ? rust_model.ProtocolType.https : rust_model.ProtocolType.http,
      hasWebInterface: localDevice.download,
    );
  }

  Future<Device> _ensureLocalServer() async {
    if (ref.read(serverProvider) == null) {
      _log('receiver_server_start', 'Starting the local HTTP server for pairing');
      await ref.notifier(serverProvider).startServerFromSettings();
    }
    final device = ref.read(deviceFullInfoProvider);
    if (device.port < 1 || device.ip == '-') throw StateError('The local receive server has no usable host address.');
    _log('receiver_server_ready', 'Local HTTP server ready at ${device.ip}:${device.port} (${device.https ? 'https' : 'http'})');
    return device;
  }

  String _sendOfferUrl(bool https, String ip, int port) =>
      Uri(scheme: https ? 'https' : 'http', host: ip, port: port, path: '/api/omnidrop/v1/send-offer').toString();

  String _joinUrl(bool https, String ip, int port) =>
      Uri(scheme: https ? 'https' : 'http', host: ip, port: port, path: '/api/omnidrop/v1/join').toString();

  Future<List<PairingLogEntry>> readPairingLog() async {
    final nativeEntries = checkPlatform([TargetPlatform.android])
        ? await android_channel.getNativePairingLogAndroid()
        : <android_channel.AndroidPairingLogEntry>[];
    final entries = [
      ...nativeEntries.map((entry) => PairingLogEntry(timestamp: entry.timestamp, step: entry.step, message: entry.message)),
      ...state.dartLog,
    ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return entries;
  }

  bool get canUse5GMode => state.canUse5GMode;

  Future<void> refreshNearby() => scanNearbyOffers();

  Future<void> _listenForNativeDisconnect() async {
    if (!checkPlatform([TargetPlatform.android]) || _disconnectSubscription != null) return;
    _disconnectSubscription = android_channel.pairingDisconnectEvents.listen((_) => unawaited(stop(disconnected: true)));
  }

  Future<void> _keepPairingServiceAlive() async {
    if (!checkPlatform([TargetPlatform.android])) return;
    try {
      await android_channel.startPairingKeepAliveAndroid();
      _log('service_keepalive_started', 'Pairing foreground service is keeping the connection alive');
    } catch (error) {
      _log('service_keepalive_failed', 'Could not keep the pairing connection alive: ${_safePairingError(error)}');
    }
  }
}
