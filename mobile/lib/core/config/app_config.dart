import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Environment & Network Configuration for EvenBill Mobile
class AppConfig {
  /// Dynamically resolved API Base URL
  /// Supports:
  /// - `--dart-define=API_BASE_URL=http://<LAN_IP>:8000/api/v1` (Physical devices)
  /// - `http://10.0.2.2:8000/api/v1` (Android Emulator loopback)
  /// - `http://127.0.0.1:8000/api/v1` (iOS Simulator & Desktop)
  static String get apiBaseUrl {
    const defined = String.fromEnvironment('API_BASE_URL');
    if (defined.isNotEmpty) {
      return defined;
    }

    if (kIsWeb) {
      return 'http://localhost:8000/api/v1';
    }

    try {
      if (Platform.isAndroid) {
        return 'http://10.0.2.2:8000/api/v1';
      }
    } catch (_) {
      // Platform check not supported in certain test runners
    }

    return 'http://127.0.0.1:8000/api/v1';
  }

  /// Supabase Configuration
  /// Injected at compile/run time via:
  /// `--dart-define=SUPABASE_URL=https://<project-ref>.supabase.co`
  /// `--dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...`
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://aniqkrmuurmhwxkiahxv.supabase.co',
  );

  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_GSrWtiv5G3Egh6YjoMz28Q_PXoMt-x5',
  );

  /// Check whether Supabase configuration is present
  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
