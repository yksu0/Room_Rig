import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../models/benchmark_compare_source.dart';
import '../models/published_layout.dart';
import '../models/room_model.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'guest_signup_gate.dart';
import 'publish_layout_action.dart';
import 'room_model_scene.dart';

/// Benchmark → Community: Reddit-style feed with inline 3D preview + direct votes.
class CommunityBenchmarkPanel extends StatefulWidget {
  const CommunityBenchmarkPanel({super.key});

  @override
  State<CommunityBenchmarkPanel> createState() =>
      _CommunityBenchmarkPanelState();
}

class _CommunityBenchmarkPanelState extends State<CommunityBenchmarkPanel> {
  var _loading = true;
  String? _error;
  List<PublishedLayout> _baselines = const [];
  List<PublishedLayout> _monthly = const [];
  List<PublishedLayout> _recent = const [];
  List<PublishedLayout> _top = const [];
  var _feedTab = 0; // 0 recent, 1 top
  String? _previewId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repo = context.read<AppState>().publishedLayoutRepository;
    try {
      final baselines = await repo.fetchBaselines();
      final monthly = await repo.fetchMonthlyFeatured();
      final recent = await repo.fetchRecent();
      final top = await repo.fetchTop();
      if (!mounted) return;
      for (final l in [...baselines, ...monthly, ...recent, ...top]) {
        context.read<AppState>().cachePublishedLayout(l);
      }
      setState(() {
        _baselines = baselines;
        _monthly = monthly;
        _recent = recent;
        _top = top;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load Community feed. Check your connection.';
        _loading = false;
      });
    }
  }

  Future<void> _publish() async {
    final ok = await publishCurrentLayoutToCommunity(context);
    if (ok && mounted) await _reload();
  }

  void _replaceInFeeds(PublishedLayout updated) {
    context.read<AppState>().cachePublishedLayout(updated);
    PublishedLayout mapOne(PublishedLayout l) =>
        l.id == updated.id ? updated : l;
    setState(() {
      _baselines = _baselines.map(mapOne).toList(growable: false);
      _monthly = _monthly.map(mapOne).toList(growable: false);
      _recent = _recent.map(mapOne).toList(growable: false);
      _top = _top.map(mapOne).toList(growable: false);
    });
  }

  Future<void> _vote(PublishedLayout layout, int vote) async {
    if (!await ensureProfileCompleteForPublish(context)) return;
    if (!mounted) return;
    final uid = context.read<AuthService>().userId;
    if (uid == null) return;
    final repo = context.read<AppState>().publishedLayoutRepository;
    try {
      // Same button again clears the vote; opposite button switches it.
      final updated = layout.myVote == vote
          ? await repo.clearRating(layoutId: layout.id, raterId: uid)
          : await repo.rate(
              layoutId: layout.id,
              raterId: uid,
              vote: vote,
              tags: layout.myTags,
            );
      if (!mounted) return;
      _replaceInFeeds(updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Vote failed: $e')),
      );
    }
  }

  Future<void> _clone(PublishedLayout layout) async {
    if (!await ensureSignedInForCommunity(context, actionLabel: 'clone layouts')) {
      return;
    }
    if (!mounted) return;
    final ok = await context.read<AppState>().clonePublishedLayout(layout.id);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not clone this layout')),
      );
      return;
    }
    context.read<AppState>().setTab(roomTabIndex);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cloned into your Room')),
    );
  }

  Future<void> _compare(PublishedLayout layout) async {
    if (!await ensureSignedInForCommunity(
      context,
      actionLabel: 'open layouts in Compare',
    )) {
      return;
    }
    if (!mounted) return;
    final ok = await context.read<AppState>().openPublishedInCompare(layout.id);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open in Compare')),
      );
      return;
    }
    context.read<AppState>().setBenchmarkMode('airflow');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Compare right side set to this Community layout'),
      ),
    );
  }

  Future<void> _apply(PublishedLayout layout) async {
    if (!await ensureSignedInForCommunity(
      context,
      actionLabel: 'apply community layouts',
    )) {
      return;
    }
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Apply to Room?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          'Replaces your current Room furniture with this layout '
          '(a snapshot is saved first).',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await _clone(layout);
  }

  @override
  Widget build(BuildContext context) {
    final feed = _feedTab == 0 ? _recent : _top;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Community — scroll, preview, vote. Sign in to publish / clone.',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
              FilledButton.tonal(
                onPressed: _loading ? null : _publish,
                child: const Text('Publish'),
              ),
              IconButton(
                onPressed: _loading ? null : _reload,
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),
        if (_loading)
          const Expanded(
            child: Center(
              child: CircularProgressIndicator(color: AppColors.cyan),
            ),
          )
        else if (_error != null)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _reload, child: const Text('Retry')),
                  ],
                ),
              ),
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                children: [
                  _sectionTitle('Baselines'),
                  if (_baselines.isEmpty)
                    const _EmptyHint('No admin baselines yet.')
                  else
                    ..._baselines.map(_post),
                  const SizedBox(height: 12),
                  _sectionTitle("This month's top 3"),
                  if (_monthly.isEmpty)
                    const _EmptyHint(
                      'No featured layouts yet — vote on posts to fill this next month.',
                    )
                  else
                    ..._monthly.map(_post),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _sectionTitle(_feedTab == 0 ? 'Recent' : 'Top'),
                      const Spacer(),
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 0, label: Text('Recent')),
                          ButtonSegment(value: 1, label: Text('Top')),
                        ],
                        selected: {_feedTab},
                        onSelectionChanged: (s) =>
                            setState(() => _feedTab = s.first),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (feed.isEmpty)
                    const _EmptyHint(
                      'No community layouts yet. Be the first to publish.',
                    )
                  else
                    ...feed.map(_post),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _post(PublishedLayout layout) {
    return _CommunityPostCard(
      layout: layout,
      previewActive: _previewId == layout.id,
      onTogglePreview: () {
        setState(() {
          _previewId = _previewId == layout.id ? null : layout.id;
        });
      },
      onUp: () => _vote(layout, 1),
      onDown: () => _vote(layout, -1),
      onClone: () => _clone(layout),
      onCompare: () => _compare(layout),
      onApply: () => _apply(layout),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 14,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
      ),
    );
  }
}

