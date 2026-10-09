import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/pages/pairing/pairing_cards.dart';
import 'package:localsend_isolates/rust/api/model.dart' as rust_model;
import 'package:localsend_isolates/rust/api/pairing.dart';

PairingDeviceInfo _device(String fingerprint, String alias) => PairingDeviceInfo(
  fingerprint: fingerprint,
  alias: alias,
  version: '2.2',
  deviceModel: null,
  deviceType: null,
  ip: '192.168.1.2',
  port: 53317,
  protocol: rust_model.ProtocolType.http,
  hasWebInterface: false,
);

void main() {
  testWidgets('selecting all and individual recipients updates selection', (tester) async {
    await tester.pumpWidget(_SelectionHarness(peers: [_device('one', 'Phone'), _device('two', 'Tablet')]));

    expect(find.text('Selected: 0'), findsOneWidget);
    await tester.tap(find.text('All devices'));
    await tester.pump();
    expect(find.text('Selected: 2'), findsOneWidget);

    await tester.tap(find.text('Tablet'));
    await tester.pump();
    expect(find.text('Selected: 1'), findsOneWidget);
  });

  test('a single recipient is selected directly without a picker choice', () {
    final peer = _device('one', 'Phone');
    expect(pairingTargetsForSelection([peer], const {}), [peer]);
  });
}

class _SelectionHarness extends StatefulWidget {
  final List<PairingDeviceInfo> peers;

  const _SelectionHarness({required this.peers});

  @override
  State<_SelectionHarness> createState() => _SelectionHarnessState();
}

class _SelectionHarnessState extends State<_SelectionHarness> {
  Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final fingerprints = widget.peers.map((peer) => peer.fingerprint).toSet();
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            PairingTargetSelectionList(
              peers: widget.peers,
              selectedFingerprints: _selected,
              onToggleAll: (_) => setState(() => _selected = _selected.containsAll(fingerprints) ? {} : fingerprints),
              onTogglePeer: (fingerprint, checked) => setState(() {
                if (checked) {
                  _selected = {..._selected, fingerprint};
                } else {
                  _selected = {..._selected}..remove(fingerprint);
                }
              }),
            ),
            Text('Selected: ${_selected.length}'),
          ],
        ),
      ),
    );
  }
}
