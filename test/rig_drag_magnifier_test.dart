import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:room_rig/widgets/rig_customizer/rig_drag_magnifier.dart';

void main() {
  group('RigDragMagnifier.sampleTransform', () {
    test('maps focal point to bubble center', () {
      const diameter = 112.0;
      const scale = 2.2;
      final focal = const Offset(180, 240);
      final m = RigDragMagnifier.sampleTransform(
        focal: focal,
        diameter: diameter,
        scale: scale,
      );

      final out = MatrixUtils.transformPoint(m, focal);
      expect(out.dx, closeTo(diameter * 0.5, 0.01));
      expect(out.dy, closeTo(diameter * 0.5, 0.01));
    });

    test('neighboring pixels stay locally consistent under zoom', () {
      const diameter = 112.0;
      const scale = 2.2;
      final focal = const Offset(100, 100);
      final m = RigDragMagnifier.sampleTransform(
        focal: focal,
        diameter: diameter,
        scale: scale,
      );

      final a = MatrixUtils.transformPoint(m, focal);
      final b = MatrixUtils.transformPoint(m, focal + const Offset(10, 0));
      expect(b.dx - a.dx, closeTo(10 * scale, 0.01));
      expect(b.dy - a.dy, closeTo(0, 0.01));
    });
  });

  group('RigDragMagnifier.bubbleOrigin', () {
    test('prefers above the finger when there is room', () {
      final origin = RigDragMagnifier.bubbleOrigin(
        pointer: const Offset(200, 300),
        canvas: const Size(400, 600),
      );
      expect(origin.dy, lessThan(300 - RigDragMagnifier.diameter));
      expect(origin.dx, closeTo(200 - RigDragMagnifier.diameter * 0.5, 0.5));
    });

    test('moves sideways near the top edge', () {
      final origin = RigDragMagnifier.bubbleOrigin(
        pointer: const Offset(200, 40),
        canvas: const Size(400, 600),
      );
      expect(origin.dy, greaterThanOrEqualTo(RigDragMagnifier.edgePad));
      // Should not sit on top of the finger when lifted above would clip.
      final coversFinger = Rect.fromLTWH(
        origin.dx,
        origin.dy,
        RigDragMagnifier.diameter,
        RigDragMagnifier.diameter,
      ).contains(const Offset(200, 40));
      expect(coversFinger, isFalse);
    });
  });

  testWidgets('loupe lays scene out at full canvas size', (tester) async {
    Size? laidOut;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 480,
            child: RigDragMagnifier(
              pointerLocal: const Offset(160, 240),
              focalPoint: const Offset(160, 240),
              canvasSize: const Size(320, 480),
              blocked: false,
              scene: LayoutBuilder(
                builder: (context, constraints) {
                  laidOut = Size(constraints.maxWidth, constraints.maxHeight);
                  return const ColoredBox(color: Colors.blue);
                },
              ),
            ),
          ),
        ),
      ),
    );

    expect(laidOut, equals(const Size(320, 480)));
    expect(find.byType(RigDragMagnifier), findsOneWidget);
  });
}
