import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../models/published_layout.dart';
import '../models/saved_room.dart';
import '../services/auth_service.dart';
import '../services/published_layout_repository.dart';
import '../theme/app_theme.dart';
import 'guest_signup_gate.dart';

/// Compose + publish a Community post (room, title, caption, tags).
Future<bool> publishCurrentLayoutToCommunity(BuildContext context) async {
  if (!await ensureProfileCompleteForPublish(context)) return false;
  if (!context.mounted) return false;

  final draft = await showModalBottomSheet<_PublishDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    builder: (ctx) => const _PublishComposeSheet(),
  );
  if (draft == null || !context.mounted) return false;

  final uid = context.read<AuthService>().userId;
  if (uid == null) return false;

  try {
    await context.read<AppState>().publishCurrentRoom(
          authorId: uid,
          title: draft.title,
          description: draft.description,
          tags: draft.tags,
          roomId: draft.roomId,
        );
    if (!context.mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Published to Community')),
    );
    return true;
  } catch (e) {
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Publish failed: $e')),
    );
    return false;
  }
}

/// Edit title / description / tags on an existing Community post.
Future<PublishedLayout?> editPublishedLayoutPost(
  BuildContext context,
  PublishedLayout layout,
) async {
  final draft = await showModalBottomSheet<_EditDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    builder: (ctx) => _EditPostSheet(layout: layout),
  );
  if (draft == null || !context.mounted) return null;

  try {
    final updated = await PublishedLayoutRepository().updatePost(
      layoutId: layout.id,
      title: draft.title,
      description: draft.description,
      tags: draft.tags,
    );
    if (!context.mounted) return updated;
    context.read<AppState>().cachePublishedLayout(updated);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Post updated')),
    );
    return updated;
  } catch (e) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Update failed: $e')),
    );
    return null;
  }
}

class _PublishDraft {
  final String roomId;
  final String title;
  final String? description;
  final List<String> tags;

  const _PublishDraft({
    required this.roomId,
    required this.title,
    this.description,
    required this.tags,
  });
}

class _EditDraft {
  final String title;
  final String? description;
  final List<String> tags;

  const _EditDraft({
    required this.title,
    this.description,
    required this.tags,
  });
}

class _PublishComposeSheet extends StatefulWidget {
  const _PublishComposeSheet();

  @override
  State<_PublishComposeSheet> createState() => _PublishComposeSheetState();
}

