import 'package:flutter/material.dart';

import '../models/room_model.dart';
import '../models/surface_mount.dart';
import '../theme/app_theme.dart';

/// Whether Auto-Rig / Benchmark Improved will leave this piece where it is.
bool autoRigPinsItem(FurnitureItem item) =>
    item.locked || SurfaceMounts.isStructuralMount(item);

String autoRigPinReason(FurnitureItem item) {
  if (SurfaceMounts.isStructuralMount(item)) return 'Door/window';
  if (item.locked) return 'Locked by you';
  return 'Pinned';
}

/// Lists what Auto-Rig will not move vs what it can rearrange.
class AutoRigLockSummary extends StatelessWidget {
  const AutoRigLockSummary({
    super.key,
    required this.furniture,
    this.compact = false,
  });

  final List<FurnitureItem> furniture;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final visible = furniture.where((f) => !f.hidden).toList(growable: false);
    if (visible.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 4 : 8),
        child: Text(
          'No furniture yet — add items on the Room.',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: compact ? 11 : 12,
          ),
        ),
      );
    }

    final pinned = visible.where(autoRigPinsItem).toList(growable: false);
    final movable = visible.where((f) => !autoRigPinsItem(f)).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AUTO-ROOM WILL NOT MOVE',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        if (pinned.isEmpty)
          Text(
            'Nothing pinned — every piece can be rearranged.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: compact ? 11 : 12),
          )
        else
          ...pinned.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(
                    SurfaceMounts.isStructuralMount(item)
                        ? Icons.door_front_door_outlined
                        : Icons.lock_rounded,
                    size: 14,
                    color: AppColors.amber,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${item.name} · ${autoRigPinReason(item)}',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: compact ? 11 : 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        SizedBox(height: compact ? 8 : 10),
        Text(
          'CAN BE REARRANGED',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          movable.isEmpty
              ? 'All items are pinned.'
              : '${movable.length} item${movable.length == 1 ? '' : 's'}: '
                  '${movable.take(compact ? 4 : 8).map((f) => f.name).join(', ')}'
                  '${movable.length > (compact ? 4 : 8) ? '…' : ''}',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: compact ? 11 : 12,
            height: 1.35,
          ),
        ),
        SizedBox(height: compact ? 6 : 8),
        Text(
          'Lock an item on the Room to keep it fixed when you rearrange or run Benchmark Improved.',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: compact ? 10 : 11,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}
