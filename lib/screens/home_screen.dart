// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/app_state.dart';
import '../models/room_model.dart';
import '../models/room_scale.dart';
import '../models/scan_layout_model.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/onboarding_sheet.dart';
import '../widgets/room_icons.dart';
import '../widgets/score_ring.dart';

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

  Future<void> _confirmSelectPreset(
    BuildContext context,
    AppState state,
    RoomPreset preset,
  ) async {
    if (preset == state.selectedPreset) return;
    final hasWork = state.hasLayoutWork;
    if (hasWork) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Replace current layout?', style: TextStyle(color: AppColors.textPrimary)),
          content: const Text(
            'This saves your current room and starts a new lot from the preset.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Load preset')),
          ],
        ),
      );
      if (ok != true) return;
    }
    state.selectPreset(preset);
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
          content: const Text(
            'Unsaved layout changes on this room may be lost.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Switch')),
          ],
        ),
      );
      if (ok != true) return;
    }
    state.loadSavedRoom(roomId);
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
      const SnackBar(content: Text('Original layout restored')),
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
        onJumpTab: (tab) => state.setTab(tab),
      ),
    );
    if (mounted) state.completeOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final room = state.currentRoomData;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, room, state),
              const SizedBox(height: 20),
              if (!state.roomIsReady) ...[
                _GettingStartedBanner(
                  onScan: () => state.setTab(1),
                  onCreate: () => _showCreateRoomSheet(context, state),
                ),
                const SizedBox(height: 16),
              ] else if (state.scanComplete && state.lastScanConfidence != null) ...[
                _ScanConfidenceBanner(metrics: state.lastScanConfidence!),
                const SizedBox(height: 12),
                _JourneySteps(state: state),
                const SizedBox(height: 16),
              ] else if (state.roomIsReady) ...[
                _ManualRoomBanner(state: state),
                const SizedBox(height: 12),
                _JourneySteps(state: state),
                const SizedBox(height: 16),
              ],
              _buildScoreSection(context, state),
              const SizedBox(height: 24),
              _buildMyRooms(context, state),
              const SizedBox(height: 24),
              _buildPresetSelector(context, state),
              const SizedBox(height: 24),
              _buildQuickActions(context, state),
              const SizedBox(height: 24),
              _buildMetricsRow(context, state),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, RoomData room, AppState state) {
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
                fontWeight: FontWeight.w700,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 4),
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
                  onDone: () => Navigator.of(ctx).pop(),
                  onJumpTab: (tab) {
                    Navigator.of(ctx).pop();
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
    return GlassCard(
      gradient: const LinearGradient(
        colors: [Color(0xFF1A1E32), Color(0xFF0E1020)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        children: [
          Row(
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
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (simulated ? AppColors.amber : AppColors.green).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: (simulated ? AppColors.amber : AppColors.green).withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  simulated ? 'ROUGH EST.' : 'BENCH OK',
                  style: TextStyle(
                    color: simulated ? AppColors.amber : AppColors.green,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.cyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
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
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _tappableRing(state, 'airflow', state.airflowScore, 70, AppColors.airflowColor, 'Airflow'),
              ScoreRing(score: state.overallScore, size: 104, color: AppColors.cyan, label: 'Overall'),
              _tappableRing(state, 'lighting', state.lightingScore, 70, AppColors.lightingColor, 'Lighting'),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _tappableRing(state, 'ergonomics', state.ergonomicsScore, 64, AppColors.ergonomicsColor, 'Ergo'),
              _tappableRing(state, 'spatial', state.spatialScore, 64, AppColors.spatialColor, 'Space'),
            ],
          ),
        ],
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
            selected: r.id == state.activeRoomId,
            onTap: () => _confirmLoadSavedRoom(context, state, r.id),
            onDuplicate: () async {
              if (r.id != state.activeRoomId) {
                await _confirmLoadSavedRoom(context, state, r.id);
                if (!context.mounted) return;
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

  Widget _buildPresetSelector(BuildContext context, AppState state) {
    if (state.hasLayoutWork) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ROOM PRESETS',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _showPresetPicker(context, state),
            child: const Text('Start new from preset…'),
          ),
        ],
      );
    }
    return _buildPresetGrid(context, state);
  }

  Future<void> _showPresetPicker(BuildContext context, AppState state) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Load preset',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 12),
            _buildPresetGrid(context, state),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetGrid(BuildContext context, AppState state) {
    final presets = [
      (RoomPreset.gamingSetup, RoomSvg.gaming, 'Gaming'),
      (RoomPreset.homeOffice, RoomSvg.briefcase, 'Office'),
      (RoomPreset.studioApartment, RoomSvg.house, 'Studio'),
      (RoomPreset.minimalistBedroom, RoomSvg.moon, 'Zen'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ROOM PRESETS',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: presets.map((p) {
            final isSelected = state.selectedPreset == p.$1;
            return Expanded(
              child: GestureDetector(
                onTap: () => _confirmSelectPreset(context, state, p.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.cyan.withValues(alpha: 0.15) : AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? AppColors.cyan : AppColors.border,
                      width: isSelected ? 1.5 : 1,
                    ),
                    boxShadow: isSelected
                        ? [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.2), blurRadius: 12)]
                        : [],
                  ),
                  child: Column(
                    children: [
                      SvgIcon(p.$2, size: 24, color: isSelected ? AppColors.cyan : AppColors.textSecondary),
                      const SizedBox(height: 6),
                      Text(
                        p.$3,
                        style: TextStyle(
                          color: isSelected ? AppColors.cyan : AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
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
                svgString: RoomSvg.scan,
                label: 'Scan Room',
                color: AppColors.cyan,
                onTap: () => context.read<AppState>().setTab(1),
              ),
              _ActionButton(
                svgString: RoomSvg.home,
                label: 'Create',
                color: AppColors.purple,
                onTap: () => _showCreateRoomSheet(context, state),
              ),
              _ActionButton(
                svgString: RoomSvg.tune,
                label: 'Customize',
                color: AppColors.purple,
                onTap: () => context.read<AppState>().setTab(2),
              ),
              _ActionButton(
                svgString: RoomSvg.speedometer,
                label: 'Benchmark',
                color: AppColors.amber,
                onTap: () => context.read<AppState>().setTab(3),
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

  Widget _buildMetricsRow(BuildContext context, AppState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                  label: 'Compare',
                  value: 'Original saved',
                  valueColor: AppColors.cyan,
                  onTap: () {
                    state.setBenchmarkMode('airflow');
                    state.setTab(3);
                  },
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  if (state.hasCompareSnapshot)
                    TextButton(
                      onPressed: () => _confirmRestoreOriginal(context, state),
                      child: const Text('Restore original'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Share.share(state.buildShareReport(), subject: 'Room Rig report'),
                    child: const Text('Share report'),
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
    final nameCtrl = TextEditingController(text: 'My Room');
    var length = 3.6;
    var width = 4.8;
    var height = 2.7;
    final created = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
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
                    'Fallback when the camera cannot scan. Empty rectangle plus a door and window.',
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
                  const SizedBox(height: 8),
                  _MeterSlider(
                    label: 'Length',
                    value: length,
                    onChanged: (v) => setLocal(() => length = v),
                  ),
                  _MeterSlider(
                    label: 'Width',
                    value: width,
                    onChanged: (v) => setLocal(() => width = v),
                  ),
                  _MeterSlider(
                    label: 'Height',
                    value: height,
                    min: 2.2,
                    max: 3.6,
                    onChanged: (v) => setLocal(() => height = v),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
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
              );
            },
          ),
        );
      },
    );
    nameCtrl.dispose();
    if (created == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Created ${state.currentRoomData.name}'),
          action: SnackBarAction(
            label: 'OPEN RIG',
            onPressed: () => state.setTab(2),
          ),
        ),
      );
    }
  }
}

class _GettingStartedBanner extends StatelessWidget {
  final VoidCallback onScan;
  final VoidCallback onCreate;
  const _GettingStartedBanner({required this.onScan, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cyan.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          SvgIcon(RoomSvg.scan, size: 22, color: AppColors.cyan),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'No scan loaded yet',
                  style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 13),
                ),
                const SizedBox(height: 3),
                Text(
                  'Scan if the camera works, or create a room by hand.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              GestureDetector(
                onTap: onScan,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Scan', style: TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w800, fontSize: 12)),
                ),
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: onCreate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.purple.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Create', style: TextStyle(color: AppColors.purple, fontWeight: FontWeight.w800, fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
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
    final note = metrics.notes.isNotEmpty ? metrics.notes.first : 'Ready for Rig + Bench.';
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
                  'Last scan · $pct% confidence · ${metrics.objectCount} objects',
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
            color: AppColors.purple,
            onTap: () => state.setTab(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _JourneyChip(
            label: '2. Bench',
            color: AppColors.amber,
            onTap: () => state.setTab(3),
          ),
        ),
        const SizedBox(width: 8),
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
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
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
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 15)],
        ),
        child: Column(
          children: [
            SvgIcon(svgString, size: 26, color: color),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
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
        Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
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

class _MeterSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _MeterSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 2.6,
    this.max = 8.5,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            RoomScale.formatMeters(value),
            textAlign: TextAlign.right,
            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _RoomSlotTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDuplicate;
  final VoidCallback? onDelete;

  const _RoomSlotTile({
    required this.title,
    required this.subtitle,
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
          title: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
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
