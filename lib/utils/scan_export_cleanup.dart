import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Deletes leftover Scan export folders under the OS temp directory.
Future<void> clearRoomRigExportTemps({Directory? only}) async {
  if (kIsWeb) return;
  try {
    if (only != null) {
      if (await only.exists()) await only.delete(recursive: true);
      return;
    }
    final tempDir = await getTemporaryDirectory();
    await for (final entity in tempDir.list()) {
      if (entity is! Directory) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      if (!name.startsWith('room_rig_export_')) continue;
      try {
        await entity.delete(recursive: true);
      } catch (_) {}
    }
  } catch (_) {}
}
