// lib/main.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'models/app_state.dart';
import 'models/room_catalog.dart';
import 'services/auth_service.dart';
import 'services/autorug_ranker.dart';
import 'services/profile_service.dart';
import 'services/furniture_sprites.dart';
import 'services/supabase_bootstrap.dart';
import 'theme/app_layout.dart';
import 'theme/app_theme.dart';
import 'widgets/app_snack_bar.dart';
import 'widgets/room_icons.dart';
import 'screens/home_screen.dart';
import 'screens/scanner_screen_selector.dart';
import 'screens/room_customizer_screen.dart';
import 'screens/benchmark_screen.dart';
import 'screens/set_password_screen.dart';
import 'widgets/room_model_scene_pointer_guard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Portrait + landscape so phones can use the same wide shell as Chrome.
  // Skip upside-down portrait (awkward for camera / one-handed use).
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0A0B0F),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  await SupabaseBootstrap.ensureInitialized();
  await FurnitureSprites.warmCache({
    ...RoomCatalog.items.map((e) => e.iconName),
    'fan',
    'purifier',
    'floorLamp',
    'smartBlinds',
    'heater',
    'wardrobe',
    'plant',
    'tv',
    'intake',
    'exhaust',
    'ceilingLight',
  });
  // Distilled Auto-Rig ranker (opt-in via AutoRigRanker.enabled).
  try {
    await AutoRigRanker.load();
  } catch (_) {
    // Keep pipeline sort if weights are missing / mismatched.
  }
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => ProfileService()),
        ChangeNotifierProvider(create: (_) => AppState()),
      ],
      child: const RoomRigApp(),
    ),
  );
}

class RoomRigApp extends StatelessWidget {
  const RoomRigApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Room Rig',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark.copyWith(scaffoldBackgroundColor: Colors.transparent),
      navigatorObservers: [RoomModelScenePointerGuard()],
      home: const _MainShell(),
    );
  }
}

class _MainShell extends StatefulWidget {
  const _MainShell();

