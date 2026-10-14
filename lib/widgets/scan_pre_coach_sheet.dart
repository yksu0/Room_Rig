import 'package:flutter/material.dart';

import '../models/scan_layout_model.dart';
import '../services/scan_model_availability.dart';
import '../theme/app_theme.dart';
import 'room_icons.dart';

class ScanPreCoachResult {
  final RoomDimensions? manualDimensions;
  final bool preferArCore;

  const ScanPreCoachResult({
    this.manualDimensions,
    this.preferArCore = false,
  });
}

enum _SizeMode { arMeasure, enterManual }

/// Short pre-scan tips — honest about approximate Scan vs Rig/Bench core loop.
/// Returns null if cancelled.
///
/// Size source is exclusive: ARCore measure **or** typed L×W — never neither
/// (that used to silently fall back to a preset room size).
Future<ScanPreCoachResult?> showScanPreCoachSheet(
  BuildContext context, {
  required String detectorLabel,
  RoomDimensions? initialDimensions,
  bool initialPreferArCore = true,
}) async {
  final lengthCtrl = TextEditingController(
    text: (initialDimensions?.lengthMeters ?? 4.2).toStringAsFixed(1),
  );
  final widthCtrl = TextEditingController(
    text: (initialDimensions?.widthMeters ?? 3.6).toStringAsFixed(1),
  );
  final heightCtrl = TextEditingController(
    text: (initialDimensions?.heightMeters ?? 2.7).toStringAsFixed(1),
  );
  var sizeMode =
      initialPreferArCore ? _SizeMode.arMeasure : _SizeMode.enterManual;
  String? sizeError;

  final result = await showModalBottomSheet<ScanPreCoachResult>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModal) {
          void selectMode(_SizeMode next) {
            setModal(() {
              sizeMode = next;
              sizeError = null;
            });
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpace.screen,
                AppSpace.md,
                AppSpace.screen,
                AppSpace.xl + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SingleChildScrollView(
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
                    const SizedBox(height: 16),
                    const Text(
                      'BEFORE YOU SCAN',
                      style: TextStyle(
                        color: AppColors.cyan,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Measure room size',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.amber.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded, size: 16, color: AppColors.amber),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Pick how to set L×W — AR measure or type it. '
                              'After you confirm size, a lighter detect pass finds furniture.',
                              style: TextStyle(
                                color: AppColors.amber,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'HOW TO SET SIZE',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SizeModeTile(
                      selected: sizeMode == _SizeMode.arMeasure,
                      title: 'Use ARCore to measure',
                      subtitle:
                          'Lock tracking, mark floor corners, confirm size, then open Rig',
                      onTap: () => selectMode(_SizeMode.arMeasure),
                    ),
                    const SizedBox(height: 8),
                    _SizeModeTile(
                      selected: sizeMode == _SizeMode.enterManual,
                      title: 'Enter room size (meters)',
                      subtitle: 'Type length × width × height — no AR corner marks',
                      onTap: () => selectMode(_SizeMode.enterManual),
                    ),
                    if (sizeMode == _SizeMode.enterManual) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _MeterField(controller: lengthCtrl, label: 'Length')),
                          const SizedBox(width: 8),
                          Expanded(child: _MeterField(controller: widthCtrl, label: 'Width')),
                          const SizedBox(width: 8),
                          Expanded(child: _MeterField(controller: heightCtrl, label: 'Height')),
                        ],
                      ),
                    ],
                    if (sizeError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        sizeError!,
                        style: const TextStyle(
                          color: AppColors.amber,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    ...ScanModelAvailability.honestyBullets.map(
                      (b) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.check_rounded, size: 14, color: AppColors.cyan),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                b,
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (sizeMode == _SizeMode.arMeasure) ...[
                      const SizedBox(height: 4),
                      const _TipRow(
                        icon: Icons.smartphone_rounded,
                        title: 'Hold chest-high, move slowly',
                        detail: 'Good light helps. Fast spins confuse tracking.',
                      ),
                      const _TipRow(
                        icon: Icons.crop_square_rounded,
                        title: 'Mark floor + ceiling corners',
                        detail:
                            'Need 3 corners on the floor (or ceiling) plus 1 on the other for height — min 4. Ideal is all 8. Blocked? Edit L×W×H after.',
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                              side: const BorderSide(color: AppColors.border),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('NOT NOW'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: () {
                              if (sizeMode == _SizeMode.enterManual) {
                                final L = double.tryParse(lengthCtrl.text.trim());
                                final W = double.tryParse(widthCtrl.text.trim());
                                final H =
                                    double.tryParse(heightCtrl.text.trim()) ?? 2.7;
                                if (L == null || W == null || L < 2.0 || W < 2.0) {
                                  setModal(() {
                                    sizeError =
                                        'Enter length and width of at least 2.0 m.';
                                  });
                                  return;
                                }
                                Navigator.pop(
                                  context,
                                  ScanPreCoachResult(
                                    manualDimensions: RoomDimensions(
                                      lengthMeters: L.clamp(2.6, 8.5),
                                      widthMeters: W.clamp(2.6, 8.5),
                                      heightMeters: H.clamp(2.2, 3.5),
                                    ),
                                    preferArCore: false,
                                  ),
                                );
                                return;
                              }
                              Navigator.pop(
                                context,
                                const ScanPreCoachResult(
                                  manualDimensions: null,
                                  preferArCore: true,
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.cyan,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              elevation: 0,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SvgIcon(RoomSvg.camera, size: 18, color: Colors.black),
                                const SizedBox(width: 8),
                                Text(
                                  sizeMode == _SizeMode.arMeasure
                                      ? 'START MEASURE'
                                      : 'USE THIS SIZE',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );

  lengthCtrl.dispose();
  widthCtrl.dispose();
  heightCtrl.dispose();
  return result;
}

class _SizeModeTile extends StatelessWidget {
  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SizeModeTile({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final border = selected ? AppColors.cyan : AppColors.border;
    final fill = selected
        ? AppColors.cyan.withValues(alpha: 0.12)
        : AppColors.card;
    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: selected ? 1.5 : 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 20,
                color: selected ? AppColors.cyan : AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        height: 1.3,
                      ),
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

class _MeterField extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const _MeterField({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 11),
        isDense: true,
        filled: true,
        fillColor: AppColors.card,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _TipRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;

  const _TipRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.cyan),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  detail,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
