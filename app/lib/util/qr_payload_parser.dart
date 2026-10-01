class PairQrPayload {
  final String alias;
  final String ip;
  final int port;
  final bool https;
  final String fingerprint;
  final String sessionId;

  const PairQrPayload({
    required this.alias,
    required this.ip,
    required this.port,
    required this.https,
    required this.fingerprint,
    required this.sessionId,
  });
}

sealed class ParsedQrPayload {
  const ParsedQrPayload();
}

class ParsedPairQr extends ParsedQrPayload {
  final PairQrPayload payload;

  const ParsedPairQr(this.payload);
}

class ParsedWebDropQr extends ParsedQrPayload {
  final Uri uri;

  const ParsedWebDropQr(this.uri);
}

class InvalidQrPayload extends ParsedQrPayload {
  const InvalidQrPayload();
}

ParsedQrPayload parseQrPayload(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null) return const InvalidQrPayload();

  if (uri.scheme == 'omnidrop' && uri.host == 'pair') {
    final alias = uri.queryParameters['alias'];
    final ip = uri.queryParameters['ip'];
    final port = int.tryParse(uri.queryParameters['port'] ?? '');
    final httpsValue = uri.queryParameters['https'];
    final fingerprint = uri.queryParameters['fp'];
    final sessionId = uri.queryParameters['sid'];
    if (alias == null || alias.isEmpty || ip == null || ip.isEmpty || port == null || port < 1 || port > 65535) {
      return const InvalidQrPayload();
    }
    if (httpsValue != 'true' && httpsValue != 'false' || fingerprint == null || fingerprint.isEmpty || sessionId == null || sessionId.isEmpty) {
      return const InvalidQrPayload();
    }
    return ParsedPairQr(
      PairQrPayload(
        alias: alias,
        ip: ip,
        port: port,
        https: httpsValue == 'true',
        fingerprint: fingerprint,
        sessionId: sessionId,
      ),
    );
  }

  if ((uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty) {
    return ParsedWebDropQr(uri);
  }

  return const InvalidQrPayload();
}