import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/theme/app_theme.dart';
import 'package:room_rig/widgets/guest_import_dialog.dart';

void main() {
  test('guest import copy is singular for one room', () {
    expect(guestImportDialogTitle(1), "Keep this device's room?");
    expect(
      guestImportDialogBody(1),
      'A room made on this device as a guest is still here. '
      'Add it to your account, or discard it from this phone.',
    );
    expect(guestImportDialogBody(1).contains('rooms '), isFalse);
    expect(guestImportDialogBody(1).contains('them'), isFalse);
  });

  test('guest import copy is plural for multiple rooms', () {
    expect(guestImportDialogTitle(3), "Keep this device's rooms?");
    expect(
      guestImportDialogBody(3),
      '3 rooms made on this device as a guest are still here. '
      'Add them to your account, or discard them from this phone.',
    );
  });

  testWidgets('singular dialog shows room? title and singular body', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(scaffoldBackgroundColor: AppColors.bg),
        home: Builder(
          builder: (context) => Scaffold(
            body: buildGuestImportDialog(
              context: context,
              roomCount: 1,
              onDiscard: () {},
              onKeep: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text("Keep this device's room?"), findsOneWidget);
    expect(find.textContaining('A room made on this device'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);
    expect(find.text('Add to account'), findsOneWidget);
    expect(find.text("Keep this device's rooms?"), findsNothing);
  });
}
