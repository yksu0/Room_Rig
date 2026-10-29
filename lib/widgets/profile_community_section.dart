import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/published_layout.dart';
import '../services/auth_service.dart';
import '../services/published_layout_repository.dart';
import '../theme/app_theme.dart';
import 'app_snack_bar.dart';
import 'publish_layout_action.dart';

/// Profile SOCIAL block: karma/posts stats + the user's Community posts.
class ProfileCommunitySection extends StatefulWidget {
  const ProfileCommunitySection({super.key});

  @override
  State<ProfileCommunitySection> createState() =>
      _ProfileCommunitySectionState();
}

class _ProfileCommunitySectionState extends State<ProfileCommunitySection> {
  final _repo = PublishedLayoutRepository();
  AuthorSocialSummary _summary = AuthorSocialSummary.empty;
  var _loading = true;
  var _busyId = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    final uid = context.read<AuthService>().userId;
    if (uid == null) {
      if (mounted) {
        setState(() {
          _summary = AuthorSocialSummary.empty;
          _loading = false;
        });
      }
      return;
    }
    setState(() => _loading = true);
    final summary = await _repo.fetchAuthorSocial(uid);
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _loading = false;
    });
  }

  Future<void> _toggleHidden(PublishedLayout layout) async {
    setState(() => _busyId = layout.id);
    try {
      await _repo.setHidden(layoutId: layout.id, hidden: !layout.hidden);
      await _reload();
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: layout.hidden
            ? 'Post visible in Community again.'
            : 'Post hidden from Community.',
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, message: 'Could not update post: $e');
    } finally {
      if (mounted) setState(() => _busyId = '');
    }
  }

  Future<void> _deletePost(PublishedLayout layout) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Delete post?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          '“${layout.title}” will be removed from Community. Ratings go with it.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busyId = layout.id);
    try {
      await _repo.deleteLayout(layout.id);
      await _reload();
      if (!mounted) return;
      showAppSnackBar(context, message: 'Post deleted.');
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, message: 'Delete failed: $e');
    } finally {
      if (mounted) setState(() => _busyId = '');
    }
  }

  Future<void> _publishNew() async {
    final published = await publishCurrentLayoutToCommunity(context);
    if (published && mounted) await _reload();
  }

  Future<void> _editPost(PublishedLayout layout) async {
    final updated = await editPublishedLayoutPost(context, layout);
    if (updated != null && mounted) await _reload();
  }

  String _relative(DateTime utc) {
    final d = DateTime.now().toUtc().difference(utc.toUtc());
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    if (d.inDays < 30) return '${d.inDays}d ago';
    return '${utc.year}-${utc.month.toString().padLeft(2, '0')}-${utc.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'COMMUNITY',
                style: TextStyle(
                  color: AppColors.cyan,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _loading ? null : _reload,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textMuted,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: 'Posts',
                  value: '${_summary.postCount}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatTile(
                  label: 'Karma',
                  value: _summary.netReceived >= 0
                      ? '+${_summary.netReceived}'
                      : '${_summary.netReceived}',
                  valueColor: _summary.netReceived > 0
                      ? AppColors.green
                      : _summary.netReceived < 0
                          ? AppColors.red
                          : AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatTile(
                  label: 'Votes cast',
                  value: '${_summary.votesCast}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: 'Upvotes',
                  value: '${_summary.upReceived}',
                  valueColor: AppColors.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatTile(
                  label: 'Downvotes',
                  value: '${_summary.downReceived}',
                  valueColor: AppColors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Your posts',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _publishNew,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('New post'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_summary.posts.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppColors.border),
              ),
              child: const Text(
                'Nothing published yet. Share a room layout to Community '
                'and your stats will show up here.',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            )
          else
            for (final post in _summary.posts) ...[
              _PostRow(
                layout: post,
                when: _relative(post.publishedAt),
                busy: _busyId == post.id,
                onEdit: () => _editPost(post),
                onHideToggle: () => _toggleHidden(post),
                onDelete: () => _deletePost(post),
              ),
              const SizedBox(height: 8),
            ],
        ],
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _StatTile({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PostRow extends StatelessWidget {
  final PublishedLayout layout;
  final String when;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onHideToggle;
  final VoidCallback onDelete;

  const _PostRow({
    required this.layout,
    required this.when,
    required this.busy,
    required this.onEdit,
    required this.onHideToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final net = layout.netScore;
    return Material(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: busy
            ? null
            : () => showModalBottomSheet<void>(
                  context: context,
                  backgroundColor: AppColors.surface,
                  builder: (ctx) => SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            layout.title,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${layout.layout.furniture.length} items · '
                            '${layout.layout.gridCols}×${layout.layout.gridRows} · '
                            '$when'
                            '${layout.hidden ? ' · hidden' : ''}',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                          if ((layout.description ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              layout.description!.trim(),
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ],
                          if (layout.tags.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final t in layout.tags)
                                  Chip(
                                    label: Text(t),
                                    visualDensity: VisualDensity.compact,
                                    backgroundColor:
                                        AppColors.cyan.withValues(alpha: 0.12),
                                    side: BorderSide(
                                      color:
                                          AppColors.cyan.withValues(alpha: 0.35),
                                    ),
                                    labelStyle: const TextStyle(
                                      color: AppColors.cyan,
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Icon(
                                Icons.arrow_upward_rounded,
                                size: 16,
                                color: AppColors.green.withValues(alpha: 0.9),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${layout.upCount}',
                                style: const TextStyle(color: AppColors.green),
                              ),
                              const SizedBox(width: 14),
                              Icon(
                                Icons.arrow_downward_rounded,
                                size: 16,
                                color: AppColors.red.withValues(alpha: 0.9),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${layout.downCount}',
                                style: const TextStyle(color: AppColors.red),
                              ),
                              const SizedBox(width: 14),
                              Text(
                                'net $net',
                                style: TextStyle(
                                  color: net > 0
                                      ? AppColors.green
                                      : net < 0
                                          ? AppColors.red
                                          : AppColors.textMuted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              onEdit();
                            },
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text('Edit title, description, tags'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              onHideToggle();
                            },
                            icon: Icon(
                              layout.hidden
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 18,
                            ),
                            label: Text(
                              layout.hidden
                                  ? 'Show in Community'
                                  : 'Hide from Community',
                            ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.red,
                              side: BorderSide(
                                color: AppColors.red.withValues(alpha: 0.5),
                              ),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              onDelete();
                            },
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('Delete post'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Column(
                  children: [
                    Icon(
                      Icons.arrow_upward_rounded,
                      size: 14,
                      color: AppColors.green.withValues(alpha: 0.85),
                    ),
                    Text(
                      '$net',
                      style: TextStyle(
                        color: net > 0
                            ? AppColors.green
                            : net < 0
                                ? AppColors.red
                                : AppColors.textMuted,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            layout.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: layout.hidden
                                  ? AppColors.textMuted
                                  : AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (layout.hidden)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.visibility_off_outlined,
                              size: 14,
                              color: AppColors.textMuted,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${layout.upCount}↑ · ${layout.downCount}↓ · $when',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.textMuted,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
