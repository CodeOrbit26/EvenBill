import 'package:flutter_test/flutter_test.dart';
import 'package:evenbill/core/config/app_config.dart';
import 'package:evenbill/core/services/supabase_service.dart';
import 'package:evenbill/core/network/token_storage.dart';
import 'mocks/mock_repositories.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Supabase Configuration & Connectivity Tests', () {
    test('AppConfig resolves valid Supabase URL and Publishable Key from environment', () {
      expect(AppConfig.supabaseUrl, isNotEmpty);
      expect(AppConfig.supabaseUrl, startsWith('https://'));
      expect(AppConfig.supabaseUrl, contains('supabase.co'));
      expect(AppConfig.supabasePublishableKey, isNotEmpty);
      expect(AppConfig.supabasePublishableKey, startsWith('sb_publishable_'));
      expect(AppConfig.isSupabaseConfigured, isTrue);
    });

    test('SupabaseService exposes safe uninitialized state before initialize()', () {
      SupabaseService.resetForTesting();
      expect(SupabaseService.isInitialized, isFalse);
      expect(SupabaseService.client, isNull);
    });

    test('SupabaseService.checkConnectivity returns false safely when uninitialized', () async {
      SupabaseService.resetForTesting();
      final connected = await SupabaseService.checkConnectivity();
      expect(connected, isFalse);
    });

    test('AuthRepository preserves fallback when Supabase is uninitialized in test harness', () async {
      SupabaseService.resetForTesting();
      final tokenStorage = InMemoryTokenStorage();
      final authRepo = MockAuthRepository(tokenStorage: tokenStorage);

      final user = await authRepo.login(
        email: 'test@evenbill.app',
        password: 'Password123!',
      );

      expect(user.email, 'test@evenbill.app');
      expect(authRepo.authenticated, isTrue);
    });

    test('TokenStorage correctly stores and clears Supabase JWT session tokens', () async {
      final tokenStorage = InMemoryTokenStorage();
      const fakeSupabaseAccessToken = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.supabase-token';
      const fakeSupabaseRefreshToken = 'sb_refresh_token_xyz987';

      await tokenStorage.saveTokens(
        accessToken: fakeSupabaseAccessToken,
        refreshToken: fakeSupabaseRefreshToken,
      );

      expect(await tokenStorage.getAccessToken(), fakeSupabaseAccessToken);
      expect(await tokenStorage.getRefreshToken(), fakeSupabaseRefreshToken);
      expect(await tokenStorage.hasAccessToken(), isTrue);

      await tokenStorage.clearAll();
      expect(await tokenStorage.getAccessToken(), isNull);
      expect(await tokenStorage.getRefreshToken(), isNull);
      expect(await tokenStorage.hasAccessToken(), isFalse);
    });
  });
}
