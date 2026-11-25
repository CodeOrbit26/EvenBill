import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

class GoogleAuthResult {
  final String email;
  final String fullName;
  final String? avatarUrl;
  final String? idToken;
  final String? nonce;

  const GoogleAuthResult({
    required this.email,
    required this.fullName,
    this.avatarUrl,
    this.idToken,
    this.nonce,
  });
}

class GoogleAuthService {
  static const String serverClientId =
      '34497581041-m4kcf9orlm764lq0bh60l46rgjjamo1f.apps.googleusercontent.com';

  static bool _initialized = false;

  /// Generates a fresh 256-bit cryptographically secure random URL-safe raw nonce.
  static String generateRawNonce([Random? random]) {
    final rng = random ?? Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  /// Computes the SHA-256 hex digest of [rawNonce] to pass to Google Sign-In.
  static String hashNonce(String rawNonce) {
    return sha256.convert(utf8.encode(rawNonce)).toString();
  }

  static Future<void> _configureAttemptNonce(String hashedNonce) async {
    if (!_initialized) {
      await GoogleSignIn.instance.initialize(
        serverClientId: serverClientId,
        nonce: hashedNonce,
      );
      _initialized = true;
      return;
    }

    // google_sign_in ^7.2.0 only accepts `nonce` via initialization parameters
    // and warns against calling GoogleSignIn.initialize() more than once.
    // On Android & iOS (where authenticationEvents == null), calling
    // GoogleSignInPlatform.instance.init refreshes the per-attempt nonce cleanly
    // without duplicating stream listeners or triggering Web's repeat-init error.
    if (!kIsWeb && GoogleSignInPlatform.instance.authenticationEvents == null) {
      await GoogleSignInPlatform.instance.init(
        InitParameters(
          serverClientId: serverClientId,
          nonce: hashedNonce,
        ),
      );
    }
  }

  /// Initiates native Google Sign-In via Google Play Services / Credential Manager
  /// with a fresh per-attempt raw/SHA-256 nonce pair.
  static Future<GoogleAuthResult?> signIn() async {
    final rawNonce = generateRawNonce();
    final hashedNonce = hashNonce(rawNonce);

    try {
      await _configureAttemptNonce(hashedNonce);
      final GoogleSignInAccount account = await GoogleSignIn.instance.authenticate(
        scopeHint: const ['email', 'profile'],
      );

      final GoogleSignInAuthentication auth = account.authentication;

      return GoogleAuthResult(
        email: account.email,
        fullName: account.displayName ?? account.email.split('@').first,
        avatarUrl: account.photoUrl,
        idToken: auth.idToken,
        nonce: rawNonce,
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        debugPrint('Google Sign-In notice: flow ${e.code.name} by user.');
        return null;
      }
      final str = '${e.description ?? ''} $e'.toLowerCase();
      if (str.contains('cancel') || str.contains('16:')) {
        debugPrint('Google Sign-In notice: flow cancelled or dismissed by user.');
        return null;
      }
      debugPrint('Google Sign In Notice: $e');
      rethrow;
    } catch (e) {
      final str = e.toString().toLowerCase();
      // Handle user cancellation or bottom sheet dismissal cleanly without errors
      if (str.contains('canceled') ||
          str.contains('cancelled') ||
          str.contains('16:') ||
          str.contains('cancel') ||
          str.contains('activity was cancelled')) {
        debugPrint('Google Sign-In notice: flow cancelled or dismissed by user.');
        return null;
      }
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

  /// Resets initialization flag strictly for test isolation.
  @visibleForTesting
  static void resetForTesting() {
    _initialized = false;
  }
}
