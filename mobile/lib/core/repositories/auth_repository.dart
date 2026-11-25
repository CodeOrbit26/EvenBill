import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../network/api_client.dart';
import '../network/token_storage.dart';
import '../models/user_model.dart';
import '../constants/api_constants.dart';
import '../services/supabase_service.dart';
import '../services/google_auth_service.dart';

/// Thrown during registration when Supabase Auth requires the user to verify
/// their email address before an active session is issued.
class EmailConfirmationRequiredException implements Exception {
  final String message;
  const EmailConfirmationRequiredException([
    this.message = 'Account created! Please check your email to verify your account before logging in.',
  ]);

  @override
  String toString() => message;
}

class AuthRepository {
  final ApiClient apiClient;
  final TokenStorage tokenStorage;

  AuthRepository({
    required this.apiClient,
    required this.tokenStorage,
  });

  /// Maps GoTrue exceptions cleanly to typed [ApiException] instances so callers
  /// preserve offline connection semantics vs auth rejection errors.
  ApiException _mapAuthException(
    AuthException e, {
    int defaultStatusCode = 400,
    bool isAuthError = false,
  }) {
    if (e is AuthRetryableFetchException) {
      return ApiException(e.message, isConnectionError: true);
    }
    final code = e.code;
    if (code == ErrorCode.userAlreadyExists.code ||
        code == ErrorCode.emailExists.code) {
      return ApiException(
        e.message,
        statusCode: 409,
        details: {'code': code},
      );
    }
    final statusCode =
        int.tryParse(e.statusCode ?? '') ?? defaultStatusCode;
    return ApiException(
      e.message,
      statusCode: isAuthError ? 401 : statusCode,
      isAuthError: isAuthError,
      details: code != null ? {'code': code} : null,
    );
  }

  /// Derives effective authentication capability claims from Supabase's active user.
  bool _supabaseUserHasPassword(User? sbUser) {
    if (sbUser == null) return false;
    final provider = sbUser.appMetadata['provider']?.toString().toLowerCase();
    final providers = (sbUser.appMetadata['providers'] as List?)
            ?.map((e) => e.toString().toLowerCase())
            .toList() ??
        const <String>[];
    return provider == 'email' || providers.contains('email');
  }

  bool _supabaseUserIsVerified(User? sbUser) {
    if (sbUser == null) return false;
    if (sbUser.emailConfirmedAt != null) return true;
    final provider = sbUser.appMetadata['provider']?.toString().toLowerCase();
    final providers = (sbUser.appMetadata['providers'] as List?)
            ?.map((e) => e.toString().toLowerCase())
            .toList() ??
        const <String>[];
    return provider == 'google' ||
        provider == 'apple' ||
        providers.contains('google') ||
        providers.contains('apple');
  }

  UserModel _enrichWithSupabaseIdentity(UserModel user) {
    final sbUser = SupabaseService.client?.auth.currentUser;
    if (sbUser == null || (user.id.isNotEmpty && sbUser.id != user.id)) {
      return user;
    }
    return user.copyWith(
      hasPassword: user.hasPassword || _supabaseUserHasPassword(sbUser),
      isVerified: user.isVerified || _supabaseUserIsVerified(sbUser),
    );
  }

  Future<void> _clearRejectedLocalSession() async {
    try {
      await SupabaseService.client?.auth.signOut(scope: SignOutScope.local);
    } catch (_) {}
    await tokenStorage.clearAll();
  }

