import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:room_rig/models/app_state.dart';
import 'package:room_rig/models/published_layout.dart';
import 'package:room_rig/screens/benchmark_screen.dart';
import 'package:room_rig/services/auth_service.dart';
import 'package:room_rig/services/profile_service.dart';
import 'package:room_rig/services/published_layout_repository.dart';
import 'package:room_rig/theme/app_theme.dart';
import 'package:room_rig/widgets/community_benchmark_panel.dart';

PublishedLayout _sampleLayout({
  String id = 'layout-1',
  String title = 'Cached Studio',
}) {
  return PublishedLayout(
    id: id,
    title: title,
    layout: const PublishedLayoutSnapshot(
      name: 'Studio',
      gridCols: 6,
      gridRows: 8,
      furniture: [],
    ),
    publishedAt: DateTime.utc(2026, 1, 15),
    upCount: 3,
    downCount: 0,
    netScore: 3,
  );
}

class _ThrowingFeedRepo extends PublishedLayoutRepository {
  @override
  Future<List<PublishedLayout>> fetchBaselines({int limit = 20}) async {
    throw Exception('offline');
  }

  @override
  Future<List<PublishedLayout>> fetchRecent({int limit = 30}) async {
    throw Exception('offline');
  }

  @override
  Future<List<PublishedLayout>> fetchTop({int limit = 30}) async {
    throw Exception('offline');
  }

  @override
  Future<List<PublishedLayout>> fetchMonthlyFeatured() async {
    throw Exception('offline');
  }
}

/// Holds the first fetch until [complete] so the loading spinner stays visible.
class _HangingFeedRepo extends PublishedLayoutRepository {
  final Completer<List<PublishedLayout>> _baselines = Completer();

  void complete([List<PublishedLayout>? layouts]) {
    if (!_baselines.isCompleted) {
      _baselines.complete(layouts ?? const []);
    }
  }

  @override
  Future<List<PublishedLayout>> fetchBaselines({int limit = 20}) => _baselines.future;

  @override
  Future<List<PublishedLayout>> fetchRecent({int limit = 30}) async => const [];

  @override
  Future<List<PublishedLayout>> fetchTop({int limit = 30}) async => const [];

  @override
  Future<List<PublishedLayout>> fetchMonthlyFeatured() async => const [];
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

  Future<void> pumpCommunity(
    WidgetTester tester, {
    required AppState state,
    required double width,
  }) async {
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
          home: const Scaffold(body: CommunityBenchmarkPanel()),
        ),
      ),
    );
  }

  testWidgets('Community guest sees sign-in unlock hint', (tester) async {
    ignoreLayoutNoise();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final state = AppState();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthService()),
          ChangeNotifierProvider(create: (_) => ProfileService()),
          ChangeNotifierProvider.value(value: state),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: CommunityBenchmarkPanel()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const ValueKey('community_guest_hint')), findsOneWidget);
    expect(
      find.textContaining('Sign in to unlock'),
      findsOneWidget,
    );
  });

  testWidgets('Community offline shows stale feed banner with Retry', (tester) async {
    ignoreLayoutNoise();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final cached = _sampleLayout();
    SharedPreferences.setMockInitialValues({
      'room_rig.onboarding_seen': true,
      'room_rig.community_feed_cache_v1': jsonEncode({
        'baselines': [cached.toCacheJson()],
        'monthly': <Map<String, dynamic>>[],
        'recent': [cached.toCacheJson()],
        'top': <Map<String, dynamic>>[],
      }),
    });

    final state = AppState(publishedLayouts: _ThrowingFeedRepo());
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthService()),
          ChangeNotifierProvider(create: (_) => ProfileService()),
          ChangeNotifierProvider.value(value: state),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: CommunityBenchmarkPanel()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const ValueKey('community_stale_banner')), findsOneWidget);
    expect(find.textContaining('Offline'), findsOneWidget);
    expect(find.text('Retry'), findsWidgets);
    expect(find.text('Cached Studio'), findsWidgets);
  });

  test('Community Compare keeps Benchmark mode (no silent Airflow force)', () async {
    final layout = _sampleLayout(id: 'cmp-1', title: 'Compare Me');
    final state = AppState();
    state.debugSetSignedInForTests(true);
    state.cachePublishedLayout(layout);
    state.setBenchmarkMode('lighting');

    final ok = await state.openPublishedInCompare(layout.id, title: layout.title);
    expect(ok, isTrue);
    expect(state.benchmarkMode, 'lighting');
    expect(state.benchmarkCompareRight.isPublishedLayout, isTrue);
  });

  testWidgets('Narrow Benchmark puts Community behind overflow control', (tester) async {
    ignoreLayoutNoise();
    tester.view.physicalSize = const Size(390 * 2.75, 844 * 2.75);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final state = AppState();
    state.createManualRoom(name: 'Studio', lengthMeters: 3.6, widthMeters: 4.8);
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
          home: const BenchmarkScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('benchmark_community_overflow')), findsOneWidget);
    expect(find.byKey(const ValueKey('benchmark_mode_row')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('benchmark_community_overflow')));
    await tester.pump();
    expect(state.benchmarkMode, 'community');
  });

  testWidgets('Community offline empty state at 360 and 412dp shows icon + Retry',
      (tester) async {
    ignoreLayoutNoise();
    for (final width in const [360.0, 412.0]) {
      final state = AppState(publishedLayouts: _ThrowingFeedRepo());
      await pumpCommunity(tester, state: state, width: width);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byKey(const ValueKey('community_offline_error')), findsOneWidget,
          reason: 'error at ${width}dp');
      expect(find.byKey(const ValueKey('community_offline_error_icon')), findsOneWidget,
          reason: 'icon at ${width}dp');
      expect(find.textContaining('Could not load Community feed'), findsOneWidget,
          reason: 'copy at ${width}dp');
      expect(find.text('Retry'), findsOneWidget, reason: 'Retry at ${width}dp');
      expect(find.byKey(const ValueKey('community_stale_banner')), findsNothing,
          reason: 'no stale at ${width}dp');
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('Community loading spinner shows while feed loads', (tester) async {
    ignoreLayoutNoise();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = _HangingFeedRepo();
    addTearDown(repo.complete);
    final state = AppState(publishedLayouts: repo);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthService()),
          ChangeNotifierProvider(create: (_) => ProfileService()),
          ChangeNotifierProvider.value(value: state),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: CommunityBenchmarkPanel()),
        ),
      ),
    );
    // First frame: _loading starts true; post-frame starts hanging fetch.
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.bySemanticsLabel('Loading Community feed'),
      findsOneWidget,
    );

    repo.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
