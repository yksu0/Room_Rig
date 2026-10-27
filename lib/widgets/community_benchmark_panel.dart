import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../models/benchmark_compare_source.dart';
import '../models/published_layout.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import 'guest_signup_gate.dart';

/// Benchmark → Community: browse baselines / featured / recent, publish, rate,
/// clone, and open in Compare.
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
    if (!await ensureProfileCompleteForPublish(context)) return;
    if (!mounted) return;
    final titleCtrl = TextEditingController(
      text: context.read<AppState>().currentRoomData.name,
    );
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Publish layout',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: TextField(
          controller: titleCtrl,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            labelText: 'Title',
            hintText: 'My gaming setup',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, titleCtrl.text.trim()),
            child: const Text('Publish'),
          ),
        ],
      ),
    );
    titleCtrl.dispose();
    if (title == null || title.isEmpty || !mounted) return;
    final uid = context.read<AuthService>().userId;
    if (uid == null) return;
    try {
      await context.read<AppState>().publishCurrentRoom(
            authorId: uid,
            title: title,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Published to Community')),
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Publish failed: $e')),
      );
    }
  }

  Future<void> _openDetail(PublishedLayout layout) async {
    context.read<AppState>().cachePublishedLayout(layout);
    final refreshed = await showModalBottomSheet<PublishedLayout>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) => _CommunityDetailSheet(layout: layout),
    );
    if (refreshed != null && mounted) {
      context.read<AppState>().cachePublishedLayout(refreshed);
      await _reload();
    }
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
                  'Community layouts — browse freely. '
                  'Sign in to publish, rate, clone, or compare.',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(width: 8),
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
            child: Center(child: CircularProgressIndicator(color: AppColors.cyan)),
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
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  _sectionTitle('Baselines'),
                  if (_baselines.isEmpty)
                    const _EmptyHint('No admin baselines yet.')
                  else
                    ..._baselines.map(
                      (l) => _LayoutCard(layout: l, onTap: () => _openDetail(l)),
                    ),
                  const SizedBox(height: 16),
                  _sectionTitle("This month's top 3"),
                  if (_monthly.isEmpty)
                    const _EmptyHint(
                      'No featured layouts yet — rate community posts last month to fill this.',
                    )
                  else
                    ..._monthly.map(
                      (l) => _LayoutCard(layout: l, onTap: () => _openDetail(l)),
                    ),
                  const SizedBox(height: 16),
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
                    const _EmptyHint('No community layouts yet. Be the first to publish.')
                  else
                    ...feed.map(
                      (l) => _LayoutCard(layout: l, onTap: () => _openDetail(l)),
                    ),
                ],
              ),
            ),
          ),
      ],
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

class _LayoutCard extends StatelessWidget {
  final PublishedLayout layout;
  final VoidCallback onTap;

  const _LayoutCard({required this.layout, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final author = layout.isAdminBaseline
        ? 'Room Rig baseline'
        : (layout.authorName?.trim().isNotEmpty == true
            ? layout.authorName!
            : 'Community');
    return Card(
      color: AppColors.surfaceAlt,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        title: Text(
          layout.title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          '$author · ${layout.layout.furniture.length} items · '
          '▲${layout.upCount} ▼${layout.downCount}',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
      ),
    );
  }
}

class _CommunityDetailSheet extends StatefulWidget {
  final PublishedLayout layout;

  const _CommunityDetailSheet({required this.layout});

  @override
  State<_CommunityDetailSheet> createState() => _CommunityDetailSheetState();
}

class _CommunityDetailSheetState extends State<_CommunityDetailSheet> {
  late PublishedLayout _layout;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _layout = widget.layout;
  }

