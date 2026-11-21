import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';

/// Centralized service managing the lifecycle and connectivity of the Supabase Client
class SupabaseService {
  static bool _initialized = false;

  /// Whether Supabase SDK has been successfully initialized
  static bool get isInitialized => _initialized;

  /// Safe accessor for the SupabaseClient instance (null if uninitialized)
  static SupabaseClient? get client {
    if (!_initialized) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Initialize Supabase using environment-specific AppConfig
  static Future<bool> initialize({
    String? url,
    String? publishableKey,
  }) async {
    final targetUrl = url ?? AppConfig.supabaseUrl;
    final targetKey = publishableKey ?? AppConfig.supabasePublishableKey;

    if (targetUrl.isEmpty || targetKey.isEmpty) {
      debugPrint('[SupabaseService] Skipping initialization: missing URL or publishable key');
      return false;
    }

    try {
      await Supabase.initialize(
        url: targetUrl,
        publishableKey: targetKey,
        debug: kDebugMode,
      );
      _initialized = true;
      debugPrint('[SupabaseService] Successfully initialized connected to $targetUrl');
      return true;
    } catch (e) {
      debugPrint('[SupabaseService] Initialization error: $e');
      return false;
    }
  }

  /// Tests connectivity and responsiveness to the Supabase endpoint
  static Future<bool> checkConnectivity() async {
    if (!_initialized) return false;
    try {
      final currentClient = client;
      if (currentClient == null) return false;
      // Probe Supabase Auth health/status
      final _ = currentClient.auth.currentSession;
      return true;
    } catch (e) {
      debugPrint('[SupabaseService] Connectivity check error: $e');
      return false;
    }
  }

  /// Explicitly reset for test harness isolation
  @visibleForTesting
  static void resetForTesting() {
    _initialized = false;
  }
}
