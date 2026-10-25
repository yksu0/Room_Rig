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
import '../services/room_compare.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../widgets/chrome/adaptive_panel.dart';
import '../widgets/confirm_dialogs.dart';
import '../widgets/glass_card.dart';
import '../widgets/onboarding_sheet.dart';
import '../widgets/room_icons.dart';
import '../widgets/room_status_strip.dart';
import '../widgets/score_ring.dart';
import 'auth_screen.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notice)));
    }
  }

  Future<void> _openAccountSheet(BuildContext context) async {
    final auth = context.read<AuthService>();
    if (auth.isSignedIn) {
      final email = auth.email ?? 'Signed in';
      final action = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'ACCOUNT',
                  style: TextStyle(
                    color: AppColors.cyan,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(email, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text(
                  'Rooms sync to your account when signed in.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, 'signOut'),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      );
      if (action == 'signOut' && context.mounted) {
        await auth.signOut();
      }
      return;
    }
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Original layout restored · scores are ROUGH EST. until Bench')),
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
                              if (state.roomIsReady) ...[
                                RoomStatusStrip(
                                  compact: true,
                                  onTapScores: () => state.setTab(3),
                                ),
                                const SizedBox(height: AppSpace.md),
                              ],
                              ..._hubStatusBlocks(context, state),
                              _buildScoreSection(context, state),
                              if (state.roomIsReady &&
                                  state.suggestedUpgrade() != null) ...[
                                const SizedBox(height: AppSpace.md),
                                _UpgradeSuggestionBanner(
                                  suggestion: state.suggestedUpgrade()!,
                                ),
                              ],
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
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
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
              if (state.roomIsReady) ...[
                const SizedBox(height: AppSpace.sm),
                RoomStatusStrip(
                  compact: true,
                  onTapScores: () => state.setTab(3),
                ),
              ],
              const SizedBox(height: AppSpace.xl),
              ..._hubStatusBlocks(context, state),
              _buildScoreSection(context, state),
              if (state.roomIsReady && state.suggestedUpgrade() != null) ...[
                const SizedBox(height: AppSpace.md),
                _UpgradeSuggestionBanner(suggestion: state.suggestedUpgrade()!),
              ],
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
    return FloatingActionButton(
      heroTag: 'hub_create_room_fab',
      backgroundColor: AppColors.cyan,
      foregroundColor: AppColors.bg,
      tooltip: 'New room',
      onPressed: () => _showCreateRoomSheet(context, state),
      child: const Icon(Icons.add_rounded),
    );
  }

  /// Getting-started / journey banners shared by mobile stack and desktop Status rail.
  List<Widget> _hubStatusBlocks(BuildContext context, AppState state) {
    if (!state.roomIsReady) {
      return [
        _GettingStartedBanner(
          onScan: () => state.setTab(1),
          onCreate: () => _showCreateRoomSheet(context, state),
        ),
        const SizedBox(height: AppSpace.xl),
      ];
    }
    if (state.scanComplete && state.lastScanConfidence != null) {
      return [
        _ScanConfidenceBanner(metrics: state.lastScanConfidence!),
        const SizedBox(height: AppSpace.md),
        _JourneySteps(state: state),
        const SizedBox(height: AppSpace.xl),
      ];
    }
    return [
      _ManualRoomBanner(state: state),
      const SizedBox(height: AppSpace.md),
      _JourneySteps(state: state),
      const SizedBox(height: AppSpace.xl),
    ];
  }

  Widget _buildHeader(BuildContext context, RoomData room, AppState state) {
    final auth = context.watch<AuthService>();
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
              'Rig Hub',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const Spacer(),
        if (state.hasSeenOnboarding)
          GestureDetector(
            onTap: () {
              _onboardingPresented = false;
              state.completeOnboarding(); // keep flag; reopen sheet manually
              showModalBottomSheet<void>(
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
            },
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Icon(Icons.help_outline_rounded, color: AppColors.textMuted, size: 22),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Material(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => _openAccountSheet(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      auth.isSignedIn ? Icons.person_rounded : Icons.person_outline_rounded,
                      size: 16,
                      color: AppColors.cyan,
                    ),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 110),
                      child: Text(
                        auth.isSignedIn ? (auth.email ?? 'Account') : 'Guest',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.accentGradient,
            boxShadow: [
              BoxShadow(color: AppColors.cyan.withValues(alpha: 0.3), blurRadius: 20),
            ],
          ),
          child: SvgIcon(
            presetSvgFor(room.iconName.isNotEmpty ? room.iconName : room.name),
            size: 26,
            color: Colors.white,
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
      gradient: const LinearGradient(
        colors: [Color(0xFF1A1E32), Color(0xFF0E1020)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Overall Rig Score',
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
                  onTap: simulated
                      ? () {
                          state.setTab(3);
                        }
                      : null,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: (simulated ? AppColors.amber : AppColors.green).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(
                        color: (simulated ? AppColors.amber : AppColors.green).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      simulated ? HubScoreLabels.roughEst : HubScoreLabels.benchOk,
                      style: TextStyle(
                        color: simulated ? AppColors.amber : AppColors.green,
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
                  style: TextStyle(
                    color: AppColors.cyan,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          if (simulated) ...[
            const SizedBox(height: AppSpace.sm),
            GestureDetector(
              onTap: () => state.setTab(3),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: AppColors.amber.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        HubScoreLabels.roughSubtitle,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      'OPEN BENCH',
                      style: TextStyle(
                        color: AppColors.amber,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
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
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: _tappableRing(
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
      ),
    ),
    );
  }

  Widget _tappableRing(
    AppState state,
    String mode,
    double score,
    double size,
    Color color,
    String label,
  ) {
    return GestureDetector(
      onTap: () {
        state.setBenchmarkMode(mode);
        state.setTab(3);
      },
      child: ScoreRing(score: score, size: size, color: color, label: label),
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
            Text(
              'MY ROOMS',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
            const Spacer(),
          ],
        ),
        Wrap(
          spacing: 0,
          runSpacing: 0,
          alignment: WrapAlignment.end,
          children: [
            TextButton(
              onPressed: () {
                final ok = state.checkpointActiveRoom('Manual save');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? 'Checkpoint saved' : 'Nothing to checkpoint yet'),
                  ),
                );
              },
              child: const Text('Save checkpoint', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            TextButton(
              onPressed: () => _showRoomHistorySheet(context, state),
              child: const Text('History', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            TextButton(
              onPressed: () => _showCompareRoomsSheet(context, state),
              child: const Text('Compare rooms', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            TextButton(
              onPressed: () => _showCreateRoomSheet(context, state),
              child: const Text('New', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (!activeListed)
          _RoomSlotTile(
            title: state.currentRoomData.name,
            subtitle: 'Current lot',
            badgeLabel: '${state.furniture.length}',
            selected: true,
            onTap: () => _showRenameRoomSheet(context, state),
            onDuplicate: () {
              state.duplicateActiveRoom();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Duplicated as ${state.currentRoomData.name}')),
                );
              }
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
              if (r.id != state.activeRoomId) {
                await _confirmLoadSavedRoom(context, state, r.id);
                if (!context.mounted) return;
                // Cancelled switch — do not duplicate the wrong room.
                if (state.activeRoomId != r.id) return;
              }
              state.duplicateActiveRoom();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Duplicated as ${state.currentRoomData.name}')),
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
                  'ROOM HISTORY',
                  style: TextStyle(
                    color: AppColors.cyan,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Checkpoints for ${state.currentRoomData.name}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 12),
                if (revisions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No checkpoints yet. Use Save checkpoint to capture this layout.',
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
                                  'Replace the current layout with “${rev.label}”? Scores become ROUGH EST. until you run Bench again.',
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
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok ? 'Restored “${rev.label}”' : 'Could not restore checkpoint',
                                ),
                              ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Save or duplicate a room first — need two lots to compare'),
        ),
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

  Widget _buildQuickActions(BuildContext context, AppState state) {
    if (!state.roomIsReady) {
      return const SizedBox.shrink();
    }
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
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 360;
            final actions = [
              _ActionButton(
                svgString: RoomSvg.home,
                label: 'Create',
                color: AppColors.amber,
                onTap: () => _showCreateRoomSheet(context, state),
              ),
              _ActionButton(
                svgString: RoomSvg.tune,
                label: 'Customize',
                color: AppColors.cyan,
                onTap: () => context.read<AppState>().setTab(2),
              ),
              _ActionButton(
                svgString: RoomSvg.speedometer,
                label: 'Bench',
                color: AppColors.amber,
                onTap: () => context.read<AppState>().setTab(3),
              ),
              _ActionButton(
                svgString: RoomSvg.scan,
                label: 'Scan (opt.)',
                color: AppColors.textMuted,
                onTap: () => context.read<AppState>().setTab(1),
              ),
            ];
            if (narrow) {
              return Column(
                children: [
                  Row(children: [Expanded(child: actions[0]), const SizedBox(width: 12), Expanded(child: actions[1])]),
                  const SizedBox(height: 12),
                  Row(children: [Expanded(child: actions[2]), const SizedBox(width: 12), Expanded(child: actions[3])]),
                ],
              );
            }
            return Row(
              children: [
                for (int i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
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
                label: 'Rig Name',
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
                  value: 'Open Bench',
                  valueColor: AppColors.cyan,
                  onTap: () {
                    state.setBenchmarkMode('airflow');
                    state.setTab(3);
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
        text: 'Room Rig layout export (heuristic scores — see benchOk in JSON)',
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
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
          'Remove "$name" from saved rooms. This cannot be undone.',
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
    final created = await showModalBottomSheet<bool>(
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
                        state.createManualRoom(
                          name: nameCtrl.text,
                          lengthMeters: length,
                          widthMeters: width,
                          heightMeters: height,
                        );
                        Navigator.pop(ctx, true);
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
    if (created == true && context.mounted) {
      state.setTab(2);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created ${state.currentRoomData.name}')),
      );
    }
  }
}

class _GettingStartedBanner extends StatelessWidget {
  final VoidCallback onScan;
  final VoidCallback onCreate;
  const _GettingStartedBanner({
    required this.onScan,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.cyan.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SvgIcon(RoomSvg.scan, size: 24, color: AppColors.cyan),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Set up your room',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: AppSpace.xxs),
                    Text(
                      'Create an empty room or Scan to measure. Then arrange in Rig and run Bench.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              Expanded(
                child: _StartChip(
                  label: 'Create',
                  color: AppColors.amber,
                  onTap: onCreate,
                ),
              ),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: _StartChip(
                  label: 'Scan',
                  color: AppColors.cyan,
                  onTap: onScan,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StartChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _StartChip({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: color.withValues(alpha: 0.45)),
          boxShadow: AppColors.activeGlow(color, blur: 12, alpha: 0.2),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13),
        ),
      ),
    );
  }
}

class _ManualRoomBanner extends StatelessWidget {
  final AppState state;
  const _ManualRoomBanner({required this.state});

  @override
  Widget build(BuildContext context) {
    final isManual = state.activeRoomLayout?.scanSource == 'manual';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.purple.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          SvgIcon(RoomSvg.home, size: 22, color: AppColors.purple),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isManual ? 'Room created · ready to edit' : 'Room ready',
                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 13),
                ),
                const SizedBox(height: 3),
                Text(
                  isManual
                      ? 'Add furniture in Rig or run Bench to simulate scores.'
                      : 'Continue with Rig, Bench, or Upgrades.',
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

class _ScanConfidenceBanner extends StatelessWidget {
  final ScanConfidenceMetrics metrics;
  const _ScanConfidenceBanner({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final pct = (metrics.overallScore * 100).round();
    final sizeOnly = metrics.detectionCount == 0 &&
        metrics.notes.any((n) => n.contains('place furniture on Rig'));
    final title = sizeOnly
        ? 'Last measure · room sized · open Rig'
        : 'Last scan · $pct% confidence · ${metrics.objectCount} objects';
    final note = metrics.notes.isNotEmpty
        ? metrics.notes.first
        : (sizeOnly ? 'Place furniture on Rig.' : 'Ready for Rig + Bench.');
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
    return Row(
      children: [
        Expanded(
          child: _JourneyChip(
            label: '1. Edit Rig',
            color: AppColors.cyan,
            onTap: () => state.setTab(2),
          ),
        ),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: _JourneyChip(
            label: '2. Bench',
            color: AppColors.amber,
            onTap: () => state.setTab(3),
          ),
        ),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: _JourneyChip(
            label: '3. Upgrades',
            color: AppColors.green,
            onTap: () => state.setTab(4),
          ),
        ),
      ],
    );
  }
}

class _JourneyChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _JourneyChip({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800),
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
    return GestureDetector(
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

class _UpgradeSuggestionBanner extends StatelessWidget {
  final ({String category, String name, int index}) suggestion;

  const _UpgradeSuggestionBanner({required this.suggestion});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final label = switch (suggestion.category) {
      'airflow' => 'Airflow',
      'lighting' => 'Lighting',
      'ergonomics' => 'Ergonomics',
      _ => suggestion.category,
    };
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$label looks weak',
                  style: const TextStyle(
                    color: AppColors.amber,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Try ${suggestion.name} on Upgrades to place it on your Rig.',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              state.setBenchmarkMode(suggestion.category);
              state.setTab(4);
            },
            child: const Text('UPGRADES', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
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
              'COMPARE ROOMS',
              style: TextStyle(
                color: AppColors.cyan,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Pick two saved lots to see score deltas and layout changes.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
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
