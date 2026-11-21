import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_model.dart';
import '../network/api_client.dart';
import '../repositories/auth_repository.dart';
import '../network/token_storage.dart';
import '../di/injection.dart';

/// Authentication state machine states
enum AuthStatus { initializing, unauthenticated, authenticated, expired, error }

/// Immutable authentication state
class AuthState {
  final AuthStatus status;
  final UserModel? user;
  final String? errorMessage;
  final bool setupSkipped;

  const AuthState({
    required this.status,
    this.user,
    this.errorMessage,
    this.setupSkipped = false,
  });

  const AuthState.initializing()
    : status = AuthStatus.initializing,
      user = null,
      errorMessage = null,
      setupSkipped = false;

  const AuthState.unauthenticated()
    : status = AuthStatus.unauthenticated,
      user = null,
      errorMessage = null,
      setupSkipped = false;

  const AuthState.authenticated(UserModel user, {bool setupSkipped = false})
    : status = AuthStatus.authenticated,
      user = user,
      errorMessage = null,
      setupSkipped = setupSkipped;

  const AuthState.expired({String? message, UserModel? cachedUser})
    : status = AuthStatus.expired,
      user = cachedUser,
      errorMessage =
          message ?? 'Your session has expired. Please sign in again.',
      setupSkipped = false;

  const AuthState.error(String message)
    : status = AuthStatus.error,
      user = null,
      errorMessage = message,
      setupSkipped = false;

  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get isInitializing => status == AuthStatus.initializing;
  bool get isExpired => status == AuthStatus.expired;
  bool get isUnauthenticated => status == AuthStatus.unauthenticated;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthState &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          user == other.user &&
          errorMessage == other.errorMessage &&
          setupSkipped == other.setupSkipped;

  @override
  int get hashCode => Object.hash(status, user, errorMessage, setupSkipped);

  @override
  String toString() =>
      'AuthState(status: $status, user: ${user?.email}, setupSkipped: $setupSkipped, error: $errorMessage)';
}

/// Riverpod 3 Notifier managing the Authentication State Machine
class AuthNotifier extends Notifier<AuthState> {
  late final AuthRepository _authRepository;
  late final TokenStorage _tokenStorage;

  @override
  AuthState build() {
    _authRepository = Injection.authRepository;
    _tokenStorage = Injection.tokenStorage;

    // Register global session expiry callback with ApiClient
    Injection.apiClient.onSessionExpired = (reason) {
      if (ref.mounted) {
        markExpired(reason);
      }
    };

    // Auto-restore session asynchronously on app start
    Future.microtask(() {
      if (ref.mounted) {
        restoreSession();
      }
    });

    return const AuthState.initializing();
  }

  /// Restores session from secure storage, validating credentials against backend
  Future<void> restoreSession() async {
    if (!ref.mounted) return;
    state = const AuthState.initializing();

    final hasAccess = await _tokenStorage.hasAccessToken();
    final refreshToken = await _tokenStorage.getRefreshToken();

    if (!hasAccess && (refreshToken == null || refreshToken.isEmpty)) {
      if (ref.mounted) {
        state = const AuthState.unauthenticated();
      }
      return;
    }

    try {
      if (hasAccess) {
        final user = await _authRepository.getMe();
        if (ref.mounted) {
          state = AuthState.authenticated(user);
        }
        return;
      }

      // No access token, but refresh token exists: try refresh
      await _authRepository.refreshToken();
      final user = await _authRepository.getMe();
      if (ref.mounted) {
        state = AuthState.authenticated(user);
      }
    } catch (e) {
      if (!ref.mounted) return;

      if (e is ApiException && e.isAuthError) {
        // Access token rejected: attempt refresh
        try {
          await _authRepository.refreshToken();
          final user = await _authRepository.getMe();
          if (ref.mounted) {
            state = AuthState.authenticated(user);
          }
          return;
        } catch (_) {
          await _tokenStorage.clearAll();
          final cachedUser = await _tokenStorage.getCachedUser();
          if (ref.mounted) {
            state = AuthState.expired(cachedUser: cachedUser);
          }
          return;
        }
      }

      if (e is ApiException && e.isConnectionError) {
        // Offline or connection failure: check if cached session exists
        final cachedUser = await _tokenStorage.getCachedUser();
        if (ref.mounted) {
          if (cachedUser != null) {
            // Allow offline session restoration
            state = AuthState.authenticated(cachedUser);
          } else {
            state = AuthState.error(e.message);
          }
        }
        return;
      }

      // Any other exception: fallback safely
      final cachedUser = await _tokenStorage.getCachedUser();
      if (ref.mounted) {
        if (cachedUser != null) {
          state = AuthState.authenticated(cachedUser);
        } else {
          state = const AuthState.unauthenticated();
        }
      }
    }
  }

