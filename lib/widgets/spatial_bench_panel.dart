// lib/widgets/spatial_bench_panel.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../models/room_model.dart';
import '../models/room_scale.dart';
import '../services/bench_layouts.dart';
import '../services/spatial_analyzer.dart';
import '../theme/app_theme.dart';
import 'bench_room_views.dart';
import 'furniture_shapes.dart';
import 'glass_card.dart';
import 'score_ring.dart';

class SpatialBenchPanel extends StatefulWidget {
  const SpatialBenchPanel({super.key});

  @override
  State<SpatialBenchPanel> createState() => _SpatialBenchPanelState();
}

class _SpatialBenchPanelState extends State<SpatialBenchPanel> {
  BenchLayoutKind _variant = BenchLayoutKind.myRoom;
  BenchLayouts? _layouts;
  int _seenFocusToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _rebuild());
  }

  void _rebuild() {
    final state = context.read<AppState>();
    final room = state.currentRoomData;
    _layouts = BenchLayoutBuilder.build(
      mode: BenchMode.spatial,
      roomFurniture: state.furniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
    );
    if (state.benchLayoutFocusToken != _seenFocusToken) {
      _seenFocusToken = state.benchLayoutFocusToken;
      _variant = state.benchLayoutFocus;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.currentTab == benchTabIndex) {
      final fp = BenchLayoutBuilder.fingerprintOf(state.furniture);
      if (_layouts == null || _layouts!.fingerprint != fp) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _rebuild();
        });
      }
    }
    final layouts = _layouts;
    if (layouts == null) {
      return const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()));
    }
    final room = state.currentRoomData;
    final furniture = layouts.forKind(_variant);
    final metrics = SpatialAnalyzer.evaluate(
      furniture: furniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'WALKWAYS',
          style: TextStyle(
            color: AppColors.spatialColor,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Estimated floor use — not a measured survey.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _chip('My Room', BenchLayoutKind.myRoom),
            _chip('Improved', BenchLayoutKind.improved),
            _chip('Sample', BenchLayoutKind.sample),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: 280,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: CustomPaint(
            painter: _SpatialHeatPainter(
              occupied: metrics.occupied,
              cols: room.gridCols,
              rows: room.gridRows,
              furniture: furniture,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ScoreRing(score: metrics.utilizationScore, size: 72, color: AppColors.spatialColor, label: 'Use'),
            ScoreRing(score: metrics.accessibilityScore, size: 88, color: AppColors.cyan, label: 'Access'),
            ScoreRing(score: metrics.overallScore, size: 72, color: AppColors.green, label: 'Space'),
          ],
        ),
        const SizedBox(height: 12),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Largest aisle ${RoomScale.formatCellsAsMeters(metrics.largestAisleCells)}  ·  '
                '${(metrics.walkableRatio * 100).round()}% walkable',
                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 13),
              ),
              const SizedBox(height: 8),
              ...metrics.notes.map(
                (n) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(n, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ),
              ),
              if (_variant != BenchLayoutKind.improved && layouts.improvedReasons.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...layouts.improvedReasons.take(3).map(
                  (r) => Text('Improved: $r', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ),
              ],
            ],
          ),
        ),
        if (_variant == BenchLayoutKind.improved) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                state.applyFurnitureLayout(layouts.improved, markOptimized: true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Applied walkway layout to Rig')),
                );
              },
              child: const Text('Apply improved layout'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _chip(String label, BenchLayoutKind kind) {
    final on = _variant == kind;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _variant = kind),
        child: Container(
          margin: EdgeInsets.only(right: kind == BenchLayoutKind.sample ? 0 : 8),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: on ? AppColors.spatialColor.withValues(alpha: 0.16) : AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: on ? AppColors.spatialColor : AppColors.border),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: on ? AppColors.spatialColor : AppColors.textMuted,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }
}

class _SpatialHeatPainter extends CustomPainter {
  final List<bool> occupied;
  final int cols;
  final int rows;
  final List<FurnitureItem> furniture;

  _SpatialHeatPainter({
    required this.occupied,
    required this.cols,
    required this.rows,
    required this.furniture,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = BenchRoom2DGeometry.fieldRectFor(
      size: size,
      gridCols: cols,
      gridRows: rows,
    );
    final cellW = rect.width / cols;
    final cellH = rect.height / rows;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      Paint()..color = AppColors.surfaceAlt,
    );

    for (int y = 0; y < rows; y++) {
      for (int x = 0; x < cols; x++) {
        final blocked = occupied[y * cols + x];
        canvas.drawRect(
          Rect.fromLTWH(rect.left + x * cellW, rect.top + y * cellH, cellW - 0.6, cellH - 0.6),
          Paint()
            ..color = blocked
                ? AppColors.red.withValues(alpha: 0.28)
                : AppColors.spatialColor.withValues(alpha: 0.16),
        );
      }
    }

    for (final f in furniture) {
      if (!FurnitureShapes.drawsMesh(f)) continue;
      FurnitureShapes.paintItemPlan(
        canvas,
        f,
        cell: Rect.fromLTWH(
          rect.left + f.gridX * cellW,
          rect.top + f.gridY * cellH,
          f.width * cellW,
          f.height * cellH,
        ),
        color: Colors.white,
        strong: true,
      );
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      Paint()
        ..color = AppColors.spatialColor.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant _SpatialHeatPainter old) =>
      old.occupied != occupied || old.furniture != furniture;
}
