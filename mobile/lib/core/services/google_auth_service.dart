import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleAuthResult {
  final String email;
  final String fullName;
  final String? avatarUrl;
  final String? idToken;

  const GoogleAuthResult({
    required this.email,
    required this.fullName,
    this.avatarUrl,
    this.idToken,
  });
}

class GoogleAuthService {
  static const String serverClientId =
      '34497581041-32g5m3c4oet10tbf1m6cr03m1eugqc50.apps.googleusercontent.com';

  static bool _initialized = false;

  static Future<void> _ensureInitialized() async {
    if (!_initialized) {
      try {
        await GoogleSignIn.instance.initialize(
          serverClientId: serverClientId,
        );
        _initialized = true;
      } catch (e) {
        debugPrint('GoogleSignIn initialize notice: $e');
      }
    }
  }

  /// Initiates native Google Sign-In via Google Play Services / Credential Manager.
  static Future<GoogleAuthResult?> signIn() async {
    try {
      await _ensureInitialized();
      final GoogleSignInAccount account = await GoogleSignIn.instance.authenticate(
        scopeHint: const ['email', 'profile'],
      );

      final GoogleSignInAuthentication auth = await account.authentication;

      return GoogleAuthResult(
        email: account.email,
        fullName: account.displayName ?? account.email.split('@').first,
        avatarUrl: account.photoUrl,
        idToken: auth.idToken,
      );
    } catch (e) {
      debugPrint('Google Sign In Notice: $e');
      rethrow;
    }
  }

  /// Signs out of Google session
  static Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }
}
