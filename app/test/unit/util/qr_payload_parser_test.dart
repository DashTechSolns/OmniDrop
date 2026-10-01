import 'package:localsend_app/util/qr_payload_parser.dart';
import 'package:test/test.dart';

void main() {
  group('parseQrPayload', () {
    test('parses a complete OmniDrop pairing code', () {
      final parsed = parseQrPayload('omnidrop://pair?alias=Phone&ip=192.168.1.4&port=53317&https=true&fp=ABCD&sid=once');

      expect(parsed, isA<ParsedPairQr>());
      final payload = (parsed as ParsedPairQr).payload;
      expect(payload.alias, 'Phone');
      expect(payload.ip, '192.168.1.4');
      expect(payload.port, 53317);
      expect(payload.https, isTrue);
      expect(payload.fingerprint, 'ABCD');
      expect(payload.sessionId, 'once');
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