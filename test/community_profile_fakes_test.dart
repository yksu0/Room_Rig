import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:room_rig/models/app_state.dart';
import 'package:room_rig/models/published_layout.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/models/saved_room.dart';
import 'package:room_rig/models/scan_layout_model.dart';
import 'package:room_rig/screens/profile_screen.dart';
import 'package:room_rig/services/auth_service.dart';
import 'package:room_rig/services/profile_service.dart';
import 'package:room_rig/services/published_layout_repository.dart';
import 'package:room_rig/services/room_repository.dart';
import 'package:room_rig/theme/app_theme.dart';
import 'package:room_rig/widgets/guest_signup_gate.dart';

PublishedLayout _layout({
  String id = 'pub-1',
  String title = 'Studio Post',
  int? myVote,
  List<FurnitureItem>? furniture,
}) {
  return PublishedLayout(
    id: id,
    authorId: 'author-1',
    title: title,
    layout: PublishedLayoutSnapshot(
      name: 'Studio',
      gridCols: 6,
      gridRows: 8,
      furniture: furniture ??
          [
            FurnitureItem(
              id: 'desk',
              name: 'Desk',
              iconName: 'desk',
              category: 'neutral',
              gridX: 2,
              gridY: 3,
              width: 2,
              height: 1,
            ),
          ],
    ),
    publishedAt: DateTime.utc(2026, 10, 1),
    upCount: myVote == 1 ? 1 : 0,
    downCount: myVote == -1 ? 1 : 0,
    netScore: myVote ?? 0,
    myVote: myVote,
  );
}

SavedRoom _guestRoom({String id = 'guest-1', String name = 'Guest Lot'}) {
  return SavedRoom(
    id: id,
    name: name,
    presetName: 'manual',
    scanComplete: false,
    scanProgress: 0,
    layout: RoomLayoutModel(
      roomName: name,
      dimensions: const RoomDimensions(
        lengthMeters: 3.6,
        widthMeters: 4.8,
        heightMeters: 2.7,
      ),
      coverageGrid: CoverageGrid.empty(cols: 6, rows: 8),
      objects: const [],
      detections: const [],
      updatedAt: DateTime.utc(2026, 10, 30),
      scanSource: 'manual',
    ),
    furniture: const [],
  );
}

class FakePublishedLayoutRepository extends PublishedLayoutRepository {
  final Map<String, PublishedLayout> store = {};
  final List<String> publishTitles = [];
  final List<(String, int)> rates = [];
  final List<String> cleared = [];
  bool throwOnPublish = false;

  @override
  Future<PublishedLayout> publish({
    required String authorId,
    required String title,
    String? description,
    required PublishedLayoutSnapshot layout,
    Map<String, dynamic>? scores,
    List<String> tags = const [],
  }) async {
    if (throwOnPublish) throw StateError('publish failed');
    publishTitles.add(title);
    final published = PublishedLayout(
      id: 'pub-${store.length + 1}',
      authorId: authorId,
      title: title,
      description: description,
      layout: layout,
      scores: scores,
      tags: tags,
      publishedAt: DateTime.utc(2026, 10, 30),
    );
    store[published.id] = published;
    return published;
  }

  @override
  Future<PublishedLayout?> fetchById(String id) async => store[id];

  @override
  Future<PublishedLayout> rate({
    required String layoutId,
    required String raterId,
    required int vote,
    List<String> tags = const [],
  }) async {
    rates.add((layoutId, vote));
    final existing = store[layoutId] ?? _layout(id: layoutId, myVote: null);
    final updated = PublishedLayout(
      id: existing.id,
      authorId: existing.authorId,
      authorName: existing.authorName,
      authorAvatarUrl: existing.authorAvatarUrl,
      title: existing.title,
      description: existing.description,
      layout: existing.layout,
      scores: existing.scores,
      tags: existing.tags,
      isAdminBaseline: existing.isAdminBaseline,
      featuredUntil: existing.featuredUntil,
      publishedAt: existing.publishedAt,
      hidden: existing.hidden,
      upCount: vote == 1 ? 1 : 0,
      downCount: vote == -1 ? 1 : 0,
      netScore: vote,
      myVote: vote,
      myTags: tags,
    );
    store[layoutId] = updated;
    return updated;
  }

  @override
  Future<PublishedLayout> clearRating({
    required String layoutId,
    required String raterId,
  }) async {
    cleared.add(layoutId);
    final existing = store[layoutId] ?? _layout(id: layoutId);
    final updated = PublishedLayout(
      id: existing.id,
      authorId: existing.authorId,
      authorName: existing.authorName,
      authorAvatarUrl: existing.authorAvatarUrl,
      title: existing.title,
      description: existing.description,
      layout: existing.layout,
      scores: existing.scores,
      tags: existing.tags,
      isAdminBaseline: existing.isAdminBaseline,
      featuredUntil: existing.featuredUntil,
      publishedAt: existing.publishedAt,
      hidden: existing.hidden,
      upCount: 0,
      downCount: 0,
      netScore: 0,
      myVote: null,
      myTags: const [],
    );
    store[layoutId] = updated;
    return updated;
  }
}

