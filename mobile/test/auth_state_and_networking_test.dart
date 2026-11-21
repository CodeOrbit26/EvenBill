import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:evenbill/core/models/user_model.dart';
import 'package:evenbill/core/models/activity_model.dart';
import 'package:evenbill/core/network/api_client.dart';
import 'package:evenbill/core/network/token_storage.dart';
import 'package:evenbill/core/providers/auth_provider.dart';
import 'package:evenbill/core/repositories/auth_repository.dart';
import 'package:evenbill/core/di/injection.dart';
import 'package:evenbill/routing/app_router.dart';
import 'package:evenbill/routing/route_names.dart';
import 'package:evenbill/screens/auth/sign_in_screen.dart';
import 'package:evenbill/screens/overview/overview_screen.dart';
import 'mocks/mock_repositories.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('EvenBill Authentication & State Machine Tests', () {
    late InMemoryTokenStorage testTokenStorage;

    setUp(() {
      testTokenStorage = InMemoryTokenStorage();
    });

    tearDown(() {
      Injection.reset();
    });

    test('Test 1: New installation with no existing session -> AuthStatus.unauthenticated', () async {
      final container = ProviderContainer();
      try {
        Injection.setMockRepositories(
          tokens: testTokenStorage,
          auth: MockAuthRepository(tokenStorage: testTokenStorage),
        );

        final notifier = container.read(authProvider.notifier);
        await notifier.restoreSession();

        final state = container.read(authProvider);
        expect(state.status, AuthStatus.unauthenticated);
        expect(state.user, isNull);
        expect(state.isAuthenticated, isFalse);
      } finally {
        container.dispose();
      }
    });

    test('Test 2: Successful registration and login transitions to AuthStatus.authenticated', () async {
      final container = ProviderContainer();
      try {
        Injection.setMockRepositories(
          tokens: testTokenStorage,
          auth: MockAuthRepository(tokenStorage: testTokenStorage),
        );

        final notifier = container.read(authProvider.notifier);
        final user = await notifier.login(email: 'sarah.connor@example.com', password: 'ValidPassword123!');

        final state = container.read(authProvider);
        expect(state.status, AuthStatus.authenticated);
        expect(state.user?.email, user.email);
        expect(state.isAuthenticated, isTrue);
      } finally {
        container.dispose();
      }
    });

    test('Test 3: Application restart with valid session restores authenticated state', () async {
      final container = ProviderContainer();
      try {
        // Pre-populate secure storage with existing session
        await testTokenStorage.saveTokens(
          accessToken: 'valid_mock_access_token',
          refreshToken: 'valid_mock_refresh_token',
        );
        const cached = UserModel(
          id: 'u-101',
          email: 'saved.user@example.com',
          fullName: 'Saved User',
        );
        await testTokenStorage.saveUser(cached);

        Injection.setMockRepositories(
          tokens: testTokenStorage,
          auth: MockAuthRepository(tokenStorage: testTokenStorage),
        );

        final notifier = container.read(authProvider.notifier);
        await notifier.restoreSession();

        final state = container.read(authProvider);
        expect(state.status, AuthStatus.authenticated);
        expect(state.isAuthenticated, isTrue);
      } finally {
        container.dispose();
      }
    });

    test('Test 4: Expired access token triggers seamless refresh via refresh token', () async {
      await testTokenStorage.saveTokens(
        accessToken: 'expired_access_token',
        refreshToken: 'valid_refresh_token',
      );

      // Create a Dio adapter that rejects expired_access_token with 401, but succeeds on refresh and retry
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
      dio.httpClientAdapter = _MockHttpAdapter((options) {
        if (options.path.contains('/auth/refresh')) {
          return ResponseBody.fromString(
            '{"data": {"access_token": "new_refreshed_access", "refresh_token": "new_refreshed_refresh"}}',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }

        final authHeader = options.headers['Authorization'] as String?;
        if (authHeader == 'Bearer expired_access_token') {
          return ResponseBody.fromString(
            '{"detail": "Token expired"}',
            401,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }

        if (authHeader == 'Bearer new_refreshed_access') {
          return ResponseBody.fromString(
            '{"data": {"status": "ok", "value": 42}}',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }

        return ResponseBody.fromString('{"detail": "Not authenticated"}', 401);
      });

      final apiClient = ApiClient(customDio: dio, customTokenStorage: testTokenStorage);

      // Perform a protected request
      final res = await apiClient.get('/protected-resource');
      expect(res, isNotNull);
      expect(res['status'], 'ok');

      // Verify refreshed tokens are persisted
      expect(await testTokenStorage.getAccessToken(), 'new_refreshed_access');
      expect(await testTokenStorage.getRefreshToken(), 'new_refreshed_refresh');
    });

    test('Test 5: Invalid access token with expired refresh token transitions to AuthStatus.expired', () async {
      final container = ProviderContainer();
      try {
        await testTokenStorage.saveTokens(
          accessToken: 'invalid_access',
          refreshToken: 'expired_refresh',
        );

        final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
        dio.httpClientAdapter = _MockHttpAdapter((options) {
          return ResponseBody.fromString(
            '{"detail": "Expired or invalid refresh token"}',
            401,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        });

        final apiClient = ApiClient(
          customDio: dio,
          customTokenStorage: testTokenStorage,
          onSessionExpired: (reason) {
            container.read(authProvider.notifier).markExpired(reason);
          },
        );

        final authRepo = AuthRepository(apiClient: apiClient, tokenStorage: testTokenStorage);
        Injection.setMockRepositories(tokens: testTokenStorage, client: apiClient, auth: authRepo);

        final notifier = container.read(authProvider.notifier);
        await notifier.restoreSession();

        final state = container.read(authProvider);
        expect(state.status, AuthStatus.expired);
        expect(state.isExpired, isTrue);
        expect(await testTokenStorage.hasAccessToken(), isFalse);
      } finally {
        container.dispose();
      }
    });

    test('Test 6: Backend unavailable yields connection error, not 401 or Not Authenticated', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://unreachable.local'));
      dio.httpClientAdapter = _MockHttpAdapter((options) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: 'Connection refused',
        );
      });

      final apiClient = ApiClient(customDio: dio, customTokenStorage: testTokenStorage);

      expect(
        () async => await apiClient.get('/activity/summary'),
        throwsA(predicate((e) =>
            e is ApiException &&
            e.isConnectionError &&
            !e.isAuthError &&
            e.message.contains('Unable to connect to EvenBill server'))),
      );
    });

    test('Test 7: Incorrect emulator URL or connection timeout produces distinct network error', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://10.0.2.99:8000'));
      dio.httpClientAdapter = _MockHttpAdapter((options) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
          error: 'Connection timed out',
        );
      });

      final apiClient = ApiClient(customDio: dio, customTokenStorage: testTokenStorage);

      try {
        await apiClient.get('/health');
        fail('Should have thrown ApiException');
      } catch (e) {
        expect(e, isA<ApiException>());
        final apiEx = e as ApiException;
        expect(apiEx.isConnectionError, isTrue);
        expect(apiEx.isAuthError, isFalse);
      }
    });

    test('Test 8: Logout clears session and subsequent protected calls fail with AuthStatus.unauthenticated', () async {
      final container = ProviderContainer();
      try {
        await testTokenStorage.saveTokens(
          accessToken: 'active_session_token',
          refreshToken: 'active_refresh_token',
        );
        Injection.setMockRepositories(
          tokens: testTokenStorage,
          auth: MockAuthRepository(tokenStorage: testTokenStorage),
        );

        final notifier = container.read(authProvider.notifier);
        await notifier.signOut();

        final state = container.read(authProvider);
        expect(state.status, AuthStatus.unauthenticated);
        expect(await testTokenStorage.hasAccessToken(), isFalse);
        expect(await testTokenStorage.getRefreshToken(), isNull);
      } finally {
        container.dispose();
      }
    });

    test('Test 9: Offline application startup restores session safely from cached profile', () async {
      final container = ProviderContainer();
      try {
        await testTokenStorage.saveTokens(
          accessToken: 'offline_token',
          refreshToken: 'offline_refresh',
        );
        const cached = UserModel(
          id: 'u-offline-1',
          email: 'offline.user@evenbill.app',
          fullName: 'Offline User',
        );
        await testTokenStorage.saveUser(cached);

        // Dio throws connection error (offline)
        final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
        dio.httpClientAdapter = _MockHttpAdapter((options) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          );
        });

        final apiClient = ApiClient(customDio: dio, customTokenStorage: testTokenStorage);
        final authRepo = AuthRepository(apiClient: apiClient, tokenStorage: testTokenStorage);
        Injection.setMockRepositories(tokens: testTokenStorage, client: apiClient, auth: authRepo);

        final notifier = container.read(authProvider.notifier);
        await notifier.restoreSession();

        final state = container.read(authProvider);
        // Confirmed: Offline-first architecture allows cached user access
        expect(state.status, AuthStatus.authenticated);
        expect(state.user?.email, 'offline.user@evenbill.app');
      } finally {
        container.dispose();
      }
    });

    test('Test 10: Session restoration during slow network maintains initializing state', () async {
      final container = ProviderContainer();
      try {
        await testTokenStorage.saveTokens(
          accessToken: 'slow_token',
          refreshToken: 'slow_refresh',
        );

        final completer = Completer<ResponseBody>();
        final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
        dio.httpClientAdapter = _MockHttpAdapter((options) async {
          return completer.future;
        });

        final apiClient = ApiClient(customDio: dio, customTokenStorage: testTokenStorage);
        final authRepo = AuthRepository(apiClient: apiClient, tokenStorage: testTokenStorage);
        Injection.setMockRepositories(tokens: testTokenStorage, client: apiClient, auth: authRepo);

        final notifier = container.read(authProvider.notifier);
        // Start restoration without awaiting completion immediately
        final restoreFuture = notifier.restoreSession();

        // State is initializing while network request is pending
        expect(container.read(authProvider).status, AuthStatus.initializing);

        // Now complete the slow request
        completer.complete(
          ResponseBody.fromString(
            '{"data": {"id": "u-slow", "email": "slow@evenbill.app", "full_name": "Slow Net", "default_currency": "USD"}}',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          ),
        );

        await restoreFuture;
        expect(container.read(authProvider).status, AuthStatus.authenticated);
      } finally {
        container.dispose();
      }
    });

    testWidgets('UI Guard: OverviewScreen renders Authentication Required (NOT Connection Disrupted) on 401', (tester) async {
      // Mock activity repo throwing 401 ApiException
      final mockActivity = _Mock401ActivityRepository();
      Injection.setMockRepositories(activity: mockActivity);

      await tester.pumpWidget(
        MaterialApp(
          home: OverviewScreen(
            onExpenseTap: (_) {},
            onSettleUpTap: () {},
            onScanReceiptTap: () {},
            onAddExpenseTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verified: Title must NOT say 'Connection Disrupted'
      expect(find.text('Connection Disrupted'), findsNothing);
      expect(find.text('Authentication Required'), findsOneWidget);
      expect(find.text('Sign In Again'), findsOneWidget);
    });

    testWidgets('UI Guard: SignInScreen displays session expired alert banner when expired', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SignInScreen(
            sessionExpiredMessage: 'Your session has expired. Please sign in again.',
            onSignInSuccess: () {},
            onNavigateToRegister: () {},
            onBack: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Your session has expired. Please sign in again.'), findsOneWidget);
      expect(find.byType(SignInScreen), findsOneWidget);
    });

    testWidgets('GoRouter Guard: Unauthenticated user navigating to /shell is redirected to /onboarding', (tester) async {
      final router = createAppRouter(
        initialLocation: AppRoutes.shell,
        getAuthState: () => const AuthState.unauthenticated(),
      );

      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Get Started'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
    });

    test('Test 14: Google OAuth sign-in establishes authenticated state and stores session', () async {
      final container = ProviderContainer();
      try {
        final mockAuth = MockAuthRepository(tokenStorage: testTokenStorage);
        Injection.setMockRepositories(tokens: testTokenStorage, auth: mockAuth);

        final notifier = container.read(authProvider.notifier);
        final user = await notifier.loginWithOAuth(
          provider: 'google',
          email: 'google.tester@gmail.com',
          fullName: 'Google Tester',
        );

        final state = container.read(authProvider);
        expect(state.status, AuthStatus.authenticated);
        expect(state.user?.email, 'google.tester@gmail.com');
        expect(user.fullName, 'Google Tester');
      } finally {
        container.dispose();
      }
    });

    test('Test 15: Token storage remembers user email for subsequent login sessions', () async {
      final container = ProviderContainer();
      try {
        final mockAuth = MockAuthRepository(tokenStorage: testTokenStorage);
        Injection.setMockRepositories(tokens: testTokenStorage, auth: mockAuth);

        await testTokenStorage.saveLastEmail('abhay.gupta@gmail.com');
        final remembered = await testTokenStorage.getLastEmail();
        expect(remembered, 'abhay.gupta@gmail.com');

        final notifier = container.read(authProvider.notifier);
        final user = await notifier.login(email: 'abhay.gupta@gmail.com', password: 'Password123!');

        final state = container.read(authProvider);
        expect(state.status, AuthStatus.authenticated);
        expect(state.user?.email, 'abhay.gupta@gmail.com');
        expect(user.fullName, 'Abhay Gupta');
      } finally {
        container.dispose();
      }
    });
  });
}

class _MockHttpAdapter implements HttpClientAdapter {
  final FutureOr<ResponseBody> Function(RequestOptions options) handler;

  _MockHttpAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

class _Mock401ActivityRepository extends MockActivityRepository {
  @override
  Future<ActivitySummaryModel> getActivitySummary({String? currency}) async {
    throw ApiException('Not authenticated', statusCode: 401, isAuthError: true);
  }

  @override
  Future<List<ActivityItemModel>> listActivity({
    String? groupId,
    String? category,
    String? search,
    int limit = 50,
  }) async {
    throw ApiException('Not authenticated', statusCode: 401, isAuthError: true);
  }
}