  Future<void> _rate(int vote) async {
    if (!await ensureProfileCompleteForPublish(context)) return;
    if (!mounted) return;
    final uid = context.read<AuthService>().userId;
    if (uid == null) return;
    final selected = Set<String>.from(_layout.myTags);
    final tags = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              title: Text(
                vote > 0 ? 'Upvote tags' : 'Downvote tags',
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              content: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in kLayoutRatingTagOptions)
                    FilterChip(
                      label: Text(t),
                      selected: selected.contains(t),
                      onSelected: (on) => setLocal(() {
                        if (on) {
                          selected.add(t);
                        } else {
                          selected.remove(t);
                        }
                      }),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, selected),
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
    if (tags == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final updated = await context.read<AppState>().publishedLayoutRepository.rate(
            layoutId: _layout.id,
            raterId: uid,
            vote: vote,
            tags: tags.toList(),
          );
      if (!mounted) return;
      setState(() {
        _layout = updated;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rate failed: $e')),
      );
    }
  }

  Future<void> _clone() async {
    if (!await ensureSignedInForCommunity(context, actionLabel: 'clone layouts')) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    final ok = await context.read<AppState>().clonePublishedLayout(_layout.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not clone this layout')),
      );
      return;
    }
    Navigator.pop(context, _layout);
    context.read<AppState>().setTab(roomTabIndex);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cloned into your Room')),
    );
  }

  Future<void> _compare() async {
    if (!await ensureSignedInForCommunity(
      context,
      actionLabel: 'open layouts in Compare',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    final ok = await context.read<AppState>().openPublishedInCompare(_layout.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open in Compare')),
      );
      return;
    }
    // Switch to airflow so Compare chrome is visible; community source is set.
    context.read<AppState>().setBenchmarkMode('airflow');
    Navigator.pop(context, _layout);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Compare right side set to this Community layout'),
      ),
    );
  }

  Future<void> _apply() async {
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
          'This replaces your current Room furniture with the published layout '
          'and saves a snapshot first.',
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
    await _clone();
  }

  @override
  Widget build(BuildContext context) {
    final scores = _layout.scores;
    final signedIn = context.watch<AuthService>().isSignedIn;
    final profileOk = context.watch<ProfileService>().canPublishOrRate;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _layout.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context, _layout),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Text(
                _layout.isAdminBaseline
                    ? 'Admin baseline'
                    : (_layout.authorName ?? 'Community author'),
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 8),
              Text(
                '${_layout.layout.furniture.length} items · '
                '${_layout.layout.gridCols}×${_layout.layout.gridRows} grid · '
                '▲${_layout.upCount} ▼${_layout.downCount}'
                '${_layout.myVote == 1 ? ' · you ▲' : _layout.myVote == -1 ? ' · you ▼' : ''}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              if (scores != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Scores — overall ${scores['overall'] ?? '—'} · '
                  'air ${scores['airflow'] ?? '—'} · '
                  'light ${scores['lighting'] ?? '—'} · '
                  'ergo ${scores['ergonomics'] ?? '—'} · '
                  'space ${scores['spatial'] ?? '—'}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
              if (!signedIn) ...[
                const SizedBox(height: 12),
                const Text(
                  'Sign in to rate, clone, compare, or apply.',
                  style: TextStyle(color: AppColors.cyan, fontSize: 12),
                ),
              ] else if (!profileOk) ...[
                const SizedBox(height: 12),
                const Text(
                  'Add a name and avatar on Profile to publish or rate.',
                  style: TextStyle(color: AppColors.cyan, fontSize: 12),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: _busy ? null : () => _rate(1),
                    child: const Text('Up'),
                  ),
                  FilledButton.tonal(
                    onPressed: _busy ? null : () => _rate(-1),
                    child: const Text('Down'),
                  ),
                  FilledButton(
                    onPressed: _busy ? null : _clone,
                    child: const Text('Clone'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : _compare,
                    child: const Text('Compare'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : _apply,
                    child: const Text('Apply'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Items: ${_layout.layout.furniture.map((f) => f.name).take(12).join(', ')}'
                '${_layout.layout.furniture.length > 12 ? '…' : ''}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
