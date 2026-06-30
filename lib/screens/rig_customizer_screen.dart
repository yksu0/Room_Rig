// lib/screens/rig_customizer_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../models/room_model.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/room_icons.dart';

class RigCustomizerScreen extends StatefulWidget {
  const RigCustomizerScreen({super.key});

  @override
  State<RigCustomizerScreen> createState() => _RigCustomizerScreenState();
}

class _RigCustomizerScreenState extends State<RigCustomizerScreen> {
  FurnitureItem? _selected;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, state),
            Expanded(
              child: Stack(
                children: [
                  Column(
                    children: [
                      Expanded(child: _buildCanvas(state)),
                      _buildSliders(state),
                    ],
                  ),
                  if (_selected != null) _buildInfoCard(_selected!),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RIG CUSTOMIZER',
                style: TextStyle(color: AppColors.cyan, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 3),
              ),
              Text(
                state.currentRoomData.name,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const Spacer(),
          GestureDetector(
            onTap: () {
              state.runOptimization();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      SvgIcon(RoomSvg.star, size: 16, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text('Auto-Rig Optimization applied!'),
                    ],
                  ),
                  backgroundColor: AppColors.cyan.withValues(alpha: 0.9),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: AppColors.accentGradient,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.3), blurRadius: 12)],
              ),
              child: Row(
                children: [
                  SvgIcon(RoomSvg.star, size: 16, color: Colors.white),
                  const SizedBox(width: 6),
                  const Text('Auto-Rig', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas(AppState state) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cellW = constraints.maxWidth / state.currentRoomData.gridCols;
            final cellH = constraints.maxHeight / state.currentRoomData.gridRows;
            return Stack(
              children: [
                CustomPaint(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                  painter: _RoomGridPainter(
                    gridCols: state.currentRoomData.gridCols,
                    gridRows: state.currentRoomData.gridRows,
                  ),
                ),
                ...state.furniture.map((item) {
                  final isSelected = _selected?.id == item.id;
                  return Positioned(
                    left: item.gridX * cellW + cellW * 0.05,
                    top: item.gridY * cellH + cellH * 0.05,
                    width: item.width * cellW * 0.9,
                    height: item.height * cellH * 0.9,
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _selected = isSelected ? null : item;
                      }),
                      onPanUpdate: (details) {
                        final newX = (item.gridX + details.delta.dx / cellW)
                            .clamp(0.0, (state.currentRoomData.gridCols - item.width).toDouble());
                        final newY = (item.gridY + details.delta.dy / cellH)
                            .clamp(0.0, (state.currentRoomData.gridRows - item.height).toDouble());
                        state.moveFurniture(item.id, newX, newY);
                        if (_selected?.id == item.id) {
                          setState(() => _selected = item.copyWith(gridX: newX, gridY: newY));
                        }
                      },
                      child: _FurnitureCell(item: item, isSelected: isSelected),
                    ),
                  );
                }),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSliders(AppState state) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OPTIMIZATION TARGETS',
            style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2),
          ),
          const SizedBox(height: 10),
          _SliderRow(svgString: RoomSvg.airflow, label: 'Airflow', value: state.airflowSlider, color: AppColors.airflowColor, onChanged: state.setAirflowSlider),
          const SizedBox(height: 6),
          _SliderRow(svgString: RoomSvg.lightbulb, label: 'Lighting', value: state.lightingSlider, color: AppColors.lightingColor, onChanged: state.setLightingSlider),
          const SizedBox(height: 6),
          _SliderRow(svgString: RoomSvg.ergonomics, label: 'Ergonomics', value: state.ergonomicsSlider, color: AppColors.ergonomicsColor, onChanged: state.setErgonomicsSlider),
        ],
      ),
    );
  }

  Widget _buildInfoCard(FurnitureItem item) {
    return Positioned(
      bottom: 210,
      left: 16,
      right: 16,
      child: GestureDetector(
        onTap: () => setState(() => _selected = null),
        child: NeonBorderCard(
          glowColor: AppColors.cyan,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.cyan.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.cyan.withValues(alpha: 0.3)),
                    ),
                    child: Center(child: SvgIcon(furnitureSvgFor(item.iconName), size: 22, color: AppColors.cyan)),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
                      Text(item.category.toUpperCase(), style: TextStyle(color: AppColors.cyan, fontSize: 10, letterSpacing: 2)),
                    ],
                  ),
                  const Spacer(),
                  SvgIcon(RoomSvg.info, size: 18, color: AppColors.textMuted),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _ImpactChip(label: 'Airflow', value: item.airflowImpact, color: AppColors.airflowColor),
                  const SizedBox(width: 8),
                  _ImpactChip(label: 'Lighting', value: item.lightingImpact, color: AppColors.lightingColor),
                  const SizedBox(width: 8),
                  _ImpactChip(label: 'Ergo', value: item.ergonomicsImpact, color: AppColors.ergonomicsColor),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Drag to reposition  •  Tap to deselect',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FurnitureCell extends StatelessWidget {
  final FurnitureItem item;
  final bool isSelected;
  const _FurnitureCell({required this.item, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final color = _categoryColor(item.category);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isSelected ? 0.2 : 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isSelected ? color : color.withValues(alpha: 0.35),
          width: isSelected ? 1.8 : 1,
        ),
        boxShadow: isSelected
            ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 12)]
            : [],
      ),
      child: Center(
        child: SvgIcon(
          furnitureSvgFor(item.iconName),
          size: isSelected ? 24 : 20,
          color: isSelected ? color : AppColors.textSecondary,
        ),
      ),
    );
  }

  Color _categoryColor(String cat) {
    switch (cat) {
      case 'airflow': return AppColors.airflowColor;
      case 'lighting': return AppColors.lightingColor;
      case 'ergonomics': return AppColors.ergonomicsColor;
      default: return AppColors.textMuted;
    }
  }
}

