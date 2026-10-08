import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/pages/transfer/transfer_dock.dart';

void main() {
  testWidgets('dock displays the staged file count', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 360,
          height: 640,
          child: TransferDock(
            count: 7,
            active: false,
            bottomClearance: 80,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('dock drag snaps to the nearest screen edge', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 360,
          height: 640,
          child: TransferDock(
            count: 2,
            active: false,
            bottomClearance: 80,
            onTap: () {},
          ),
        ),
      ),
    );

    final dock = find.byKey(const ValueKey('transfer-dock'));
    expect(tester.getTopLeft(dock).dx, greaterThan(250));

    await tester.drag(dock, const Offset(-300, 80));
    await tester.pumpAndSettle();

    final snappedPosition = tester.getTopLeft(dock);
    expect(snappedPosition.dx, closeTo(12, 1));
    expect(snappedPosition.dy, greaterThanOrEqualTo(8));
    expect(snappedPosition.dy, lessThan(500));
  });
}
