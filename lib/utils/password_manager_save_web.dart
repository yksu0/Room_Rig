import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Best-effort store via Credential Management API (Chromium browsers).
Future<bool> trySavePasswordToManager({
  required String email,
  required String password,
}) async {
  try {
    final ctor = globalContext['PasswordCredential'];
    if (ctor == null) return false;

    final data = JSObject()
      ..['id'] = email.toJS
      ..['password'] = password.toJS
      ..['name'] = email.toJS;

    final cred = (ctor as JSFunction).callAsConstructor(data);
    final navigator = globalContext['navigator'];
    if (navigator == null) return false;
    final credentials = (navigator as JSObject)['credentials'];
    if (credentials == null) return false;
    final store = (credentials as JSObject)['store'];
    if (store == null) return false;

    final promise =
        (store as JSFunction).callAsFunction(credentials, cred) as JSPromise?;
    if (promise == null) return false;
    await promise.toDart;
    return true;
  } catch (_) {
    return false;
  }
}
