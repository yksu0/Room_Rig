import 'package:flutter/material.dart';
import '../../services/scan_setup.dart';
import '../../theme/app_theme.dart';
import '../../widgets/room_icons.dart';

class ScanSetupActionsBar extends StatelessWidget {
  final ScanSetupSnapshot snap;
  final ScanSessionPhase phase;
  final int markCount;
  final VoidCallback? onAdvance;
  final VoidCallback? onDropMark;
  final VoidCallback? onUndoMark;
  final VoidCallback? onEnableWalkEstimate;
  final VoidCallback onSkipToPreset;
  final VoidCallback? onEnterManualSize;
  final VoidCallback? onConfirmContinue;

  const ScanSetupActionsBar({
    super.key,
    required this.snap,
    required this.phase,
    this.markCount = 0,
    required this.onAdvance,
    this.onDropMark,
    this.onUndoMark,
    this.onEnableWalkEstimate,
    required this.onSkipToPreset,
    this.onEnterManualSize,
    this.onConfirmContinue,
  });

  @override
  Widget build(BuildContext context) {
    final isLock = phase == ScanSessionPhase.lockTracking;
    final isMark = phase == ScanSessionPhase.markFootprint;
    final isConfirm = phase == ScanSessionPhase.confirmSize;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isMark) ...[
          // Measure-app primary action: add the corner under the center reticle.
          Center(
            child: GestureDetector(
              onTap: onDropMark,
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: onDropMark != null ? AppColors.accentGradient : null,
                  color: onDropMark != null ? null : AppColors.card,
                  border: Border.all(
                    color: onDropMark != null
                        ? Colors.white.withValues(alpha: 0.35)
                        : AppColors.border,
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.cyan.withValues(alpha: onDropMark != null ? 0.35 : 0.08),
                      blurRadius: 18,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add,
                      color: onDropMark != null ? Colors.white : AppColors.textMuted,
                      size: 28,
                    ),
                    Text(
                      'CORNER',
                      style: TextStyle(
                        color: onDropMark != null ? Colors.white : AppColors.textMuted,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '$markCount corners marked',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: onUndoMark,
                  child: Text(
                    'Undo',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: snap.canAdvance ? onAdvance : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: snap.canAdvance
                          ? AppColors.cyan.withValues(alpha: 0.15)
                          : AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: snap.canAdvance ? AppColors.cyan : AppColors.border,
                      ),
                    ),
                    child: Text(
                      snap.canAdvance
                          ? 'DONE — REVIEW SIZE'
                          : 'NEED 3+ ONE PLANE + HEIGHT (4 MIN)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: snap.canAdvance ? AppColors.cyan : AppColors.textMuted,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (onEnableWalkEstimate != null)
            TextButton(
              onPressed: onEnableWalkEstimate,
              child: Text(
                'Estimate from walk instead',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ] else if (isConfirm) ...[
          GestureDetector(
            onTap: onConfirmContinue,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: AppColors.accentGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'CONFIRM SIZE — DETECT ITEMS',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ] else ...[
          GestureDetector(
            onTap: snap.canAdvance ? onAdvance : null,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: snap.canAdvance ? AppColors.accentGradient : null,
                color: snap.canAdvance ? null : AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: snap.canAdvance ? Colors.transparent : AppColors.border,
                ),
              ),
              child: Text(
                isLock
                    ? (snap.canAdvance ? 'TRACKING LOCKED — CONTINUE' : 'PAN SLOWLY TO LOCK')
                    : (snap.canAdvance ? 'CONTINUE' : 'KEEP GOING'),
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
        ],
        const SizedBox(height: 8),
        if (!isConfirm)
          TextButton(
            onPressed: onSkipToPreset,
            child: Text(
              'Skip and use preset room size',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (onEnterManualSize != null && (isMark || isLock))
          TextButton(
            onPressed: onEnterManualSize,
            child: Text(
              'Enter length × width manually',
              style: TextStyle(
                color: AppColors.cyan,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
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
      margin: const EdgeInsets.only(bottom: AppSpace.xs),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        spacing: AppSpace.xs,
        runSpacing: AppSpace.xs,
        children: blockers
            .map(
              (text) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: AppColors.amber.withValues(alpha: 0.35)),
                ),
                child: Text(
                  text,
                  style: TextStyle(
                    color: AppColors.amber,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
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
  final VoidCallback? onSkipDetection;
  final VoidCallback onCancel;

  const ScanActiveCaptureBottomBar({
    super.key,
    required this.canFinishScan,
    required this.requiredCoverageToFinish,
    required this.finishBlockers,
    required this.onFinish,
    this.onSkipDetection,
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
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              gradient: canFinishScan ? AppColors.accentGradient : null,
              color: canFinishScan ? null : AppColors.card,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: canFinishScan ? Colors.transparent : AppColors.border,
              ),
              boxShadow: [
                BoxShadow(
                  color: canFinishScan
                      ? AppColors.cyan.withValues(alpha: 0.35)
                      : Colors.black.withValues(alpha: 0.12),
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
                      ? 'FINISH — OPEN RIG'
                      : 'DETECTING... NEED ${(100 * requiredCoverageToFinish).toInt()}% + STABLE QUALITY',
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
        if (onSkipDetection != null)
          TextButton(
            onPressed: onSkipDetection,
            child: Text(
              'Skip items — open empty Rig',
              style: TextStyle(
                color: AppColors.cyan,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        TextButton(
          onPressed: onCancel,
          child: Text(
            'Cancel scan',
            style: TextStyle(
              color: AppColors.red.withValues(alpha: 0.9),
              fontWeight: FontWeight.w700,
            ),
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
                  'MEASURE ROOM AGAIN',
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
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
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
  final int markCount;
  final bool scanComplete;
  final bool canFinishScan;
  final double requiredCoverageToFinish;
  final List<String> finishBlockers;
  final Animation<double> pulseAnimation;
  final VoidCallback onRequestStartScan;
  final VoidCallback? onSetupAdvance;
  final VoidCallback? onDropMark;
  final VoidCallback? onUndoMark;
  final VoidCallback? onEnableWalkEstimate;
  final VoidCallback onSetupSkipToPreset;
  final VoidCallback? onEnterManualSize;
  final VoidCallback? onConfirmContinue;
  final VoidCallback? onFinishScan;
  final VoidCallback? onSkipDetection;
  final VoidCallback onCancelScan;
  final VoidCallback onOpenRig;
  final VoidCallback onExportScanBundle;

  const ScanBottomBar({
    super.key,
    required this.isScanning,
    required this.setupPhase,
    required this.setupSnap,
    this.markCount = 0,
    required this.scanComplete,
    required this.canFinishScan,
    required this.requiredCoverageToFinish,
    required this.finishBlockers,
    required this.pulseAnimation,
    required this.onRequestStartScan,
    required this.onSetupAdvance,
    this.onDropMark,
    this.onUndoMark,
    this.onEnableWalkEstimate,
    required this.onSetupSkipToPreset,
    this.onEnterManualSize,
    this.onConfirmContinue,
    required this.onFinishScan,
    this.onSkipDetection,
    required this.onCancelScan,
    required this.onOpenRig,
    required this.onExportScanBundle,
  });

  @override
  Widget build(BuildContext context) {
    final inSetup = isScanning &&
        setupPhase != ScanSessionPhase.capture;

    return Container(
      padding: const EdgeInsets.all(20),
      child: inSetup
          ? ScanSetupActionsBar(
              snap: setupSnap,
              phase: setupPhase,
              markCount: markCount,
              onAdvance: setupSnap.canAdvance || setupPhase == ScanSessionPhase.lockTracking
                  ? onSetupAdvance
                  : null,
              onDropMark: onDropMark,
              onUndoMark: markCount > 0 ? onUndoMark : null,
              onEnableWalkEstimate: onEnableWalkEstimate,
              onSkipToPreset: onSetupSkipToPreset,
              onEnterManualSize: onEnterManualSize,
              onConfirmContinue: onConfirmContinue,
            )
          : isScanning
          ? ScanActiveCaptureBottomBar(
              canFinishScan: canFinishScan,
              requiredCoverageToFinish: requiredCoverageToFinish,
              finishBlockers: finishBlockers,
              onFinish: canFinishScan ? onFinishScan : null,
              onSkipDetection: onSkipDetection,
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
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: 0.1 + pulseAnimation.value * 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
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
                        'TAP TO MEASURE ROOM',
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
