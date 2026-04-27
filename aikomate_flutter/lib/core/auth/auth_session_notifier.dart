import 'package:flutter/foundation.dart';
import 'package:aikomate_flutter/core/api/auth_api.dart';
import 'package:aikomate_flutter/core/storage/secure_storage.dart';

bool _parseAdminFromMe(Map<String, dynamic>? data) {
  if (data == null) return false;
  final a = data['admin'];
  if (a is bool) return a;
  if (a is num) return a != 0;
  if (a is String) {
    final s = a.toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }
  return false;
}

/// Drives app-router redirects and reflects whether a validated session exists.
class AuthSessionNotifier extends ChangeNotifier {
  AuthSessionNotifier();

  /// Test-only: skips async [restore].
  factory AuthSessionNotifier.test({
    bool loggedIn = false,
    bool isAdmin = false,
  }) {
    final s = AuthSessionNotifier();
    s._loggedIn = loggedIn;
    s._isAdmin = isAdmin;
    return s;
  }

  bool _loggedIn = false;
  bool _isAdmin = false;

  bool get isLoggedIn => _loggedIn;

  /// From latest successful `GET /auth/me` (`admin` field).
  bool get isAdmin => _isAdmin;

  void _setMe(Map<String, dynamic>? data) {
    _isAdmin = _parseAdminFromMe(data);
  }

  /// Call before [runApp] to resolve token + [auth] without a loading route.
  Future<void> restore() async {
    final token = await SecureStorage.getToken();
    if (token == null) {
      _loggedIn = false;
      _isAdmin = false;
      return;
    }

    final res = await auth();
    if (!res.success) {
      await SecureStorage.deleteToken();
      _loggedIn = false;
      _isAdmin = false;
      return;
    }

    _loggedIn = true;
    final data = res.result is Map<String, dynamic>
        ? res.result as Map<String, dynamic>
        : null;
    _setMe(data);
  }

  /// Refresh `/auth/me` (e.g. after login). Does not log out on failure.
  Future<void> refreshFromMe() async {
    final res = await auth();
    if (!res.success) return;
    final data = res.result is Map<String, dynamic>
        ? res.result as Map<String, dynamic>
        : null;
    _setMe(data);
    notifyListeners();
  }

  void setLoggedIn() {
    if (_loggedIn) return;
    _loggedIn = true;
    notifyListeners();
  }

  void setLoggedOut() {
    if (!_loggedIn && !_isAdmin) return;
    _loggedIn = false;
    _isAdmin = false;
    notifyListeners();
  }
}
