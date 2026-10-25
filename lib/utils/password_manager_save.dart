import 'password_manager_save_stub.dart'
    if (dart.library.html) 'password_manager_save_web.dart' as impl;

Future<bool> trySavePasswordToManager({
  required String email,
  required String password,
}) =>
    impl.trySavePasswordToManager(email: email, password: password);