  @override
  State<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<_MainShell> with WidgetsBindingObserver {
  /// Order must match [hubTabIndex] / [roomTabIndex] / [scanTabIndex] /
  /// [benchmarkTabIndex] in `models/app_tabs.dart`.
  static const _screens = [
    HomeScreen(),
    RoomCustomizerScreen(),
    ScannerScreen(),
    BenchmarkScreen(),
  ];

  int? _handledTab;
  bool _authHooked = false;
  bool _importDialogOpen = false;
  bool _recoveryRouteOpen = false;
  DateTime? _pausedAt;
  Timer? _signOutDebounce;
  bool _authWasSignedIn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _signOutDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only [paused] means the user left the app. [inactive] also fires for
    // notification shade / dialogs / brief focus loss and must not start the
    // shared-phone idle timer (or short background hops look like a reset).
    if (state == AppLifecycleState.paused) {
      _pausedAt ??= DateTime.now();
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    if (!mounted) return;
    // Drop any banner that lingered while backgrounded so tabs stay tappable.
    clearAppSnackBars(context);
    final pausedAt = _pausedAt;
    _pausedAt = null;
    if (pausedAt == null) return;
    final app = context.read<AppState>();
    final auth = context.read<AuthService>();
    if (!app.sharedPhoneLock || !auth.isSignedIn) return;
    if (DateTime.now().difference(pausedAt) < AppState.sharedPhoneLockIdle) {
      return;
    }
    unawaited(() async {
      await app.flushRoomsToCloud();
      await auth.signOut();
    }());
    showAppSnackBar(
      context,
      message:
          'Signed out after idle (shared phone lock). '
          'Sign in again to restore rooms from the cloud.',
      duration: const Duration(seconds: 4),
    );
  }

  void _consumeTabNotice(AppState state) {
    final notice = state.takeTabNotice();
    if (notice == null || !mounted) return;
    showAppSnackBar(context, message: notice);
  }

  void _hookAuth(AuthService auth, AppState app, ProfileService profiles) {
    if (_authHooked) return;
    _authHooked = true;
    _authWasSignedIn = auth.isSignedIn;
    if (_authWasSignedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(app.handleSignedIn());
        // load() also cancels a pending soft-delete (sign-in inside 7 days).
        unawaited(profiles.load());
      });
    }
    auth.addListener(() {
      final now = auth.isSignedIn;
      if (now && !_authWasSignedIn) {
        // Session restored (or real sign-in) — cancel a pending wipe.
        _signOutDebounce?.cancel();
        _signOutDebounce = null;
        _authWasSignedIn = true;
        unawaited(app.handleSignedIn());
        unawaited(profiles.load());
      } else if (!now && _authWasSignedIn) {
        final intentional = auth.consumeIntentionalSignOut();
        if (intentional) {
          _signOutDebounce?.cancel();
          _signOutDebounce = null;
          _authWasSignedIn = false;
          profiles.clear();
          unawaited(app.handleSignedOut());
          return;
        }
        // Token refresh / brief auth blips can emit signed-out then signed-in.
        // Wait long enough for session restore after backgrounding.
        _signOutDebounce?.cancel();
        _signOutDebounce = Timer(const Duration(seconds: 2), () {
          if (!mounted) return;
          if (auth.isSignedIn) return;
          _authWasSignedIn = false;
          profiles.clear();
          unawaited(app.handleSignedOut());
        });
      }
    });
  }

  Future<void> _maybeOpenPasswordRecovery(AuthService auth) async {
    if (!auth.passwordRecoveryPending || _recoveryRouteOpen || !mounted) {
      return;
    }
    _recoveryRouteOpen = true;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const SetPasswordScreen(mode: SetPasswordMode.recovery),
      ),
    );
    if (!mounted) return;
    _recoveryRouteOpen = false;
    // If they closed somehow without saving, keep flag until password is set.
    if (auth.passwordRecoveryPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_maybeOpenPasswordRecovery(auth));
      });
    }
  }

  Future<void> _maybePromptGuestImport(AppState state) async {
    if (!state.awaitingGuestImportPrompt || _importDialogOpen || !mounted) {
      return;
    }
    _importDialogOpen = true;
    final n = state.guestRoomsPendingImportCount;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Keep this device\'s room?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          n == 1
              ? 'A room made on this device as a guest is still here. '
                  'Add it to your account, or discard it from this phone.'
              : '$n rooms made on this device as a guest are still here. '
                  'Add them to your account, or discard them from this phone.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add to account'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (ok == true) {
      await state.importGuestRoomsToCloud();
    } else {
      await state.declineGuestImport();
    }
    _importDialogOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final state = context.watch<AppState>();
    _hookAuth(auth, state, context.read<ProfileService>());
    if (auth.passwordRecoveryPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_maybeOpenPasswordRecovery(auth));
      });
    }
    if (state.awaitingGuestImportPrompt) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_maybePromptGuestImport(state));
      });
    }
    final tab = state.currentTab;
    if (_handledTab != tab) {
      final previous = _handledTab;
      _handledTab = tab;
      if (previous != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _consumeTabNotice(context.read<AppState>());
        });
      }
    }

    final desktop = AppLayout.useSideNav(MediaQuery.sizeOf(context));
    final stack = IndexedStack(
      index: state.currentTab,
      children: _screens,
    );

    // Desktop website shell: persistent left nav + full remaining width.
    // Mobile: body + bottomNavigationBar so floating snackbars sit above tabs
    // (they used to paint over the custom nav and block tab switches).
    if (desktop) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: Row(
          children: [
            _RoomSideNav(currentIndex: state.currentTab),
            Expanded(child: stack),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: stack,
      bottomNavigationBar: _RoomNavBar(currentIndex: state.currentTab),
    );
  }
}

/// Main nav, in [IndexedStack] order (see `models/app_tabs.dart`).
/// Scan sits in the centre and is drawn emphasised on the mobile bar.
const kAppNavItems = [
  (RoomSvg.home, 'Hub'),
  (RoomSvg.floorPlan, 'Room'),
  (RoomSvg.scan, 'Scan'),
  (RoomSvg.speedometer, 'Benchmark'),
];

