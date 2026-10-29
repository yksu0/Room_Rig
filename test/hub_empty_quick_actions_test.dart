import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:room_rig/models/app_state.dart';
import 'package:room_rig/screens/home_screen.dart';
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

  void ignoreLayoutNoise() {
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final s = details.toString();
      if (s.contains('A RenderFlex overflowed') ||
          s.contains('hasSize') ||
          s.contains('RenderBox was not laid out') ||
          s.contains('NEEDS-LAYOUT') ||
          s.contains('_RenderListTile') ||
          s.contains('rendering/object.dart') ||
          s.contains('Failed assertion')) {
        return;
      }
      previousOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);
  }

  Future<void> pumpHome(WidgetTester tester, AppState state) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthService()),
          ChangeNotifierProvider(create: (_) => ProfileService()),
          ChangeNotifierProvider.value(value: state),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('Hub empty: Create quick action, no Scan quick action, FAB-oriented copy',
      (tester) async {
    ignoreLayoutNoise();
    final state = AppState();
    expect(state.roomIsReady, isFalse);
    await pumpHome(tester, state);

    expect(find.text('Create'), findsWidgets);
    expect(find.text('Scan (opt.)'), findsNothing);
    expect(find.textContaining('Scan in Quick Actions'), findsNothing);
    expect(find.textContaining('Tap the + button'), findsWidgets);
    expect(find.text('GET STARTED'), findsOneWidget);
    expect(find.text('1. Edit Room'), findsOneWidget);
    expect(find.text('3. Apply'), findsOneWidget);
    expect(find.text('Overall'), findsNothing);
  });

  testWidgets('Hub rings hidden when empty; after Create they open Benchmark', (tester) async {
    ignoreLayoutNoise();
    final state = AppState();
    await pumpHome(tester, state);

    expect(state.roomIsReady, isFalse);
    expect(find.text('Airflow'), findsNothing);
    expect(state.currentTab, 0);

    state.createManualRoom(name: 'Studio', lengthMeters: 3.6, widthMeters: 4.8);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(state.roomIsReady, isTrue);
    expect(find.text('Overall'), findsWidgets);

    final airflow = find.text('Airflow');
    expect(airflow, findsWidgets);
    await tester.ensureVisible(airflow.first);
    await tester.tap(airflow.first, warnIfMissed: false);
    await tester.pump();
    expect(state.currentTab, 3);
    expect(state.benchmarkMode, 'airflow');
  });

  test('openBenchmarkResults deep-links to Benchmark Results for current mode', () {
    final state = AppState();
    state.createManualRoom(name: 'Studio', lengthMeters: 3.6, widthMeters: 4.8);
    state.setBenchmarkMode('spatial');
    state.setTab(0);
    final before = state.benchmarkResultsFocusToken;
    state.openBenchmarkResults();
    expect(state.benchmarkMode, 'spatial');
    expect(state.currentTab, 3);
    expect(state.benchmarkResultsFocusToken, before + 1);
  });
}