  /// Authenticates user credentials against backend
  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    try {
      final user = await _authRepository.login(
        email: email,
        password: password,
      );
      if (ref.mounted) {
        state = AuthState.authenticated(user, setupSkipped: false);
      }
      return user;
    } catch (e) {
      final message = e is ApiException ? e.message : e.toString();
      if (ref.mounted) {
        state = AuthState.error(message);
      }
      rethrow;
    }
  }

  /// Registers a new account and establishes authenticated session
  Future<UserModel> register({
    required String email,
    required String password,
    required String fullName,
    String? phoneNumber,
    String defaultCurrency = 'USD',
  }) async {
    try {
      final user = await _authRepository.register(
        email: email,
        password: password,
        fullName: fullName,
        phoneNumber: phoneNumber,
        defaultCurrency: defaultCurrency,
      );
      if (ref.mounted) {
        state = AuthState.authenticated(user, setupSkipped: false);
      }
      return user;
    } catch (e) {
      final message = e is ApiException ? e.message : e.toString();
      if (ref.mounted) {
        state = AuthState.error(message);
      }
      rethrow;
    }
  }

  /// Authenticates using OAuth provider (Google)
  Future<UserModel> loginWithOAuth({
    required String provider,
    String? idToken,
    String? email,
    String? fullName,
    String? avatarUrl,
    String? phoneNumber,
    String? password,
  }) async {
    try {
      final user = await _authRepository.loginWithOAuth(
        provider: provider,
        idToken: idToken,
        email: email,
        fullName: fullName,
        avatarUrl: avatarUrl,
        phoneNumber: phoneNumber,
        password: password,
      );
      if (ref.mounted) {
        state = AuthState.authenticated(user, setupSkipped: false);
      }
      return user;
    } catch (e) {
      final message = e is ApiException ? e.message : e.toString();
      if (ref.mounted) {
        state = AuthState.error(message);
      }
      rethrow;
    }
  }

  /// Sets or updates password and phone number for authenticated user
  Future<UserModel> setPassword({
    required String password,
    String? phoneNumber,
    String? fullName,
  }) async {
    try {
      final user = await _authRepository.setPassword(
        password: password,
        phoneNumber: phoneNumber,
        fullName: fullName,
      );
      if (ref.mounted) {
        state = AuthState.authenticated(user, setupSkipped: false);
      }
      return user;
    } catch (e) {
      final message = e is ApiException ? e.message : e.toString();
      if (ref.mounted) {
        state = AuthState.error(message);
      }
      rethrow;
    }
  }

  /// Skips direct password setup for OAuth users who choose to set it later
  void skipSetup() {
    if (ref.mounted && state.user != null) {
      state = AuthState.authenticated(state.user!, setupSkipped: true);
    }
  }

  /// Clears user session and tokens
  Future<void> signOut() async {
    await _authRepository.signOut();
    if (ref.mounted) {
      state = const AuthState.unauthenticated();
    }
  }

  /// Marks session as expired (e.g. from 401 refresh failure)
  void markExpired([String? reason]) {
    if (!ref.mounted) return;
    final cachedUser = state.user;
    state = AuthState.expired(message: reason, cachedUser: cachedUser);
  }

  /// Updates user profile (name, currency, etc.) and propagates state
  Future<UserModel> updateUser({
    String? fullName,
    String? defaultCurrency,
    String? avatarUrl,
  }) async {
    try {
      final updated = await _authRepository.updateMe(
        fullName: fullName,
        defaultCurrency: defaultCurrency,
        avatarUrl: avatarUrl,
      );
      if (ref.mounted) {
        state = AuthState.authenticated(updated, setupSkipped: state.setupSkipped);
      }
      return updated;
    } catch (e) {
      rethrow;
    }
  }

  /// Manually update cached user in state
  void setUser(UserModel user) {
    if (ref.mounted) {
      state = AuthState.authenticated(user, setupSkipped: state.setupSkipped);
    }
  }

  /// Resets error state back to unauthenticated
  void clearError() {
    if (!ref.mounted) return;
    if (state.status == AuthStatus.error) {
      state = const AuthState.unauthenticated();
    }
  }
}

/// Global provider for AuthNotifier
final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

/// Listenable adapter that notifies GoRouter when AuthState changes
class AuthRouterListenable extends ChangeNotifier {
  final Ref _ref;

  AuthRouterListenable(this._ref) {
    _ref.listen<AuthState>(authProvider, (previous, next) {
      if (previous?.status != next.status) {
        notifyListeners();
      }
    });
  }
}

/// Global Listenable provider for GoRouter refreshListenable
final authRouterListenableProvider = Provider<AuthRouterListenable>((ref) {
  return AuthRouterListenable(ref);
});
