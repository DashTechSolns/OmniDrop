import 'package:localsend_app/util/qr_payload_parser.dart';
import 'package:test/test.dart';

void main() {
  group('parseQrPayload', () {
    test('parses a complete OmniDrop pairing code', () {
      final fingerprint = List.filled(64, 'A').join();
      final expiresAtMs = DateTime.now().millisecondsSinceEpoch + 60000;
      final parsed = parseQrPayload(
        Uri(
          scheme: 'omnidrop',
          host: 'pair',
          queryParameters: {
            'alias': 'Phone',
            'ip': '192.168.1.4',
            'port': '53317',
            'https': 'true',
            'fp': fingerprint,
            'token': 'once',
            'ssid': 'OmniDrop',
            'password': 'wifi-password',
            'pin': 'false',
            'exp': '$expiresAtMs',
          },
        ).toString(),
      );

      expect(parsed, isA<ParsedPairQr>());
      final payload = (parsed as ParsedPairQr).payload;
      expect(payload.alias, 'Phone');
      expect(payload.ip, '192.168.1.4');
      expect(payload.port, 53317);
      expect(payload.https, isTrue);
      expect(payload.fingerprint, fingerprint);
      expect(payload.sessionToken, 'once');
      expect(payload.ssid, 'OmniDrop');
      expect(payload.password, 'wifi-password');
      expect(payload.pinRequired, isFalse);
      expect(payload.expiresAtMs, expiresAtMs);
    });

    test('rejects incomplete or invalid pairing codes', () {
      expect(parseQrPayload('omnidrop://pair?alias=Phone&ip=192.168.1.4&port=0&https=false&fp=ABCD&sid=once'), isA<InvalidQrPayload>());
      expect(parseQrPayload('omnidrop://pair?alias=Phone&ip=192.168.1.4&port=53317&https=false&fp=ABCD'), isA<InvalidQrPayload>());
      expect(parseQrPayload('omnidrop://other?value=1'), isA<InvalidQrPayload>());
    });

    test('recognizes WebDrop links as a separate QR type', () {
      final parsed = parseQrPayload('https://192.168.1.4:53317/download');

      expect(parsed, isA<ParsedWebDropQr>());
      expect((parsed as ParsedWebDropQr).uri.path, '/download');
    });
  });
}
