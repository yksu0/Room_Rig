import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

/// Scan is parked on the `model` branch — Rig + Bench model viz is the focus.
class ScanFocusPlaceholderScreen extends StatelessWidget {
  const ScanFocusPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.screen),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SCAN',
                style: TextStyle(
                  color: AppColors.cyan,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.8,
                ),
              ),
              const SizedBox(height: AppSpace.xxs),
              const Text(
                'Parked on this branch',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpace.xl),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Model branch focus',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      'AR scanning is intentionally sidelined here so we can ship '
                      'real GLB furniture + textured rooms in Rig and Bench '
                      '(Kenney CC0 meshes, Poly Haven materials).',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: AppSpace.lg),
                    FilledButton(
                      onPressed: () => context.read<AppState>().setTab(2),
                      child: const Text('OPEN RIG MODEL VIEW'),
                    ),
                    const SizedBox(height: AppSpace.xs),
                    OutlinedButton(
                      onPressed: () => context.read<AppState>().setTab(3),
                      child: const Text('OPEN BENCH'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