class FakeRoomRepository extends RoomRepository {
  final List<SavedRoom> upserted = [];
  bool failUpsert = false;

  @override
  Future<void> upsertMany(String userId, List<SavedRoom> rooms) async {
    if (failUpsert) throw StateError('upsert failed');
    upserted.addAll(rooms);
  }

  @override
  Future<void> upsertRoom(String userId, SavedRoom room) async {
    if (failUpsert) throw StateError('upsert failed');
    upserted.add(room);
  }

  @override
  Future<List<SavedRoom>> fetchRooms(String userId) async => const [];

  @override
  Future<void> ensureProfile({required String userId}) async {}
}

class FakeAuthService extends AuthService {
  FakeAuthService({
    bool signedIn = false,
    String? email = 'user@example.com',
    String? userId = 'user-1',
  })  : _signedIn = signedIn,
        _email = email,
        _userId = userId;

  bool _signedIn;
  final String? _email;
  final String? _userId;
  var signOutCalls = 0;

  @override
  bool get isSignedIn => _signedIn;

  @override
  bool get isGuest => !_signedIn;

  @override
  String? get email => _email;

  @override
  String? get userId => _userId;

  @override
  bool get hasGoogleIdentity => false;

  @override
  bool get hasEmailIdentity => _signedIn;

  @override
  Future<void> signOut() async {
    signOutCalls++;
    _signedIn = false;
    notifyListeners();
  }
}

class FakeProfileService extends ProfileService {
  FakeProfileService({UserProfile? profile}) {
    if (profile != null) debugSetProfileForTests(profile);
  }

  String? reachabilityError;
  String? sendCodeError;
  String? confirmError;
  String? lastConfirmCode;
  var sendCodeCalls = 0;
  var confirmCalls = 0;

  @override
  Future<String?> cloudReachabilityError() async => reachabilityError;

  @override
  Future<String?> sendDeleteConfirmationCode() async {
    sendCodeCalls++;
    return sendCodeError;
  }

  @override
  Future<String?> confirmDeleteWithCode(String code) async {
    confirmCalls++;
    lastConfirmCode = code;
    return confirmError;
  }

