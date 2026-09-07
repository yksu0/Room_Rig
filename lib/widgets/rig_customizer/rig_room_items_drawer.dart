// lib/widgets/rig_customizer/rig_room_items_drawer.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../models/scan_layout_model.dart';
import '../../models/surface_mount.dart';
import '../../theme/app_theme.dart';
import '../empty_state.dart';
import '../room_icons.dart';
import '../confirm_dialogs.dart';
import 'rig_scan_action_button.dart';

Color _categoryColor(String cat) {
  switch (cat) {
    case 'airflow':
      return AppColors.airflowColor;
    case 'lighting':
      return AppColors.lightingColor;
    case 'ergonomics':
      return AppColors.ergonomicsColor;
    default:
      return AppColors.textMuted;
  }
}

/// End drawer listing layout items and scan-detected objects with filters.
class RigRoomItemsDrawer extends StatelessWidget {
  final String sidebarQuery;
  final String? sidebarCategory;
  final double sidebarMinConfidence;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<double> onMinConfidenceChanged;
  final Future<void> Function(ScanObject obj) onReplaceScanObject;
  final void Function(ScanObject obj) onDeleteScanObject;

  const RigRoomItemsDrawer({
    super.key,
    required this.sidebarQuery,
    required this.sidebarCategory,
    required this.sidebarMinConfidence,
    required this.onQueryChanged,
    required this.onCategoryChanged,
    required this.onMinConfidenceChanged,
    required this.onReplaceScanObject,
    required this.onDeleteScanObject,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scanObjects = state.detectedScanObjects;
    final q = sidebarQuery.trim().toLowerCase();
    bool matchesQuery(String name, String category, String id) {
      if (q.isEmpty) return true;
      return name.toLowerCase().contains(q) ||
          category.toLowerCase().contains(q) ||
          id.toLowerCase().contains(q);
    }

    bool matchesCategory(String category) {
      final filter = sidebarCategory;
      if (filter == null) return true;
      return category.toLowerCase() == filter;
    }

    final layoutItems = state.furniture.where((item) {
      if (!matchesQuery(item.name, item.category, item.id)) return false;
      if (!matchesCategory(item.category)) return false;
      final conf = state.confidenceForFurniture(item.id) ?? 0.95;
      return conf >= sidebarMinConfidence;
    }).toList(growable: false);

    final filteredScan = scanObjects.where((obj) {
      if (!matchesQuery(obj.label, obj.category, obj.id)) return false;
      if (!matchesCategory(obj.category)) return false;
      return obj.confidence >= sidebarMinConfidence;
    }).toList(growable: false);

    return Drawer(
      backgroundColor: AppColors.surface,
      width: 320,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
              child: Row(
                children: [
                  Text(
                    'ROOM ITEMS',
                    style: TextStyle(color: AppColors.cyan, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2),
                  ),
                  const Spacer(),
                  Text(
                    '${layoutItems.length + filteredScan.length}/${state.furniture.length + scanObjects.length}',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: TextField(
                onChanged: onQueryChanged,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search name or category',
                  hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  prefixIcon: Icon(Icons.search_rounded, color: AppColors.textMuted, size: 18),
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.cyan.withValues(alpha: 0.7)),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final cat in const [null, 'airflow', 'lighting', 'ergonomics', 'neutral'])
                    _SidebarFilterChip(
                      label: cat ?? 'All',
                      active: sidebarCategory == cat,
                      onTap: () => onCategoryChanged(cat),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final entry in const [
                    (0.0, 'Any %'),
                    (0.5, '≥50%'),
                    (0.7, '≥70%'),
                    (0.85, '≥85%'),
                  ])
                    _SidebarFilterChip(
                      label: entry.$2,
                      active: (sidebarMinConfidence - entry.$1).abs() < 0.001,
                      onTap: () => onMinConfidenceChanged(entry.$1),
                    ),
                ],
              ),
            ),
            const Divider(color: AppColors.border, height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
                children: [
                  Text(
                    'LAYOUT ITEMS',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 8),
                  if (layoutItems.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text('No layout items match filters.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    )
                  else
                    ...layoutItems.map((item) {
                      final isSelected = state.selectedItemId == item.id && !state.selectedIsScanObject;
                      final catColor = _categoryColor(item.category);
                      final conf = state.confidenceForFurniture(item.id);
                      final confLabel = conf == null ? '—' : '${(conf * 100).round()}%';
                      final canDelete = item.iconName != 'door' &&
                          item.iconName != 'window' &&
                          (state.invasiveEdit || !SurfaceMounts.isStructuralMount(item));
                      final structuralFixed =
                          !state.invasiveEdit && SurfaceMounts.isStructuralMount(item);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isSelected ? catColor.withValues(alpha: 0.12) : AppColors.card,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? catColor : AppColors.border,
                              width: isSelected ? 1.4 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              GestureDetector(
                                onTap: () {
                                  state.selectFurniture(item.id, toggle: true);
                                  Navigator.of(context).pop();
                                },
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: catColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Center(
                                        child: Opacity(
                                          opacity: item.hidden ? 0.35 : 1,
                                          child: SvgIcon(
                                            furnitureSvgFor(item.iconName),
                                            size: 18,
                                            color: catColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(item.name, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                                          const SizedBox(height: 3),
                                          Text(
                                            '${item.category.toUpperCase()}  •  ${item.statusLabel}  •  $confLabel'
                                            '${structuralFixed ? '  •  FIXED' : ''}',
                                            style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (item.locked || structuralFixed)
                                      const Padding(
                                        padding: EdgeInsets.only(right: 4),
                                        child: Icon(Icons.lock_rounded, size: 14, color: AppColors.amber),
                                      ),
                                    if (item.hidden)
                                      const Icon(Icons.visibility_off_rounded, size: 14, color: AppColors.textMuted),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  RigScanActionButton(
                                    icon: item.hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                                    label: item.hidden ? 'Show' : 'Hide',
                                    color: AppColors.textSecondary,
                                    onTap: () => state.toggleFurnitureHidden(item.id),
                                  ),
                                  const SizedBox(width: 6),
                                  RigScanActionButton(
                                    icon: item.locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                                    label: item.locked ? 'Unlock' : 'Lock',
                                    color: item.locked ? AppColors.amber : AppColors.textSecondary,
                                    onTap: () => state.toggleFurnitureLock(item.id),
                                  ),
                                  const SizedBox(width: 6),
                                  RigScanActionButton(
                                    icon: Icons.copy_rounded,
                                    label: 'Dup',
                                    color: AppColors.cyan,
                                    onTap: () {
                                      state.duplicateFurniture(item.id);
                                      Navigator.of(context).pop();
                                    },
                                  ),
                                  if (canDelete) ...[
                                    const SizedBox(width: 6),
                                    RigScanActionButton(
                                      icon: Icons.delete_outline_rounded,
                                      label: 'Del',
                                      color: AppColors.red,
                                      onTap: () async {
                                        final ok = await confirmAction(
                                          context,
                                          title: 'Delete ${item.name}?',
                                          body: 'This removes the item from your Rig. Use Undo in the Rig header if you change your mind.',
                                          confirmLabel: 'Delete',
                                          danger: true,
                                        );
                                        if (!ok || !context.mounted) return;
                                        state.deleteFurniture(item.id);
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 6),
                  Text(
                    'SCAN OBJECTS',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 8),
                  if (filteredScan.isEmpty)
                    EmptyState(
                      iconSvg: RoomSvg.scan,
                      title: scanObjects.isEmpty ? 'No scan objects yet' : 'No matches',
                      message: scanObjects.isEmpty
                          ? 'Run a room scan to detect furniture with confidence scores. Layout items stay available above.'
                          : 'Try a different filter.',
                      actionLabel: scanObjects.isEmpty ? 'Go to Scan' : null,
                      onAction: scanObjects.isEmpty
                          ? () {
                              Navigator.of(context).pop();
                              state.setTab(1);
                            }
                          : null,
                    )
                  else
                    ...filteredScan.map((obj) {
                      final isSelected = state.selectedItemId == obj.id && state.selectedIsScanObject;
                      final catColor = _categoryColor(obj.category);
                      final status = [
                        if (obj.hidden) 'Hidden',
                        if (obj.locked) 'Locked',
                        if (!obj.hidden && !obj.locked) 'Active',
                      ].join(' · ');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isSelected ? catColor.withValues(alpha: 0.12) : AppColors.card,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? catColor : catColor.withValues(alpha: 0.55),
                              width: isSelected ? 1.4 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              GestureDetector(
                                onTap: () {
                                  state.selectScanObject(obj.id, toggle: true);
                                  Navigator.of(context).pop();
                                },
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: catColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Center(
                                        child: Opacity(
                                          opacity: obj.hidden ? 0.35 : 1,
                                          child: Icon(Icons.view_in_ar_rounded, size: 18, color: catColor),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(obj.label, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                                          const SizedBox(height: 3),
                                          Text(
                                            '${obj.category.toUpperCase()}  •  $status',
                                            style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppColors.green.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '${(obj.confidence * 100).round()}%',
                                        style: TextStyle(color: AppColors.green, fontSize: 10, fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  RigScanActionButton(
                                    icon: obj.hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                                    label: obj.hidden ? 'Show' : 'Hide',
                                    color: AppColors.textSecondary,
                                    onTap: () => state.toggleDetectedScanObjectHidden(obj.id),
                                  ),
                                  const SizedBox(width: 6),
                                  RigScanActionButton(
                                    icon: obj.locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                                    label: obj.locked ? 'Unlock' : 'Lock',
                                    color: obj.locked ? AppColors.amber : AppColors.textSecondary,
                                    onTap: () => state.toggleDetectedScanObjectLock(obj.id),
                                  ),
                                  const SizedBox(width: 6),
                                  RigScanActionButton(
                                    icon: Icons.copy_rounded,
                                    label: 'Dup',
                                    color: AppColors.cyan,
                                    onTap: () {
                                      state.duplicateDetectedScanObject(obj.id);
                                      Navigator.of(context).pop();
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  RigScanActionButton(
                                    icon: Icons.swap_horiz_rounded,
                                    label: 'Replace',
                                    color: AppColors.cyan,
                                    onTap: () => onReplaceScanObject(obj),
                                  ),
                                  const SizedBox(width: 6),
                                  RigScanActionButton(
                                    icon: Icons.delete_outline_rounded,
                                    label: 'Del',
                                    color: AppColors.red,
                                    onTap: () async {
                                      final ok = await confirmAction(
                                        context,
                                        title: 'Delete ${obj.label}?',
                                        body: 'You can undo from the snackbar after delete.',
                                        confirmLabel: 'Delete',
                                        danger: true,
                                      );
                                      if (!ok || !context.mounted) return;
                                      onDeleteScanObject(obj);
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarFilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _SidebarFilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AppColors.cyan.withValues(alpha: 0.18) : AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? AppColors.cyan.withValues(alpha: 0.6) : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? AppColors.cyan : AppColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}