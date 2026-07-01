// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../models/room_model.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/room_icons.dart';
import '../widgets/score_ring.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

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
              _buildHeader(context, room),
              const SizedBox(height: 20),
              _buildScoreSection(context, state),
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

  Widget _buildHeader(BuildContext context, RoomData room) {
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
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.accentGradient,
            boxShadow: [
              BoxShadow(color: AppColors.cyan.withValues(alpha: 0.3), blurRadius: 20),
            ],
          ),
          child: SvgIcon(presetSvgFor(room.name), size: 26, color: Colors.white),
        ),
      ],
    );
  }

  Widget _buildScoreSection(BuildContext context, AppState state) {
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
              ScoreRing(score: state.airflowScore, size: 80, color: AppColors.airflowColor, label: 'Airflow'),
              ScoreRing(score: state.overallScore, size: 110, color: AppColors.cyan, label: 'Overall'),
              ScoreRing(score: state.lightingScore, size: 80, color: AppColors.lightingColor, label: 'Lighting'),
            ],
          ),
          const SizedBox(height: 16),
          ScoreRing(score: state.ergonomicsScore, size: 70, color: AppColors.ergonomicsColor, label: 'Ergonomics'),
        ],
      ),
    );
  }

  Widget _buildPresetSelector(BuildContext context, AppState state) {
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
                onTap: () => state.selectPreset(p.$1),
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
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                svgString: RoomSvg.scan,
                label: 'Scan Room',
                color: AppColors.cyan,
                onTap: () => context.read<AppState>().setTab(1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionButton(
                svgString: RoomSvg.tune,
                label: 'Customize',
                color: AppColors.purple,
                onTap: () => context.read<AppState>().setTab(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionButton(
                svgString: RoomSvg.speedometer,
                label: 'Benchmark',
                color: AppColors.amber,
                onTap: () => context.read<AppState>().setTab(3),
              ),
            ),
          ],
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
              _SpecRow(svgString: RoomSvg.home, label: 'Rig Name', value: state.currentRoomData.name),
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
                valueColor: AppColors.green,
              ),
            ],
          ),
        ),
      ],
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

  const _SpecRow({required this.svgString, required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
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
      ],
    );
  }
}