  @override
  Future<void> load({bool cancelPendingDeletion = true}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'room_rig.onboarding_seen': true,
    });
  });

  group('publishCurrent / clonePublished with fake repo', () {
    test('publishCurrentRoom writes through the injected repository', () async {
      final repo = FakePublishedLayoutRepository();
      final state = AppState(publishedLayouts: repo);
      state.debugSetSignedInForTests(true, userId: 'author-9');
      state.createManualRoom(
        name: 'Publish Me',
        lengthMeters: 3.6,
        widthMeters: 4.8,
      );

      final published = await state.publishCurrentRoom(
        authorId: 'author-9',
        title: 'My first post',
        description: 'hello',
      );

      expect(repo.publishTitles, ['My first post']);
      expect(published.title, 'My first post');
      expect(published.authorId, 'author-9');
      expect(published.layout.furniture, isNotEmpty);
      expect(state.publishedLayoutRepository, same(repo));
    });

    test('clonePublishedLayout replaces the active room from cache', () async {
      final repo = FakePublishedLayoutRepository();
      final layout = _layout(id: 'clone-me', title: 'Clone Target');
      repo.store[layout.id] = layout;
      final state = AppState(publishedLayouts: repo);
      state.debugSetSignedInForTests(true, userId: 'user-1');
      state.createManualRoom(
        name: 'Before',
        lengthMeters: 3.6,
        widthMeters: 4.8,
      );
      final beforeIds = state.furniture.map((f) => f.id).toSet();

      final ok = await state.clonePublishedLayout('clone-me');

      expect(ok, isTrue);
      expect(state.furniture.map((f) => f.id), ['desk']);
      expect(beforeIds.contains('desk'), isFalse);
    });

    test('clonePublishedLayout refuses guests', () async {
      final repo = FakePublishedLayoutRepository();
      repo.store['x'] = _layout(id: 'x');
      final state = AppState(publishedLayouts: repo);
      expect(await state.clonePublishedLayout('x'), isFalse);
    });
  });

  group('rate / clearRating fake repo', () {
    test('rate then clearRating update myVote', () async {
      final repo = FakePublishedLayoutRepository();
      repo.store['L1'] = _layout(id: 'L1');

      final rated = await repo.rate(layoutId: 'L1', raterId: 'u1', vote: 1);
      expect(rated.myVote, 1);
      expect(repo.rates, [('L1', 1)]);

      final cleared = await repo.clearRating(layoutId: 'L1', raterId: 'u1');
      expect(cleared.myVote, isNull);
      expect(repo.cleared, ['L1']);
    });
  });

  group('importGuestRoomsToCloud', () {
    test('claims pending guest drafts onto the account via room repo', () async {
      final rooms = FakeRoomRepository();
      final state = AppState(roomRepo: rooms);
      state.debugSetSignedInForTests(true, userId: 'user-42');
      final guest = _guestRoom(id: 'g1', name: 'Phone draft');
      state.debugSeedGuestImportPending([guest]);

      await state.importGuestRoomsToCloud();

      expect(state.awaitingGuestImportPrompt, isFalse);
      expect(state.guestRoomsPendingImportCount, 0);
      final claimed = rooms.upserted.where((r) => r.id == 'g1').toList();
      expect(claimed, isNotEmpty);
      expect(claimed.first.ownerUserId, 'user-42');
    });

    test('keeps the prompt open when cloud upsert fails', () async {
      final rooms = FakeRoomRepository()..failUpsert = true;
      final state = AppState(roomRepo: rooms);
      state.debugSetSignedInForTests(true, userId: 'user-42');
      state.debugSeedGuestImportPending([_guestRoom()]);

      await state.importGuestRoomsToCloud();

      expect(state.awaitingGuestImportPrompt, isTrue);
      expect(state.guestRoomsPendingImportCount, 1);
    });
  });

  group('delete-account OTP flow (ProfileScreen)', () {
    Future<void> pumpProfile(
      WidgetTester tester, {
      required FakeAuthService auth,
      required FakeProfileService profiles,
      AppState? state,
    }) async {
      final appState = state ?? AppState();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: appState),
            ChangeNotifierProvider<AuthService>.value(value: auth),
            ChangeNotifierProvider<ProfileService>.value(value: profiles),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const ProfileScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('sends code, confirms OTP, then signs out', (tester) async {
      final auth = FakeAuthService(signedIn: true, email: 'a@b.co', userId: 'u1');
      final profiles = FakeProfileService(
        profile: const UserProfile(
          id: 'u1',
          displayName: 'Ada',
          avatarUrl: 'https://example.com/a.png',
        ),
      );
      await pumpProfile(tester, auth: auth, profiles: profiles);

      await tester.scrollUntilVisible(
        find.text('Delete account'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();

      expect(find.text('Delete account?'), findsOneWidget);
      await tester.tap(find.text('Send code'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(profiles.sendCodeCalls, 1);

      expect(find.text('Enter the code'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('Confirm delete'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(profiles.confirmCalls, 1);
      expect(profiles.lastConfirmCode, '123456');
      expect(auth.signOutCalls, 1);
    });

    testWidgets('blocks delete when cloud is unreachable', (tester) async {
      final auth = FakeAuthService(signedIn: true);
      final profiles = FakeProfileService(
        profile: const UserProfile(id: 'u1', displayName: 'Ada', avatarUrl: 'x'),
      )..reachabilityError = 'offline';
      await pumpProfile(tester, auth: auth, profiles: profiles);

      await tester.scrollUntilVisible(
        find.text('Delete account'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Delete account'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('Delete needs an internet connection'), findsOneWidget);
      expect(profiles.sendCodeCalls, 0);
      expect(find.text('Delete account?'), findsNothing);
    });
  });

  group('ProfileScreen guest + incomplete gates', () {
    testWidgets('guest Profile shows Sign up / Sign in', (tester) async {
      final auth = FakeAuthService(signedIn: false, email: null, userId: null);
      final profiles = FakeProfileService();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AppState()),
            ChangeNotifierProvider<AuthService>.value(value: auth),
            ChangeNotifierProvider<ProfileService>.value(value: profiles),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const ProfileScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Guest'), findsOneWidget);
      expect(find.textContaining('Sign up'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Delete account'), findsNothing);
    });

    testWidgets('incomplete profile fails ensureProfileCompleteForPublish',
        (tester) async {
      final auth = FakeAuthService(signedIn: true);
      final profiles = FakeProfileService(
        profile: const UserProfile(id: 'u1'), // no name/avatar
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AppState()),
            ChangeNotifierProvider<AuthService>.value(value: auth),
            ChangeNotifierProvider<ProfileService>.value(value: profiles),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: FilledButton(
                    onPressed: () async {
                      final ok = await ensureProfileCompleteForPublish(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(ok ? 'ready' : 'blocked')),
                      );
                    },
                    child: const Text('Try publish'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(profiles.canPublishOrRate, isFalse);
      await tester.tap(find.text('Try publish'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Complete your Profile'), findsOneWidget);

      await tester.tap(find.text('Not now'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('blocked'), findsOneWidget);
    });

    testWidgets('complete profile passes ensureProfileCompleteForPublish',
        (tester) async {
      final auth = FakeAuthService(signedIn: true);
      final profiles = FakeProfileService(
        profile: const UserProfile(
          id: 'u1',
          displayName: 'Ada',
          avatarUrl: 'https://example.com/a.png',
        ),
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AppState()),
            ChangeNotifierProvider<AuthService>.value(value: auth),
            ChangeNotifierProvider<ProfileService>.value(value: profiles),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: FilledButton(
                    onPressed: () async {
                      final ok = await ensureProfileCompleteForPublish(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(ok ? 'ready' : 'blocked')),
                      );
                    },
                    child: const Text('Try publish'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(profiles.canPublishOrRate, isTrue);
      await tester.tap(find.text('Try publish'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('ready'), findsOneWidget);
      expect(find.text('Complete your Profile'), findsNothing);
    });
  });
}
