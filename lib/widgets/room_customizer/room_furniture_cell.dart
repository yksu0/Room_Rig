// lib/widgets/room_customizer/room_furniture_cell.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/room_model.dart';
import '../../services/furniture_sprites.dart';
import '../../theme/app_theme.dart';
import '../furniture_shapes.dart';

class RoomFurnitureCell extends StatefulWidget {
  final FurnitureItem item;
  final bool isSelected;
  final bool hasConflict;
  final bool isPending;
  const RoomFurnitureCell({
    super.key,
    required this.item,
    required this.isSelected,
    this.hasConflict = false,
    this.isPending = false,
  });

  @override
  State<RoomFurnitureCell> createState() => _RoomFurnitureCellState();
}

class _RoomFurnitureCellState extends State<RoomFurnitureCell> {
  @override
  void initState() {
    super.initState();
    _resolveSprites(widget.item.iconName);
  }

  @override
  void didUpdateWidget(covariant RoomFurnitureCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.iconName != widget.item.iconName) {
      _resolveSprites(widget.item.iconName);
    }
  }

  Future<void> _resolveSprites(String iconName) async {
    final hadSprite =
        FurnitureSprites.cachedHasPng(iconName) || FurnitureSprites.cachedHasSvg(iconName);
    final svg = await FurnitureSprites.hasSvg(iconName);
    final png = svg ? false : await FurnitureSprites.hasPng(iconName);
    if (!mounted) return;
    final hasSprite = png || svg;
    if (hasSprite != hadSprite) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isSelected = widget.isSelected;
    final hasConflict = widget.hasConflict;
    final isPending = widget.isPending;
    final color = hasConflict
        ? AppColors.red
        : switch (item.category) {
            'airflow' => AppColors.airflowColor,
            'lighting' => AppColors.lightingColor,
            'ergonomics' => AppColors.ergonomicsColor,
            _ => AppColors.textMuted,
          };
    final glowColor = hasConflict
        ? AppColors.red
        : (isPending ? AppColors.amber : (isSelected ? AppColors.cyan : color));

    final usePng = FurnitureSprites.cachedHasPng(item.iconName);
    final useSvg = !usePng && FurnitureSprites.cachedHasSvg(item.iconName);
    Widget cell;
    if (usePng || useSvg) {
      cell = _SpritePlanCell(
        iconName: item.iconName,
        color: color,
        selected: isSelected || isPending,
        hasConflict: hasConflict,
        yawDegrees: item.yawDegrees,
        usePng: usePng,
      );
    } else {
      final kind = FurnitureShapes.kindOf(item);
      cell = CustomPaint(
        painter: _FurniturePlanPainter(
          kind: kind,
          color: color,
          selected: isSelected || isPending,
          hasConflict: hasConflict,
          yawDegrees: item.yawDegrees,
          showFacing: FurnitureShapes.showsFacing(kind),
        ),
      );
    }
    Widget painted = cell;
    if (isSelected || isPending || hasConflict) {
      painted = DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: AppColors.activeGlow(glowColor, blur: 14, alpha: 0.35),
        ),
        child: cell,
      );
    }
    return Semantics(
      label: item.name,
      selected: isSelected,
      button: true,
      child: painted,
    );
  }
}

class _SpritePlanCell extends StatelessWidget {
  final String iconName;
  final Color color;
  final bool selected;
  final bool hasConflict;
  final double yawDegrees;
  final bool usePng;

  const _SpritePlanCell({
    required this.iconName,
    required this.color,
    required this.selected,
    required this.hasConflict,
    required this.yawDegrees,
    required this.usePng,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = hasConflict
        ? AppColors.red
        : (selected ? AppColors.cyan : color.withValues(alpha: 0.7));
    // Fill the hitbox — contain + padded SVGs left empty gaps between beds etc.
    final sprite = usePng
        ? Image.asset(
            FurnitureSprites.pngPath(iconName),
            fit: BoxFit.fill,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          )
        : SvgPicture.asset(
            FurnitureSprites.svgPath(iconName),
            fit: BoxFit.fill,
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: selected || hasConflict ? 2 : 1.2),
        color: color.withValues(alpha: selected ? 0.18 : 0.08),
      ),
      child: Transform.rotate(
        angle: yawDegrees * math.pi / 180.0,
        child: sprite,
      ),
    );
  }
}

