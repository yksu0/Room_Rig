// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'models/app_state.dart';
import 'models/rig_catalog.dart';
import 'services/autorug_ranker.dart';
import 'services/furniture_sprites.dart';
import 'theme/app_layout.dart';
import 'theme/app_theme.dart';
import 'widgets/room_icons.dart';
import 'screens/home_screen.dart';
import 'screens/scan_focus_placeholder_screen.dart';
import 'screens/rig_customizer_screen.dart';
import 'screens/benchmark_screen.dart';
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
    ChangeNotifierProvider(
      create: (_) => AppState(),
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

class _MainShellState extends State<_MainShell> {
  static const _screens = [
    HomeScreen(),
    ScanFocusPlaceholderScreen(),
    RigCustomizerScreen(),
    BenchmarkScreen(),
    UpgradesScreen(),
  ];

  int? _handledTab;

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

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
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
