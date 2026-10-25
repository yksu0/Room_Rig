/// Non-web: password managers rely on autofill / OS prompts.
Future<bool> trySavePasswordToManager({
  required String email,
  required String password,
}) async {
  return false;
}