class RoomScanObject2DCell extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final String label;

  const RoomScanObject2DCell({
    super.key,
    required this.color,
    required this.isSelected,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ScanObjectPlanPainter(
        color: color,
        selected: isSelected,
        label: label,
      ),
    );
  }
}

class _ScanObjectPlanPainter extends CustomPainter {
  final Color color;
  final bool selected;
  final String label;

  _ScanObjectPlanPainter({
    required this.color,
    required this.selected,
    required this.label,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(1, 1, size.width - 2, size.height - 2);
    canvas.drawRect(rect, Paint()..color = color.withValues(alpha: selected ? 0.32 : 0.2));
    final stroke = Paint()
      ..color = selected ? AppColors.cyan : color
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 2 : 1.2;
    _drawDashedRect(canvas, rect, stroke);
    if (size.width > 28 && size.height > 16) {
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: selected ? AppColors.cyan : color,
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: size.width - 4);
      tp.paint(canvas, Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
    }
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    const dash = 4.0;
    const gap = 3.0;
    void edge(Offset a, Offset b) {
      final delta = b - a;
      final len = delta.distance;
      if (len <= 0) return;
      final step = dash + gap;
      final dir = Offset(delta.dx / len, delta.dy / len);
      var dist = 0.0;
      while (dist < len) {
        final start = a + dir * dist;
        final end = a + dir * math.min(dist + dash, len);
        canvas.drawLine(start, end, paint);
        dist += step;
      }
    }

    edge(rect.topLeft, rect.topRight);
    edge(rect.topRight, rect.bottomRight);
    edge(rect.bottomRight, rect.bottomLeft);
    edge(rect.bottomLeft, rect.topLeft);
  }

  @override
  bool shouldRepaint(covariant _ScanObjectPlanPainter old) =>
      old.color != color || old.selected != selected || old.label != label;
}

class _FurniturePlanPainter extends CustomPainter {
  final FurnitureKind kind;
  final Color color;
  final bool selected;
  final bool hasConflict;
  final double yawDegrees;
  final bool showFacing;

  _FurniturePlanPainter({
    required this.kind,
    required this.color,
    required this.selected,
    required this.hasConflict,
    required this.yawDegrees,
    required this.showFacing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    FurnitureShapes.paintPlan(
      canvas,
      size,
      kind,
      color,
      selected: selected,
      hasConflict: hasConflict,
      yawDegrees: yawDegrees,
    );
    if (showFacing) {
      _FacingChevronPainter(
        color: selected ? AppColors.cyan : color,
        yawDegrees: yawDegrees,
      ).paint(canvas, size);
    }
  }

  @override
  bool shouldRepaint(covariant _FurniturePlanPainter old) =>
      old.kind != kind ||
      old.color != color ||
      old.selected != selected ||
      old.hasConflict != hasConflict ||
      old.yawDegrees != yawDegrees ||
      old.showFacing != showFacing;
}

class _FacingChevronPainter extends CustomPainter {
  final Color color;
  final double yawDegrees;
  _FacingChevronPainter({required this.color, required this.yawDegrees});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    final rad = yawDegrees * math.pi / 180.0;
    // Plan: yaw 0° → +Z → down the screen.
    final dirX = math.sin(rad);
    final dirY = math.cos(rad);
    final reach = math.min(size.width, size.height) * 0.48;
    final tip = Offset(cx + dirX * reach, cy + dirY * reach);
    final back = Offset(cx + dirX * reach * 0.15, cy + dirY * reach * 0.15);
    final px = -dirY;
    final py = dirX;
    final left = Offset(back.dx + px * reach * 0.28, back.dy + py * reach * 0.28);
    final right = Offset(back.dx - px * reach * 0.28, back.dy - py * reach * 0.28);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.95));
  }

  @override
  bool shouldRepaint(covariant _FacingChevronPainter old) =>
      old.color != color || old.yawDegrees != yawDegrees;
}
