// lib/main.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'models/app_state.dart';
import 'models/rig_catalog.dart';
import 'services/auth_service.dart';
import 'services/autorug_ranker.dart';
import 'services/furniture_sprites.dart';
import 'services/supabase_bootstrap.dart';
import 'theme/app_layout.dart';
import 'theme/app_theme.dart';
import 'widgets/room_icons.dart';
import 'screens/home_screen.dart';
import 'screens/scanner_screen_selector.dart';
import 'screens/rig_customizer_screen.dart';
import 'screens/benchmark_screen.dart';
import 'screens/set_password_screen.dart';
import 'screens/upgrades_screen.dart';
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
    ...RigCatalog.items.map((e) => e.iconName),
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
  static const _screens = [
    HomeScreen(),
    ScannerScreen(),
    RigCustomizerScreen(),
    BenchmarkScreen(),
    UpgradesScreen(),
  ];

  int? _handledTab;
  bool _authHooked = false;
  bool _importDialogOpen = false;
  bool _recoveryRouteOpen = false;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _pausedAt ??= DateTime.now();
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    final pausedAt = _pausedAt;
    _pausedAt = null;
    if (pausedAt == null || !mounted) return;
    final app = context.read<AppState>();
    final auth = context.read<AuthService>();
    if (!app.sharedPhoneLock || !auth.isSignedIn) return;
    if (DateTime.now().difference(pausedAt) < AppState.sharedPhoneLockIdle) {
      return;
    }
    unawaited(auth.signOut());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Signed out after idle (shared phone lock). '
          'Shared photos or files are not removed from the phone; delete those yourself if needed.',
        ),
      ),
    );
  }

  void _consumeTabNotice(AppState state) {
    final notice = state.takeTabNotice();
    if (notice == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(notice),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _hookAuth(AuthService auth, AppState app) {
    if (_authHooked) return;
    _authHooked = true;
    var wasSignedIn = auth.isSignedIn;
    if (wasSignedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(app.handleSignedIn());
      });
    }
    auth.addListener(() {
      final now = auth.isSignedIn;
      if (now && !wasSignedIn) {
        unawaited(app.handleSignedIn());
      } else if (!now && wasSignedIn) {
        unawaited(app.handleSignedOut());
      }
      wasSignedIn = now;
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
          'Upload rooms from this device?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          'Upload $n room(s) made on this device while signed out? '
          'They may belong to someone else who used this phone. '
          'Choose Not now to discard them from this device.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Upload'),
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
    _hookAuth(auth, state);
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
    // Mobile: full-bleed screens + bottom tab bar.
    if (desktop) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: Row(
          children: [
            _RigSideNav(currentIndex: state.currentTab),
            Expanded(child: stack),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          Expanded(child: stack),
          _RigNavBar(currentIndex: state.currentTab),
        ],
      ),
    );
  }
}

class _RigSideNav extends StatelessWidget {
  final int currentIndex;
  const _RigSideNav({required this.currentIndex});

  static const _items = [
    (RoomSvg.home, 'Hub'),
    (RoomSvg.scan, 'Scan*'),
    (RoomSvg.tune, 'Rig'),
    (RoomSvg.speedometer, 'Bench'),
    (RoomSvg.upgrade, 'Upgrades'),
  ];

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
                        onTap: () => context.read<AppState>().setTab(i),
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

class _RigNavBar extends StatelessWidget {
  final int currentIndex;
  const _RigNavBar({required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    final items = [
      (RoomSvg.home, 'Hub'),
      (RoomSvg.scan, 'Scan*'),
      (RoomSvg.tune, 'Rig'),
      (RoomSvg.speedometer, 'Bench'),
      (RoomSvg.upgrade, 'Upgrades'),
    ];

    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      height: 76 + bottom,
      padding: EdgeInsets.only(bottom: bottom),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.96),
        border: const Border(
          top: BorderSide(color: AppColors.borderSubtle, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Row(
        children: items.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          final isSelected = i == currentIndex;
          return Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => context.read<AppState>().setTab(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: isSelected ? AppColors.cyan : Colors.transparent,
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
                          fontWeight:
                              isSelected ? FontWeight.w800 : FontWeight.w600,
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
    );
  }
}