class _CommunityPostCard extends StatelessWidget {
  final PublishedLayout layout;
  final bool previewActive;
  final VoidCallback onTogglePreview;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onClone;
  final VoidCallback onCompare;
  final VoidCallback onApply;

  const _CommunityPostCard({
    required this.layout,
    required this.previewActive,
    required this.onTogglePreview,
    required this.onUp,
    required this.onDown,
    required this.onClone,
    required this.onCompare,
    required this.onApply,
  });

  RoomData get _roomData {
    final snap = layout.layout;
    return RoomData(
      name: snap.name,
      subtitle: layout.isAdminBaseline ? 'Baseline' : 'Community',
      iconName: 'desk',
      gridCols: snap.gridCols,
      gridRows: snap.gridRows,
      furniture: snap.furniture,
    );
  }

  @override
  Widget build(BuildContext context) {
    final author = layout.isAdminBaseline
        ? 'Room Rig baseline'
        : (layout.authorName?.trim().isNotEmpty == true
            ? layout.authorName!
            : 'Community');
    final scores = layout.scores;
    final upSelected = layout.myVote == 1;
    final downSelected = layout.myVote == -1;

    return Card(
      color: AppColors.surfaceAlt,
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Reddit-style vote rail
            Container(
              width: 48,
              color: AppColors.surface,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 36),
                    onPressed: onUp,
                    icon: Icon(
                      Icons.arrow_upward_rounded,
                      color: upSelected ? AppColors.amber : AppColors.textMuted,
                      size: 22,
                    ),
                    tooltip: 'Upvote',
                  ),
                  Text(
                    '${layout.netScore}',
                    style: TextStyle(
                      color: layout.netScore > 0
                          ? AppColors.amber
                          : layout.netScore < 0
                              ? AppColors.red
                              : AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 36),
                    onPressed: onDown,
                    icon: Icon(
                      Icons.arrow_downward_rounded,
                      color: downSelected ? AppColors.red : AppColors.textMuted,
                      size: 22,
                    ),
                    tooltip: 'Downvote',
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      layout.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'u/$author · ${layout.layout.furniture.length} items · '
                      '${layout.layout.gridCols}×${layout.layout.gridRows}'
                      '${scores != null ? ' · score ${scores['overall'] ?? '—'}' : ''}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                    if ((layout.description ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        layout.description!.trim(),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (layout.tags.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final t in layout.tags.take(8))
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.cyan.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: AppColors.cyan.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Text(
                                t,
                                style: const TextStyle(
                                  color: AppColors.cyan,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    // Preview pane — dormant until activated (one 3D scene at a time).
                    AspectRatio(
                      aspectRatio: 16 / 10,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.bg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: previewActive
                              ? RoomModelScene(
                                  room: _roomData,
                                  furniture: layout.layout.furniture,
                                )
                              : Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    CustomPaint(
                                      painter: _LayoutThumbPainter(
                                        furniture: layout.layout.furniture,
                                        cols: layout.layout.gridCols,
                                        rows: layout.layout.gridRows,
                                      ),
                                    ),
                                    Material(
                                      color: Colors.black.withValues(alpha: 0.35),
                                      child: InkWell(
                                        onTap: onTogglePreview,
                                        child: const Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.view_in_ar_rounded,
                                                color: AppColors.cyan,
                                                size: 36,
                                              ),
                                              SizedBox(height: 6),
                                              Text(
                                                'Tap to load 3D preview',
                                                style: TextStyle(
                                                  color: AppColors.textPrimary,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                    if (previewActive)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: onTogglePreview,
                          child: const Text('Close preview'),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 0,
                      children: [
                        TextButton(
                          onPressed: onClone,
                          child: const Text('Clone'),
                        ),
                        TextButton(
                          onPressed: onCompare,
                          child: const Text('Compare'),
                        ),
                        TextButton(
                          onPressed: onApply,
                          child: const Text('Apply'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cheap top-down stub shown before the user activates the 3D WebView.
class _LayoutThumbPainter extends CustomPainter {
  final List<FurnitureItem> furniture;
  final int cols;
  final int rows;

  _LayoutThumbPainter({
    required this.furniture,
    required this.cols,
    required this.rows,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = cols.clamp(1, 32);
    final r = rows.clamp(1, 32);
    final cellW = size.width / c;
    final cellH = size.height / r;
    final floor = Paint()..color = const Color(0xFF1A1F2A);
    canvas.drawRect(Offset.zero & size, floor);
    final grid = Paint()
      ..color = const Color(0x22FFFFFF)
      ..strokeWidth = 1;
    for (var x = 0; x <= c; x++) {
      final dx = x * cellW;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), grid);
    }
    for (var y = 0; y <= r; y++) {
      final dy = y * cellH;
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), grid);
    }
    final itemPaint = Paint()..color = AppColors.cyan.withValues(alpha: 0.55);
    for (final f in furniture) {
      if (f.hidden) continue;
      final rect = Rect.fromLTWH(
        f.gridX * cellW,
        f.gridY * cellH,
        (f.width.clamp(0.5, c.toDouble())) * cellW,
        (f.height.clamp(0.5, r.toDouble())) * cellH,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(1), const Radius.circular(2)),
        itemPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LayoutThumbPainter oldDelegate) =>
      oldDelegate.furniture != furniture ||
      oldDelegate.cols != cols ||
      oldDelegate.rows != rows;
}

/// Compare-source picker entry for a community layout (signed-in only).
Future<void> showCommunityComparePicker(
  BuildContext context, {
  required ValueChanged<BenchmarkCompareSource> onPick,
}) async {
  if (!await ensureSignedInForCommunity(
    context,
    actionLabel: 'compare community layouts',
  )) {
    return;
  }
  if (!context.mounted) return;
  final state = context.read<AppState>();
  final recent = await state.publishedLayoutRepository.fetchRecent(limit: 20);
  final baselines = await state.publishedLayoutRepository.fetchBaselines();
  if (!context.mounted) return;
  for (final l in [...baselines, ...recent]) {
    state.cachePublishedLayout(l);
  }
  final picked = await showModalBottomSheet<BenchmarkCompareSource>(
    context: context,
    backgroundColor: AppColors.surface,
    builder: (ctx) {
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Community layout',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
            if (baselines.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  'Baselines',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              for (final l in baselines)
                ListTile(
                  title: Text(
                    l.title,
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                  onTap: () => Navigator.pop(
                    ctx,
                    BenchmarkCompareSource.publishedLayout(l.id, title: l.title),
                  ),
                ),
            ],
            if (recent.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  'Recent',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              for (final l in recent)
                ListTile(
                  title: Text(
                    l.title,
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                  subtitle: Text(
                    l.authorName ?? 'Community',
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                  onTap: () => Navigator.pop(
                    ctx,
                    BenchmarkCompareSource.publishedLayout(l.id, title: l.title),
                  ),
                ),
            ],
            if (baselines.isEmpty && recent.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No published layouts yet.',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
          ],
        ),
      );
    },
  );
  if (picked != null) onPick(picked);
}
