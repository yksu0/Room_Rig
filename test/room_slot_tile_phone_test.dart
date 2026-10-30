import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/screens/home_screen.dart';
import 'package:room_rig/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('RoomSlotTile taps isolate at 360 and 412dp with 48dp targets', (tester) async {
    for (final width in const [360.0, 412.0]) {
      var tileTaps = 0;
      var duplicateTaps = 0;
      var deleteTaps = 0;

      await tester.binding.setSurfaceSize(Size(width, 740));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(8),
              child: RoomSlotTile(
                title: 'Studio',
                subtitle: 'Current lot',
                badgeLabel: '3',
                selected: true,
                onTap: () => tileTaps++,
                onDuplicate: () => duplicateTaps++,
                onDelete: () => deleteTaps++,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final dup = find.byKey(const ValueKey('room_slot_duplicate'));
      final del = find.byKey(const ValueKey('room_slot_delete'));
      final tile = find.byKey(const ValueKey('room_slot_tile'));
      expect(dup, findsOneWidget, reason: 'duplicate at ${width}dp');
      expect(del, findsOneWidget, reason: 'delete at ${width}dp');
      expect(tile, findsOneWidget, reason: 'tile at ${width}dp');

      final dupSize = tester.getSize(dup);
      final delSize = tester.getSize(del);
      expect(dupSize.width, greaterThanOrEqualTo(48),
          reason: 'duplicate width at ${width}dp was ${dupSize.width}');
      expect(dupSize.height, greaterThanOrEqualTo(48),
          reason: 'duplicate height at ${width}dp was ${dupSize.height}');
      expect(delSize.width, greaterThanOrEqualTo(48),
          reason: 'delete width at ${width}dp was ${delSize.width}');
      expect(delSize.height, greaterThanOrEqualTo(48),
          reason: 'delete height at ${width}dp was ${delSize.height}');

      await tester.tap(dup);
      await tester.pump();
      expect(duplicateTaps, 1, reason: 'duplicate fired at ${width}dp');
      expect(tileTaps, 0, reason: 'tile must not fire on duplicate at ${width}dp');
      expect(deleteTaps, 0, reason: 'delete must not fire on duplicate at ${width}dp');

      await tester.tap(del);
      await tester.pump();
      expect(deleteTaps, 1, reason: 'delete fired at ${width}dp');
      expect(tileTaps, 0, reason: 'tile must not fire on delete at ${width}dp');
      expect(duplicateTaps, 1, reason: 'duplicate unchanged after delete at ${width}dp');

      // Tap the title text area (not the action buttons) to select the tile.
      await tester.tap(find.text('Studio'));
      await tester.pump();
      expect(tileTaps, 1, reason: 'tile onTap at ${width}dp');
      expect(duplicateTaps, 1, reason: 'duplicate unchanged after tile tap at ${width}dp');
      expect(deleteTaps, 1, reason: 'delete unchanged after tile tap at ${width}dp');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });
}