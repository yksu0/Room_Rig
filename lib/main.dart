// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'models/app_state.dart';
import 'theme/app_theme.dart';
import 'widgets/room_icons.dart';
import 'screens/home_screen.dart';
import 'screens/scanner_screen.dart';
import 'screens/rig_customizer_screen.dart';
import 'screens/benchmark_screen.dart';
import 'screens/upgrades_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0A0B0F),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
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
      theme: AppTheme.dark,
      home: const _MainShell(),
    );
  }
}

class _MainShell extends StatelessWidget {
  const _MainShell();

  static const _screens = [
    HomeScreen(),
    ScannerScreen(),
    RigCustomizerScreen(),
    BenchmarkScreen(),
    UpgradesScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

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
      (RoomSvg.scan, 'Scan'),
      (RoomSvg.tune, 'Rig'),
      (RoomSvg.speedometer, 'Bench'),
      (RoomSvg.upgrade, 'Upgrades'),
    ];

    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(top: BorderSide(color: AppColors.border, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: items.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          final isSelected = i == currentIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => context.read<AppState>().setTab(i),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: isSelected ? AppColors.cyan : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedScale(
                      scale: isSelected ? 1.15 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      child: SvgIcon(
                        item.$1,
                        size: 22,
                        color: isSelected ? AppColors.cyan : AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.$2,
                      style: TextStyle(
                        color: isSelected ? AppColors.cyan : AppColors.textMuted,
                        fontSize: 10,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
