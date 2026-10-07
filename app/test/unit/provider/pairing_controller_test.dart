import 'package:localsend_app/provider/pairing/pairing_controller.dart';
import 'package:localsend_app/util/qr_payload_parser.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:test/test.dart';

void main() {
  test('single-recipient paired control event closes selection', () async {
    final service = Notifier.test(
      notifier: PairingController(),
      initialState: const PairingState(phase: PairingPhase.peerJoined, role: PairingRole.sender),
    );

    await service.notifier.handleControlEvent('paired');

    expect(service.state.phase, PairingPhase.closedForSelection);
    expect(service.state.sessionToken, isNull);
  });

  test('multi-recipient paired control event keeps the session open', () async {
    final service = Notifier.test(
      notifier: PairingController(),
      initialState: const PairingState(
        phase: PairingPhase.peerJoined,
        role: PairingRole.sender,
        sessionToken: 'active-session',
        multiRecipient: true,
      ),
    );

    await service.notifier.handleControlEvent('paired');

    expect(service.state.phase, PairingPhase.peerJoined);
    expect(service.state.sessionToken, 'active-session');
  });

  test('invalid PIN is rejected before attempting a join', () async {
    final service = Notifier.test(
      notifier: PairingController(),
      initialState: const PairingState(phase: PairingPhase.waitingForPin, role: PairingRole.receiver),
    );

    await service.notifier.submitPin('12345');

    expect(service.state.phase, PairingPhase.failed);
    expect(service.state.failureReason, 'PIN must be exactly six digits.');
  });

  test('receiver can retry after manual Wi-Fi fallback', () async {
    final service = Notifier.test(notifier: PairingController());
    const payload = PairQrPayload(
      alias: 'sender',
      ip: '192.168.1.2',
      port: 53317,
      https: true,
      fingerprint: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      sessionToken: 'session-token',
      ssid: 'network',
      password: 'password',
      pinRequired: true,
      expiresAtMs: 4_000_000_000_000,
    );

    await service.notifier.receiveQr(payload);
    expect(service.state.phase, PairingPhase.manualGuide);

    await service.notifier.continueAfterManualWifi();
    expect(service.state.phase, PairingPhase.waitingForPin);

    await service.notifier.retry();
    expect(service.state.phase, PairingPhase.manualGuide);
  });

  test('control events do not tear down the session; explicit stop does', () async {
    final service = Notifier.test(
      notifier: PairingController(),
      initialState: const PairingState(
        phase: PairingPhase.peerJoined,
        role: PairingRole.sender,
        sessionToken: 'active-session',
      ),
    );

    await service.notifier.handleControlEvent('finalized');
    expect(service.state.phase, PairingPhase.closedForSelection);
    expect(service.state.sessionToken, 'active-session');

    final explicitStop = Notifier.test(
      notifier: PairingController(),
      initialState: const PairingState(phase: PairingPhase.peerJoined, role: PairingRole.sender),
    );
    await explicitStop.notifier.stop();
    expect(explicitStop.state.phase, PairingPhase.stopped);
  });
}
