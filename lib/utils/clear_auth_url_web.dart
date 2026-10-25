import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Drop recovery/OAuth hash+query from the address bar after auth completes.
void clearAuthUrlResidue() {
  try {
    final location = globalContext['location'] as JSObject?;
    final history = globalContext['history'] as JSObject?;
    if (location == null || history == null) return;
    final origin = (location['origin'] as JSString?)?.toDart ?? '';
    final pathname = (location['pathname'] as JSString?)?.toDart ?? '/';
    final replaceState = history['replaceState'] as JSFunction?;
    replaceState?.callAsFunction(history, null, ''.toJS, '$origin$pathname'.toJS);
  } catch (_) {}
}
