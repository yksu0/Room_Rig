// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'models/app_state.dart';
import 'models/rig_catalog.dart';
import 'services/furniture_sprites.dart';
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
  // Portrait-only for now. AdaptivePanelLayout.useExpandedRails unlocks
  // supporting-pane side rails when multi-orientation is enabled (Phase 5).
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0A0B0F),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  // Decode catalog + upgrade sprites so Rig and Bench share the same art.
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
      // Transparent so AR measure can show native camera through Scan.
      // Each tab Scaffold sets its own opaque backgroundColor.
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
    // `model` branch: Scan parked — focus Rig/Bench real GLB rooms.
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

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: IndexedStack(
        index: state.currentTab,
        children: _screens,
      ),
      bottomNavigationBar: _RigNavBar(currentIndex: state.currentTab),
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
        border: const Border(top: BorderSide(color: AppColors.borderSubtle, width: 1)),
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
                          color: isSelected ? AppColors.cyan : AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.$2,
                        style: TextStyle(
                          color: isSelected ? AppColors.cyan : AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
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
