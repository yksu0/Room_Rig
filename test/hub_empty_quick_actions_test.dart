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
      if (s.contains('A RenderFlex overflowed')) {
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

  testWidgets('Hub empty: Create via FAB only — no Get Started / Quick Create',
      (tester) async {
    ignoreLayoutNoise();
    final state = AppState();
    expect(state.roomIsReady, isFalse);
    await pumpHome(tester, state);

    expect(find.text('GET STARTED'), findsNothing);
    expect(find.text('Create room'), findsNothing);
    expect(find.text('QUICK ACTIONS'), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('Scan (opt.)'), findsNothing);
    expect(find.textContaining('Scan in Quick Actions'), findsNothing);
    expect(find.textContaining('Tap the + button'), findsWidgets);
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

  testWidgets('Hub score subtitle and journey chips layout at 360 and 412dp', (tester) async {
    ignoreLayoutNoise();
    for (final width in const [360.0, 412.0]) {
      final state = AppState();
      state.createManualRoom(name: 'Studio', lengthMeters: 3.6, widthMeters: 4.8);
      await tester.binding.setSurfaceSize(Size(width, 740));
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
      await tester.pump(const Duration(seconds: 1));

      expect(find.byKey(const ValueKey('hub_score_subtitle')), findsOneWidget,
          reason: 'subtitle at ${width}dp');
      expect(find.byKey(const ValueKey('hub_journey_steps')), findsOneWidget,
          reason: 'journey at ${width}dp');
      expect(find.text('1. Edit Room'), findsOneWidget, reason: 'Edit Room at ${width}dp');
      expect(find.text('2. Benchmark'), findsOneWidget, reason: 'Benchmark at ${width}dp');
      expect(find.text('3. Apply'), findsOneWidget, reason: 'Apply at ${width}dp');
      // Flush AppState guest-scrub timer before swapping the tree for the next width.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });
}
