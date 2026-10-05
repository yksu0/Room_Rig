import 'package:flutter/material.dart';

import '../models/scan_layout_model.dart';
import '../services/scan_model_availability.dart';
import '../theme/app_theme.dart';
import 'room_icons.dart';

class ScanPreCoachResult {
  final RoomDimensions? manualDimensions;
  final bool preferArCore;
  final bool useRemoteDetect;
  final String remoteHostPort;

  const ScanPreCoachResult({
    this.manualDimensions,
    this.preferArCore = false,
    this.useRemoteDetect = false,
    this.remoteHostPort = '',
  });
}

/// Short pre-scan tips — honest about approximate Scan vs Rig/Bench core loop.
/// Returns null if cancelled.
Future<ScanPreCoachResult?> showScanPreCoachSheet(
  BuildContext context, {
  required String detectorLabel,
  RoomDimensions? initialDimensions,
  String initialRemoteHost = '192.168.254.100:8787',
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
  final remoteHostCtrl = TextEditingController(text: initialRemoteHost);
  var preferArCore = false;
  var useManualSize = false;
  var useRemoteDetect = false;

  final result = await showModalBottomSheet<ScanPreCoachResult>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModal) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                24 + MediaQuery.viewInsetsOf(context).bottom,
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
                      'Optional layout seed',
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
                              'Detector: $detectorLabel\n'
                              'Set size below if you know it. Tracking defaults to visual odometry on Android.',
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
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Enter room size (meters)',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        'Length × width × height',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                      ),
                      value: useManualSize,
                      activeTrackColor: AppColors.cyan,
                      onChanged: (v) => setModal(() => useManualSize = v),
                    ),
                    if (useManualSize) ...[
                      Row(
                        children: [
                          Expanded(child: _MeterField(controller: lengthCtrl, label: 'Length')),
                          const SizedBox(width: 8),
                          Expanded(child: _MeterField(controller: widthCtrl, label: 'Width')),
                          const SizedBox(width: 8),
                          Expanded(child: _MeterField(controller: heightCtrl, label: 'Height')),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Prefer ARCore pose',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        'Uses ARCore only while sizing the room, then live camera for detection (less lag)',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                      ),
                      value: preferArCore,
                      activeTrackColor: AppColors.cyan,
                      onChanged: (v) => setModal(() => preferArCore = v),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Use PC remote detect',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        'Offload YOLO to ml/remote_infer_server.py on your PC (same Wi‑Fi). Falls back to on-device TFLite.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                      ),
                      value: useRemoteDetect,
                      activeTrackColor: AppColors.cyan,
                      onChanged: (v) => setModal(() => useRemoteDetect = v),
                    ),
                    if (useRemoteDetect) ...[
                      const SizedBox(height: 4),
                      TextField(
                        controller: remoteHostCtrl,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'PC host:port',
                          hintText: '192.168.x.x:8787',
                          labelStyle: TextStyle(color: AppColors.textSecondary),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.cyan),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 8),
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
                    const SizedBox(height: 8),
                    const _TipRow(
                      icon: Icons.smartphone_rounded,
                      title: 'Hold chest-high, move slowly',
                      detail: 'Good light helps. Fast spins confuse tracking.',
                    ),
                    const _TipRow(
                      icon: Icons.chair_alt_outlined,
                      title: 'Point at furniture',
                      detail: 'Desk, chair, bed, fan, window — Room Rig YOLO classes.',
                    ),
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
                              RoomDimensions? dims;
                              if (useManualSize) {
                                final L = double.tryParse(lengthCtrl.text.trim());
                                final W = double.tryParse(widthCtrl.text.trim());
                                final H = double.tryParse(heightCtrl.text.trim()) ?? 2.7;
                                if (L != null && W != null && L >= 2.0 && W >= 2.0) {
                                  dims = RoomDimensions(
                                    lengthMeters: L.clamp(2.6, 8.5),
                                    widthMeters: W.clamp(2.6, 8.5),
                                    heightMeters: H.clamp(2.2, 3.5),
                                  );
                                }
                              }
                              Navigator.pop(
                                context,
                                ScanPreCoachResult(
                                  manualDimensions: dims,
                                  preferArCore: preferArCore,
                                  useRemoteDetect: useRemoteDetect,
                                  remoteHostPort: remoteHostCtrl.text.trim(),
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
                                const Text(
                                  'START SCAN',
                                  style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1),
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
