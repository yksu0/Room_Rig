// lib/screens/scanner_screen.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/room_icons.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with TickerProviderStateMixin {
  late AnimationController _scanLineController;
  late AnimationController _pulseController;
  Timer? _logTimer;

  bool _isScanning = false;
  final List<String> _logs = [];
  final List<_DetectedBox> _detectedBoxes = [];

  // No emojis — plain ASCII log messages only
  final List<String> _scanMessages = [
    '> Initializing depth sensors...',
    '> Detecting wall boundaries...',
    '> Measuring room dimensions: 4.2m x 3.8m',
    '> Room geometry locked',
    '> Object recognized: Bed [confidence: 97%]',
    '> Object recognized: PC Tower [confidence: 94%]',
    '> Object recognized: Ergonomic Chair [confidence: 91%]',
    '> Object recognized: Window [confidence: 99%]',
    '> AC Unit detected at: [North Wall]',
    '> Light sources mapped: 3 found',
    '> Thermal scan: Room temp 24 C',
    '> Generating airflow model...',
    '> Scan complete — building 3D Rig...',
  ];

  @override
  void initState() {
    super.initState();
    _scanLineController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _scanLineController.dispose();
    _pulseController.dispose();
    _logTimer?.cancel();
    super.dispose();
  }

  void _startScan() {
    final state = context.read<AppState>();
    state.resetScan();
    setState(() {
      _isScanning = true;
      _logs.clear();
      _detectedBoxes.clear();
    });

    int msgIndex = 0;
    _logTimer = Timer.periodic(const Duration(milliseconds: 900), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (msgIndex < _scanMessages.length) {
        setState(() {
          _logs.add(_scanMessages[msgIndex]);
          if (msgIndex >= 4 && msgIndex < 10) _addRandomBox();
        });
        state.setScanProgress((msgIndex + 1) / _scanMessages.length);
        msgIndex++;
      } else {
        timer.cancel();
        setState(() => _isScanning = false);
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) context.read<AppState>().setTab(2);
        });
      }
    });
  }

  void _addRandomBox() {
    final rand = Random();
    _detectedBoxes.add(_DetectedBox(
      left: rand.nextDouble() * 0.5 + 0.05,
      top: rand.nextDouble() * 0.5 + 0.1,
      width: rand.nextDouble() * 0.15 + 0.1,
      height: rand.nextDouble() * 0.1 + 0.08,
      color: [AppColors.cyan, AppColors.green, AppColors.purple][rand.nextInt(3)],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(state),
            Expanded(
              child: Stack(
                children: [
                  _buildCameraViewfinder(),
                  if (_isScanning) _buildScanLine(size),
                  ..._detectedBoxes.map((b) => _buildDetectionBox(b, size)),
                  _buildCornerBrackets(size),
                  if (_isScanning || state.scanComplete)
                    _buildScanProgress(size, state),
                ],
              ),
            ),
            _buildLogPanel(),
            _buildBottomBar(state),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(AppState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Text(
            'ROOM SCANNER',
            style: TextStyle(
              color: AppColors.cyan,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 3,
            ),
          ),
          const Spacer(),
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, _) => Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isScanning
                    ? AppColors.green.withValues(alpha: 0.5 + _pulseController.value * 0.5)
                    : AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _isScanning ? 'SCANNING' : (state.scanComplete ? 'COMPLETE' : 'READY'),
            style: TextStyle(
              color: _isScanning ? AppColors.green : AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraViewfinder() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF020508),
            AppColors.cyanDim.withValues(alpha: 0.05),
            const Color(0xFF020508),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: CustomPaint(painter: _GridPainter()),
    );
  }

  Widget _buildScanLine(Size size) {
    return AnimatedBuilder(
      animation: _scanLineController,
      builder: (context, _) => Positioned(
        top: _scanLineController.value * size.height * 0.65,
        left: 0, right: 0,
        child: Container(
          height: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                AppColors.cyan.withValues(alpha: 0.3),
                AppColors.cyan,
                AppColors.cyan.withValues(alpha: 0.3),
                Colors.transparent,
              ],
            ),
            boxShadow: [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.6), blurRadius: 12)],
          ),
        ),
      ),
    );
  }

  Widget _buildDetectionBox(_DetectedBox b, Size size) {
    final h = size.height * 0.65;
    final w = size.width;
    return Positioned(
      left: b.left * w,
      top: b.top * h,
      width: b.width * w,
      height: b.height * h,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 300),
        builder: (context, v, child) => Opacity(
          opacity: v,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: b.color, width: 1.5),
              borderRadius: BorderRadius.circular(4),
              color: b.color.withValues(alpha: 0.08),
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                color: b.color.withValues(alpha: 0.9),
                child: const Text(
                  'DETECTED',
                  style: TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 1),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCornerBrackets(Size size) {
    const bSize = 24.0;
    const bThick = 3.0;
    final color = AppColors.cyan.withValues(alpha: 0.8);
    final h = size.height * 0.65;
    const margin = 20.0;

    Widget bracket(bool flipH, bool flipV) => Transform.scale(
      scaleX: flipH ? -1 : 1,
      scaleY: flipV ? -1 : 1,
      child: SizedBox(
        width: bSize, height: bSize,
        child: CustomPaint(painter: _BracketPainter(color: color, thickness: bThick)),
      ),
    );

    return Positioned(
      left: 0, top: 0, width: size.width, height: h,
      child: Stack(
        children: [
          Positioned(left: margin, top: margin, child: bracket(false, false)),
          Positioned(right: margin, top: margin, child: bracket(true, false)),
          Positioned(left: margin, bottom: margin, child: bracket(false, true)),
          Positioned(right: margin, bottom: margin, child: bracket(true, true)),
        ],
      ),
    );
  }

  Widget _buildScanProgress(Size size, AppState state) {
    return Positioned(
      bottom: 16, left: 0, right: 0,
      child: Column(
        children: [
          Text(
            '${(state.scanProgress * 100).toInt()}%',
            style: TextStyle(color: AppColors.cyan, fontSize: 32, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: LinearProgressIndicator(
              value: state.scanProgress,
              backgroundColor: AppColors.border,
              valueColor: const AlwaysStoppedAnimation(AppColors.cyan),
              minHeight: 3,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogPanel() {
    return Container(
      height: 140,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.95),
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: ListView.builder(
        itemCount: _logs.length,
        reverse: true,
        itemBuilder: (_, i) {
          final log = _logs[_logs.length - 1 - i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              log,
              style: TextStyle(
                fontFamily: 'monospace',
                color: i == 0 ? AppColors.cyan : AppColors.textSecondary.withValues(alpha: 0.55),
                fontSize: 11,
                fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomBar(AppState state) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: state.scanComplete
          ? GestureDetector(
              onTap: () => context.read<AppState>().setTab(2),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: AppColors.accentGradient,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.4), blurRadius: 20)],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SvgIcon(RoomSvg.tune, size: 18, color: Colors.white),
                    const SizedBox(width: 8),
                    const Text(
                      'OPEN RIG CUSTOMIZER',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 2),
                    ),
                  ],
                ),
              ),
            )
          : GestureDetector(
              onTap: _isScanning ? null : _startScan,
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) => Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: _isScanning
                        ? AppColors.card
                        : AppColors.cyan.withValues(alpha: 0.1 + _pulseController.value * 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _isScanning ? AppColors.border : AppColors.cyan,
                      width: 1.5,
                    ),
                    boxShadow: _isScanning
                        ? []
                        : [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.2 + _pulseController.value * 0.15), blurRadius: 20)],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SvgIcon(
                        _isScanning ? RoomSvg.scan : RoomSvg.camera,
                        size: 20,
                        color: _isScanning ? AppColors.textMuted : AppColors.cyan,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _isScanning ? 'SCANNING ROOM...' : 'TAP TO SCAN ROOM',
                        style: TextStyle(
                          color: _isScanning ? AppColors.textMuted : AppColors.cyan,
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

class _DetectedBox {
  final double left, top, width, height;
  final Color color;
  const _DetectedBox({required this.left, required this.top, required this.width, required this.height, required this.color});
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.cyan.withValues(alpha: 0.04)
      ..strokeWidth = 0.5;
    const spacing = 30.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }
  @override bool shouldRepaint(_) => false;
}

class _BracketPainter extends CustomPainter {
  final Color color;
  final double thickness;
  const _BracketPainter({required this.color, required this.thickness});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(const Offset(0, 0), Offset(size.width, 0), paint);
    canvas.drawLine(const Offset(0, 0), Offset(0, size.height), paint);
  }
  @override bool shouldRepaint(_) => false;
}
