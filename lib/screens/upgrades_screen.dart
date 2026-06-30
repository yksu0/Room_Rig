// lib/screens/upgrades_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/room_icons.dart';
import '../widgets/score_ring.dart';

class UpgradesScreen extends StatelessWidget {
  const UpgradesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(state),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildImpactPreview(state),
                    const SizedBox(height: 24),
                    _buildUpgradeList(context, state),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppState state) {
    final addedCount = state.upgrades.where((u) => u['added'] as bool).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('UPGRADES', style: TextStyle(color: AppColors.cyan, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 3)),
              const Text('Component Store', style: TextStyle(color: AppColors.textPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
            ],
          ),
          const Spacer(),
          if (addedCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.green.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  SvgIcon(RoomSvg.checkCircle, size: 14, color: AppColors.green),
                  const SizedBox(width: 5),
                  Text('$addedCount installed', style: TextStyle(color: AppColors.green, fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImpactPreview(AppState state) {
    final hasUpgrades = state.upgrades.any((u) => u['added'] as bool);
    return GlassCard(
      gradient: const LinearGradient(
        colors: [Color(0xFF0F1A2A), Color(0xFF0A0E1A)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderColor: AppColors.purple.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SvgIcon(RoomSvg.trendingUp, size: 18, color: AppColors.purple),
              const SizedBox(width: 8),
              Text(
                'Upgrade Impact Preview',
                style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!hasUpgrades)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Install upgrades below to see score impact',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ),
            )
          else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ScoreRing(
                  score: (state.airflowScore + state.upgradeAirflowBonus).clamp(0, 100),
                  size: 75,
                  color: AppColors.airflowColor,
                  label: 'Airflow',
                ),
                ScoreRing(
                  score: (state.lightingScore + state.upgradeLightingBonus).clamp(0, 100),
                  size: 75,
                  color: AppColors.lightingColor,
                  label: 'Lighting',
                ),
                ScoreRing(
                  score: (state.ergonomicsScore + state.upgradeErgonomicsBonus).clamp(0, 100),
                  size: 75,
                  color: AppColors.ergonomicsColor,
                  label: 'Ergonomics',
                ),
              ],
            ),
            const SizedBox(height: 16),
            _BoostRow(label: 'Airflow boost', value: state.upgradeAirflowBonus, color: AppColors.airflowColor),
            const SizedBox(height: 6),
            _BoostRow(label: 'Lighting boost', value: state.upgradeLightingBonus, color: AppColors.lightingColor),
            const SizedBox(height: 6),
            _BoostRow(label: 'Ergonomics boost', value: state.upgradeErgonomicsBonus, color: AppColors.ergonomicsColor),
          ],
        ],
      ),
    );
  }

  Widget _buildUpgradeList(BuildContext context, AppState state) {
    final categories = [
      ('airflow', 'Airflow', AppColors.airflowColor, RoomSvg.airflow),
      ('lighting', 'Lighting', AppColors.lightingColor, RoomSvg.lightbulb),
      ('ergonomics', 'Ergonomics', AppColors.ergonomicsColor, RoomSvg.ergonomics),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: categories.map((cat) {
        final items = state.upgrades
            .asMap()
            .entries
            .where((e) => e.value['type'] == cat.$1)
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  SvgIcon(cat.$4, size: 16, color: cat.$3),
                  const SizedBox(width: 8),
                  Text(
                    cat.$2.toUpperCase(),
                    style: TextStyle(color: cat.$3, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2),
                  ),
                ],
              ),
            ),
            ...items.map((entry) {
              final i = entry.key;
              final u = entry.value;
              final isAdded = u['added'] as bool;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _UpgradeCard(
                  upgrade: u,
                  isAdded: isAdded,
                  categoryColor: cat.$3,
                  onToggle: () => state.toggleUpgrade(i),
                ),
              );
            }),
            const SizedBox(height: 16),
          ],
        );
      }).toList(),
    );
  }
}

class _UpgradeCard extends StatelessWidget {
  final Map<String, dynamic> upgrade;
  final bool isAdded;
  final Color categoryColor;
  final VoidCallback onToggle;

  const _UpgradeCard({
    required this.upgrade,
    required this.isAdded,
    required this.categoryColor,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final airBoost = upgrade['airflowBoost'] as double;
    final lightBoost = upgrade['lightingBoost'] as double;
    final ergoBoost = upgrade['ergonomicsBoost'] as double;

    return GestureDetector(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isAdded ? categoryColor.withValues(alpha: 0.1) : AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isAdded ? categoryColor : AppColors.border,
            width: isAdded ? 1.5 : 1,
          ),
          boxShadow: isAdded ? [BoxShadow(color: categoryColor.withValues(alpha: 0.15), blurRadius: 16)] : [],
        ),
        child: Row(
          children: [
            // Icon box
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: categoryColor.withValues(alpha: isAdded ? 0.2 : 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: categoryColor.withValues(alpha: 0.3)),
              ),
              child: Center(
                child: SvgIcon(upgradeSvgFor(upgrade['iconName'] as String), size: 22, color: categoryColor),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    upgrade['name'] as String,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    upgrade['desc'] as String,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (airBoost > 0) _SmallBoost(label: 'Air', value: airBoost, color: AppColors.airflowColor),
                      if (airBoost > 0 && (lightBoost > 0 || ergoBoost > 0)) const SizedBox(width: 4),
                      if (lightBoost > 0) _SmallBoost(label: 'Light', value: lightBoost, color: AppColors.lightingColor),
                      if (lightBoost > 0 && ergoBoost > 0) const SizedBox(width: 4),
                      if (ergoBoost > 0) _SmallBoost(label: 'Ergo', value: ergoBoost, color: AppColors.ergonomicsColor),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Add / Remove toggle
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isAdded ? categoryColor.withValues(alpha: 0.2) : AppColors.surfaceAlt,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isAdded ? categoryColor : AppColors.border,
                  width: 1.5,
                ),
              ),
              child: Center(
                child: isAdded
                    ? SvgIcon(RoomSvg.checkCircle, size: 18, color: categoryColor)
                    : SvgIcon(RoomSvg.add, size: 18, color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallBoost extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _SmallBoost({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label +${value.toInt()}',
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _BoostRow extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _BoostRow({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 110, child: Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 12))),
        Expanded(
          child: LinearProgressIndicator(
            value: (value / 50).clamp(0.0, 1.0),
            backgroundColor: AppColors.border,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 4,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '+${value.toInt()} pts',
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}
