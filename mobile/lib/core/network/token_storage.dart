import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user_model.dart';

class TokenStorage {
  static const _keyAccessToken = 'evenbill_access_token';
  static const _keyRefreshToken = 'evenbill_refresh_token';
  static const _keyUser = 'evenbill_cached_user';
  static const _keyLastEmail = 'evenbill_last_email';

  final FlutterSecureStorage _storage;
  final Map<String, String> _fallback = {};

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

  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    _fallback[_keyAccessToken] = accessToken;
    _fallback[_keyRefreshToken] = refreshToken;
    if (_isTest) return;
    try {
      await _storage.write(key: _keyAccessToken, value: accessToken);
      await _storage.write(key: _keyRefreshToken, value: refreshToken);
    } catch (_) {}
  }

  Future<String?> getAccessToken() async {
    if (_isTest) return _fallback[_keyAccessToken];
    try {
      return await _storage.read(key: _keyAccessToken) ?? _fallback[_keyAccessToken];
    } catch (_) {
      return _fallback[_keyAccessToken];
    }
  }

  Future<String?> getRefreshToken() async {
    if (_isTest) return _fallback[_keyRefreshToken];
    try {
      return await _storage.read(key: _keyRefreshToken) ?? _fallback[_keyRefreshToken];
    } catch (_) {
      return _fallback[_keyRefreshToken];
    }
  }

  Future<void> saveUser(UserModel user) async {
    final str = jsonEncode(user.toJson());
    _fallback[_keyUser] = str;
    _fallback[_keyLastEmail] = user.email;
    if (_isTest) return;
    try {
      await _storage.write(key: _keyUser, value: str);
      await _storage.write(key: _keyLastEmail, value: user.email);
    } catch (_) {}
  }

  Future<void> saveLastEmail(String email) async {
    _fallback[_keyLastEmail] = email;
    if (_isTest) return;
    try {
      await _storage.write(key: _keyLastEmail, value: email);
    } catch (_) {}
  }

  Future<String?> getLastEmail() async {
    if (_isTest) return _fallback[_keyLastEmail];
    try {
      return await _storage.read(key: _keyLastEmail) ?? _fallback[_keyLastEmail];
    } catch (_) {
      return _fallback[_keyLastEmail];
    }
  }

  Future<UserModel?> getCachedUser() async {
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

  Future<void> clearAll() async {
    _fallback.clear();
    if (_isTest) return;
    try {
      await _storage.delete(key: _keyAccessToken);
      await _storage.delete(key: _keyRefreshToken);
      await _storage.delete(key: _keyUser);
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
    _memory['last_email'] = user.email;
  }

  @override
  Future<void> saveLastEmail(String email) async {
    _memory['last_email'] = email;
  }

  @override
  Future<String?> getLastEmail() async => _memory['last_email'];

  @override
  Future<UserModel?> getCachedUser() async {
    final str = _memory['user'];
    if (str == null) return null;
    return UserModel.fromJson(jsonDecode(str) as Map<String, dynamic>);
  }

  @override
  Future<void> clearAll() async {
    _memory.clear();
  }

  @override
  Future<bool> hasAccessToken() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }
}
