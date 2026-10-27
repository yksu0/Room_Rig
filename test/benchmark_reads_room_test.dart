import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:room_rig/models/app_state.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/screens/benchmark_screen.dart';
import 'package:room_rig/services/benchmark_layouts.dart';

/// The Benchmark used to seed "My Room" from a demo layout and push it into the Room,
/// so opening a tab silently replaced the user's room. These lock that shut.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'room_rig.onboarding_seen': true});
  });

  Future<AppState> pumpBenchmark(WidgetTester tester, String mode) async {
    final state = AppState();
    state.setBenchmarkMode(mode);
    state.setTab(benchmarkTabIndex);
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: BenchmarkScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return state;
  }

  String fp(List<FurnitureItem> items) => BenchmarkLayoutBuilder.fingerprintOf(items);

  for (final mode in const ['airflow', 'lighting', 'ergonomics']) {
    testWidgets('opening the $mode benchmark leaves the Room untouched', (tester) async {
      final probe = AppState();
      await tester.pump(const Duration(milliseconds: 20));
      final expected = fp(probe.furniture);

      final state = await pumpBenchmark(tester, mode);

      expect(
        fp(state.furniture),
        expected,
        reason: 'opening the $mode benchmark rewrote the user\'s furniture',
      );
      expect(state.selectedPreset, probe.selectedPreset);
    });

    testWidgets('the $mode benchmark shows the furniture the user actually has', (tester) async {
      final state = await pumpBenchmark(tester, mode);

      // A layout the demo prototypes never produce.
      state.beginFurnitureGesture();
      state.moveFurniture('bed', 0.0, 0.0);
      state.endFurnitureGesture();
      await tester.pump(const Duration(milliseconds: 100));

      final bed = state.furniture.firstWhere((f) => f.id == 'bed');
      final layouts = BenchmarkLayoutBuilder.build(
        mode: BenchmarkMode.values.byName(mode),
        roomFurniture: state.furniture,
        gridCols: state.currentRoomData.gridCols,
        gridRows: state.currentRoomData.gridRows,
      );
      final benchmarked = layouts.myRoom.firstWhere((f) => f.id == 'bed');

      expect(benchmarked.gridX, bed.gridX);
      expect(benchmarked.gridY, bed.gridY);
      expect(state.furniture.firstWhere((f) => f.id == 'bed').gridY, bed.gridY,
          reason: 'the benchmark must not have moved it back');
    });

    testWidgets('the $mode benchmark defaults to Current Room, not the sample', (tester) async {
      await pumpBenchmark(tester, mode);
      expect(find.text('Current Room'), findsWidgets);
      expect(find.text('Auto-Rig'), findsWidgets);
      expect(find.text('Layout'), findsWidgets);
      expect(find.text('Analyze'), findsWidgets);
      expect(find.text('Results'), findsWidgets);
    });
  }

  testWidgets('switching benchmark modes never rewrites the Room', (tester) async {
    final state = await pumpBenchmark(tester, 'airflow');
    state.beginFurnitureGesture();
    state.moveFurniture('desk', 3.0, 5.0);
    state.endFurnitureGesture();
    await tester.pump(const Duration(milliseconds: 100));
    final expected = fp(state.furniture);

    for (final mode in const ['lighting', 'ergonomics', 'airflow']) {
      state.setBenchmarkMode(mode);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(fp(state.furniture), expected, reason: 'switching to $mode rewrote the Room');
    }
  });

  testWidgets('the visible benchmark redraws when furniture moves', (tester) async {
    final state = await pumpBenchmark(tester, 'airflow');
    expect(find.text('Current Room'), findsWidgets);

    // The layout preview is keyed by the room fingerprint, so its key only
    // changes once the benchmark has actually re-read the Room. The AnimatedSwitcher
    // holds the outgoing child for its transition, so collect every key.
    Set<String> previewKeys() => tester
        .widgetList<KeyedSubtree>(find.byType(KeyedSubtree))
        .map((w) => w.key)
        .whereType<ValueKey<String>>()
        .map((k) => k.value)
        .where((v) => v.startsWith('myRoom_'))
        .toSet();

    final before = previewKeys();
    expect(before, isNotEmpty);

    state.beginFurnitureGesture();
    state.moveFurniture('shelf', 0.0, 4.0);
    state.endFurnitureGesture();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      previewKeys().intersection(before),
      isEmpty,
      reason: 'the benchmark kept showing the stale room',
    );
  });

  testWidgets('a hidden benchmark does not resimulate while you drag on the Room', (tester) async {
    final state = await pumpBenchmark(tester, 'airflow');
    state.setTab(roomTabIndex); // Room
    await tester.pump(const Duration(milliseconds: 50));

    // Whatever the benchmark is holding must survive a drag it cannot see, so a
    // pointer-frame storm on the Room never pays for three field solves.
    for (int i = 0; i < 8; i++) {
      state.beginFurnitureGesture();
      state.moveFurniture('shelf', i * 0.2, 4.0);
      state.endFurnitureGesture();
      await tester.pump();
    }

    state.setTab(benchmarkTabIndex);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Coming back to the tab picks the room back up.
    final shelf = state.furniture.firstWhere((f) => f.id == 'shelf');
    final layouts = BenchmarkLayoutBuilder.build(
      mode: BenchmarkMode.airflow,
      roomFurniture: state.furniture,
      gridCols: state.currentRoomData.gridCols,
      gridRows: state.currentRoomData.gridRows,
    );
    expect(layouts.myRoom.firstWhere((f) => f.id == 'shelf').gridX, shelf.gridX);
  });

  testWidgets('asking for the sample room shows it without touching the Room', (tester) async {
    final state = await pumpBenchmark(tester, 'airflow');
    final expected = fp(state.furniture);

    // What the Room's "Sample Room" button does.
    state.focusBenchmarkLayout(BenchmarkLayoutKind.sample);
    state.setTab(benchmarkTabIndex);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(fp(state.furniture), expected, reason: 'the sample was stamped over the Room');
    expect(find.text('Sample room — AC in a corner, weak coverage'), findsOneWidget);

    // And it is a one-shot: the user can go straight back to their own room.
    await tester.tap(find.text('Current Room').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Current Room'), findsWidgets);
  });

  testWidgets('applying an improved layout keeps the room you were in', (tester) async {
    final state = AppState();
    state.selectPreset(RoomPreset.homeOffice);
    final before = state.selectedPreset;

    final layouts = BenchmarkLayoutBuilder.build(
      mode: BenchmarkMode.airflow,
      roomFurniture: state.furniture,
      gridCols: state.currentRoomData.gridCols,
      gridRows: state.currentRoomData.gridRows,
    );
    state.applyFurnitureLayout(layouts.improved, markOptimized: true);

    expect(state.selectedPreset, before, reason: 'apply must not swap the room preset');
    expect(
      state.furniture.map((f) => f.id).toSet(),
      layouts.improved.map((f) => f.id).toSet(),
    );
  });
}
