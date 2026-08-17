import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Rotate landscape sensor luma 90° CW so it matches a portrait phone.
(Uint8List, int, int) rotateLuma90Cw(Uint8List src, int width, int height) {
  if (width <= 0 || height <= 0 || src.length < width * height) {
    return (src, width, height);
  }
  final outW = height;
  final outH = width;
  final out = Uint8List(outW * outH);
  for (int y = 0; y < height; y++) {
    final srcRow = y * width;
    for (int x = 0; x < width; x++) {
      out[x * outW + (height - 1 - y)] = src[srcRow + x];
    }
  }
  return (out, outW, outH);
}

/// Live grayscale viewfinder from ARCore / camera luma frames.
class ScanLumaPreview extends StatefulWidget {
  final Uint8List? bytes;
  final int width;
  final int height;
  final Widget? placeholder;

  const ScanLumaPreview({
    super.key,
    required this.bytes,
    required this.width,
    required this.height,
    this.placeholder,
  });

  @override
  State<ScanLumaPreview> createState() => _ScanLumaPreviewState();
}

class _ScanLumaPreviewState extends State<ScanLumaPreview> {
  ui.Image? _image;
  int _decodeGen = 0;

  @override
  void didUpdateWidget(covariant ScanLumaPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bytes != widget.bytes ||
        oldWidget.width != widget.width ||
        oldWidget.height != widget.height) {
      unawaited(_decode());
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_decode());
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _decode() async {
    final bytes = widget.bytes;
    final w = widget.width;
    final h = widget.height;
    if (bytes == null || w <= 0 || h <= 0 || bytes.length < w * h) {
      if (mounted) {
        setState(() {
          _image?.dispose();
          _image = null;
        });
      }
      return;
    }

    final gen = ++_decodeGen;
    var luma = bytes;
    var decW = w;
    var decH = h;
    // Back-camera frames are landscape; the app is locked to portrait.
    if (decW > decH) {
      final rotated = rotateLuma90Cw(luma, decW, decH);
      luma = rotated.$1;
      decW = rotated.$2;
      decH = rotated.$3;
    }
    final rgba = Uint8List(decW * decH * 4);
    for (int i = 0; i < decW * decH; i++) {
      final v = luma[i];
      final o = i * 4;
      rgba[o] = v;
      rgba[o + 1] = v;
      rgba[o + 2] = v;
      rgba[o + 3] = 255;
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      decW,
      decH,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final next = await completer.future;
    if (!mounted || gen != _decodeGen) {
      next.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return widget.placeholder ??
          Container(
            color: const Color(0xFF020508),
            child: Center(
              child: Text(
                'Waiting for camera…',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
    }

    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: image.width.toDouble(),
        height: image.height.toDouble(),
        child: RawImage(image: image, fit: BoxFit.cover),
      ),
    );
  }
}
