import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/config/crash_report.dart';

void main() {
  test('sanitizes credential and PIN values from crash text', () {
    const text = 'password=hunter2 access_token=token-value PIN is 123456 Bearer bearer-value';

    final sanitized = sanitizeCrashText(text);

    expect(sanitized, isNot(contains('hunter2')));
    expect(sanitized, isNot(contains('token-value')));
    expect(sanitized, isNot(contains('123456')));
    expect(sanitized, isNot(contains('bearer-value')));
    expect(sanitized, contains('[REDACTED]'));
  });
}
