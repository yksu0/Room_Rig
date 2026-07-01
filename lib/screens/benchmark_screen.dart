// lib/screens/benchmark_screen.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../models/room_model.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/room_icons.dart';
import '../widgets/score_ring.dart';

class BenchmarkScreen extends StatefulWidget {
  const BenchmarkScreen({super.key});

  @override
  State<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

class _BenchmarkScreenState extends State<BenchmarkScreen>
    with TickerProviderStateMixin {
  late AnimationController _particleController;
  late AnimationController _heatmapController;
  bool _isRunning = false;
  double _runProgress = 0.0;
  bool _showResults = false;

  @override
  void initState() {
    super.initState();
    _particleController = AnimationController(duration: const Duration(seconds: 3), vsync: this)..repeat();
    _heatmapController = AnimationController(duration: const Duration(seconds: 2), vsync: this)..repeat(reverse: true);
  }

  @override
  void dispose() {
    _particleController.dispose();
    _heatmapController.dispose();
    super.dispose();
  }

  void _runBenchmark() async {
    setState(() { _isRunning = true; _showResults = false; _runProgress = 0; });
    for (int i = 1; i <= 20; i++) {
      await Future.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
      setState(() => _runProgress = i / 20);
    }
    if (!mounted) return;
    setState(() { _isRunning = false; _showResults = true; });
    context.read<AppState>().runOptimization();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 20),
              _buildModeSelector(state),
              const SizedBox(height: 20),
              _buildModelPreview(state),
              const SizedBox(height: 20),
              _buildSimulationCanvas(state),
              const SizedBox(height: 20),
              _buildRunButton(),
              if (_isRunning) ...[
                const SizedBox(height: 16),
                _buildProgressBar(),
              ],
              if (_showResults) ...[
                const SizedBox(height: 24),
                _buildResultsPanel(state),
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('BENCHMARK CENTER', style: TextStyle(color: AppColors.cyan, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 3)),
        const Text('Room Stress Tests', style: TextStyle(color: AppColors.textPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _buildModeSelector(AppState state) {
    final modes = [
      ('airflow', RoomSvg.airflow, 'Airflow', AppColors.airflowColor),
      ('lighting', RoomSvg.lightbulb, 'Lighting', AppColors.lightingColor),
      ('ergonomics', RoomSvg.ergonomics, 'Ergonomics', AppColors.ergonomicsColor),
    ];

    return Row(
      children: modes.map((m) {
        final isSelected = state.benchmarkMode == m.$1;
        return Expanded(
          child: GestureDetector(
            onTap: () => state.setBenchmarkMode(m.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.only(right: m.$1 == 'ergonomics' ? 0 : 8),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? m.$4.withValues(alpha: 0.15) : AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isSelected ? m.$4 : AppColors.border, width: isSelected ? 1.5 : 1),
                boxShadow: isSelected ? [BoxShadow(color: m.$4.withValues(alpha: 0.2), blurRadius: 12)] : [],
              ),
              child: Column(
                children: [
                  SvgIcon(m.$2, size: 22, color: isSelected ? m.$4 : AppColors.textMuted),
                  const SizedBox(height: 5),
                  Text(m.$3, style: TextStyle(color: isSelected ? m.$4 : AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSimulationCanvas(AppState state) {
    return Container(
      height: 240,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedBuilder(
        animation: Listenable.merge([_particleController, _heatmapController]),
        builder: (context, _) => CustomPaint(
          painter: _SimulationPainter(
            mode: state.benchmarkMode,
            particleT: _particleController.value,
            heatT: _heatmapController.value,
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6, height: 6,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.green),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${state.benchmarkMode.toUpperCase()} SIMULATION',
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModelPreview(AppState state) {
    final room = state.currentRoomData;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'LIVE MODEL',
          style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2),
        ),
        const SizedBox(height: 10),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SvgIcon(RoomSvg.house, size: 18, color: AppColors.cyan),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${room.name} model',
                      style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                  Text(
                    '${state.furniture.length} items',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 180,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: CustomPaint(
                    painter: _RoomModelPainter(
                      room: room,
                      furniture: state.furniture,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRunButton() {
    return GestureDetector(
      onTap: _isRunning ? null : _runBenchmark,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: _isRunning ? null : AppColors.accentGradient,
          color: _isRunning ? AppColors.card : null,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _isRunning ? AppColors.border : Colors.transparent),
          boxShadow: _isRunning ? [] : [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.4), blurRadius: 20)],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgIcon(
              _isRunning ? RoomSvg.scan : RoomSvg.speedometer,
              size: 20,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Text(
              _isRunning ? 'RUNNING BENCHMARK...' : 'RUN BENCHMARK',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    final steps = ['Airflow analysis', 'Lighting ray-trace', 'Ergonomics mapping', 'Generating report'];
    final stepIdx = (_runProgress * steps.length).floor().clamp(0, steps.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(steps[stepIdx], style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const Spacer(),
            Text('${(_runProgress * 100).toInt()}%', style: TextStyle(color: AppColors.cyan, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: _runProgress,
          backgroundColor: AppColors.border,
          valueColor: const AlwaysStoppedAnimation(AppColors.cyan),
          minHeight: 4,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }

  Widget _buildResultsPanel(AppState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('BENCHMARK RESULTS', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2)),
        const SizedBox(height: 12),
        GlassCard(
          gradient: const LinearGradient(
            colors: [Color(0xFF0D1A14), Color(0xFF0A1018)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderColor: AppColors.green.withValues(alpha: 0.4),
          child: Column(
            children: [
              Row(
                children: [
                  SvgIcon(RoomSvg.trophy, size: 22, color: AppColors.amber),
                  const SizedBox(width: 10),
                  const Text('Optimization Applied', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('PASS', style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w800, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ScoreRing(score: state.airflowScore, size: 80, color: AppColors.airflowColor, label: 'Airflow'),
                  ScoreRing(score: state.lightingScore, size: 80, color: AppColors.lightingColor, label: 'Lighting'),
                  ScoreRing(score: state.ergonomicsScore, size: 80, color: AppColors.ergonomicsColor, label: 'Ergo'),
                ],
              ),
              const SizedBox(height: 20),
              _ComparisonRow(label: 'Airflow', before: state.previousOverallScore * 0.85, after: state.airflowScore, color: AppColors.airflowColor),
              const SizedBox(height: 10),
              _ComparisonRow(label: 'Lighting', before: state.previousOverallScore * 0.78, after: state.lightingScore, color: AppColors.lightingColor),
              const SizedBox(height: 10),
              _ComparisonRow(label: 'Ergonomics', before: state.previousOverallScore * 0.80, after: state.ergonomicsScore, color: AppColors.ergonomicsColor),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.cyan.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.cyan.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    SvgIcon(RoomSvg.trendingUp, size: 20, color: AppColors.cyan),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Overall: ${state.previousOverallScore.toStringAsFixed(1)} → ${state.overallScore.toStringAsFixed(1)}',
                        style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      '+${(state.overallScore - state.previousOverallScore).toStringAsFixed(1)}',
                      style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w800, fontSize: 18),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  final String label;
  final double before;
  final double after;
  final Color color;

  const _ComparisonRow({required this.label, required this.before, required this.after, required this.color});

  @override
  Widget build(BuildContext context) {
    final improvement = after - before;
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 12))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                Container(height: 8, color: AppColors.border),
                FractionallySizedBox(widthFactor: before / 100, child: Container(height: 8, color: AppColors.textMuted)),
                FractionallySizedBox(widthFactor: after / 100, child: Container(height: 8, color: color.withValues(alpha: 0.8))),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('+${improvement.toStringAsFixed(1)}', style: TextStyle(color: AppColors.green, fontSize: 12, fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _SimulationPainter extends CustomPainter {
  final String mode;
  final double particleT;
  final double heatT;

  _SimulationPainter({required this.mode, required this.particleT, required this.heatT});

  @override
  void paint(Canvas canvas, Size size) {
    if (mode == 'airflow') {
      _drawAirflow(canvas, size);
    } else if (mode == 'lighting') {
      _drawLighting(canvas, size);
    } else {
      _drawErgonomics(canvas, size);
    }
  }

  void _drawAirflow(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.8, -0.8),
        radius: 1.2,
        colors: [AppColors.cyanDim.withValues(alpha: 0.15), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    for (int i = 0; i < 22; i++) {
      final baseY = (i / 22) * size.height;
      final t = (particleT + i * 0.045) % 1.0;
      final x = t * size.width;
      final y = baseY + sin(t * pi * 2 + i) * 14;
      final opacity = sin(t * pi).clamp(0.2, 0.9);

      final paint = Paint()
        ..color = AppColors.airflowColor.withValues(alpha: opacity.toDouble())
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;

      if (t > 0.05) {
        canvas.drawLine(Offset(x - 14 * sin(t * pi), y), Offset(x, y), paint);
      }
      canvas.drawCircle(Offset(x, y), 2.5, Paint()..color = AppColors.airflowColor.withValues(alpha: opacity.toDouble()));
    }

    // Stagnation zone
    canvas.drawCircle(
      Offset(size.width * 0.72, size.height * 0.62),
      52,
      Paint()
        ..shader = RadialGradient(
          colors: [AppColors.red.withValues(alpha: 0.2), Colors.transparent],
        ).createShader(Rect.fromCircle(center: Offset(size.width * 0.72, size.height * 0.62), radius: 52))
        ..blendMode = BlendMode.plus,
    );
  }

  void _drawLighting(Canvas canvas, Size size) {
    final sources = [
      Offset(size.width * 0.25, 0),
      Offset(size.width * 0.75, 0),
      Offset(size.width * 0.1, size.height * 0.45),
    ];

    for (int s = 0; s < sources.length; s++) {
      final src = sources[s];
      final brightness = (0.45 + heatT * 0.3 + s * 0.08).clamp(0.0, 0.9);
      canvas.drawCircle(
        src,
        size.width * 0.6,
        Paint()
          ..shader = RadialGradient(
            colors: [AppColors.lightingColor.withValues(alpha: brightness), AppColors.lightingColor.withValues(alpha: 0.08), Colors.transparent],
            stops: const [0.0, 0.35, 1.0],
          ).createShader(Rect.fromCircle(center: src, radius: size.width * 0.6)),
      );
    }

    const gridSize = 20.0;
    for (double x = 0; x < size.width; x += gridSize) {
      for (double y = 0; y < size.height; y += gridSize) {
        double brightness = 0;
        for (final src in sources) {
          final dist = (Offset(x, y) - src).distance;
          brightness += (1 - (dist / size.width).clamp(0.0, 1.0)) * 0.45;
        }
        canvas.drawRect(
          Rect.fromLTWH(x, y, gridSize - 1, gridSize - 1),
          Paint()..color = AppColors.lightingColor.withValues(alpha: (brightness * 0.15 * (0.8 + heatT * 0.2)).clamp(0.0, 0.28)),
        );
      }
    }
  }

  void _drawErgonomics(Canvas canvas, Size size) {
    final chairPos = Offset(size.width * 0.45, size.height * 0.55);
    final deskPos = Offset(size.width * 0.45, size.height * 0.28);

    canvas.drawCircle(
      chairPos,
      92,
      Paint()
        ..shader = RadialGradient(
          colors: [AppColors.ergonomicsColor.withValues(alpha: 0.28), AppColors.ergonomicsColor.withValues(alpha: 0.04), Colors.transparent],
          stops: const [0.2, 0.6, 1.0],
        ).createShader(Rect.fromCircle(center: chairPos, radius: 92)),
    );

    final pathPaint = Paint()
      ..color = AppColors.ergonomicsColor.withValues(alpha: 0.2 + heatT * 0.15)
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(20, size.height / 2)
      ..cubicTo(size.width * 0.2, size.height * 0.4, size.width * 0.3, size.height * 0.6, chairPos.dx, chairPos.dy);
    canvas.drawPath(path, pathPaint);

    canvas.drawCircle(chairPos, 18, Paint()..color = AppColors.ergonomicsColor.withValues(alpha: 0.7));
    canvas.drawCircle(deskPos, 14, Paint()..color = AppColors.purple.withValues(alpha: 0.7));

    canvas.drawRect(
      Rect.fromCenter(center: chairPos, width: 80, height: 100),
      Paint()
        ..color = AppColors.ergonomicsColor.withValues(alpha: 0.25)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_SimulationPainter old) =>
      old.particleT != particleT || old.heatT != heatT || old.mode != mode;
}

class _RoomModelPainter extends CustomPainter {
  final RoomData room;
  final List<FurnitureItem> furniture;

  _RoomModelPainter({required this.room, required this.furniture});

  @override
  void paint(Canvas canvas, Size size) {
    final roomRect = Rect.fromLTWH(16, 16, size.width - 32, size.height - 32);
    final wallPaint = Paint()
      ..color = AppColors.surfaceAlt.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;
    final framePaint = Paint()
      ..color = AppColors.cyan.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    canvas.drawRRect(RRect.fromRectAndRadius(roomRect, const Radius.circular(14)), wallPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(roomRect, const Radius.circular(14)), framePaint);

    for (int c = 1; c < room.gridCols; c++) {
      final dx = roomRect.left + roomRect.width * (c / room.gridCols);
      canvas.drawLine(Offset(dx, roomRect.top), Offset(dx, roomRect.bottom), Paint()..color = AppColors.border.withValues(alpha: 0.55)..strokeWidth = 0.7);
    }
    for (int r = 1; r < room.gridRows; r++) {
      final dy = roomRect.top + roomRect.height * (r / room.gridRows);
      canvas.drawLine(Offset(roomRect.left, dy), Offset(roomRect.right, dy), Paint()..color = AppColors.border.withValues(alpha: 0.55)..strokeWidth = 0.7);
    }

    for (final item in furniture) {
      final x = roomRect.left + roomRect.width * (item.gridX / room.gridCols);
      final y = roomRect.top + roomRect.height * (item.gridY / room.gridRows);
      final w = roomRect.width * (item.width / room.gridCols);
      final h = roomRect.height * (item.height / room.gridRows);
      final rect = RRect.fromRectAndRadius(Rect.fromLTWH(x + 1, y + 1, w - 2, h - 2), const Radius.circular(8));

      canvas.drawRRect(
        rect,
        Paint()..color = AppColors.cyan.withValues(alpha: item.category == 'lighting' ? 0.18 : 0.12),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = _categoryColor(item.category).withValues(alpha: 0.65)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: item.name,
          style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: w - 8);
      tp.paint(canvas, Offset(x + 4, y + 4));
    }

    final titlePaint = TextPainter(
      text: const TextSpan(
        text: 'Current room layout',
        style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    titlePaint.paint(canvas, const Offset(14, 12));
  }

  Color _categoryColor(String cat) {
    switch (cat) {
      case 'airflow':
        return AppColors.airflowColor;
      case 'lighting':
        return AppColors.lightingColor;
      case 'ergonomics':
        return AppColors.ergonomicsColor;
      default:
        return AppColors.textMuted;
    }
  }

  @override
  bool shouldRepaint(covariant _RoomModelPainter oldDelegate) {
    return oldDelegate.room != room || oldDelegate.furniture != furniture;
  }
}
