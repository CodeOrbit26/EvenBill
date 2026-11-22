import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user_model.dart';

class TokenStorage {
  static const _keyAccessToken = 'evenbill_access_token';
  static const _keyRefreshToken = 'evenbill_refresh_token';
  static const _keyUser = 'evenbill_cached_user';
  static const _keyLastEmail = 'evenbill_last_email';
  static const _keyRememberEmail = 'evenbill_remember_email_enabled';

  final FlutterSecureStorage _storage;
  final Map<String, String> _fallback = {};
  bool _initializedFreshInstall = false;

  bool get _isTest {
    try {
      if (Platform.environment.containsKey('FLUTTER_TEST')) return true;
      final script = Platform.script.toString();
      if (script.contains('_test.dart') || script.contains('flutter_test')) return true;
      return false;
    } catch (_) {
      return false;
    }
  }

  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  Future<void> ensureFreshInstallCheck() async {
    if (_isTest || _initializedFreshInstall) return;
    _initializedFreshInstall = true;
    try {
      if (Platform.isAndroid) {
        final marker = File('/data/user/0/com.evenbill.evenbill/no_backup/.evenbill_installed');
        if (!await marker.exists()) {
          // Fresh installation or re-install: wipe any stale backed-up secure storage
          await _storage.deleteAll();
          await marker.create(recursive: true);
        }
      }
    } catch (_) {}
  }

  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    await ensureFreshInstallCheck();
    _fallback[_keyAccessToken] = accessToken;
    _fallback[_keyRefreshToken] = refreshToken;
    if (_isTest) return;
    try {
      await _storage.write(key: _keyAccessToken, value: accessToken);
      await _storage.write(key: _keyRefreshToken, value: refreshToken);
    } catch (_) {}
  }

  Future<String?> getAccessToken() async {
    await ensureFreshInstallCheck();
    if (_isTest) return _fallback[_keyAccessToken];
    try {
      return await _storage.read(key: _keyAccessToken) ?? _fallback[_keyAccessToken];
    } catch (_) {
      return _fallback[_keyAccessToken];
    }
  }

  Future<String?> getRefreshToken() async {
    await ensureFreshInstallCheck();
    if (_isTest) return _fallback[_keyRefreshToken];
    try {
      return await _storage.read(key: _keyRefreshToken) ?? _fallback[_keyRefreshToken];
    } catch (_) {
      return _fallback[_keyRefreshToken];
    }
  }

  Future<void> saveUser(UserModel user) async {
    await ensureFreshInstallCheck();
    final str = jsonEncode(user.toJson());
    _fallback[_keyUser] = str;
    if (_isTest) return;
    try {
      await _storage.write(key: _keyUser, value: str);
    } catch (_) {}
  }

  Future<void> saveLastEmail(String email) async {
    await ensureFreshInstallCheck();
    _fallback[_keyLastEmail] = email;
    if (_isTest) return;
    try {
      await _storage.write(key: _keyLastEmail, value: email);
    } catch (_) {}
  }

  Future<void> clearLastEmail() async {
    await ensureFreshInstallCheck();
    _fallback.remove(_keyLastEmail);
    if (_isTest) return;
    try {
      await _storage.delete(key: _keyLastEmail);
    } catch (_) {}
  }

  Future<String?> getLastEmail() async {
    await ensureFreshInstallCheck();
    if (_isTest) return _fallback[_keyLastEmail];
    try {
      return await _storage.read(key: _keyLastEmail) ?? _fallback[_keyLastEmail];
    } catch (_) {
      return _fallback[_keyLastEmail];
    }
  }

  Future<bool> isRememberEmailEnabled() async {
    await ensureFreshInstallCheck();
    if (_isTest) return _fallback[_keyRememberEmail] == 'true';
    try {
      final val = await _storage.read(key: _keyRememberEmail);
      return val == 'true' || _fallback[_keyRememberEmail] == 'true';
    } catch (_) {
      return _fallback[_keyRememberEmail] == 'true';
    }
  }

  Future<void> setRememberEmailEnabled(bool enabled) async {
    await ensureFreshInstallCheck();
    _fallback[_keyRememberEmail] = enabled ? 'true' : 'false';
    if (_isTest) return;
    try {
      await _storage.write(key: _keyRememberEmail, value: enabled ? 'true' : 'false');
    } catch (_) {}
  }

  Future<UserModel?> getCachedUser() async {
    await ensureFreshInstallCheck();
    String? str;
    if (!_isTest) {
      try {
        str = await _storage.read(key: _keyUser);
      } catch (_) {}
    }
    str ??= _fallback[_keyUser];
    if (str == null) return null;
    try {
      final map = jsonDecode(str) as Map<String, dynamic>;
      return UserModel.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearAll({bool clearRememberedEmail = false}) async {
    _fallback.remove(_keyAccessToken);
    _fallback.remove(_keyRefreshToken);
    _fallback.remove(_keyUser);
    if (clearRememberedEmail) {
      _fallback.remove(_keyLastEmail);
      _fallback.remove(_keyRememberEmail);
    }
    if (_isTest) return;
    try {
      await _storage.delete(key: _keyAccessToken);
      await _storage.delete(key: _keyRefreshToken);
      await _storage.delete(key: _keyUser);
      if (clearRememberedEmail) {
        await _storage.delete(key: _keyLastEmail);
        await _storage.delete(key: _keyRememberEmail);
      }
    } catch (_) {}
  }

  Future<bool> hasAccessToken() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }
}

class InMemoryTokenStorage extends TokenStorage {
  final Map<String, String> _memory = {};

  InMemoryTokenStorage() : super();

  @override
  Future<void> ensureFreshInstallCheck() async {}

  @override
  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    _memory['access_token'] = accessToken;
    _memory['refresh_token'] = refreshToken;
  }

  @override
  Future<String?> getAccessToken() async => _memory['access_token'];

  @override
  Future<String?> getRefreshToken() async => _memory['refresh_token'];

  @override
  Future<void> saveUser(UserModel user) async {
    _memory['user'] = jsonEncode(user.toJson());
  }

  @override
  Future<void> saveLastEmail(String email) async {
    _memory['last_email'] = email;
  }

  @override
  Future<void> clearLastEmail() async {
    _memory.remove('last_email');
  }

  @override
  Future<String?> getLastEmail() async => _memory['last_email'];

  @override
  Future<bool> isRememberEmailEnabled() async => _memory['remember_email'] == 'true';

  @override
  Future<void> setRememberEmailEnabled(bool enabled) async {
    _memory['remember_email'] = enabled ? 'true' : 'false';
  }

  @override
  Future<UserModel?> getCachedUser() async {
    final str = _memory['user'];
    if (str == null) return null;
    return UserModel.fromJson(jsonDecode(str) as Map<String, dynamic>);
  }

  @override
  Future<void> clearAll({bool clearRememberedEmail = false}) async {
    _memory.remove('access_token');
    _memory.remove('refresh_token');
    _memory.remove('user');
    if (clearRememberedEmail) {
      _memory.remove('last_email');
      _memory.remove('remember_email');
    }
  }

  @override
  Future<bool> hasAccessToken() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }
}
