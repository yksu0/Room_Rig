import 'package:flutter/material.dart';

import '../models/scan_layout_model.dart';
import '../theme/app_theme.dart';

/// Edit L×W×H after AR marks (or manual/preset), then continue to item detection.
Future<RoomDimensions?> showScanConfirmSizeSheet(
  BuildContext context, {
  required RoomDimensions initial,
  required String roomSizeSource,
  int markCount = 0,
}) async {
  final lengthCtrl = TextEditingController(
    text: initial.lengthMeters.toStringAsFixed(1),
  );
  final widthCtrl = TextEditingController(
    text: initial.widthMeters.toStringAsFixed(1),
  );
  final heightCtrl = TextEditingController(
    text: initial.heightMeters.toStringAsFixed(1),
  );

  final sourceLabel = switch (roomSizeSource) {
    'measured' => markCount > 0
        ? 'From $markCount AR corner marks (approx)'
        : 'From AR walk estimate (approx)',
    'manual' => 'Manual entry',
    _ => 'Preset — edit to match your room',
  };

  try {
    final result = await showModalBottomSheet<RoomDimensions>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpace.screen,
              AppSpace.md,
              AppSpace.screen,
              AppSpace.xl + MediaQuery.viewInsetsOf(context).bottom,
            ),
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
                const SizedBox(height: AppSpace.md),
                const Text(
                  'CONFIRM ROOM SIZE',
                  style: TextStyle(
                    color: AppColors.cyan,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
                const Text(
                  'Then detect items',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  sourceLabel,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Approximate footprint — edit if a corner was blocked by furniture.',
                  style: TextStyle(
                    color: AppColors.amber.withValues(alpha: 0.95),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _MeterField(controller: lengthCtrl, label: 'Length'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MeterField(controller: widthCtrl, label: 'Width'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MeterField(controller: heightCtrl, label: 'Height'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                AspectRatio(
                  aspectRatio: (initial.lengthMeters / initial.widthMeters)
                      .clamp(0.55, 1.85),
                  child: CustomPaint(
                    painter: _FootprintPainter(
                      length: initial.lengthMeters,
                      width: initial.widthMeters,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
                const SizedBox(height: 16),
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
                        child: const Text('BACK'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () {
                          final l = double.tryParse(lengthCtrl.text.trim());
                          final w = double.tryParse(widthCtrl.text.trim());
                          final h = double.tryParse(heightCtrl.text.trim());
                          if (l == null || w == null || h == null) return;
                          Navigator.pop(
                            context,
                            RoomDimensions(
                              lengthMeters: l,
                              widthMeters: w,
                              heightMeters: h,
                            ),
                          );
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.cyan,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          'CONTINUE TO DETECT',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    return result;
  } finally {
    lengthCtrl.dispose();
    widthCtrl.dispose();
    heightCtrl.dispose();
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
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.textSecondary),
        suffixText: 'm',
        filled: true,
        fillColor: AppColors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.border),
        ),
      ),
    );
  }
}

class _FootprintPainter extends CustomPainter {
  final double length;
  final double width;

  _FootprintPainter({required this.length, required this.width});

  @override
  void paint(Canvas canvas, Size size) {
    final pad = 16.0;
    final availW = size.width - pad * 2;
    final availH = size.height - pad * 2;
    final aspect = (length / width).clamp(0.2, 5.0);
    double w;
    double h;
    if (availW / availH > aspect) {
      h = availH;
      w = h * aspect;
    } else {
      w = availW;
      h = w / aspect;
    }
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: w,
      height: h,
    );
    final fill = Paint()..color = AppColors.cyan.withValues(alpha: 0.12);
    final stroke = Paint()
      ..color = AppColors.cyan
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _FootprintPainter oldDelegate) =>
      oldDelegate.length != length || oldDelegate.width != width;
}
