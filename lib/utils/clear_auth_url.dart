import 'clear_auth_url_stub.dart'
    if (dart.library.html) 'clear_auth_url_web.dart' as impl;

void clearAuthUrlResidue() => impl.clearAuthUrlResidue();