class _RoomSideNav extends StatelessWidget {
  final int currentIndex;
  const _RoomSideNav({required this.currentIndex});

  static const _items = kAppNavItems;

  @override
  Widget build(BuildContext context) {
    final compact = AppLayout.isLandscapeShell(MediaQuery.sizeOf(context)) &&
        MediaQuery.sizeOf(context).width < AppLayout.desktopMinWidth;
    final navWidth = compact ? 72.0 : 92.0;
    return Material(
      color: AppColors.surface,
      child: Container(
        width: navWidth,
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: AppColors.borderSubtle)),
        ),
        child: SafeArea(
          right: false,
          child: Column(
            children: [
              SizedBox(height: compact ? 10 : 16),
              Text(
                compact ? 'RIG' : 'ROOM\nRIG',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.cyan.withValues(alpha: 0.95),
                  fontSize: compact ? 10 : 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.6,
                  height: 1.15,
                ),
              ),
              SizedBox(height: compact ? 12 : 20),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  itemCount: _items.length,
                  separatorBuilder: (context, index) =>
                      SizedBox(height: compact ? 4 : 6),
                  itemBuilder: (context, i) {
                    final item = _items[i];
                    final selected = i == currentIndex;
                    return Material(
                      color: selected
                          ? AppColors.cyan.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        onTap: () {
                          clearAppSnackBars(context);
                          context.read<AppState>().setTab(i);
                        },
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: compact ? 10 : 14,
                            horizontal: 4,
                          ),
                          child: Column(
                            children: [
                              SvgIcon(
                                item.$1,
                                size: compact ? 20 : 22,
                                color: selected
                                    ? AppColors.cyan
                                    : AppColors.textMuted,
                              ),
                              SizedBox(height: compact ? 4 : 6),
                              Text(
                                item.$2,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: selected
                                      ? AppColors.cyan
                                      : AppColors.textMuted,
                                  fontSize: compact ? 9 : 10,
                                  fontWeight: selected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomNavBar extends StatelessWidget {
  final int currentIndex;
  const _RoomNavBar({required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    const items = kAppNavItems;

    final bottom = MediaQuery.paddingOf(context).bottom;
    return Material(
      color: AppColors.surface.withValues(alpha: 0.96),
      elevation: 8,
      child: Container(
        height: 76 + bottom,
        padding: EdgeInsets.only(bottom: bottom),
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.borderSubtle, width: 1),
          ),
        ),
        child: Row(
          children: items.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            final isSelected = i == currentIndex;
            final emphasized = i == scanTabIndex;
            return Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    clearAppSnackBars(context);
                    context.read<AppState>().setTab(i);
                  },
                  child: emphasized
                      ? _ScanNavTile(label: item.$2, selected: isSelected)
                      : AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color:
                              isSelected ? AppColors.cyan : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedScale(
                          scale: isSelected ? 1.1 : 1.0,
                          duration: const Duration(milliseconds: 200),
                          child: SvgIcon(
                            item.$1,
                            size: 22,
                            color: isSelected
                                ? AppColors.cyan
                                : AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.$2,
                          style: TextStyle(
                            color: isSelected
                                ? AppColors.cyan
                                : AppColors.textMuted,
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// Centre Scan tab: a raised filled disc so it reads as the primary action.
/// Sized to fit the 76px nav bar without overflow (icon + label).
class _ScanNavTile extends StatelessWidget {
  final String label;
  final bool selected;
  const _ScanNavTile({required this.label, required this.selected});

  @override
  Widget build(BuildContext context) {
    final fill = selected ? AppColors.cyan : AppColors.cyan.withValues(alpha: 0.18);
    final iconColor = selected ? AppColors.bg : AppColors.cyan;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.cyan.withValues(alpha: selected ? 1 : 0.6),
              width: 1.5,
            ),
          ),
          child: Center(
            child: SvgIcon(RoomSvg.scan, size: 18, color: iconColor),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.cyan,
            fontSize: 10,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
            letterSpacing: 0.2,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}
