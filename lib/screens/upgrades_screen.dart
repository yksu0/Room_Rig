// lib/screens/upgrades_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../models/upgrade_catalog.dart';
import '../theme/app_layout.dart';
import '../theme/app_money.dart';
import '../theme/app_theme.dart';
import '../widgets/chrome/adaptive_panel.dart';
import '../widgets/glass_card.dart';
import '../widgets/room_icons.dart';
import '../widgets/score_ring.dart';
import '../widgets/confirm_dialogs.dart';

class UpgradesScreen extends StatelessWidget {
  const UpgradesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final desktop = AppLayout.isDesktop(context);

    if (desktop) {
      final wideDesktop =
          MediaQuery.sizeOf(context).width >= AppLayout.desktopMinWidth;
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(state, desktop: true),
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
                          title: 'Impact',
                          icon: Icons.trending_up_rounded,
                          accent: AppColors.purple,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildImpactPreview(state),
                              const SizedBox(height: AppSpace.sm),
                              Text(
                                UpgradeCatalog.honestyNote,
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
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
                          child: _buildUpgradeList(
                            context,
                            state,
                            // Landscape shell: 3 columns when wide; 2 on compact landscape.
                            columns: wideDesktop ? 3 : 2,
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
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(state),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.screen,
                  0,
                  AppSpace.screen,
                  AppSpace.xxl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildImpactPreview(state),
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      UpgradeCatalog.honestyNote,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: AppSpace.section),
                    _buildUpgradeList(context, state, columns: 2),
                    const SizedBox(height: AppSpace.xxl),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppState state, {bool desktop = false}) {
    final addedCount = state.upgrades.where((u) => u['added'] as bool).length;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        desktop ? AppSpace.lg : AppSpace.screen,
        desktop ? AppSpace.sm : AppSpace.lg,
        desktop ? AppSpace.lg : AppSpace.screen,
        desktop ? AppSpace.xs : AppSpace.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'UPGRADES',
                  style: TextStyle(
                    color: AppColors.cyan,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.8,
                  ),
                ),
                const SizedBox(height: AppSpace.xxs),
                Text(
                  'Component Store',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: desktop ? 20 : 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (addedCount > 0)
            Text(
              '${AppMoney.format(state.upgradesCost)} spent',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (addedCount > 0) const SizedBox(width: 8),
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
                  Text(
                    '$addedCount installed',
                    style: TextStyle(
                      color: AppColors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
              Flexible(
                child: Text(
                  'Upgrade Impact Preview',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!hasUpgrades)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Install an upgrade to drop it onto your Rig layout, then rescore in Bench',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ),
            )
          else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ScoreRing(
                  score: state.airflowScore.clamp(0, 100),
                  size: 75,
                  color: AppColors.airflowColor,
                  label: 'Airflow',
                ),
                ScoreRing(
                  score: state.lightingScore.clamp(0, 100),
                  size: 75,
                  color: AppColors.lightingColor,
                  label: 'Lighting',
                ),
                ScoreRing(
                  score: state.ergonomicsScore.clamp(0, 100),
                  size: 75,
                  color: AppColors.ergonomicsColor,
                  label: 'Ergonomics',
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Catalog tags (not Hub score points). Hub rings use Bench sims / layout impacts.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            _BoostRow(
              label: 'Airflow tag',
              value: state.upgradeAirflowBonus,
              color: AppColors.airflowColor,
            ),
            const SizedBox(height: 6),
            _BoostRow(
              label: 'Lighting tag',
              value: state.upgradeLightingBonus,
              color: AppColors.lightingColor,
            ),
            const SizedBox(height: 6),
            _BoostRow(
              label: 'Ergo tag',
              value: state.upgradeErgonomicsBonus,
              color: AppColors.ergonomicsColor,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUpgradeList(
    BuildContext context,
    AppState state, {
    int columns = 1,
  }) {
    final categories = [
      ('airflow', 'Airflow', AppColors.airflowColor, RoomSvg.airflow),
      ('lighting', 'Lighting', AppColors.lightingColor, RoomSvg.lightbulb),
      ('ergonomics', 'Ergonomics', AppColors.ergonomicsColor, RoomSvg.ergonomics),
    ];

    // Category-per-column when we have room for all three domains.
    if (columns >= 3) {
      Widget categoryColumn((String, String, Color, String) cat) {
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
                    style: TextStyle(
                      color: cat.$3,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            ...items.map((entry) {
              final i = entry.key;
              final u = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _UpgradeCard(
                  upgrade: u,
                  isAdded: u['added'] as bool,
                  categoryColor: cat.$3,
                  categoryLabel: cat.$2,
                  onToggle: () => _toggleUpgrade(context, state, i, u, cat.$3),
                ),
              );
            }),
          ],
        );
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < categories.length; i++) ...[
            if (i > 0) const SizedBox(width: 14),
            Expanded(child: categoryColumn(categories[i])),
          ],
        ],
      );
    }

    // Portrait / compact landscape: stacked categories, 2-column card grid.
    final gridCols = columns.clamp(1, 2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final cat in categories) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                SvgIcon(cat.$4, size: 16, color: cat.$3),
                const SizedBox(width: 8),
                Text(
                  cat.$2.toUpperCase(),
                  style: TextStyle(
                    color: cat.$3,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final items = state.upgrades
                  .asMap()
                  .entries
                  .where((e) => e.value['type'] == cat.$1)
                  .toList();
              if (gridCols <= 1) {
                return Column(
                  children: [
                    for (final entry in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _UpgradeCard(
                          upgrade: entry.value,
                          isAdded: entry.value['added'] as bool,
                          categoryColor: cat.$3,
                          categoryLabel: cat.$2,
                          onToggle: () => _toggleUpgrade(
                            context,
                            state,
                            entry.key,
                            entry.value,
                            cat.$3,
                          ),
                        ),
                      ),
                  ],
                );
              }
              final gap = 10.0;
              final cardW = (constraints.maxWidth - gap) / 2;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final entry in items)
                    SizedBox(
                      width: cardW,
                      child: _UpgradeCard(
                        upgrade: entry.value,
                        isAdded: entry.value['added'] as bool,
                        categoryColor: cat.$3,
                        categoryLabel: cat.$2,
                        compact: true,
                        onToggle: () => _toggleUpgrade(
                          context,
                          state,
                          entry.key,
                          entry.value,
                          cat.$3,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Future<void> _toggleUpgrade(
    BuildContext context,
    AppState state,
    int i,
    Map<String, dynamic> u,
    Color categoryColor,
  ) async {
    final adding = !(u['added'] as bool);
    if (!adding) {
      final ok = await confirmAction(
        context,
        title: 'Remove ${u['name']}?',
        body: 'This removes the upgrade from your Rig layout.',
        confirmLabel: 'Remove',
        danger: true,
      );
      if (!ok || !context.mounted) return;
    }
    final ok = state.toggleUpgrade(i, pending: adding);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No free cell — move furniture in Rig first'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (adding) {
      state.setTab(2);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          adding
              ? '${u['name']} — drag the ghost on Rig, then Place'
              : '${u['name']} removed from Rig',
        ),
        backgroundColor: categoryColor.withValues(alpha: 0.9),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'OPEN RIG',
          textColor: Colors.black,
          onPressed: () => state.setTab(2),
        ),
      ),
    );
  }
}

class _UpgradeCard extends StatelessWidget {
  final Map<String, dynamic> upgrade;
  final bool isAdded;
  final Color categoryColor;
  final String categoryLabel;
  final VoidCallback onToggle;
  final bool compact;

  const _UpgradeCard({
    required this.upgrade,
    required this.isAdded,
    required this.categoryColor,
    required this.categoryLabel,
    required this.onToggle,
    this.compact = false,
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
        padding: EdgeInsets.all(compact ? AppSpace.sm : AppSpace.md),
        decoration: BoxDecoration(
          color: isAdded ? categoryColor.withValues(alpha: 0.1) : AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: isAdded ? categoryColor : AppColors.border,
            width: isAdded ? 1.5 : 1,
          ),
          boxShadow: isAdded
              ? AppColors.activeGlow(categoryColor, blur: 16, alpha: 0.22)
              : null,
        ),
        child: compact
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: categoryColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: categoryColor.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            categoryLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: categoryColor,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      SvgIcon(
                        isAdded ? RoomSvg.checkCircle : RoomSvg.add,
                        size: 16,
                        color: isAdded ? categoryColor : AppColors.textMuted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    upgrade['name'] as String,
                    maxLines: 2,
                    softWrap: true,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppMoney.format((upgrade['price'] as num?) ?? 0),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.cyan,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: categoryColor.withValues(alpha: isAdded ? 0.2 : 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: categoryColor.withValues(alpha: 0.3)),
                    ),
                    child: Center(
                      child: SvgIcon(
                        upgradeSvgFor(upgrade['iconName'] as String),
                        size: 22,
                        color: categoryColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                upgrade['name'] as String,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: categoryColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: categoryColor.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                categoryLabel,
                                style: TextStyle(
                                  color: categoryColor,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpace.xxs),
                        Text(
                          upgrade['desc'] as String,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: AppSpace.xs),
                        Row(
                          children: [
                            Text(
                              AppMoney.format((upgrade['price'] as num?) ?? 0),
                              style: const TextStyle(
                                color: AppColors.cyan,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: AppSpace.xs),
                            if (isAdded)
                              Text(
                                'Installed',
                                style: TextStyle(
                                  color: categoryColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpace.xs),
                        Row(
                          children: [
                            if (airBoost > 0)
                              _SmallBoost(
                                label: 'Air',
                                value: airBoost,
                                color: AppColors.airflowColor,
                              ),
                            if (airBoost > 0 && (lightBoost > 0 || ergoBoost > 0))
                              const SizedBox(width: 6),
                            if (lightBoost > 0)
                              _SmallBoost(
                                label: 'Light',
                                value: lightBoost,
                                color: AppColors.lightingColor,
                              ),
                            if (lightBoost > 0 && ergoBoost > 0)
                              const SizedBox(width: 6),
                            if (ergoBoost > 0)
                              _SmallBoost(
                                label: 'Ergo',
                                value: ergoBoost,
                                color: AppColors.ergonomicsColor,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isAdded
                          ? categoryColor.withValues(alpha: 0.2)
                          : AppColors.surfaceAlt,
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
  const _SmallBoost({
    required this.label,
    required this.value,
    required this.color,
  });

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
  const _BoostRow({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ),
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
          '+${value.toInt()}',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
