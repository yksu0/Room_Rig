// lib/screens/home_screen.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/app_state.dart';
import '../models/room_model.dart';
import '../models/room_scale.dart';
import '../models/saved_room.dart';
import '../models/room_revision.dart';
import '../models/scan_layout_model.dart';
import '../models/upgrade_catalog.dart';
import '../services/auth_service.dart';
import '../services/layout_share_image.dart';
import '../services/profile_service.dart';
import '../services/room_compare.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/chrome/adaptive_panel.dart';
import '../widgets/confirm_dialogs.dart';
import '../widgets/glass_card.dart';
import '../widgets/guest_signup_gate.dart';
import '../widgets/onboarding_sheet.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/publish_layout_action.dart';
import '../widgets/room_icons.dart';
import '../widgets/score_ring.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _onboardingPresented = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.watch<AppState>();
    if (!_onboardingPresented && state.shouldShowOnboarding) {
      _onboardingPresented = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showOnboarding(context.read<AppState>());
      });
    }
  }

  Future<void> _confirmLoadSavedRoom(
    BuildContext context,
    AppState state,
    String roomId,
  ) async {
    if (roomId == state.activeRoomId) return;
    if (state.hasLayoutWork) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Switch room?', style: TextStyle(color: AppColors.textPrimary)),
          content: Text(
            state.isScanSessionActive
                ? 'Switching cancels the in-progress scan, saves this lot, then opens the other room.'
                : 'This room will be saved to My Rooms, then you will switch.',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Switch')),
          ],
        ),
      );
      if (ok != true) return;
    }
    final notice = state.loadSavedRoom(roomId);
    if (notice != null && context.mounted) {
      showAppSnackBar(context, message: notice);
    }
  }

  Future<void> _openProfile(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
  }

  Future<void> _confirmRestoreOriginal(BuildContext context, AppState state) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Restore original layout?', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'This reverts to the layout saved before your last optimization.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restore')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    state.restoreOriginalLayout();
    showAppSnackBar(
      context,
      message: 'Original layout restored · scores are ROUGH EST. until Benchmark',
    );
  }

  Future<void> _showOnboarding(AppState state) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => OnboardingSheet(
        onDone: () {
          Navigator.of(ctx).pop();
          state.completeOnboarding();
        },
        onJumpTab: (tab) {
          Navigator.of(ctx).pop();
          state.setTab(tab);
          state.completeOnboarding();
        },
      ),
    );
    if (mounted) state.completeOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final room = state.currentRoomData;
    final desktop = AppLayout.isDesktop(context);

    if (desktop) {
      final wideDesktop =
          MediaQuery.sizeOf(context).width >= AppLayout.desktopMinWidth;
      return Scaffold(
        backgroundColor: AppColors.bg,
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        floatingActionButton: _buildCreateRoomFab(context, state),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.lg,
                  AppSpace.sm,
                  AppSpace.lg,
                  AppSpace.xs,
                ),
                child: _buildHeader(context, room, state),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: AppLayout.inspectRailWidthFor(context),
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          border: Border(
                            right: BorderSide(color: AppColors.borderSubtle),
                          ),
                        ),
                        child: AdaptiveRailPane(
                          title: 'Status',
                          icon: Icons.insights_outlined,
                          accent: AppColors.cyan,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ..._hubStatusBlocks(context, state),
                              _buildScoreSection(context, state),
                              if (!wideDesktop) ...[
                                const SizedBox(height: AppSpace.section),
                                _buildMetricsRow(
                                  context,
                                  state,
                                  includeTitle: true,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ColoredBox(
                        color: AppColors.bg,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(AppSpace.md, 10, AppSpace.md, AppSpace.xl + 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!state.roomIsReady) ...[
                                _buildEmptyStartCard(context, state),
                                const SizedBox(height: AppSpace.section),
                              ],
                              _buildMyRooms(context, state),
                              const SizedBox(height: AppSpace.section),
                              _buildQuickActions(context, state),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (wideDesktop)
                      SizedBox(
                        width: AppLayout.toolsRailWidthFor(context),
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            border: Border(
                              left: BorderSide(color: AppColors.borderSubtle),
                            ),
                          ),
                          child: AdaptiveRailPane(
                            title: 'Specs',
                            icon: Icons.meeting_room_outlined,
                            accent: AppColors.cyan,
                            child: _buildMetricsRow(
                              context,
                              state,
                              includeTitle: false,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _buildCreateRoomFab(context, state),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.screen,
            AppSpace.lg,
            AppSpace.screen,
            AppSpace.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, room, state),
              const SizedBox(height: AppSpace.xl),
              if (!state.roomIsReady) ...[
                _buildEmptyStartCard(context, state),
                const SizedBox(height: AppSpace.section),
              ],
              ..._hubStatusBlocks(context, state),
              _buildScoreSection(context, state),
              const SizedBox(height: AppSpace.section),
              _buildMyRooms(context, state),
              const SizedBox(height: AppSpace.section),
              _buildQuickActions(context, state),
              const SizedBox(height: AppSpace.section),
              _buildMetricsRow(context, state),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreateRoomFab(BuildContext context, AppState state) {
    return Semantics(
      button: true,
      label: 'Create room',
      child: FloatingActionButton(
      heroTag: 'hub_create_room_fab',
      backgroundColor: AppColors.cyan,
      foregroundColor: AppColors.bg,
      tooltip: 'New room',
      onPressed: () => _showCreateRoomSheet(context, state),
      child: const Icon(Icons.add_rounded),
    ),
    );
  }

  Future<void> _openHowItWorks(BuildContext context, AppState state) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => OnboardingSheet(
        onDone: () {
          if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
        },
        onJumpTab: (tab) {
          if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
          state.setTab(tab);
        },
      ),
    );
  }

  /// Scan confidence only — Set up banner removed; create via + FAB / Quick Actions.
  List<Widget> _hubStatusBlocks(BuildContext context, AppState state) {
    if (state.roomIsReady &&
        state.scanComplete &&
        state.lastScanConfidence != null) {
      return [
        _ScanConfidenceBanner(metrics: state.lastScanConfidence!),
        const SizedBox(height: AppSpace.xl),
      ];
    }
    return const [];
  }

  Widget _buildHeader(BuildContext context, RoomData room, AppState state) {
    final auth = context.watch<AuthService>();
    final profiles = context.watch<ProfileService>();
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ROOM RIG',
              style: TextStyle(
                color: AppColors.cyan,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 3.2,
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              'Room Hub',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const Spacer(),
        // Profile button (top-right). Guests see the generic glyph; signed-in
        // users see their photo / initial.
        Tooltip(
          message: auth.isSignedIn ? 'Profile' : 'Sign in or sign up',
          child: Semantics(
            button: true,
            label: auth.isSignedIn ? 'Profile' : 'Sign in or sign up',
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _openProfile(context),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.cyan.withValues(alpha: auth.isSignedIn ? 0.9 : 0.4),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(color: AppColors.cyan.withValues(alpha: 0.25), blurRadius: 16),
                    ],
                  ),
                  child: ProfileAvatar(
                    size: 44,
                    imageUrl: auth.isSignedIn ? profiles.avatarUrl : null,
                    label: auth.isSignedIn && profiles.hasDisplayName
                        ? profiles.displayLabel
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScoreSection(BuildContext context, AppState state) {
    final simulated = state.scoresAreSimulated;
    final accent = simulated ? AppColors.amber : AppColors.green;
    return Container(
      decoration: AppColors.activeGlowDecoration(
        color: accent,
        fill: Colors.transparent,
        radius: AppRadius.lg,
        borderAlpha: state.roomIsReady ? 0.35 : 0.15,
        blur: 16,
        glowAlpha: state.roomIsReady ? (simulated ? 0.12 : 0.2) : 0.06,
      ),
      child: GlassCard(
        gradient: AppColors.cardGradient,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'Overall Room Score',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      ),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => state.setTab(benchmarkTabIndex),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              border: Border.all(color: accent.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              simulated ? HubScoreLabels.roughEst : HubScoreLabels.benchmarkOk,
                              style: TextStyle(
                                color: accent,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.cyan.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(color: AppColors.cyan.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          'GRADE ${state.scoreGrade}',
                          style: const TextStyle(
                            color: AppColors.cyan,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'How Room Rig works',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: () => _openHowItWorks(context, state),
                  icon: Icon(
                    Icons.help_outline_rounded,
                    color: AppColors.textMuted,
                    size: 22,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            LayoutBuilder(
              builder: (context, constraints) {
                final phone = constraints.maxWidth < 412;
                final copy = state.roomIsReady
                  ? (simulated
                      ? '${HubScoreLabels.roughSubtitle} Tap a ring to open that Benchmark domain. Tap ? for Create → Room → Benchmark tips.'
                      : 'Benchmark locked these scores. Tap a ring for that domain — edit in Room, then Benchmark again after layout changes. Tap ? for a quick tour.')
                  : 'Tap the + button to create a room (or use Create below). Scan from the Scan tab when you can. Then arrange in Room and run Benchmark to lock scores. Tap ? for the tour.';
                return Text(
                  copy,
                  key: const ValueKey('hub_score_subtitle'),
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: phone ? 11 : 12,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                );
              },
            ),
            if (state.roomIsReady) ...[
              const SizedBox(height: AppSpace.md),
              LayoutBuilder(
                builder: (context, constraints) {
                  final tight = constraints.maxWidth < 360;
                  final side = tight ? 56.0 : 70.0;
                  final overall = tight ? 84.0 : 104.0;
                  return Row(
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: _tappableRing(
                            context,
                            state,
                            'airflow',
                            state.airflowScore,
                            side,
                            AppColors.airflowColor,
                            'Airflow',
                          ),
                        ),
                      ),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: ScoreRing(
                            score: state.overallScore,
                            size: overall,
                            color: AppColors.cyan,
                            label: 'Overall',
                          ),
                        ),
                      ),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: _tappableRing(
                            context,
                            state,
                            'lighting',
                            state.lightingScore,
                            side,
                            AppColors.lightingColor,
                            'Lighting',
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpace.sm),
              Row(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _tappableRing(
                        context,
                        state,
                        'ergonomics',
                        state.ergonomicsScore,
                        64,
                        AppColors.ergonomicsColor,
                        'Ergo',
                      ),
                    ),
                  ),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _tappableRing(
                        context,
                        state,
                        'spatial',
                        state.spatialScore,
                        64,
                        AppColors.spatialColor,
                        'Space',
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpace.md),
            _JourneySteps(state: state),
          ],
        ),
      ),
    );
  }

  Widget _tappableRing(
    BuildContext context,
    AppState state,
    String mode,
    double score,
    double size,
    Color color,
    String label,
  ) {
    return Semantics(
      button: true,
      label: '$label benchmark',
      child: GestureDetector(
        onTap: () {
          if (!state.roomIsReady) {
            showAppSnackBar(
              context,
              message: 'Create a room with + first, then Benchmark opens from these rings.',
            );
            return;
          }
          state.setBenchmarkMode(mode);
          state.setTab(benchmarkTabIndex);
        },
        child: ScoreRing(score: score, size: size, color: color, label: label),
      ),
    );
  }

  Widget _buildMyRooms(BuildContext context, AppState state) {
    final rooms = [
      for (final r in state.savedRooms) r,
    ];
    final activeListed = rooms.any((r) => r.id == state.activeRoomId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'MY ROOMS',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
            const Spacer(),
            // Create lives in + FAB / Quick Actions; Scan is the bottom-nav Scan tab. Checkpoints + Publish here.
            Builder(
              builder: (ctx) {
                final guest = ctx.watch<AuthService>().isGuest;
                final empty = !state.roomIsReady || state.furniture.isEmpty;
                final muted = guest && empty;
                return TextButton(
                  key: const ValueKey('hub_my_rooms_publish'),
                  onPressed: () => publishCurrentLayoutToCommunity(ctx),
                  child: Text(
                    'Publish',
                    style: TextStyle(
                      fontWeight: muted ? FontWeight.w600 : FontWeight.w700,
                      color: muted
                          ? AppColors.textMuted.withValues(alpha: 0.55)
                          : null,
                    ),
                  ),
                );
              },
            ),
            TextButton(
              onPressed: () => _showRoomHistorySheet(context, state),
              child: const Text('Checkpoints', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.xs),
        if (!activeListed)
          _RoomSlotTile(
            title: state.currentRoomData.name,
            subtitle: 'Current lot',
            badgeLabel: '${state.furniture.length}',
            selected: true,
            onTap: () => _showRenameRoomSheet(context, state),
            onDuplicate: () async {
              if (!await ensureCanCreateRoom(context)) return;
              if (!context.mounted) return;
              state.duplicateActiveRoom();
              showAppSnackBar(
                context,
                message: 'Duplicated as ${state.currentRoomData.name}',
              );
            },
            onDelete: null,
          ),
        ...rooms.map(
          (r) => _RoomSlotTile(
            title: r.name,
            subtitle: r.scanComplete
                ? 'Scanned'
                : (r.layout.scanSource == 'manual' ? 'Created' : 'Preset'),
            badgeLabel: '${r.furniture.length}',
            selected: r.id == state.activeRoomId,
            onTap: () => _confirmLoadSavedRoom(context, state, r.id),
            onDuplicate: () async {
              if (!await ensureCanCreateRoom(context)) return;
              if (!context.mounted) return;
              if (r.id != state.activeRoomId) {
                await _confirmLoadSavedRoom(context, state, r.id);
                if (!context.mounted) return;
                // Cancelled switch — do not duplicate the wrong room.
                if (state.activeRoomId != r.id) return;
              }
              state.duplicateActiveRoom();
              if (context.mounted) {
                showAppSnackBar(
                  context,
                  message: 'Duplicated as ${state.currentRoomData.name}',
                );
              }
            },
            onDelete: rooms.length > 1
                ? () => _confirmDeleteRoom(context, state, r.id, r.name)
                : null,
          ),
        ),
      ],
    );
  }

  String _formatRevisionTime(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  Future<void> _showRoomHistorySheet(BuildContext context, AppState state) async {
    final List<RoomRevision> revisions =
        state.activeRoomRevisions.reversed.toList(growable: false);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CHECKPOINTS',
                  style: TextStyle(
                    color: AppColors.cyan,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Named snapshots for ${state.currentRoomData.name}. Auto-save already keeps the live lot.',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: () {
                          final ok = state.checkpointActiveRoom('Manual save');
                          if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                          if (!context.mounted) return;
                          showAppSnackBar(
                            context,
                            message: ok
                                ? 'Checkpoint saved'
                                : 'Nothing to checkpoint yet',
                          );
                        },
                        child: const Text('Save snapshot'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                          _showCompareRoomsSheet(context, state);
                        },
                        child: const Text('Compare lots'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                      if (!context.mounted) return;
                      await publishCurrentLayoutToCommunity(context);
                    },
                    icon: const Icon(Icons.public, size: 18),
                    label: const Text('Publish to Community'),
                  ),
                ),
                const SizedBox(height: 12),
                if (revisions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No checkpoints yet. Save a snapshot to restore this layout later.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.5,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: revisions.length,
                      separatorBuilder: (_, _) => const Divider(color: AppColors.border, height: 1),
                      itemBuilder: (context, index) {
                        final rev = revisions[index];
                        final overall = rev.scores?['overall'];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            rev.label,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            _formatRevisionTime(rev.savedAt),
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                          ),
                          trailing: overall != null
                              ? Text(
                                  overall.toStringAsFixed(0),
                                  style: const TextStyle(
                                    color: AppColors.cyan,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                )
                              : null,
                          onTap: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (dCtx) => AlertDialog(
                                backgroundColor: AppColors.surface,
                                title: const Text(
                                  'Restore checkpoint?',
                                  style: TextStyle(color: AppColors.textPrimary),
                                ),
                                content: Text(
                                  'Replace the current layout with “${rev.label}”? Scores become ROUGH EST. until you run Benchmark again.',
                                  style: const TextStyle(color: AppColors.textSecondary),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(dCtx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(dCtx, true),
                                    child: const Text('Restore'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm != true || !context.mounted) return;
                            final ok = state.restoreRoomRevision(rev.id);
                            if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                            if (!context.mounted) return;
                            showAppSnackBar(
                              context,
                              message: ok
                                  ? 'Restored “${rev.label}”'
                                  : 'Could not restore checkpoint',
                            );
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCompareRoomsSheet(BuildContext context, AppState state) async {
    final rooms = state.savedRooms;
    if (rooms.length < 2) {
      showAppSnackBar(
        context,
        message: 'Save or duplicate a room first — need two lots to compare',
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: _CompareRoomsSheetBody(
            rooms: rooms,
            fallbackCols: state.currentRoomData.gridCols,
            fallbackRows: state.currentRoomData.gridRows,
          ),
        );
      },
    );
  }

  /// Empty-lot CTA: + FAB creates a room; Scan is the bottom-nav Scan tab.
  Widget _buildEmptyStartCard(BuildContext context, AppState state) {
    if (state.roomIsReady) return const SizedBox.shrink();
    return GlassCard(
      gradient: AppColors.cardGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'GET STARTED',
            style: TextStyle(
              color: AppColors.cyan,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          const Text(
            'Tap the + button to create an empty room with a door and window. '
            'When you can, open the Scan tab to measure a real space.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _showCreateRoomSheet(context, state),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create room'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context, AppState state) {
    // Scan is the bottom-nav Scan tab (not Quick Actions / not the + FAB).
    // FAB opens Create room; Quick Actions always offer Create, plus Room/Benchmark when ready.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'QUICK ACTIONS',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 360;
            final actions = <Widget>[
              _ActionButton(
                svgString: RoomSvg.home,
                label: 'Create',
                color: AppColors.amber,
                onTap: () => _showCreateRoomSheet(context, state),
              ),
              if (state.roomIsReady) ...[
                _ActionButton(
                  svgString: RoomSvg.floorPlan,
                  label: 'Room',
                  color: AppColors.cyan,
                  onTap: () => context.read<AppState>().setTab(roomTabIndex),
                ),
                _ActionButton(
                  svgString: RoomSvg.speedometer,
                  label: 'Benchmark',
                  color: AppColors.amber,
                  onTap: () => context.read<AppState>().setTab(benchmarkTabIndex),
                ),
              ],
            ];
            if (actions.length == 1) {
              return Row(children: [Expanded(child: actions[0])]);
            }
            if (narrow && actions.length >= 3) {
              return Column(
                children: [
                  Row(children: [
                    Expanded(child: actions[0]),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(child: actions[1]),
                  ]),
                  const SizedBox(height: AppSpace.sm),
                  Row(children: [
                    Expanded(child: actions[2]),
                    const SizedBox(width: AppSpace.sm),
                    const Expanded(child: SizedBox.shrink()),
                  ]),
                ],
              );
            }
            return Row(
              children: [
                for (int i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpace.sm),
                  Expanded(child: actions[i]),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildMetricsRow(
    BuildContext context,
    AppState state, {
    bool includeTitle = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (includeTitle) ...[
          Text(
            'ROOM SPECS',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),
        ],
        GlassCard(
          child: Column(
            children: [
              _SpecRow(
                svgString: RoomSvg.home,
                label: 'Room Name',
                value: state.currentRoomData.name,
                onTap: () => _showRenameRoomSheet(context, state),
              ),
              const Divider(color: AppColors.border, height: 24),
              _SpecRow(
                svgString: RoomSvg.tune,
                label: 'Size',
                value: _roomSizeLabel(state),
              ),
              const Divider(color: AppColors.border, height: 24),
              _SpecRow(svgString: RoomSvg.tune, label: 'Components', value: '${state.furniture.length} items'),
              const Divider(color: AppColors.border, height: 24),
              _SpecRow(
                svgString: RoomSvg.star,
                label: 'Optimization',
                value: state.isOptimized ? 'Applied' : 'Not Applied',
                valueColor: state.isOptimized ? AppColors.green : AppColors.textSecondary,
              ),
              const Divider(color: AppColors.border, height: 24),
              _SpecRow(
                svgString: RoomSvg.trendingUp,
                label: 'Score Delta',
                value: state.isOptimized
                    ? '+${(state.overallScore - state.previousOverallScore).toStringAsFixed(1)} pts'
                    : '—',
                valueColor: state.isOptimized && (state.overallScore - state.previousOverallScore) > 0
                    ? AppColors.green
                    : AppColors.textSecondary,
              ),
              if (state.hasCompareSnapshot) ...[
                const Divider(color: AppColors.border, height: 24),
                _SpecRow(
                  svgString: RoomSvg.star,
                  label: 'Before/after',
                  value: 'Open Benchmark',
                  valueColor: AppColors.cyan,
                  onTap: () {
                    state.setBenchmarkMode('airflow');
                    state.setTab(benchmarkTabIndex);
                  },
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                runSpacing: 4,
                children: [
                  if (state.hasCompareSnapshot)
                    TextButton(
                      onPressed: () => _confirmRestoreOriginal(context, state),
                      child: const Text('Restore original'),
                    ),
                  TextButton(
                    onPressed: () => Share.share(
                      state.buildShareReport(),
                      subject: 'Room Rig report',
                    ),
                    child: const Text('Share report'),
                  ),
                  TextButton(
                    onPressed: () => _exportRoomJson(context, state),
                    child: const Text('Export JSON'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _roomSizeLabel(AppState state) {
    final room = state.currentRoomData;
    final dims = state.activeRoomLayout?.dimensions;
    final l = dims?.lengthMeters ?? RoomScale.metersFromCells(room.gridCols);
    final w = dims?.widthMeters ?? RoomScale.metersFromCells(room.gridRows);
    final h = dims?.heightMeters ?? room.heightMeters;
    return '${RoomScale.formatMeters(l)} × ${RoomScale.formatMeters(w)} × ${RoomScale.formatMeters(h)}';
  }

  Future<void> _exportRoomJson(BuildContext context, AppState state) async {
    try {
      final raw = state.currentRoomData.name;
      final safe = raw.replaceAll(RegExp(r'[^\w\-]+'), '_');
      final file = File('${Directory.systemTemp.path}/room_rig_${safe}_layout.json');
      await file.writeAsString(state.buildShareJson());
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: '$raw layout.json',
        text: 'Room Rig layout export (heuristic scores — see benchmarkOk in JSON)',
      );
    } catch (e) {
      if (!context.mounted) return;
      showAppSnackBar(context, message: 'Export failed: $e');
    }
  }

  Future<void> _confirmDeleteRoom(
    BuildContext context,
    AppState state,
    String id,
    String name,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete room?', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          state.isSignedIn
              ? 'Remove "$name" from this device and your account cloud. This cannot be undone.'
              : 'Remove "$name" from saved rooms on this device. This cannot be undone.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) state.deleteSavedRoom(id);
  }

  Future<void> _showRenameRoomSheet(BuildContext context, AppState state) async {
    final ctrl = TextEditingController(text: state.currentRoomData.name);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'RENAME ROOM',
              style: TextStyle(color: AppColors.cyan, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Name',
                labelStyle: TextStyle(color: AppColors.textMuted),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  state.renameActiveRoom(ctrl.text);
                  Navigator.pop(ctx);
                },
                child: const Text('Save name'),
              ),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
  }

  Future<void> _showCreateRoomSheet(BuildContext context, AppState state) async {
    // Guests own exactly one room — room #2 is a hard sign-up gate.
    if (!await ensureCanCreateRoom(context)) return;
    if (!context.mounted) return;
    if (state.hasLayoutWork) {
      final ok = await confirmAction(
        context,
        title: 'Replace current layout?',
        body:
            'Creating a room saves your current lot and starts an empty rectangle with a door and window.',
        confirmLabel: 'Create room',
        danger: true,
      );
      if (!ok || !context.mounted) return;
    }
    final nameCtrl = TextEditingController(text: 'My Room');
    final lengthCtrl = TextEditingController(text: '3.6');
    final widthCtrl = TextEditingController(text: '4.8');
    final heightCtrl = TextEditingController(text: '2.7');
    String? dimError;
    // Pop with params first — mutating AppState under an open sheet rebuilds
    // InheritedWidgets and trips framework.dart _dependents.isEmpty.
    final created = await showModalBottomSheet<({
      String name,
      double length,
      double width,
      double height,
    })>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                20 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CREATE ROOM',
                    style: TextStyle(
                      color: AppColors.cyan,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Empty rectangle plus a door and window. Enter size in metres.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      labelStyle: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: lengthCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: const InputDecoration(
                            labelText: 'Length (m)',
                            labelStyle: TextStyle(color: AppColors.textMuted),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: widthCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: const InputDecoration(
                            labelText: 'Width (m)',
                            labelStyle: TextStyle(color: AppColors.textMuted),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: heightCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: const InputDecoration(
                            labelText: 'Height (m)',
                            labelStyle: TextStyle(color: AppColors.textMuted),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (dimError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      dimError!,
                      style: const TextStyle(color: AppColors.amber, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        final length = double.tryParse(lengthCtrl.text.trim());
                        final width = double.tryParse(widthCtrl.text.trim());
                        final height = double.tryParse(heightCtrl.text.trim());
                        if (length == null ||
                            width == null ||
                            height == null ||
                            length < RoomScale.minMeters ||
                            width < RoomScale.minMeters ||
                            height < 2.0 ||
                            length > RoomScale.maxMeters ||
                            width > RoomScale.maxMeters ||
                            height > 4.5) {
                          setLocal(() {
                            dimError =
                                'Enter L/W ${RoomScale.minMeters}–${RoomScale.maxMeters} m and height 2.0–4.5 m.';
                          });
                          return;
                        }
                        Navigator.pop(ctx, (
                          name: nameCtrl.text,
                          length: length,
                          width: width,
                          height: height,
                        ));
                      },
                      child: const Text('Create empty room'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    nameCtrl.dispose();
    lengthCtrl.dispose();
    widthCtrl.dispose();
    heightCtrl.dispose();
    if (created == null || !context.mounted) return;
    state.createManualRoom(
      name: created.name,
      lengthMeters: created.length,
      widthMeters: created.width,
      heightMeters: created.height,
    );
    await state.flushRoomsToCloud();
    if (!context.mounted) return;
    state.setTab(roomTabIndex);
    showAppSnackBar(
      context,
      message: 'Created ${state.currentRoomData.name}',
    );
  }
}

class _ScanConfidenceBanner extends StatelessWidget {
  final ScanConfidenceMetrics metrics;
  const _ScanConfidenceBanner({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final pct = (metrics.overallScore * 100).round();
    final sizeOnly = metrics.detectionCount == 0 &&
        metrics.notes.any((n) => n.contains('place furniture on Room'));
    final title = sizeOnly
        ? 'Last measure · room sized · open Room'
        : 'Last scan · $pct% confidence · ${metrics.objectCount} objects';
    final note = metrics.notes.isNotEmpty
        ? metrics.notes.first
        : (sizeOnly ? 'Place furniture on Room.' : 'Ready for Room + Benchmark.');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.green.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.green.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          SvgIcon(RoomSvg.scan, size: 22, color: AppColors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 13),
                ),
                const SizedBox(height: 3),
                Text(
                  note,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JourneySteps extends StatelessWidget {
  final AppState state;
  const _JourneySteps({required this.state});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          key: const ValueKey('hub_journey_steps'),
          children: [
            Expanded(
              child: _JourneyChip(
                label: '1. Edit Room',
                color: AppColors.cyan,
                onTap: () => state.setTab(roomTabIndex),
              ),
            ),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: _JourneyChip(
                label: '2. Benchmark',
                color: AppColors.amber,
                onTap: () => state.setTab(benchmarkTabIndex),
              ),
            ),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: _JourneyChip(
                label: '3. Apply',
                color: AppColors.green,
                onTap: () => state.openBenchmarkResults(),
              ),
            ),
          ],
        );
      },
    );
  }

}

class _JourneyChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _JourneyChip({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String svgString;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({required this.svgString, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 15)],
          ),
          child: Column(
            children: [
              SvgIcon(svgString, size: 26, color: color),
              const SizedBox(height: AppSpace.xs),
              Text(
                label,
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpecRow extends StatelessWidget {
  final String svgString;
  final String label;
  final String value;
  final Color? valueColor;
  final VoidCallback? onTap;

  const _SpecRow({
    required this.svgString,
    required this.label,
    required this.value,
    this.valueColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        SvgIcon(svgString, size: 18, color: AppColors.textMuted),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: valueColor ?? AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (onTap != null) ...[
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textMuted),
        ],
      ],
    );
    if (onTap == null) return row;
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: row);
  }
}

class _RoomSlotTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? badgeLabel;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDuplicate;
  final VoidCallback? onDelete;

  const _RoomSlotTile({
    required this.title,
    required this.subtitle,
    this.badgeLabel,
    required this.selected,
    required this.onTap,
    required this.onDuplicate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? AppColors.cyan.withValues(alpha: 0.12) : AppColors.card,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          onTap: onTap,
          dense: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: selected ? AppColors.cyan : AppColors.border),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              if (badgeLabel != null)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.orange.withValues(alpha: 0.55)),
                  ),
                  child: Text(
                    badgeLabel!,
                    style: const TextStyle(
                      color: AppColors.orange,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          subtitle: Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.copy_outlined, size: 18, color: AppColors.textMuted),
                onPressed: onDuplicate,
                tooltip: 'Duplicate',
              ),
              if (onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.textMuted),
                  onPressed: onDelete,
                  tooltip: 'Delete',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompareRoomsSheetBody extends StatefulWidget {
  final List<SavedRoom> rooms;
  final int fallbackCols;
  final int fallbackRows;

  const _CompareRoomsSheetBody({
    required this.rooms,
    required this.fallbackCols,
    required this.fallbackRows,
  });

  @override
  State<_CompareRoomsSheetBody> createState() => _CompareRoomsSheetBodyState();
}

class _CompareRoomsSheetBodyState extends State<_CompareRoomsSheetBody> {
  String? _idA;
  String? _idB;

  SavedRoom? _byId(String? id) {
    if (id == null) return null;
    for (final r in widget.rooms) {
      if (r.id == id) return r;
    }
    return null;
  }

  Widget _roomPicker({
    required String label,
    required String? value,
    required ValueChanged<String?> onChanged,
    required String? excludeId,
  }) {
    final options = widget.rooms.where((r) => r.id != excludeId).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: value != null && options.any((r) => r.id == value) ? value : null,
              dropdownColor: AppColors.card,
              hint: const Text('Select room', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
              items: [
                for (final r in options)
                  DropdownMenuItem(value: r.id, child: Text(r.name)),
              ],
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _scoreRow(String label, double a, double b, double delta) {
    final deltaColor = delta > 0.05
        ? AppColors.green
        : (delta < -0.05 ? AppColors.amber : AppColors.textSecondary);
    final sign = delta > 0 ? '+' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ),
          Expanded(
            child: Text(
              a.toStringAsFixed(0),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              b.toStringAsFixed(0),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              '$sign${delta.toStringAsFixed(1)}',
              textAlign: TextAlign.right,
              style: TextStyle(color: deltaColor, fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = _byId(_idA);
    final b = _byId(_idB);
    final result = (a != null && b != null && a.id != b.id) ? RoomCompare.compare(a, b) : null;

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'COMPARE LOTS',
              style: TextStyle(
                color: AppColors.cyan,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Rough side-by-side from furniture tags — not Benchmark sims. Use Benchmark Apply for locked scores.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.35),
            ),
            const SizedBox(height: 14),
            _roomPicker(
              label: 'ROOM A',
              value: _idA,
              excludeId: _idB,
              onChanged: (v) => setState(() => _idA = v),
            ),
            const SizedBox(height: 12),
            _roomPicker(
              label: 'ROOM B',
              value: _idB,
              excludeId: _idA,
              onChanged: (v) => setState(() => _idB = v),
            ),
            if (result != null) ...[
              const SizedBox(height: 16),
              GlassCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${result.a.name}  →  ${result.b.name}',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Row(
                      children: [
                        SizedBox(width: 88, child: Text('', style: TextStyle(fontSize: 11))),
                        Expanded(
                          child: Text(
                            'A',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'B',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ),
                        SizedBox(
                          width: 52,
                          child: Text(
                            'Δ',
                            textAlign: TextAlign.right,
                            style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: AppColors.border, height: 16),
                    for (final key in const [
                      'overall',
                      'airflow',
                      'lighting',
                      'ergonomics',
                      'spatial',
                    ])
                      _scoreRow(
                        key[0].toUpperCase() + key.substring(1),
                        result.scoresA[key] ?? 0,
                        result.scoresB[key] ?? 0,
                        result.delta(key),
                      ),
                    const Divider(color: AppColors.border, height: 20),
                    Text(
                      result.layoutDiff,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.35),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () async {
                          final colsA = RoomScale.colsFrom(
                            result.a.layout,
                            fallback: widget.fallbackCols,
                          );
                          final rowsA = RoomScale.rowsFrom(
                            result.a.layout,
                            fallback: widget.fallbackRows,
                          );
                          final colsB = RoomScale.colsFrom(
                            result.b.layout,
                            fallback: widget.fallbackCols,
                          );
                          final rowsB = RoomScale.rowsFrom(
                            result.b.layout,
                            fallback: widget.fallbackRows,
                          );
                          await LayoutShareImage.shareBeforeAfter(
                            gridCols: colsA > colsB ? colsA : colsB,
                            gridRows: rowsA > rowsB ? rowsA : rowsB,
                            before: result.a.furniture,
                            after: result.b.furniture,
                            beforeLabel: result.a.name,
                            afterLabel: result.b.name,
                            footer: result.layoutDiff,
                          );
                        },
                        icon: const Icon(Icons.ios_share_rounded, size: 18),
                        label: const Text('Share image'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