  /// Persists session tokens and fetches the authoritative FastAPI profile.
  /// Retries once on transient connection errors (e.g. cold starts), and clears
  /// unverified local session state on rejection or persistent network failure
  /// so a device never enters an empty unsynced offline shell on initial login.
  Future<UserModel> _finalizeSupabaseSession(
    Session session,
    User? sbUser, {
    required String fallbackEmail,
    String? fallbackFullName,
    String? fallbackAvatarUrl,
    String? fallbackPhoneNumber,
    String defaultCurrency = 'USD',
    bool forceHasPassword = false,
  }) async {
    await tokenStorage.saveTokens(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken ?? '',
    );

    try {
      return await getMe();
    } catch (e) {
      if (e is ApiException && e.isConnectionError) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        try {
          return await getMe();
        } catch (_) {
          await _clearRejectedLocalSession();
          rethrow;
        }
      }
      await _clearRejectedLocalSession();
      rethrow;
    }
  }

  Future<UserModel> register({
    required String email,
    required String password,
    required String fullName,
    String? phoneNumber,
    String defaultCurrency = 'USD',
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanName = fullName.trim();
    final cleanPhone = phoneNumber?.trim();
    final currency = defaultCurrency.toUpperCase().trim();

    final client = SupabaseService.client;
    if (client != null) {
      try {
        final res = await client.auth.signUp(
          email: cleanEmail,
          password: password,
          data: {
            'full_name': cleanName,
            'default_currency': currency,
            if (cleanPhone != null && cleanPhone.isNotEmpty)
              'phone_number': cleanPhone,
          },
        );

        final session = res.session;
        if (session != null) {
          return await _finalizeSupabaseSession(
            session,
            res.user,
            fallbackEmail: cleanEmail,
            fallbackFullName: cleanName,
            fallbackPhoneNumber: cleanPhone,
            defaultCurrency: currency,
            forceHasPassword: true,
          );
        }

        // Email confirmation is required by Supabase GoTrue; no active session issued yet.
        throw const EmailConfirmationRequiredException();
      } on EmailConfirmationRequiredException {
        rethrow;
      } on AuthException catch (e) {
        throw _mapAuthException(e, defaultStatusCode: 400);
      }
    }

    // Fallback for mock/offline testing environments
    final payload = <String, dynamic>{
      'email': cleanEmail,
      'password': password,
      'full_name': cleanName,
      'default_currency': currency,
    };
    if (cleanPhone != null && cleanPhone.isNotEmpty) {
      payload['phone_number'] = cleanPhone;
    }
    await apiClient.post(
      ApiConstants.register,
      data: payload,
    );

    return await login(email: cleanEmail, password: password);
  }

  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    final identifier = email.trim();
    final client = SupabaseService.client;

    // Route email/password logins through Supabase Auth; preserve backend lookup for phone numbers.
    if (client != null && identifier.contains('@')) {
      try {
        final res = await client.auth.signInWithPassword(
          email: identifier.toLowerCase(),
          password: password,
        );

        final session = res.session;
        if (session == null) {
          throw ApiException(
            'Unable to establish session. Please verify your email and try again.',
            statusCode: 401,
            isAuthError: true,
          );
        }

        return await _finalizeSupabaseSession(
          session,
          res.user,
          fallbackEmail: identifier.toLowerCase(),
          forceHasPassword: true,
        );
      } on AuthException catch (e) {
        throw _mapAuthException(e, defaultStatusCode: 401, isAuthError: true);
      }
    }

    // Fallback for phone-number login or uninitialized Supabase environments
    final res = await apiClient.post(
      ApiConstants.login,
      data: {
        'email': identifier,
        'password': password,
      },
    );

    final accessToken = res['access_token'] as String;
    final refreshToken = res['refresh_token'] as String;
    await tokenStorage.saveTokens(accessToken: accessToken, refreshToken: refreshToken);

    // Fetch and cache authenticated profile
    return await getMe();
  }

  Future<UserModel> loginWithOAuth({
    required String provider,
    String? idToken,
    String? nonce,
    String? email,
    String? fullName,
    String? avatarUrl,
    String? phoneNumber,
    String? password,
  }) async {
    final normalizedProvider = provider.toLowerCase().trim();
    final client = SupabaseService.client;

    if (client != null) {
      if (idToken == null || idToken.isEmpty) {
        throw ApiException(
          'Sign-in with $normalizedProvider did not return an ID token. Please try again.',
          statusCode: 401,
          isAuthError: true,
        );
      }

      final OAuthProvider oauthProvider;
      if (normalizedProvider == 'google') {
        oauthProvider = OAuthProvider.google;
      } else if (normalizedProvider == 'apple') {
        oauthProvider = OAuthProvider.apple;
      } else {
        throw ApiException(
          'Unsupported OAuth provider: $provider',
          statusCode: 400,
        );
      }

      try {
        final res = await client.auth.signInWithIdToken(
          provider: oauthProvider,
          idToken: idToken,
          nonce: nonce,
        );
        final session = res.session;
        if (session == null) {
          throw ApiException(
            'Unable to establish session with $normalizedProvider. Please try again.',
            statusCode: 401,
            isAuthError: true,
          );
        }

        return await _finalizeSupabaseSession(
          session,
          res.user,
          fallbackEmail: email?.trim().toLowerCase() ?? '',
          fallbackFullName: fullName,
          fallbackAvatarUrl: avatarUrl,
          fallbackPhoneNumber: phoneNumber,
        );
      } on AuthException catch (e) {
        throw _mapAuthException(e, defaultStatusCode: 401, isAuthError: true);
      }
    }

    // Legacy backend OAuth fallback when Supabase SDK is uninitialized (e.g., widget/unit tests)
    final payload = <String, dynamic>{
      'provider': normalizedProvider,
    };
    if (idToken != null) payload['id_token'] = idToken;
    if (email != null) payload['email'] = email.trim().toLowerCase();
    if (fullName != null) payload['full_name'] = fullName.trim();
    if (avatarUrl != null) payload['avatar_url'] = avatarUrl.trim();
    if (phoneNumber != null && phoneNumber.trim().isNotEmpty) {
      payload['phone_number'] = phoneNumber.trim();
    }
    if (password != null && password.isNotEmpty) {
      payload['password'] = password;
    }

    final res = await apiClient.post(
      ApiConstants.oauth,
      data: payload,
    );

    final accessToken = res['access_token'] as String;
    final refreshToken = res['refresh_token'] as String;
    await tokenStorage.saveTokens(accessToken: accessToken, refreshToken: refreshToken);

    return await getMe();
  }

  Future<void> resetPasswordForEmail(String email) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      throw ApiException('Please enter a valid email address.', statusCode: 400);
    }

    final client = SupabaseService.client;
    if (client == null) {
      throw ApiException(
        'Password recovery service is currently unavailable. Please verify connectivity and try again.',
        isConnectionError: true,
      );
    }

    try {
      await client.auth.resetPasswordForEmail(cleanEmail);
    } on AuthException catch (e) {
      throw _mapAuthException(e, defaultStatusCode: 400);
    }
  }

  Future<UserModel> setPassword({
    required String password,
    String? phoneNumber,
    String? fullName,
  }) async {
    // Synchronize password & metadata with Supabase Auth as primary identity authority
    final client = SupabaseService.client;
    if (client != null && client.auth.currentSession != null) {
      try {
        await client.auth.updateUser(
          UserAttributes(
            password: password,
            data: {
              if (fullName != null && fullName.trim().isNotEmpty) 'full_name': fullName.trim(),
              if (phoneNumber != null && phoneNumber.trim().isNotEmpty) 'phone_number': phoneNumber.trim(),
            },
          ),
        );
      } on AuthException catch (e) {
        throw _mapAuthException(e, defaultStatusCode: 400);
      }
    }

    final payload = <String, dynamic>{
      'password': password,
    };
    if (phoneNumber != null && phoneNumber.trim().isNotEmpty) {
      payload['phone_number'] = phoneNumber.trim();
    }
    if (fullName != null && fullName.trim().isNotEmpty) {
      payload['full_name'] = fullName.trim();
    }

    final res = await apiClient.post(
      ApiConstants.setPassword,
      data: payload,
    );
    final user = _enrichWithSupabaseIdentity(
      UserModel.fromJson(res).copyWith(hasPassword: true),
    );
    await tokenStorage.saveUser(user);
    return user;
  }

  Future<String> refreshToken() async {
    final client = SupabaseService.client;
    if (client != null && client.auth.currentSession != null) {
      try {
        final res = await client.auth.refreshSession();
        final session = res.session;
        if (session != null) {
          await tokenStorage.saveTokens(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken ?? '',
          );
          return session.accessToken;
        }
      } on AuthException catch (e) {
        throw _mapAuthException(e, defaultStatusCode: 401, isAuthError: true);
      }
    }

    final token = await tokenStorage.getRefreshToken();
    if (token == null || token.isEmpty) {
      throw ApiException('No refresh token available', statusCode: 401, isAuthError: true);
    }
    final res = await apiClient.post(
      ApiConstants.refresh,
      data: {'refresh_token': token},
    );
    final access = res['access_token'] as String;
    final refresh = res['refresh_token'] as String;
    await tokenStorage.saveTokens(accessToken: access, refreshToken: refresh);
    return access;
  }

  Future<UserModel> getMe() async {
    final res = await apiClient.get(ApiConstants.me);
    final user = _enrichWithSupabaseIdentity(
      UserModel.fromJson(res as Map<String, dynamic>),
    );
    await tokenStorage.saveUser(user);
    return user;
  }

  Future<UserModel> updateMe({
    String? fullName,
    String? defaultCurrency,
    String? avatarUrl,
  }) async {
    final data = <String, dynamic>{};
    if (fullName != null) data['full_name'] = fullName.trim();
    if (defaultCurrency != null) data['default_currency'] = defaultCurrency.toUpperCase().trim();
    if (avatarUrl != null) data['avatar_url'] = avatarUrl.trim();

    final res = await apiClient.put(ApiConstants.me, data: data);

    final client = SupabaseService.client;
    if (client != null && client.auth.currentSession != null && data.isNotEmpty) {
      try {
        await client.auth.updateUser(UserAttributes(data: data));
      } catch (e) {
        debugPrint('[AuthRepository] Supabase updateMe userMetadata notice: $e');
      }
    }

    final user = _enrichWithSupabaseIdentity(
      UserModel.fromJson(res as Map<String, dynamic>),
    );
    await tokenStorage.saveUser(user);
    return user;
  }

  Future<Map<String, dynamic>> exportUserData() async {
    final res = await apiClient.post(ApiConstants.userExport);
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  Future<void> signOut() async {
    try {
      await GoogleAuthService.signOut();
    } catch (_) {}

    try {
      final client = SupabaseService.client;
      if (client != null) {
        await client.auth.signOut();
      }
    } catch (_) {}

    try {
      final refresh = await tokenStorage.getRefreshToken();
      // Only invoke legacy backend revocation for legacy JWT refresh tokens
      if (refresh != null && refresh.isNotEmpty && refresh.split('.').length == 3) {
        await apiClient.post(
          '/auth/logout',
          data: {'refresh_token': refresh},
        );
      }
    } catch (_) {
      // Best-effort remote revocation
    } finally {
      await tokenStorage.clearAll();
    }
  }

  Future<UserModel?> getCachedUser() async {
    return await tokenStorage.getCachedUser();
  }

  Future<bool> isAuthenticated() async {
    return await tokenStorage.hasAccessToken();
  }
}
