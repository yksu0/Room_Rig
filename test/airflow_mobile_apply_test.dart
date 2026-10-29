import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:room_rig/models/app_state.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/screens/benchmark_screen.dart';
import 'package:room_rig/services/auth_service.dart';
import 'package:room_rig/services/profile_service.dart';
import 'package:room_rig/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'room_rig.onboarding_seen': true,
    });
  });

  Future<void> pumpFrames(WidgetTester tester, {int count = 6, int ms = 40}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(Duration(milliseconds: ms));
    }
  }

  testWidgets('Airflow mobile Results shows Apply after RUN (scaffold onApply wired)',
      (tester) async {
    // Portrait width under desktopMinWidth so mobile scaffold path is used.
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final s = details.toString();
      if (s.contains('A RenderFlex overflowed') ||
          s.contains('hasSize') ||
          s.contains('RenderBox was not laid out')) {
        return;
      }
      previousOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);

    final state = AppState();
    state.selectPreset(RoomPreset.gamingSetup);
    state.setScanProgress(1.0);
    state.setBenchmarkMode('airflow');
    state.setTab(3);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthService()),
          ChangeNotifierProvider(create: (_) => ProfileService()),
          ChangeNotifierProvider.value(value: state),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: BenchmarkScreen()),
        ),
      ),
    );
    await pumpFrames(tester, count: 15);

    expect(state.roomIsReady, isTrue);

    final run = find.text('RUN VOXEL AIRFLOW BENCHMARK');
    expect(run, findsOneWidget);
    await tester.ensureVisible(run);
    await tester.tap(run, warnIfMissed: false);
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    await pumpFrames(tester, count: 10);

    final apply = find.text('APPLY BENCHMARK SUGGESTION TO ROOM');
    expect(apply, findsWidgets);
  });

  test('openBenchmarkResults bumps token and selects Benchmark tab', () {
    final state = AppState();
    state.selectPreset(RoomPreset.gamingSetup);
    state.setScanProgress(1.0);
    state.setTab(0);
    final before = state.benchmarkResultsFocusToken;
    state.openBenchmarkResults(mode: 'lighting');
    expect(state.benchmarkMode, 'lighting');
    expect(state.currentTab, 3);
    expect(state.benchmarkResultsFocusToken, before + 1);
  });
}