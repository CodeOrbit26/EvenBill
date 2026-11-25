import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState, Headers;
import 'package:evenbill/core/models/user_model.dart';
import 'package:evenbill/core/models/activity_model.dart';
import 'package:evenbill/core/models/expense_model.dart';
import 'package:evenbill/core/models/friend_model.dart';
import 'package:evenbill/core/models/group_model.dart';
import 'package:evenbill/core/network/api_client.dart';
import 'package:evenbill/core/network/token_storage.dart';
import 'package:evenbill/core/providers/auth_provider.dart';
import 'package:evenbill/core/repositories/auth_repository.dart';
import 'package:evenbill/core/repositories/expense_repository.dart';
import 'package:evenbill/core/repositories/settlement_repository.dart';
import 'package:evenbill/core/services/google_auth_service.dart';
import 'package:evenbill/core/services/supabase_service.dart';
import 'package:evenbill/core/utils/identity_utils.dart';
import 'package:evenbill/core/di/injection.dart';
import 'package:evenbill/routing/app_router.dart';
import 'package:evenbill/routing/route_names.dart';
import 'package:evenbill/screens/auth/registration_screen.dart';
import 'package:evenbill/screens/auth/sign_in_screen.dart';
import 'package:evenbill/screens/expenses/add_edit_expense_screen.dart';
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

        await testTokenStorage.saveLastEmail('test.user@example.com');
        final remembered = await testTokenStorage.getLastEmail();
        expect(remembered, 'test.user@example.com');

        final notifier = container.read(authProvider.notifier);
        final user = await notifier.login(email: 'test.user@example.com', password: 'Password123!');

        final state = container.read(authProvider);
        expect(state.status, AuthStatus.authenticated);
        expect(state.user?.email, 'test.user@example.com');
        expect(user.fullName, 'Abhay Gupta');
      } finally {
        container.dispose();
      }
    });

    test('Test 16: Registration requiring email confirmation raises EmailConfirmationRequiredException & leaves state unauthenticated', () async {
      final container = ProviderContainer();
      try {
        final mockAuth = MockAuthRepository(tokenStorage: testTokenStorage);
        mockAuth.requireEmailConfirmation = true;
        Injection.setMockRepositories(tokens: testTokenStorage, auth: mockAuth);

        final notifier = container.read(authProvider.notifier);
        try {
          await notifier.register(
            email: 'unconfirmed@evenbill.app',
            password: 'StrongPassword123!',
            fullName: 'Unconfirmed User',
          );
          fail('Expected EmailConfirmationRequiredException');
        } catch (e) {
          expect(e, isA<EmailConfirmationRequiredException>());
        }

        final state = container.read(authProvider);
        expect(state.status, AuthStatus.unauthenticated);
        expect(state.isAuthenticated, isFalse);
      } finally {
        container.dispose();
      }
    });

    test('Test 17: Login with unconfirmed email raises error with clear guidance message', () async {
      final container = ProviderContainer();
      try {
        final mockAuth = MockAuthRepository(tokenStorage: testTokenStorage);
        mockAuth.throwEmailNotConfirmedOnLogin = true;
        Injection.setMockRepositories(tokens: testTokenStorage, auth: mockAuth);

        final notifier = container.read(authProvider.notifier);
        try {
          await notifier.login(email: 'pending@evenbill.app', password: 'Password123!');
          fail('Expected ApiException');
        } catch (e) {
          expect(e, isA<ApiException>());
          final apiErr = e as ApiException;
          expect(apiErr.statusCode, 401);
          expect(apiErr.message.toLowerCase(), contains('email not confirmed'));
        }

        final state = container.read(authProvider);
        expect(state.status, AuthStatus.error);
        expect(state.errorMessage?.toLowerCase(), contains('email not confirmed'));
      } finally {
        container.dispose();
      }
    });

    testWidgets('Test 18: RegistrationScreen routes to SignIn with verification notice when confirmation is required', (tester) async {
      final mockAuth = MockAuthRepository(tokenStorage: testTokenStorage);
      mockAuth.requireEmailConfirmation = true;
      Injection.setMockRepositories(tokens: testTokenStorage, auth: mockAuth);

      bool navigatedToLogin = false;
      bool registeredSuccess = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: RegistrationScreen(
              onRegisterSuccess: () => registeredSuccess = true,
              onNavigateToLogin: () => navigatedToLogin = true,
              onBack: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Confirm Tester');
      await tester.enterText(fields.at(1), 'confirm.tester@evenbill.app');
      await tester.enterText(fields.at(3), 'StrongPass123!');
      await tester.pumpAndSettle();

      final submitBtn = find.text('Create Account').last;
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(registeredSuccess, isFalse);
      expect(navigatedToLogin, isTrue);
      expect(
        find.text('Account created! Please check your email to verify your account before logging in.'),
        findsOneWidget,
      );
    });

    testWidgets('Test 19: SignInScreen shows email confirmation guidance when Email not confirmed returned', (tester) async {
      final mockAuth = MockAuthRepository(tokenStorage: testTokenStorage);
      mockAuth.throwEmailNotConfirmedOnLogin = true;
      Injection.setMockRepositories(tokens: testTokenStorage, auth: mockAuth);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: SignInScreen(
              onSignInSuccess: () {},
              onNavigateToRegister: () {},
              onBack: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'pending@evenbill.app');
      await tester.enterText(find.byType(TextField).last, 'Password123!');
      await tester.tap(find.text('Sign In').last);
      await tester.pumpAndSettle();

      expect(
        find.text('Your email address is not confirmed yet. Please check your inbox and verify your account before signing in.'),
        findsOneWidget,
      );
    });

    testWidgets('Test 20: SignInScreen Forgot Password validates email and invokes password recovery', (tester) async {
      final mockAuth = MockAuthRepository(tokenStorage: testTokenStorage);
      Injection.setMockRepositories(tokens: testTokenStorage, auth: mockAuth);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: SignInScreen(
              onSignInSuccess: () {},
              onNavigateToRegister: () {},
              onBack: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Recover.User@EvenBill.App');
      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();

      expect(find.text('Reset Password'), findsOneWidget);
      await tester.tap(find.text('Send Reset Link'));
      await tester.pumpAndSettle();

      expect(mockAuth.lastPasswordResetEmail, 'recover.user@evenbill.app');
      expect(
        find.text('Password recovery instructions sent to Recover.User@EvenBill.App if an account exists.'),
        findsOneWidget,
      );
    });

    test('Test 21: ApiClient does not fire session expiry without prior access or loop endlessly on repeated 401', () async {
      int refreshCalls = 0;
      int expiryCallbacks = 0;

      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
      dio.httpClientAdapter = _MockHttpAdapter((options) {
        if (options.path.contains('/auth/refresh')) {
          refreshCalls++;
          return ResponseBody.fromString(
            '{"data": {"access_token": "still_bad_access", "refresh_token": "r2"}}',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        return ResponseBody.fromString('{"detail": "Unauthorized"}', 401);
      });

      final apiClient = ApiClient(
        customDio: dio,
        customTokenStorage: testTokenStorage,
        onSessionExpired: (_) => expiryCallbacks++,
      );

      // Case A: Unauthenticated call (no stored access or refresh) -> must NOT trigger session expiry
      await expectLater(
        () => apiClient.get('/protected-resource'),
        throwsA(isA<ApiException>()),
      );
      expect(refreshCalls, 0);
      expect(expiryCallbacks, 0);

      // Case B: Authenticated call where retried request STILL gets 401 -> refresh runs only once
      await testTokenStorage.saveTokens(
        accessToken: 'expired_access',
        refreshToken: 'valid_refresh',
      );
      await expectLater(
        () => apiClient.get('/protected-resource'),
        throwsA(isA<ApiException>()),
      );
      expect(refreshCalls, 1);
    });

    test('Test 22: AuthNotifier.setPassword updates hasPassword flag on authenticated user', () async {
      final container = ProviderContainer();
      try {
        final mockAuth = MockAuthRepository(tokenStorage: testTokenStorage);
        Injection.setMockRepositories(tokens: testTokenStorage, auth: mockAuth);

        final notifier = container.read(authProvider.notifier);
        final oauthUser = await notifier.loginWithOAuth(
          provider: 'google',
          email: 'google.user@evenbill.app',
          fullName: 'Google User',
        );
        expect(oauthUser.hasPassword, isFalse);

        final updated = await notifier.setPassword(
          password: 'NewDirectPassword123!',
          fullName: 'Google User Updated',
        );
        expect(updated.hasPassword, isTrue);
        expect(container.read(authProvider).user?.hasPassword, isTrue);
      } finally {
        container.dispose();
      }
    });

    test('Test 23: GoogleAuthService generates distinct high-entropy raw nonces and standard SHA-256 hex digests', () {
      final nonces = <String>{};
      for (int i = 0; i < 20; i++) {
        final raw = GoogleAuthService.generateRawNonce();
        expect(raw.length, greaterThanOrEqualTo(43));
        expect(raw.contains('='), isFalse);
        expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(raw), isTrue);
        nonces.add(raw);

        final expectedDigest = sha256.convert(utf8.encode(raw)).toString();
        expect(GoogleAuthService.hashNonce(raw), expectedDigest);
        expect(expectedDigest.length, 64);
        expect(expectedDigest, isNot(equals(raw)));
      }
      expect(nonces.length, 20);
    });

    test('Test 24: GoogleAuthService.signIn sends fresh SHA-256 nonce per attempt, returns raw nonce, and handles cancel safely', () async {
      final originalPlatform = GoogleSignInPlatform.instance;
      final fakePlatform = _FakeGoogleSignInPlatform();
      GoogleSignInPlatform.instance = fakePlatform;
      GoogleAuthService.resetForTesting();

      try {
        // Attempt 1
        final res1 = await GoogleAuthService.signIn();
        expect(res1, isNotNull);
        expect(res1!.idToken, 'google_id_token_1');
        expect(res1.nonce, isNotNull);
        expect(fakePlatform.recordedInitParams.length, 1);
        expect(
          fakePlatform.recordedInitParams[0].serverClientId,
          GoogleAuthService.serverClientId,
        );
        expect(
          fakePlatform.recordedInitParams[0].nonce,
          GoogleAuthService.hashNonce(res1.nonce!),
        );

        // User cancels Attempt 2
        fakePlatform.nextError = const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled,
          description: 'User dismissed credential sheet',
        );
        final canceledRes = await GoogleAuthService.signIn();
        expect(canceledRes, isNull);
        expect(fakePlatform.recordedInitParams.length, 2);
        expect(
          fakePlatform.recordedInitParams[1].nonce,
          isNot(equals(fakePlatform.recordedInitParams[0].nonce)),
        );

        // Attempt 3 succeeds with a brand-new nonce
        final res3 = await GoogleAuthService.signIn();
        expect(res3, isNotNull);
        expect(res3!.nonce, isNotNull);
        expect(res3.nonce, isNot(equals(res1.nonce)));
        expect(fakePlatform.recordedInitParams.length, 3);
        expect(
          fakePlatform.recordedInitParams[2].nonce,
          GoogleAuthService.hashNonce(res3.nonce!),
        );
      } finally {
        GoogleAuthService.resetForTesting();
        GoogleSignInPlatform.instance = originalPlatform;
      }
    });

    test('Test 25: End-to-end Google OAuth nonce passes hashed digest to SDK and matching raw nonce to Supabase signInWithIdToken', () async {
      final originalPlatform = GoogleSignInPlatform.instance;
      final fakePlatform = _FakeGoogleSignInPlatform();
      GoogleSignInPlatform.instance = fakePlatform;
      GoogleAuthService.resetForTesting();

      final recordedTokenRequests = <Map<String, dynamic>>[];
      bool simulateNonceMismatch = false;

      final fakeSupabaseHttp = _FakeSupabaseHttpClient((request) async {
        if (request.url.path == '/auth/v1/token' &&
            request.url.queryParameters['grant_type'] == 'id_token') {
          final parsed = jsonDecode(request.body) as Map<String, dynamic>;
          recordedTokenRequests.add(parsed);

          if (simulateNonceMismatch) {
            return http.Response(
              jsonEncode({
                'error': 'invalid_grant',
                'error_description': 'Nonces mismatch',
                'message':
                    'Passed nonce and nonce in id_token should either both exist or not',
              }),
              400,
              headers: const {'content-type': 'application/json'},
            );
          }

          return http.Response(
            jsonEncode({
              'access_token': 'sb_oauth_access_jwt',
              'token_type': 'bearer',
              'expires_in': 3600,
              'refresh_token': 'sb_oauth_refresh_opaque',
              'user': {
                'id': '00000000-0000-0000-0000-000000000123',
                'aud': 'authenticated',
                'email': 'google.user@evenbill.app',
                'created_at': '2026-11-25T10:00:00Z',
                'email_confirmed_at': '2026-11-25T10:00:00Z',
                'app_metadata': {
                  'provider': 'google',
                  'providers': ['google'],
                },
                'user_metadata': {
                  'full_name': 'Google OAuth User',
                },
              },
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }

        return http.Response('{"error":"not_found"}', 404);
      });

      final testSupabaseClient = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: fakeSupabaseHttp,
        authOptions: const AuthClientOptions(
          authFlowType: AuthFlowType.implicit,
          autoRefreshToken: false,
        ),
      );
      SupabaseService.setClientForTesting(testSupabaseClient);

      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
      dio.httpClientAdapter = _MockHttpAdapter((options) {
        if (options.path.contains('/auth/me') &&
            options.headers['Authorization'] == 'Bearer sb_oauth_access_jwt') {
          return ResponseBody.fromString(
            jsonEncode({
              'data': {
                'id': '00000000-0000-0000-0000-000000000123',
                'email': 'google.user@evenbill.app',
                'full_name': 'Google OAuth User',
                'default_currency': 'USD',
                'is_active': true,
                'is_verified': true,
                'has_password': false,
                'is_pro': false,
                'created_at': '2026-11-25T10:00:00Z',
              },
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        return ResponseBody.fromString('{"detail": "Unexpected request"}', 401);
      });

      final apiClient = ApiClient(customDio: dio, customTokenStorage: testTokenStorage);
      final authRepo = AuthRepository(apiClient: apiClient, tokenStorage: testTokenStorage);

      try {
        // Happy path: GoogleAuthService -> AuthRepository -> Supabase /auth/v1/token -> /auth/me
        final googleResult = await GoogleAuthService.signIn();
        expect(googleResult, isNotNull);
        final sentHashedNonce = fakePlatform.recordedInitParams.single.nonce!;
        expect(sentHashedNonce, GoogleAuthService.hashNonce(googleResult!.nonce!));

        final user = await authRepo.loginWithOAuth(
          provider: 'google',
          idToken: googleResult.idToken,
          nonce: googleResult.nonce,
          email: googleResult.email,
          fullName: googleResult.fullName,
          avatarUrl: googleResult.avatarUrl,
        );

        expect(user.id, '00000000-0000-0000-0000-000000000123');
        expect(user.email, 'google.user@evenbill.app');
        expect(recordedTokenRequests.length, 1);
        expect(recordedTokenRequests[0]['provider'], 'google');
        expect(recordedTokenRequests[0]['id_token'], googleResult.idToken);
        expect(recordedTokenRequests[0]['nonce'], googleResult.nonce);
        expect(
          GoogleAuthService.hashNonce(recordedTokenRequests[0]['nonce'] as String),
          sentHashedNonce,
        );
        expect(await testTokenStorage.getAccessToken(), 'sb_oauth_access_jwt');

        // Failure path: Supabase rejects mismatched nonce -> typed ApiException thrown safely
        simulateNonceMismatch = true;
        final retryGoogle = await GoogleAuthService.signIn();
        expect(retryGoogle, isNotNull);
        await expectLater(
          () => authRepo.loginWithOAuth(
            provider: 'google',
            idToken: retryGoogle!.idToken,
            nonce: retryGoogle.nonce,
          ),
          throwsA(predicate((e) =>
              e is ApiException &&
              e.isAuthError &&
              e.statusCode == 401 &&
              e.message.toLowerCase().contains('nonce'))),
        );
      } finally {
        await testSupabaseClient.dispose();
        SupabaseService.resetForTesting();
        GoogleAuthService.resetForTesting();
        GoogleSignInPlatform.instance = originalPlatform;
      }
    });

    test('Test 26: ExpenseRepository & SettlementRepository reject placeholder and malformed UUIDs client-side', () async {
      int networkCalls = 0;
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
      dio.httpClientAdapter = _MockHttpAdapter((options) {
        networkCalls++;
        return ResponseBody.fromString('{"detail": "Should not reach network"}', 500);
      });

      final apiClient = ApiClient(customDio: dio, customTokenStorage: testTokenStorage);
      final expenseRepo = ExpenseRepository(apiClient: apiClient);
      final settlementRepo = SettlementRepository(apiClient: apiClient);
      const validUuid = '11111111-1111-4111-8111-111111111111';

      expect(isPlaceholderUserId('current_user'), isTrue);
      expect(isPlaceholderUserId('usr_me'), isTrue);
      expect(isValidUuid('current_user'), isFalse);
      expect(isValidUuid(validUuid), isTrue);

      final invalidExpenseAttempts = <Future<ExpenseModel> Function()>[
        () => expenseRepo.createExpense(
              description: 'Bad payer',
              totalAmount: 50,
              payers: const [PayerModel(userId: 'current_user', fullName: 'Me', amountPaid: 50)],
              participantIds: const [validUuid],
            ),
        () => expenseRepo.createExpense(
              description: 'Bad participant',
              totalAmount: 50,
              payers: const [PayerModel(userId: validUuid, fullName: 'Me', amountPaid: 50)],
              participantIds: const ['usr_me'],
            ),
        () => expenseRepo.createExpense(
              description: 'Bad percentages key',
              totalAmount: 50,
              splitType: 'PERCENTAGE',
              payers: const [PayerModel(userId: validUuid, fullName: 'Me', amountPaid: 50)],
              percentages: const {'current_user': 100.0},
            ),
        () => expenseRepo.createExpense(
              description: 'Bad shares key',
              totalAmount: 50,
              splitType: 'SHARES',
              payers: const [PayerModel(userId: validUuid, fullName: 'Me', amountPaid: 50)],
              shares: const {'not-a-uuid': 1.0},
            ),
        () => expenseRepo.createExpense(
              description: 'Bad adjustments key',
              totalAmount: 50,
              splitType: 'ADJUSTMENT',
              payers: const [PayerModel(userId: validUuid, fullName: 'Me', amountPaid: 50)],
              adjustments: const {'usr_current': 0.0},
            ),
      ];

      for (final attempt in invalidExpenseAttempts) {
        await expectLater(
          attempt,
          throwsA(predicate((e) => e is ApiException && e.statusCode == 422)),
        );
      }

      await expectLater(
        () => settlementRepo.recordSettlement(
          groupId: validUuid,
          payerId: 'current_user',
          recipientId: validUuid,
          amount: 25,
        ),
        throwsA(predicate((e) => e is ApiException && e.statusCode == 422)),
      );
      await expectLater(
        () => settlementRepo.recordSettlement(
          groupId: validUuid,
          payerId: validUuid,
          recipientId: 'usr_me',
          amount: 25,
        ),
        throwsA(predicate((e) => e is ApiException && e.statusCode == 422)),
      );

      expect(networkCalls, 0);
    });

    testWidgets('Test 27: AddEditExpenseScreen uses authenticated user UUID rather than current_user for group and direct expenses', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const canonicalUuid = '11111111-1111-4111-8111-111111111111';
      const member2Uuid = '22222222-2222-4222-8222-222222222222';
      const member3Uuid = '33333333-3333-4333-8333-333333333333';
      const groupUuid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

      // Seed stale placeholder user in storage to confirm resolveAuthenticatedUser refreshes from /auth/me
      await testTokenStorage.saveUser(const UserModel(
        id: 'current_user',
        email: 'alex@evenbill.app',
        fullName: 'Stale User',
      ));

      final mockAuth = MockAuthRepository(tokenStorage: testTokenStorage)
        ..currentUser = const UserModel(
          id: canonicalUuid,
          email: 'alex@evenbill.app',
          fullName: 'Alex Mercer',
        );
      final targetGroup = const GroupModel(
        id: groupUuid,
        name: 'Goa Crew',
        groupType: 'TRIP',
        baseCurrency: 'USD',
        inviteCode: 'GOACREW1',
        createdBy: canonicalUuid,
        memberCount: 3,
      );
      final mockGroup = _FixedGroupDetailRepository(
        groupList: [targetGroup],
        detail: GroupDetailModel(
          group: targetGroup,
          members: const [
            GroupMemberModel(id: 'gm1', userId: canonicalUuid, fullName: 'Alex Mercer', email: 'alex@evenbill.app', role: 'ADMIN'),
            GroupMemberModel(id: 'gm2', userId: member2Uuid, fullName: 'Maya Rao', email: 'maya@evenbill.app', role: 'MEMBER'),
            GroupMemberModel(id: 'gm3', userId: member3Uuid, fullName: 'Rohan Nair', email: 'rohan@evenbill.app', role: 'MEMBER'),
          ],
          netBalances: const [],
          simplifiedDebts: const [],
          bilateralDebts: const [],
        ),
      );
      final mockFriend = MockFriendRepository()
        ..friends.clear()
        ..friends.add(
          const FriendModel(id: member2Uuid, name: 'Maya Rao', email: 'maya@evenbill.app', netBalance: 0.0),
        );
      final spyExpense = _IdentitySpyExpenseRepository();

      Injection.setMockRepositories(
        tokens: testTokenStorage,
        auth: mockAuth,
        group: mockGroup,
        friend: mockFriend,
        expense: spyExpense,
        settlement: MockSettlementRepository(),
        activity: MockActivityRepository(),
        subscription: MockSubscriptionRepository(),
      );

      // 1) Multi-member group expense
      bool groupSaved = false;
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: AddEditExpenseScreen(
            preselectedGroupId: groupUuid,
            onSaved: () => groupSaved = true,
            onBack: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), '90.00');
      await tester.enterText(find.byType(TextField).at(1), 'Villa Stay');
      await tester.pump();
      await tester.ensureVisible(find.text('Save Expense'));
      await tester.tap(find.text('Save Expense'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(groupSaved, isTrue);
      expect(spyExpense.lastGroupId, groupUuid);
      expect(spyExpense.lastPayers, isNotNull);
      expect(spyExpense.lastPayers!.single.userId, canonicalUuid);
      expect(isPlaceholderUserId(spyExpense.lastPayers!.single.userId), isFalse);
      expect(spyExpense.lastParticipantIds, containsAll(<String>[canonicalUuid, member2Uuid, member3Uuid]));

      // 2) Direct / personal (non-group) expense
      mockGroup.groupList.clear();
      bool directSaved = false;
      await tester.pumpWidget(ProviderScope(
        key: const ValueKey('direct_scope'),
        child: MaterialApp(
          key: const ValueKey('direct_app'),
          home: AddEditExpenseScreen(
            key: const ValueKey('direct_expense_screen'),
            onSaved: () => directSaved = true,
            onBack: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), '24.50');
      await tester.enterText(find.byType(TextField).at(1), 'Airport Taxi');
      await tester.pump();
      await tester.ensureVisible(find.text('Save Expense'));
      await tester.tap(find.text('Save Expense'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(directSaved, isTrue);
      expect(spyExpense.lastPayers!.single.userId, canonicalUuid);
      expect(isPlaceholderUserId(spyExpense.lastPayers!.single.userId), isFalse);
    });

    test('Test 28a: Second device Google login with fresh storage authenticates canonical user and never falls back to offline user', () async {
      const canonicalUuid = '11111111-1111-4111-8111-111111111111';
      final fakeSupabaseHttp = _FakeSupabaseHttpClient((request) async {
        if (request.url.path == '/auth/v1/token' &&
            request.url.queryParameters['grant_type'] == 'id_token') {
          return http.Response(
            jsonEncode({
              'access_token': 'sb_phone2_jwt',
              'token_type': 'bearer',
              'expires_in': 3600,
              'refresh_token': 'sb_phone2_refresh',
              'user': {
                'id': canonicalUuid,
                'aud': 'authenticated',
                'email': 'phone2@evenbill.app',
                'created_at': '2026-11-25T10:00:00Z',
                'email_confirmed_at': '2026-11-25T10:00:00Z',
                'app_metadata': {'provider': 'google', 'providers': ['google']},
                'user_metadata': {'full_name': 'Cross Device User'},
              },
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 200, headers: const {'content-type': 'application/json'});
      });

      final testSupabaseClient = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: fakeSupabaseHttp,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      SupabaseService.setClientForTesting(testSupabaseClient);

      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
      dio.httpClientAdapter = _MockHttpAdapter((options) {
        if (options.path.contains('/auth/me')) {
          return ResponseBody.fromString(
            jsonEncode({
              'data': {
                'id': canonicalUuid,
                'email': 'phone2@evenbill.app',
                'full_name': 'Cross Device User',
                'default_currency': 'USD',
                'is_active': true,
                'is_verified': true,
                'has_password': false,
                'is_pro': false,
                'created_at': '2026-11-25T10:00:00Z',
              },
            }),
            200,
            headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
          );
        }
        return ResponseBody.fromString('{"detail": "Unexpected path"}', 404);
      });

      final apiClient = ApiClient(customDio: dio, customTokenStorage: testTokenStorage);
      final authRepo = AuthRepository(apiClient: apiClient, tokenStorage: testTokenStorage);
      Injection.setMockRepositories(tokens: testTokenStorage, auth: authRepo);

      final container = ProviderContainer();
      try {
        await container.read(authProvider.notifier).loginWithOAuth(
              provider: 'google',
              idToken: 'fake_google_id_token',
            );

        final authState = container.read(authProvider);
        expect(authState.status, AuthStatus.authenticated);
        expect(authState.user?.id, canonicalUuid);
        expect(authState.user?.hasPassword, isFalse);
        expect((await testTokenStorage.getCachedUser())?.id, canonicalUuid);
      } finally {
        container.dispose();
        await testSupabaseClient.dispose();
        SupabaseService.resetForTesting();
      }
    });

    testWidgets('Test 28b: Second device OAuth user lands directly on /shell, restores groups, and surfaces fetch errors cleanly', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const canonicalUuid = '11111111-1111-4111-8111-111111111111';
      final oauthUser = const UserModel(
        id: canonicalUuid,
        email: 'phone2@evenbill.app',
        fullName: 'Cross Device User',
        hasPassword: false,
      );
      final mockAuth = MockAuthRepository(tokenStorage: testTokenStorage)
        ..currentUser = oauthUser
        ..authenticated = true;
      final restoredGroup = const GroupModel(
        id: 'gggggggg-gggg-4ggg-8ggg-gggggggggggg',
        name: 'Trip to Goa',
        groupType: 'TRIP',
        baseCurrency: 'USD',
        inviteCode: 'GOA999',
        createdBy: canonicalUuid,
        memberCount: 3,
      );

      Injection.setMockRepositories(
        tokens: testTokenStorage,
        auth: mockAuth,
        group: _FixedGroupDetailRepository(
          groupList: [restoredGroup],
          detail: GroupDetailModel(
            group: restoredGroup,
            members: const [],
            netBalances: const [],
            simplifiedDebts: const [],
            bilateralDebts: const [],
          ),
        ),
        expense: MockExpenseRepository(),
        settlement: MockSettlementRepository(),
        friend: MockFriendRepository()..friends.clear(),
        activity: MockActivityRepository(),
        subscription: MockSubscriptionRepository(),
        pro: MockProRepository(),
      );

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(authProvider.notifier).loginWithOAuth(
            provider: 'google',
            idToken: 'fake_google_id_token',
          );

      // Returning OAuth user lands directly on /shell rather than forced CompleteSetupScreen
      final router = createAppRouter(
        initialLocation: AppRoutes.signIn,
        getAuthState: () => container.read(authProvider),
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, AppRoutes.shell);
      expect(find.text('Trip to Goa'), findsOneWidget);
      expect(find.text('No Groups Yet'), findsNothing);

      // When groups fetch fails, OverviewScreen must surface an error rather than "No Groups Yet"
      Injection.setMockRepositories(
        tokens: testTokenStorage,
        auth: mockAuth,
        group: _ThrowingGroupRepository(),
        expense: MockExpenseRepository(),
        settlement: MockSettlementRepository(),
        friend: MockFriendRepository()..friends.clear(),
        activity: MockActivityRepository(),
        subscription: MockSubscriptionRepository(),
        pro: MockProRepository(),
      );
      await tester.pumpWidget(MaterialApp(
        key: const ValueKey('overview_error_app'),
        home: OverviewScreen(
          onExpenseTap: (_) {},
          onSettleUpTap: () {},
          onScanReceiptTap: () {},
          onAddExpenseTap: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Try Again'), findsOneWidget);
      expect(find.text('No Groups Yet'), findsNothing);
    });

    test('Test 29: Re-login after app restart reconciles cached identity with Supabase session and avoids fake login on /auth/me failure', () async {
      const staleUuid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
      const activeUuid = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

      final fakeSupabaseHttp = _FakeSupabaseHttpClient((request) async {
        if (request.url.path == '/auth/v1/token' &&
            request.url.queryParameters['grant_type'] == 'id_token') {
          return http.Response(
            jsonEncode({
              'access_token': 'sb_restart_jwt',
              'token_type': 'bearer',
              'expires_in': 3600,
              'refresh_token': 'sb_restart_refresh',
              'user': {
                'id': activeUuid,
                'aud': 'authenticated',
                'email': 'active@evenbill.app',
                'created_at': '2026-11-25T10:00:00Z',
                'email_confirmed_at': '2026-11-25T10:00:00Z',
                'app_metadata': {'provider': 'google', 'providers': ['google']},
                'user_metadata': {'full_name': 'Active Account'},
              },
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 200, headers: const {'content-type': 'application/json'});
      });

      final testSupabaseClient = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: fakeSupabaseHttp,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      SupabaseService.setClientForTesting(testSupabaseClient);

      bool failMe = true;
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
      dio.httpClientAdapter = _MockHttpAdapter((options) {
        if (options.path.contains('/auth/me')) {
          if (failMe) {
            return ResponseBody.fromString('{"detail": "Backend restarting"}', 503);
          }
          return ResponseBody.fromString(
            jsonEncode({
              'data': {
                'id': activeUuid,
                'email': 'active@evenbill.app',
                'full_name': 'Active Account',
                'default_currency': 'USD',
                'is_active': true,
                'is_verified': true,
                'has_password': false,
                'is_pro': false,
                'created_at': '2026-11-25T10:00:00Z',
              },
            }),
            200,
            headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
          );
        }
        return ResponseBody.fromString('{"detail": "Unexpected"}', 404);
      });

      final apiClient = ApiClient(customDio: dio, customTokenStorage: testTokenStorage);
      final authRepo = AuthRepository(apiClient: apiClient, tokenStorage: testTokenStorage);
      Injection.setMockRepositories(tokens: testTokenStorage, auth: authRepo);

      try {
        // 1) Initial Google OAuth login with /auth/me down must throw & clear tokens instead of fabricating fake user
        await expectLater(
          () => authRepo.loginWithOAuth(provider: 'google', idToken: 'google_id_tok'),
          throwsA(isA<ApiException>()),
        );
        expect(await testTokenStorage.getAccessToken(), isNull);
        expect(await testTokenStorage.getCachedUser(), isNull);

        // 2) Establish active Supabase session for activeUuid while cache holds staleUuid (account switch / restart)
        await testSupabaseClient.auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: 'google_id_tok',
        );
        await testTokenStorage.saveTokens(
          accessToken: 'sb_restart_jwt',
          refreshToken: 'sb_restart_refresh',
        );
        await testTokenStorage.saveUser(const UserModel(
          id: staleUuid,
          email: 'stale@evenbill.app',
          fullName: 'Stale Cache',
        ));

        // 2a) Offline restoreSession refuses mismatched cached user (staleUuid != activeUuid)
        final containerOffline = ProviderContainer();
        addTearDown(containerOffline.dispose);
        await containerOffline.read(authProvider.notifier).restoreSession();
        expect(containerOffline.read(authProvider).status, AuthStatus.unauthenticated);
        expect(await testTokenStorage.getCachedUser(), isNull);

        // 2b) Re-seed stale cache + restoreSession when /auth/me succeeds -> reconciles to activeUuid
        failMe = false;
        await testTokenStorage.saveTokens(
          accessToken: 'sb_restart_jwt',
          refreshToken: 'sb_restart_refresh',
        );
        await testTokenStorage.saveUser(const UserModel(
          id: staleUuid,
          email: 'stale@evenbill.app',
          fullName: 'Stale Cache',
        ));
        final containerOnline = ProviderContainer();
        addTearDown(containerOnline.dispose);
        await containerOnline.read(authProvider.notifier).restoreSession();
        expect(containerOnline.read(authProvider).status, AuthStatus.authenticated);
        expect(containerOnline.read(authProvider).user?.id, activeUuid);
        expect((await testTokenStorage.getCachedUser())?.id, activeUuid);
      } finally {
        await testSupabaseClient.dispose();
        SupabaseService.resetForTesting();
      }
    });
  });
}

class _FixedGroupDetailRepository extends MockGroupRepository {
  final List<GroupModel> groupList;
  final GroupDetailModel detail;

  _FixedGroupDetailRepository({required this.groupList, required this.detail});

  @override
  Future<List<GroupModel>> listGroups() async => List<GroupModel>.from(groupList);

  @override
  Future<GroupDetailModel> getGroupDetails(String groupId) async => detail;
}

class _ThrowingGroupRepository extends MockGroupRepository {
  @override
  Future<List<GroupModel>> listGroups() async {
    throw ApiException('Backend unavailable', statusCode: 500);
  }
}

class _IdentitySpyExpenseRepository extends MockExpenseRepository {
  String? lastGroupId;
  String? lastDescription;
  List<PayerModel>? lastPayers;
  List<String>? lastParticipantIds;

  @override
  Future<ExpenseModel> createExpense({
    String? idempotencyKey,
    String? groupId,
    required String description,
    required double totalAmount,
    String currency = 'USD',
    String splitType = 'EQUAL',
    String category = 'GENERAL',
    DateTime? expenseDate,
    String? notes,
    List<PayerModel>? payers,
    List<String>? participantIds,
    List<SplitModel>? splits,
    Map<String, double>? percentages,
    Map<String, double>? shares,
    Map<String, double>? adjustments,
    List<ItemizedItemInput>? items,
    double tax = 0.0,
    double tip = 0.0,
    double fee = 0.0,
    double discount = 0.0,
    String transactionType = 'EXPENSE',
    String? originalExpenseId,
    double? exchangeRate,
    String? exchangeRateSource,
  }) async {
    lastGroupId = groupId;
    lastDescription = description;
    lastPayers = payers;
    lastParticipantIds = participantIds;
    return super.createExpense(
      idempotencyKey: idempotencyKey,
      groupId: groupId,
      description: description,
      totalAmount: totalAmount,
      currency: currency,
      splitType: splitType,
      category: category,
      expenseDate: expenseDate,
      notes: notes,
      payers: payers,
      participantIds: participantIds,
      splits: splits,
      percentages: percentages,
      shares: shares,
      adjustments: adjustments,
      items: items,
      tax: tax,
      tip: tip,
      fee: fee,
      discount: discount,
      transactionType: transactionType,
      originalExpenseId: originalExpenseId,
      exchangeRate: exchangeRate,
      exchangeRateSource: exchangeRateSource,
    );
  }
}

class _FakeGoogleSignInPlatform extends GoogleSignInPlatform {
  final List<InitParameters> recordedInitParams = <InitParameters>[];
  Object? nextError;
  int _counter = 0;

  @override
  Future<void> init(InitParameters params) async {
    recordedInitParams.add(params);
  }

  @override
  Future<AuthenticationResults?>? attemptLightweightAuthentication(
    AttemptLightweightAuthenticationParameters params,
  ) =>
      null;

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<AuthenticationResults> authenticate(AuthenticateParameters params) async {
    final err = nextError;
    if (err != null) {
      nextError = null;
      throw err;
    }
    _counter++;
    return AuthenticationResults(
      user: const GoogleSignInUserData(
        email: 'google.user@evenbill.app',
        id: 'google-uid-1',
        displayName: 'Google OAuth User',
      ),
      authenticationTokens: AuthenticationTokenData(
        idToken: 'google_id_token_$_counter',
      ),
    );
  }

  @override
  bool authorizationRequiresUserInteraction() => false;

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
    ClientAuthorizationTokensForScopesParameters params,
  ) async =>
      null;

  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
    ServerAuthorizationTokensForScopesParameters params,
  ) async =>
      null;

  @override
  Future<void> signOut(SignOutParams params) async {}

  @override
  Future<void> disconnect(DisconnectParams params) async {}
}

class _FakeSupabaseHttpClient extends http.BaseClient {
  final Future<http.Response> Function(http.Request request) handler;

  _FakeSupabaseHttpClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bodyBytes = await request.finalize().toBytes();
    final buffered = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = bodyBytes;
    final response = await handler(buffered);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
      reasonPhrase: response.reasonPhrase,
    );
  }
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
