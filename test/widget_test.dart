// This is a basic Flutter widget test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:room_rig/main.dart';
import 'package:room_rig/models/app_state.dart';
import 'package:room_rig/models/published_layout.dart';
import 'package:room_rig/services/auth_service.dart';
import 'package:room_rig/services/profile_service.dart';
import 'package:room_rig/services/published_layout_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'room_rig.onboarding_seen': true,
    });
  });

  testWidgets('Smoke test room rig app', (WidgetTester tester) async {
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.toString().contains('A RenderFlex overflowed')) return;
      previousOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);

    final state = AppState(publishedLayouts: _EmptyFeedRepo());
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthService()),
          ChangeNotifierProvider(create: (_) => ProfileService()),
          ChangeNotifierProvider.value(value: state),
        ],
        child: const RoomRigApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Drain AppState guest-orphan scrub Future.delayed(2s).
    await tester.pump(const Duration(seconds: 2));

    // Nav shows five tabs: Hub · Room · Scan · Benchmark · Community.
    expect(find.text('Hub'), findsWidgets);
    expect(find.text('Room'), findsWidgets);
    expect(find.text('Scan'), findsWidgets);
    expect(find.text('Benchmark'), findsWidgets);
    expect(find.text('Community'), findsWidgets);
    expect(find.text('Upgrades'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}