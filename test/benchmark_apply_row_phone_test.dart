import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/theme/app_theme.dart';
import 'package:room_rig/widgets/benchmark_panel_scaffold.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('BenchmarkApplyRow shows soft-wrapped blocked reason at 360dp', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const reason =
        'Apply blocked: hard layout conflicts must be fixed in Room before applying.';

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

    expect(find.byKey(const ValueKey('benchmark_apply_blocked_reason')), findsOneWidget);
    expect(find.text(reason), findsOneWidget);
    expect(find.byKey(const ValueKey('benchmark_apply_btn')), findsOneWidget);
    expect(find.text('APPLY BENCHMARK SUGGESTION TO ROOM'), findsOneWidget);
  });
}