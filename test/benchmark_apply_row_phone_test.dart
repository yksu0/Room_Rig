import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/theme/app_theme.dart';
import 'package:room_rig/widgets/benchmark_panel_scaffold.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('BenchmarkApplyRow soft-wrapped blocked reason at 360 and 412dp', (tester) async {
    const reason =
        'Apply blocked: hard layout conflicts must be fixed in Room before applying.';

    for (final width in const [360.0, 412.0]) {
      await tester.binding.setSurfaceSize(Size(width, 740));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: BenchmarkApplyRow(
                onApply: null,
                onRefresh: () {},
                blockedReason: reason,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('benchmark_apply_blocked_reason')), findsOneWidget,
          reason: 'blocked reason at ${width}dp');
      expect(find.text(reason), findsOneWidget, reason: 'reason text at ${width}dp');
      expect(find.byKey(const ValueKey('benchmark_apply_btn')), findsOneWidget,
          reason: 'apply btn at ${width}dp');
      expect(find.text('APPLY BENCHMARK SUGGESTION TO ROOM'), findsOneWidget,
          reason: 'apply label at ${width}dp');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });
}
