import 'package:supabase_flutter/supabase_flutter.dart';
import '../network/api_client.dart';
import '../network/token_storage.dart';
import '../models/user_model.dart';
import '../constants/api_constants.dart';
import '../services/supabase_service.dart';

class AuthRepository {
  final ApiClient apiClient;
  final TokenStorage tokenStorage;

  AuthRepository({
    required this.apiClient,
    required this.tokenStorage,
  });

  Future<UserModel> register({
    required String email,
    required String password,
    required String fullName,
    String? phoneNumber,
    String defaultCurrency = 'USD',
  }) async {
    final client = SupabaseService.client;
    if (client != null) {
      try {
        final res = await client.auth.signUp(
          email: email.trim().toLowerCase(),
          password: password,
          data: {
            'full_name': fullName.trim(),
            'default_currency': defaultCurrency.toUpperCase(),
            if (phoneNumber != null && phoneNumber.trim().isNotEmpty)
              'phone_number': phoneNumber.trim(),
          },
        );

        final session = res.session;
        if (session != null) {
          await tokenStorage.saveTokens(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken ?? '',
          );
        }

        // Synchronize / verify user profile with FastAPI backend authority
        try {
          return await getMe();
        } catch (_) {
          final user = UserModel(
            id: res.user?.id ?? '',
            email: email.trim().toLowerCase(),
            fullName: fullName.trim(),
            phoneNumber: phoneNumber,
            defaultCurrency: defaultCurrency.toUpperCase(),
            isActive: true,
            createdAt: DateTime.now(),
          );
          await tokenStorage.saveUser(user);
          return user;
        }
      } catch (e) {
        if (e is AuthException) {
          throw ApiException(e.message, statusCode: 400);
        }
        rethrow;
      }
    }

    // Fallback for mock/offline testing environments
    final payload = <String, dynamic>{
      'email': email.trim().toLowerCase(),
      'password': password,
      'full_name': fullName.trim(),
      'default_currency': defaultCurrency.toUpperCase(),
    };
    if (phoneNumber != null && phoneNumber.trim().isNotEmpty) {
      payload['phone_number'] = phoneNumber.trim();
    }
    await apiClient.post(
      ApiConstants.register,
      data: payload,
    );

    return await login(email: email, password: password);
  }

  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    final client = SupabaseService.client;
    if (client != null) {
      try {
        final res = await client.auth.signInWithPassword(
          email: email.trim(),
          password: password,
        );

        final session = res.session;
        if (session != null) {
          await tokenStorage.saveTokens(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken ?? '',
          );
        }

        try {
          return await getMe();
        } catch (_) {
          final user = UserModel(
            id: res.user?.id ?? '',
            email: email.trim(),
            fullName: (res.user?.userMetadata?['full_name'] as String?) ?? 'User',
            defaultCurrency: (res.user?.userMetadata?['default_currency'] as String?) ?? 'USD',
            isActive: true,
            createdAt: DateTime.now(),
          );
          await tokenStorage.saveUser(user);
          return user;
        }
      } catch (e) {
        if (e is AuthException) {
          throw ApiException(e.message, statusCode: 401, isAuthError: true);
        }
        rethrow;
      }
    }

    // Fallback if Supabase not initialized
    final res = await apiClient.post(
      ApiConstants.login,
      data: {
        'email': email.trim(),
        'password': password,
      },
    );

    final accessToken = res['access_token'] as String;
    final refreshToken = res['refresh_token'] as String;
    await tokenStorage.saveTokens(accessToken: accessToken, refreshToken: refreshToken);

    // Fetch and cache authenticated profile
    final user = await getMe();
    await tokenStorage.saveUser(user);
    return user;
  }

  Future<UserModel> loginWithOAuth({
    required String provider,
    String? idToken,
    String? email,
    String? fullName,
    String? avatarUrl,
    String? phoneNumber,
    String? password,
  }) async {
    final payload = <String, dynamic>{
      'provider': provider.toLowerCase().trim(),
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

    final user = await getMe();
    await tokenStorage.saveUser(user);
    return user;
  }

  Future<UserModel> setPassword({
    required String password,
    String? phoneNumber,
    String? fullName,
  }) async {
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
    final user = UserModel.fromJson(res);
    await tokenStorage.saveUser(user);
    return user;
  }

  Future<String> refreshToken() async {
    final client = SupabaseService.client;
    if (client != null) {
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
      } catch (_) {}
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
    final user = UserModel.fromJson(res as Map<String, dynamic>);
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
    final user = UserModel.fromJson(res as Map<String, dynamic>);
    await tokenStorage.saveUser(user);
    return user;
  }

  Future<Map<String, dynamic>> exportUserData() async {
    final res = await apiClient.post(ApiConstants.userExport);
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  Future<void> signOut() async {
    try {
      final client = SupabaseService.client;
      if (client != null) {
        await client.auth.signOut();
      }
    } catch (_) {}

    try {
      final refresh = await tokenStorage.getRefreshToken();
      if (refresh != null && refresh.isNotEmpty) {
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
