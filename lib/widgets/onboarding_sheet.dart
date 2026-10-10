// lib/widgets/onboarding_sheet.dart
import 'package:flutter/material.dart';
import '../models/upgrade_catalog.dart';
import '../theme/app_theme.dart';
import 'room_icons.dart';

class OnboardingSheet extends StatelessWidget {
  final VoidCallback onDone;
  final ValueChanged<int>? onJumpTab;

  const OnboardingSheet({
    super.key,
    required this.onDone,
    this.onJumpTab,
  });

  @override
  Widget build(BuildContext context) {
    final steps = [
      (
        RoomSvg.home,
        'Start from a template',
        'Create a room or run Demo — no camera required. This is the golden path.',
        AppColors.green,
        0,
      ),
      (
        RoomSvg.tune,
        'Arrange in Rig',
        'Edit · Orbit · Check. Tools and Inspect open as adaptive panels so the canvas stays clear.',
        AppColors.cyan,
        2,
      ),
      (
        RoomSvg.speedometer,
        'Bench & Apply',
        'Simulate My Room → Improved, then Apply. Hub flips to ${HubScoreLabels.benchOk}. Edits show ${HubScoreLabels.roughEst} until Bench again.',
        AppColors.amber,
        3,
      ),
      (
        RoomSvg.scan,
        'Scan stays optional',
        'Scan can seed size later. Skip it anytime and stay on Create → Rig → Bench.',
        AppColors.textMuted,
        1,
      ),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.screen, AppSpace.md, AppSpace.screen, AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            Text(
              'WELCOME TO ROOM RIG',
              style: TextStyle(
                color: AppColors.cyan,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            const Text(
              'Four tips for a better setup',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            ...steps.map((s) {
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: GestureDetector(
                  onTap: () {
                    // Parent pops once via onJumpTab or onDone — never both.
                    if (onJumpTab != null) {
                      onJumpTab!(s.$5);
                    } else {
                      onDone();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(AppSpace.md),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: s.$4.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Center(child: SvgIcon(s.$1, size: 20, color: s.$4)),
                        ),
                        const SizedBox(width: AppSpace.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.$2, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 14)),
                              const SizedBox(height: AppSpace.xxs),
                              Text(s.$3, style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600, height: 1.4)),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: AppSpace.md),
            GestureDetector(
              onTap: onDone,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: AppColors.accentGradient,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: const Text(
                  'GET STARTED',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
