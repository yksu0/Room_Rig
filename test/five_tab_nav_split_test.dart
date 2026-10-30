import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:room_rig/main.dart';
import 'package:room_rig/models/app_state.dart';
import 'package:room_rig/models/published_layout.dart';
import 'package:room_rig/screens/community_screen.dart';
import 'package:room_rig/services/auth_service.dart';
import 'package:room_rig/services/profile_service.dart';
import 'package:room_rig/services/published_layout_repository.dart';
import 'package:room_rig/theme/app_theme.dart';
import 'package:room_rig/widgets/room_icons.dart';

class _EmptyFeedRepo extends PublishedLayoutRepository {
  @override
  Future<List<PublishedLayout>> fetchBaselines({int limit = 20}) async =>
      const [];

  @override
  Future<List<PublishedLayout>> fetchRecent({int limit = 30}) async =>
      const [];

  @override
  Future<List<PublishedLayout>> fetchTop({int limit = 30}) async => const [];

  @override
  Future<List<PublishedLayout>> fetchMonthlyFeatured() async => const [];
}

/// Mirrors mobile `_RoomNavBar` label row (FittedBox + 5 items) for overflow checks.
class _NavBarProbe extends StatelessWidget {
  const _NavBarProbe();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: SizedBox(
        height: 76,
        child: Row(
          children: [
            for (final item in kAppNavItems)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SvgIcon(item.$1, size: 22, color: AppColors.textMuted),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        item.$2,
                        maxLines: 1,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

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

  test('Tab indices: five tabs with Scan centered', () {
    expect(appTabCount, 5);
    expect(hubTabIndex, 0);
    expect(roomTabIndex, 1);
    expect(scanTabIndex, 2);
    expect(benchmarkTabIndex, 3);
    expect(communityTabIndex, 4);
    expect(
      kAppNavItems.map((e) => e.$2).toList(),
      ['Hub', 'Room', 'Scan', 'Benchmark', 'Community'],
    );
  });

  for (final width in const [360.0, 390.0, 412.0]) {
    testWidgets(
        'Five-tab nav probe at ${width.toInt()}dp has no overflow',
        (tester) async {
      final overflows = <String>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        final s = details.toString();
        if (s.contains('A RenderFlex overflowed')) {
          overflows.add(s);
          return;
        }
        previousOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = previousOnError);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.binding.setSurfaceSize(Size(width, 740));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: SizedBox.shrink(),
            bottomNavigationBar: _NavBarProbe(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Hub'), findsOneWidget);
      expect(find.text('Room'), findsOneWidget);
      expect(find.text('Scan'), findsOneWidget);
      expect(find.text('Benchmark'), findsOneWidget);
      expect(find.text('Community'), findsOneWidget);
      expect(overflows, isEmpty, reason: overflows.join('\n'));
    });
  }

  for (final width in const [360.0, 390.0, 412.0]) {
    testWidgets(
        'Community empty guest states at ${width.toInt()}dp', (tester) async {
      ignoreLayoutNoise();
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final state = AppState(publishedLayouts: _EmptyFeedRepo());
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
            home: const CommunityScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // Drain AppState guest-orphan scrub Future.delayed(2s).
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('COMMUNITY'), findsOneWidget);
      expect(find.textContaining('No community layouts yet'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('community_guest_hint')),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  test('openBenchmarkResults lands on Benchmark Results step', () {
    final state = AppState();
    state.createManualRoom(name: 'Studio', lengthMeters: 3.6, widthMeters: 4.8);
    state.setBenchmarkMode('airflow');
    state.setTab(hubTabIndex);

    state.openBenchmarkResults(mode: 'airflow');
    expect(state.currentTab, benchmarkTabIndex);
    expect(state.benchmarkResultsFocusToken, greaterThan(0));
    expect(state.benchmarkMode, 'airflow');

    state.setBenchmarkMode('community');
    state.openBenchmarkResults();
    expect(state.benchmarkMode, 'airflow');
    expect(state.currentTab, benchmarkTabIndex);
  });
}