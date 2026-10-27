import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../theme/app_theme.dart';
import 'app_snack_bar.dart';

Future<void> showRoomSwitchSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => const _RoomSwitchSheetBody(),
  );
}

class _RoomSwitchSheetBody extends StatelessWidget {
  const _RoomSwitchSheetBody();

  Future<void> _switchTo(BuildContext context, AppState state, String id) async {
    if (id == state.activeRoomId) {
      Navigator.pop(context);
      return;
    }
    if (state.hasLayoutWork) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dCtx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Switch room?', style: TextStyle(color: AppColors.textPrimary)),
          content: Text(
            state.isScanSessionActive
                ? 'Switching cancels the in-progress scan, saves this lot, then opens the other room.'
                : 'This room will be saved to My Rooms, then you will switch.',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('Switch')),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
    }
    final notice = state.loadSavedRoom(id);
    if (context.mounted) {
      Navigator.pop(context);
      if (notice != null) {
        showAppSnackBar(context, message: notice);
      }
    }
  }

  Future<void> _rename(BuildContext context, AppState state) async {
    final ctrl = TextEditingController(text: state.currentRoomData.name);
    final next = await showDialog<String>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Rename room', style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (next == null || next.isEmpty || !context.mounted) return;
    state.renameActiveRoom(next);
  }

  Future<void> _newRoom(BuildContext context, AppState state) async {
    if (state.hasLayoutWork) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dCtx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Create new room?', style: TextStyle(color: AppColors.textPrimary)),
          content: const Text(
            'Your current lot is saved first. New room starts empty with a door and window.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('Create')),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
    }
    final ctrl = TextEditingController(text: 'My Room');
    final name = await showDialog<String>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('New room', style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, ctrl.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || !context.mounted) return;
    state.createManualRoom(
      name: name.isEmpty ? 'My Room' : name,
      lengthMeters: 3.6,
      widthMeters: 4.8,
      heightMeters: 2.7,
    );
    state.requestOpenToolsOnRig();
    state.setTab(2);
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final rooms = state.savedRooms;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'ROOMS',
            style: TextStyle(
              color: AppColors.cyan,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            state.isSignedIn ? 'Signed in — cloud + device' : 'Guest — this device only',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.45,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final r in rooms)
                  ListTile(
                    selected: r.id == state.activeRoomId,
                    selectedTileColor: AppColors.cyan.withValues(alpha: 0.12),
                    title: Text(
                      r.name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      r.scanComplete
                          ? 'Scanned'
                          : (r.layout.scanSource == 'manual' ? 'Created' : 'Preset'),
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                    trailing: r.id == state.activeRoomId
                        ? const Icon(Icons.check_rounded, color: AppColors.cyan)
                        : null,
                    onTap: () => _switchTo(context, state, r.id),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _rename(context, state),
                  child: const Text('Rename'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => _newRoom(context, state),
                  child: const Text('New room'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
