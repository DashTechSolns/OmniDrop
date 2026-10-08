import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/pages/transfer/transfer_gauge.dart';

void main() {
  test('transfer gauge maps progress to the 72 tick ring', () {
    expect(completedTransferGaugeTicks(-0.5), 0);
    expect(completedTransferGaugeTicks(0), 0);
    expect(completedTransferGaugeTicks(0.25), 18);
    expect(completedTransferGaugeTicks(0.5), 36);
    expect(completedTransferGaugeTicks(1), 72);
    expect(completedTransferGaugeTicks(1.5), 72);
  });
}
