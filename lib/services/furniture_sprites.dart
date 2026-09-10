import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../widgets/room_icons.dart';

/// Resolves optional catalog art under [assets/sprites/].
///
/// Prefers SVG, then PNG, then the built-in inline SVG for [iconName].
/// Decoded [ui.Image]s are also cached so Bench CustomPainters can draw the
/// same sprites as Rig widget cells.
class FurnitureSprites {
  FurnitureSprites._();

  static const assetFolder = 'assets/sprites';
  static const _rasterSize = 128;

  static final Map<String, bool> _pngExists = {};
  static final Map<String, bool> _svgExists = {};
  static final Map<String, ui.Image> _images = {};
  static final Map<String, bool> _imageIsSvg = {};

  /// Bumps when a sprite finishes decoding — Bench painters can listen.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static String pngPath(String iconName) => '$assetFolder/$iconName.png';
  static String svgPath(String iconName) => '$assetFolder/$iconName.svg';

  static Future<void> warmCache(Iterable<String> iconNames) async {
    for (final name in iconNames) {
      await ensureDecoded(name);
    }
  }

  static Future<bool> hasPng(String iconName) async {
    final cached = _pngExists[iconName];
    if (cached != null) return cached;
    try {
      await rootBundle.load(pngPath(iconName));
      return _pngExists[iconName] = true;
    } catch (_) {
      return _pngExists[iconName] = false;
    }
  }

  static Future<bool> hasSvg(String iconName) async {
    final cached = _svgExists[iconName];
    if (cached != null) return cached;
    try {
      await rootBundle.load(svgPath(iconName));
      return _svgExists[iconName] = true;
    } catch (_) {
      return _svgExists[iconName] = false;
    }
  }

  /// Synchronous peek using warm cache only (false if never checked).
  static bool cachedHasPng(String iconName) => _pngExists[iconName] == true;
  static bool cachedHasSvg(String iconName) => _svgExists[iconName] == true;
  static bool cachedHasImage(String iconName) => _images.containsKey(iconName);

  /// Ensure existence flags + raster image are ready for painters.
  static Future<void> ensureDecoded(String iconName) async {
    if (_images.containsKey(iconName)) return;
    // Catalog ships SVG sprites; probe those first so web does not 404 on missing PNGs.
    final svg = await hasSvg(iconName);
    if (svg) {
      final image = await _decodeSvg(iconName);
      if (image != null) {
        _images[iconName] = image;
        _imageIsSvg[iconName] = true;
        revision.value++;
      }
      return;
    }
    final png = await hasPng(iconName);
    if (png) {
      final image = await _decodePng(iconName);
      if (image != null) {
        _images[iconName] = image;
        _imageIsSvg[iconName] = false;
        revision.value++;
      }
    }
  }

  static Future<ui.Image?> _decodePng(String iconName) async {
    try {
      final data = await rootBundle.load(pngPath(iconName));
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: _rasterSize,
        targetHeight: _rasterSize,
      );
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  static Future<ui.Image?> _decodeSvg(String iconName) async {
    try {
      final info = await vg.loadPicture(SvgAssetLoader(svgPath(iconName)), null);
      try {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final w = info.size.width <= 0 ? _rasterSize.toDouble() : info.size.width;
        final h = info.size.height <= 0 ? _rasterSize.toDouble() : info.size.height;
        canvas.scale(_rasterSize / w, _rasterSize / h);
        canvas.drawPicture(info.picture);
        return recorder.endRecording().toImage(_rasterSize, _rasterSize);
      } finally {
        info.picture.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  /// Draw a top-down sprite into [cell] (Rig/Bench shared). Returns false if
  /// no decoded asset is available yet.
  static bool paintPlanSprite(
    Canvas canvas,
    Rect cell, {
    required String iconName,
    required Color color,
    double yawDegrees = 0,
    bool selected = false,
    bool hasConflict = false,
  }) {
    final image = _images[iconName];
    if (image == null) return false;

    final borderColor = hasConflict
        ? const Color(0xFFFF4D6A)
        : (selected ? const Color(0xFF2EE6D6) : color.withValues(alpha: 0.7));
    canvas.drawRect(
      cell,
      Paint()..color = color.withValues(alpha: selected ? 0.18 : 0.08),
    );
    canvas.drawRect(
      cell,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected || hasConflict ? 2.0 : 1.2,
    );

    final inner = cell.deflate(2);
    if (inner.width <= 2 || inner.height <= 2) return true;

    canvas.save();
    canvas.translate(inner.center.dx, inner.center.dy);
    canvas.rotate(yawDegrees * math.pi / 180.0);
    final dst = Rect.fromCenter(
      center: Offset.zero,
      width: inner.width,
      height: inner.height,
    );
    final tintSvg = _imageIsSvg[iconName] == true;
    paintImage(
      canvas: canvas,
      rect: dst,
      image: image,
      fit: BoxFit.contain,
      colorFilter: tintSvg ? ColorFilter.mode(color, BlendMode.srcIn) : null,
      filterQuality: FilterQuality.medium,
    );
    canvas.restore();
    return true;
  }

  /// Top-down / list art widget with procedural SVG fallback.
  static Widget buildIcon({
    required String iconName,
    required Color color,
    double size = 24,
  }) {
    if (cachedHasSvg(iconName)) {
      return SvgPicture.asset(
        svgPath(iconName),
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        placeholderBuilder: (_) => SvgIcon(furnitureSvgFor(iconName), size: size, color: color),
      );
    }
    if (cachedHasPng(iconName)) {
      return Image.asset(
        pngPath(iconName),
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            SvgIcon(furnitureSvgFor(iconName), size: size, color: color),
      );
    }
    return SvgIcon(furnitureSvgFor(iconName), size: size, color: color);
  }
}