class _PublishComposeSheetState extends State<_PublishComposeSheet> {
  late String _roomId;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _customTagCtrl;
  final Set<String> _tags = {};

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _roomId = state.activeRoomId;
    _titleCtrl = TextEditingController(text: state.currentRoomData.name);
    _descCtrl = TextEditingController();
    _customTagCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _customTagCtrl.dispose();
    super.dispose();
  }

  SavedRoom? _roomById(String id) {
    for (final r in context.read<AppState>().savedRooms) {
      if (r.id == id) return r;
    }
    return null;
  }

  void _onRoomChanged(String? id) {
    if (id == null) return;
    final rooms = context.read<AppState>().savedRooms;
    final roomNames = rooms.map((r) => r.name).toSet();
    setState(() {
      _roomId = id;
      final room = _roomById(id);
      if (room == null) return;
      final currentTitle = _titleCtrl.text.trim();
      // Auto-fill title when empty or still matching another room's name.
      if (currentTitle.isEmpty || roomNames.contains(currentTitle)) {
        _titleCtrl.text = room.name;
      }
    });
  }

  void _addCustomTag() {
    final raw = _customTagCtrl.text.trim().toLowerCase().replaceAll(' ', '-');
    if (raw.isEmpty) return;
    if (raw.length > 24) return;
    setState(() {
      _tags.add(raw);
      _customTagCtrl.clear();
    });
  }

  void _submit() {
    final title = _titleCtrl.text.trim();
    if (title.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a title (at least 2 characters).')),
      );
      return;
    }
    final desc = _descCtrl.text.trim();
    Navigator.pop(
      context,
      _PublishDraft(
        roomId: _roomId,
        title: title,
        description: desc.isEmpty ? null : desc,
        tags: _tags.toList(growable: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rooms = context.watch<AppState>().savedRooms;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final selected = _roomById(_roomId);
    final itemCount = _roomId == context.watch<AppState>().activeRoomId
        ? context.watch<AppState>().committedFurniture.length
        : (selected?.furniture.length ?? 0);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'New Community post',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Text(
                'Pick a room, write the post, add tags — then publish.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              const Text(
                'Room',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 6),
              InputDecorator(
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: rooms.any((r) => r.id == _roomId)
                        ? _roomId
                        : (rooms.isNotEmpty ? rooms.first.id : null),
                    dropdownColor: AppColors.surfaceAlt,
                    items: [
                      for (final r in rooms)
                        DropdownMenuItem(
                          value: r.id,
                          child: Text(
                            '${r.name} (${r.furniture.length} items)'
                            '${r.id == context.read<AppState>().activeRoomId ? ' · current' : ''}',
                            style: const TextStyle(color: AppColors.textPrimary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _onRoomChanged,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _titleCtrl,
                maxLength: 80,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'Cozy WFH desk setup',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _descCtrl,
                maxLength: 400,
                maxLines: 4,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText:
                      'What changed, why you laid it out this way, what to notice…',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tags',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in kCommunityPostTagOptions)
                    FilterChip(
                      label: Text(t),
                      selected: _tags.contains(t),
                      onSelected: (on) => setState(() {
                        if (on) {
                          _tags.add(t);
                        } else {
                          _tags.remove(t);
                        }
                      }),
                    ),
                  for (final t in _tags.where(
                    (t) => !kCommunityPostTagOptions.contains(t),
                  ))
                    FilterChip(
                      label: Text(t),
                      selected: true,
                      onSelected: (_) => setState(() => _tags.remove(t)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customTagCtrl,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Custom tag',
                        hintText: 'minimal',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _addCustomTag(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _addCustomTag,
                    child: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Publishing $itemCount items from “${selected?.name ?? 'room'}”.',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submit,
                      child: const Text('Publish'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditPostSheet extends StatefulWidget {
  final PublishedLayout layout;
  const _EditPostSheet({required this.layout});

  @override
  State<_EditPostSheet> createState() => _EditPostSheetState();
}

class _EditPostSheetState extends State<_EditPostSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _customTagCtrl;
  late final Set<String> _tags;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.layout.title);
    _descCtrl = TextEditingController(text: widget.layout.description ?? '');
    _customTagCtrl = TextEditingController();
    _tags = {...widget.layout.tags};
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _customTagCtrl.dispose();
    super.dispose();
  }

  void _addCustomTag() {
    final raw = _customTagCtrl.text.trim().toLowerCase().replaceAll(' ', '-');
    if (raw.isEmpty || raw.length > 24) return;
    setState(() {
      _tags.add(raw);
      _customTagCtrl.clear();
    });
  }

  void _submit() {
    final title = _titleCtrl.text.trim();
    if (title.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a title (at least 2 characters).')),
      );
      return;
    }
    final desc = _descCtrl.text.trim();
    Navigator.pop(
      context,
      _EditDraft(
        title: title,
        description: desc.isEmpty ? null : desc,
        tags: _tags.toList(growable: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Edit post',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleCtrl,
                maxLength: 80,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _descCtrl,
                maxLength: 400,
                maxLines: 4,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Description',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tags',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in kCommunityPostTagOptions)
                    FilterChip(
                      label: Text(t),
                      selected: _tags.contains(t),
                      onSelected: (on) => setState(() {
                        if (on) {
                          _tags.add(t);
                        } else {
                          _tags.remove(t);
                        }
                      }),
                    ),
                  for (final t in _tags.where(
                    (t) => !kCommunityPostTagOptions.contains(t),
                  ))
                    FilterChip(
                      label: Text(t),
                      selected: true,
                      onSelected: (_) => setState(() => _tags.remove(t)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customTagCtrl,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Custom tag',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _addCustomTag(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _addCustomTag,
                    child: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submit,
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