class _ImpactChip extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _ImpactChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final isPositive = value >= 0;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            Text(
              '${isPositive ? '+' : ''}${(value * 100).toInt()}%',
              style: TextStyle(
                color: isPositive ? AppColors.green : AppColors.red,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String svgString;
  final String label;
  final double value;
  final Color color;
  final ValueChanged<double> onChanged;

  const _SliderRow({required this.svgString, required this.label, required this.value, required this.color, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SvgIcon(svgString, size: 18, color: color),
        const SizedBox(width: 8),
        SizedBox(
          width: 76,
          child: Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: color,
              inactiveTrackColor: AppColors.border,
              thumbColor: color,
              overlayColor: color.withValues(alpha: 0.2),
            ),
            child: Slider(value: value, min: 0, max: 1, onChanged: onChanged),
          ),
        ),
        SizedBox(
          width: 38,
          child: Text(
            '${(value * 100).toInt()}%',
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _RoomGridPainter extends CustomPainter {
  final int gridCols;
  final int gridRows;
  _RoomGridPainter({required this.gridCols, required this.gridRows});

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / gridCols;
    final cellH = size.height / gridRows;
    final gridPaint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.45)
      ..strokeWidth = 0.5;
 
    for (int col = 0; col <= gridCols; col++) {
      canvas.drawLine(Offset(col * cellW, 0), Offset(col * cellW, size.height), gridPaint);
    }
    for (int row = 0; row <= gridRows; row++) {
      canvas.drawLine(Offset(0, row * cellH), Offset(size.width, row * cellH), gridPaint);
    }
 
    // Room wall outline
    final wallPaint = Paint()
      ..color = AppColors.cyan.withValues(alpha: 0.25)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Rect.fromLTWH(1, 1, size.width - 2, size.height - 2), wallPaint);
  }

  @override
  bool shouldRepaint(_RoomGridPainter old) =>
      old.gridCols != gridCols || old.gridRows != gridRows;
}
