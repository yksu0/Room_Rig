// lib/screens/community_screen.dart
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/community_benchmark_panel.dart';

/// Bottom-nav Community tab: browse / publish / vote / clone community layouts.
class CommunityScreen extends StatelessWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.screen,
                AppSpace.sm,
                AppSpace.screen,
                AppSpace.xs,
              ),
              child: const Text(
                'COMMUNITY',
                style: TextStyle(
                  color: AppColors.cyan,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.8,
                ),
              ),
            ),
            const Expanded(child: CommunityBenchmarkPanel()),
          ],
        ),
      ),
    );
  }
}