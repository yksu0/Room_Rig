// lib/widgets/onboarding_sheet.dart
import 'package:flutter/material.dart';
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
        RoomSvg.scan,
        'Scan your room',
        'Capture walls and furniture so Room Rig can build a layout model.',
        AppColors.cyan,
        1,
      ),
      (
        RoomSvg.tune,
        'Arrange in Rig',
        'Drag items in 2D/3D. Collision, undo, and conflict warnings keep edits safe.',
        AppColors.purple,
        2,
      ),
      (
        RoomSvg.speedometer,
        'Bench & Auto-Rig',
        'Stress-test airflow, lighting, and ergonomics — then apply an improved layout.',
        AppColors.amber,
        3,
      ),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'WELCOME TO ROOM RIG',
              style: TextStyle(
                color: AppColors.cyan,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Three steps to a better setup',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 18),
            ...steps.map((s) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GestureDetector(
                  onTap: () {
                    onJumpTab?.call(s.$5);
                    onDone();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: s.$4.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(child: SvgIcon(s.$1, size: 20, color: s.$4)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.$2, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 14)),
                              const SizedBox(height: 4),
                              Text(s.$3, style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600, height: 1.3)),
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
            const SizedBox(height: 8),
            GestureDetector(
              onTap: onDone,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: AppColors.accentGradient,
                  borderRadius: BorderRadius.circular(14),
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
