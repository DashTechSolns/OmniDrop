class PairQrPayload {
  final String alias;
  final String ip;
  final int port;
  final bool https;
  final String fingerprint;
  final String sessionToken;
  final String ssid;
  final String password;
  final int expiresAtMs;

  const PairQrPayload({
    required this.alias,
    required this.ip,
    required this.port,
    required this.https,
    required this.fingerprint,
    required this.sessionToken,
    required this.ssid,
    required this.password,
    required this.expiresAtMs,
  });
}

sealed class ParsedQrPayload {
  const ParsedQrPayload();
}

class ParsedPairQr extends ParsedQrPayload {
  final PairQrPayload payload;

  const ParsedPairQr(this.payload);
}

class ExpiredPairQr extends ParsedQrPayload {
  const ExpiredPairQr();
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
    final sessionToken = uri.queryParameters['token'];
    final ssid = uri.queryParameters['ssid'];
    final password = uri.queryParameters['password'];
    final expiresAtMs = int.tryParse(uri.queryParameters['exp'] ?? '');
    if (alias == null || alias.isEmpty || ip == null || ip.isEmpty || port == null || port < 1 || port > 65535) {
      return const InvalidQrPayload();
    }
    if (httpsValue != 'true' && httpsValue != 'false' ||
        fingerprint == null ||
        !RegExp(r'^[A-Fa-f0-9]{64}$').hasMatch(fingerprint) ||
        sessionToken == null ||
        sessionToken.isEmpty ||
        ssid == null ||
        ssid.isEmpty ||
        password == null ||
        password.isEmpty ||
        expiresAtMs == null) {
      return const InvalidQrPayload();
    }
    if (expiresAtMs <= DateTime.now().millisecondsSinceEpoch) return const ExpiredPairQr();
    return ParsedPairQr(
      PairQrPayload(
        alias: alias,
        ip: ip,
        port: port,
        https: httpsValue == 'true',
        fingerprint: fingerprint,
        sessionToken: sessionToken,
        ssid: ssid,
        password: password,
        expiresAtMs: expiresAtMs,
      ),
    );
  }

  if ((uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty) {
    return ParsedWebDropQr(uri);
  }

  return const InvalidQrPayload();
}