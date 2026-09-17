import 'package:flutter/material.dart';
import '../../services/scan_setup.dart';
import '../../theme/app_theme.dart';
import '../../widgets/room_icons.dart';

class ScanSetupActionsBar extends StatelessWidget {
  final ScanSetupSnapshot snap;
  final bool isLockPhase;
  final VoidCallback? onAdvance;
  final VoidCallback onSkipToPreset;

  const ScanSetupActionsBar({
    super.key,
    required this.snap,
    required this.isLockPhase,
    required this.onAdvance,
    required this.onSkipToPreset,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: snap.canAdvance ? onAdvance : null,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              gradient: snap.canAdvance ? AppColors.accentGradient : null,
              color: snap.canAdvance ? null : AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: snap.canAdvance ? Colors.transparent : AppColors.border),
            ),
            child: Text(
              isLockPhase
                  ? (snap.canAdvance ? 'TRACKING LOCKED — CONTINUE' : 'PAN SLOWLY TO LOCK')
                  : (snap.canAdvance ? 'SIZE LOOKS GOOD — START SCAN' : 'WALK TOWARD THE FAR WALL'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: snap.canAdvance ? Colors.white : AppColors.textMuted,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                fontSize: 12,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onSkipToPreset,
          child: Text(
            'Skip and use preset room size',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class ScanFinishBlockersStrip extends StatelessWidget {
  final List<String> blockers;

  const ScanFinishBlockersStrip({super.key, required this.blockers});

  @override
  Widget build(BuildContext context) {
    if (blockers.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: blockers
            .map(
              (text) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.amber.withValues(alpha: 0.35)),
                ),
                child: Text(
                  text,
                  style: TextStyle(color: AppColors.amber, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class ScanActiveCaptureBottomBar extends StatelessWidget {
  final bool canFinishScan;
  final double requiredCoverageToFinish;
  final List<String> finishBlockers;
  final VoidCallback? onFinish;
  final VoidCallback onCancel;

  const ScanActiveCaptureBottomBar({
    super.key,
    required this.canFinishScan,
    required this.requiredCoverageToFinish,
    required this.finishBlockers,
    required this.onFinish,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ScanFinishBlockersStrip(blockers: finishBlockers),
        GestureDetector(
          onTap: canFinishScan ? onFinish : null,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              gradient: canFinishScan ? AppColors.accentGradient : null,
              color: canFinishScan ? null : AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: canFinishScan ? Colors.transparent : AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: canFinishScan ? AppColors.cyan.withValues(alpha: 0.35) : Colors.black.withValues(alpha: 0.12),
                  blurRadius: 20,
                )
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgIcon(
                  RoomSvg.checkCircle,
                  size: 20,
                  color: canFinishScan ? Colors.white : AppColors.textMuted,
                ),
                const SizedBox(width: 10),
                Text(
                  canFinishScan
                      ? 'FINISH SCAN'
                      : 'SCANNING... NEED ${(100 * requiredCoverageToFinish).toInt()}% + STABLE QUALITY',
                  style: TextStyle(
                    color: canFinishScan ? Colors.white : AppColors.textMuted,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    fontSize: canFinishScan ? 13 : 11,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onCancel,
          child: Text(
            'Cancel scan',
            style: TextStyle(color: AppColors.red.withValues(alpha: 0.9), fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class ScanCompleteBottomBar extends StatelessWidget {
  final VoidCallback onScanAgain;
  final VoidCallback onOpenRig;
  final VoidCallback onExport;

  const ScanCompleteBottomBar({
    super.key,
    required this.onScanAgain,
    required this.onOpenRig,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onScanAgain,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.cyan.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.cyan, width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgIcon(RoomSvg.camera, size: 20, color: AppColors.cyan),
                const SizedBox(width: 10),
                const Text(
                  'SCAN AGAIN',
                  style: TextStyle(
                    color: AppColors.cyan,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onOpenRig,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgIcon(RoomSvg.tune, size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                const Text(
                  'OPEN RIG',
                  style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w800, letterSpacing: 2),
                ),
              ],
            ),
          ),
        ),
        TextButton(
          onPressed: onExport,
          child: const Text(
            'Export scan bundle',
            style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class ScanBottomBar extends StatelessWidget {
  final bool isScanning;
  final ScanSessionPhase setupPhase;
  final ScanSetupSnapshot setupSnap;
  final bool scanComplete;
  final bool canFinishScan;
  final double requiredCoverageToFinish;
  final List<String> finishBlockers;
  final Animation<double> pulseAnimation;
  final VoidCallback onRequestStartScan;
  final VoidCallback? onSetupAdvance;
  final VoidCallback onSetupSkipToPreset;
  final VoidCallback? onFinishScan;
  final VoidCallback onCancelScan;
  final VoidCallback onOpenRig;
  final VoidCallback onExportScanBundle;

  const ScanBottomBar({
    super.key,
    required this.isScanning,
    required this.setupPhase,
    required this.setupSnap,
    required this.scanComplete,
    required this.canFinishScan,
    required this.requiredCoverageToFinish,
    required this.finishBlockers,
    required this.pulseAnimation,
    required this.onRequestStartScan,
    required this.onSetupAdvance,
    required this.onSetupSkipToPreset,
    required this.onFinishScan,
    required this.onCancelScan,
    required this.onOpenRig,
    required this.onExportScanBundle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: isScanning && setupPhase != ScanSessionPhase.capture
          ? ScanSetupActionsBar(
              snap: setupSnap,
              isLockPhase: setupPhase == ScanSessionPhase.lockTracking,
              onAdvance: setupSnap.canAdvance ? onSetupAdvance : null,
              onSkipToPreset: onSetupSkipToPreset,
            )
          : isScanning
          ? ScanActiveCaptureBottomBar(
              canFinishScan: canFinishScan,
              requiredCoverageToFinish: requiredCoverageToFinish,
              finishBlockers: finishBlockers,
              onFinish: canFinishScan ? onFinishScan : null,
              onCancel: onCancelScan,
            )
          : scanComplete
          ? ScanCompleteBottomBar(
              onScanAgain: onRequestStartScan,
              onOpenRig: onOpenRig,
              onExport: onExportScanBundle,
            )
          : GestureDetector(
              onTap: onRequestStartScan,
              child: AnimatedBuilder(
                animation: pulseAnimation,
                builder: (context, _) => Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: 0.1 + pulseAnimation.value * 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.cyan,
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.cyan.withValues(alpha: 0.2 + pulseAnimation.value * 0.15),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SvgIcon(
                        RoomSvg.camera,
                        size: 20,
                        color: AppColors.cyan,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'TAP TO SCAN ROOM',
                        style: TextStyle(
                          color: AppColors.cyan,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
