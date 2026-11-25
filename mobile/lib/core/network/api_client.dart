import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/api_constants.dart';
import '../services/supabase_service.dart';
import 'token_storage.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic details;
  final bool isConnectionError;
  final bool isAuthError;
  final bool isForbidden;

  ApiException(
    this.message, {
    this.statusCode,
    this.details,
    this.isConnectionError = false,
    this.isAuthError = false,
    this.isForbidden = false,
  });

  @override
  String toString() => message;
}

class ApiClient {
  final Dio dio;
  final TokenStorage tokenStorage;
  Completer<String?>? _refreshCompleter;
  void Function(String reason)? onSessionExpired;

  ApiClient({
    Dio? customDio,
    TokenStorage? customTokenStorage,
    this.onSessionExpired,
  })  : tokenStorage = customTokenStorage ?? TokenStorage(),
        dio = customDio ??
            Dio(
              BaseOptions(
                baseUrl: ApiConstants.baseUrl,
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(seconds: 30),
                headers: {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
              ),
            ) {
    _setupInterceptors();
  }

  void _setupInterceptors() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final isPublicAuth = options.path.contains('/auth/login') ||
              options.path.contains('/auth/register') ||
              options.path.contains('/auth/refresh') ||
              options.path.contains('/auth/oauth') ||
              options.path.contains('/health');

          if (!isPublicAuth) {
            final token = await tokenStorage.getAccessToken();
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) async {
          final isAuthEndpoint = error.requestOptions.path.contains('/auth/login') ||
              error.requestOptions.path.contains('/auth/register') ||
              error.requestOptions.path.contains('/auth/refresh') ||
              error.requestOptions.path.contains('/auth/oauth') ||
              error.requestOptions.path.contains('/auth/logout');
          final alreadyRetried = error.requestOptions.extra['_authRetried'] == true;

          // Automatic token refresh on 401 for protected endpoints (at most once per request)
          if (error.response?.statusCode == 401 && !isAuthEndpoint && !alreadyRetried) {
            if (_refreshCompleter != null) {
              // Refresh already in progress: wait for it and retry
              try {
                final newAccess = await _refreshCompleter!.future;
                if (newAccess != null && newAccess.isNotEmpty) {
                  final retryOptions = error.requestOptions;
                  retryOptions.extra['_authRetried'] = true;
                  retryOptions.headers['Authorization'] = 'Bearer $newAccess';
                  final retryRes = await dio.fetch(retryOptions);
                  return handler.resolve(retryRes);
                }
              } catch (_) {}
              return handler.next(error);
            }

            final hadAccess = await tokenStorage.hasAccessToken();
            final storedRefresh = await tokenStorage.getRefreshToken();
            final client = SupabaseService.client;
            final hasSupabaseSession = client?.auth.currentSession != null;

            if (!hasSupabaseSession && (storedRefresh == null || storedRefresh.isEmpty)) {
              if (hadAccess) {
                await tokenStorage.clearAll();
                onSessionExpired?.call('Your session has expired. Please sign in again.');
              }
              return handler.next(error);
            }

            final completer = Completer<String?>();
            _refreshCompleter = completer;
            try {
              String? newAccess;
              bool isNetworkFailure = false;

              // 1. Prioritize Supabase session refresh when Supabase session is active
              if (hasSupabaseSession) {
                try {
                  final refreshRes = await client!.auth.refreshSession();
                  final session = refreshRes.session;
                  if (session != null) {
                    newAccess = session.accessToken;
                    await tokenStorage.saveTokens(
                      accessToken: newAccess,
                      refreshToken: session.refreshToken ?? '',
                    );
                  }
                } on AuthRetryableFetchException catch (e) {
                  isNetworkFailure = true;
                  debugPrint('[ApiClient] Supabase refresh network error: $e');
                } on SocketException catch (e) {
                  isNetworkFailure = true;
                  debugPrint('[ApiClient] Supabase refresh socket error: $e');
                } on TimeoutException catch (e) {
                  isNetworkFailure = true;
                  debugPrint('[ApiClient] Supabase refresh timeout: $e');
                } catch (e) {
                  debugPrint('[ApiClient] Supabase refresh exception: $e');
                }
              }

              // 2. Fall back to backend refresh for legacy JWT sessions or uninitialized Supabase tests
              final shouldTryBackendRefresh = (newAccess == null || newAccess.isEmpty) &&
                  !isNetworkFailure &&
                  storedRefresh != null &&
                  storedRefresh.isNotEmpty &&
                  (client == null || storedRefresh.split('.').length == 3);

              if (shouldTryBackendRefresh) {
                try {
                  final refreshDio = Dio(
                    BaseOptions(
                      baseUrl: ApiConstants.baseUrl,
                      connectTimeout: const Duration(seconds: 30),
                      receiveTimeout: const Duration(seconds: 30),
                    ),
                  );
                  refreshDio.httpClientAdapter = dio.httpClientAdapter;
                  final res = await refreshDio.post(
                    ApiConstants.refresh,
                    data: {'refresh_token': storedRefresh},
                  );

                  if (res.statusCode == 200 && res.data != null) {
                    final data = res.data is Map<String, dynamic> && res.data.containsKey('data')
                        ? res.data['data']
                        : res.data;
                    newAccess = data['access_token'] as String;
                    final newRefresh = data['refresh_token'] as String;
                    await tokenStorage.saveTokens(accessToken: newAccess, refreshToken: newRefresh);
                  }
                } on DioException catch (e) {
                  if (e.type == DioExceptionType.connectionTimeout ||
                      e.type == DioExceptionType.receiveTimeout ||
                      e.type == DioExceptionType.sendTimeout ||
                      e.type == DioExceptionType.connectionError) {
                    isNetworkFailure = true;
                  }
                }
              }

              if (newAccess != null && newAccess.isNotEmpty) {
                completer.complete(newAccess);

                // Retry the original request once with refreshed Bearer token
                final retryOptions = error.requestOptions;
                retryOptions.extra['_authRetried'] = true;
                retryOptions.headers['Authorization'] = 'Bearer $newAccess';
                final retryRes = await dio.fetch(retryOptions);
                return handler.resolve(retryRes);
              } else if (isNetworkFailure) {
                // Preserve local offline session instead of wiping cache on transient network loss
                completer.complete(null);
              } else {
                completer.complete(null);
                if (hadAccess) {
                  await tokenStorage.clearAll();
                  onSessionExpired?.call('Your session has expired. Please sign in again.');
                }
              }
            } catch (_) {
              completer.complete(null);
              if (hadAccess) {
                await tokenStorage.clearAll();
                onSessionExpired?.call('Your session has expired. Please sign in again.');
              }
            } finally {
              _refreshCompleter = null;
            }
          }
          return handler.next(error);
        },
      ),
    );
  }

  ApiException _handleError(dynamic error) {
    if (error is ApiException) return error;

    if (error is DioException) {
      final res = error.response;
      final statusCode = res?.statusCode;
      final isConnection = error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.connectionError;

      if (isConnection) {
        return ApiException(
          'Unable to connect to EvenBill server. Please verify backend is running.',
          statusCode: statusCode,
          isConnectionError: true,
        );
      }

      if (res != null && res.data is Map<String, dynamic>) {
        final data = res.data as Map<String, dynamic>;
        String? message;
        if (data.containsKey('detail') && data['detail'] != null) {
          message = data['detail'].toString();
        } else if (data.containsKey('error') && data['error'] != null) {
          message = data['error'].toString();
        }

        if (message != null) {
          return ApiException(
            message,
            statusCode: statusCode,
            details: data,
            isAuthError: statusCode == 401,
            isForbidden: statusCode == 403,
          );
        }
      }

      if (statusCode == 401) {
        return ApiException(
          'Authentication required or session expired.',
          statusCode: 401,
          isAuthError: true,
        );
      }

      if (statusCode == 403) {
        return ApiException(
          'Access forbidden. Pro subscription or permissions required.',
          statusCode: 403,
          isForbidden: true,
        );
      }

      return ApiException(
        error.message ?? 'A network error occurred. Please try again.',
        statusCode: statusCode,
      );
    }
    return ApiException(error.toString());
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? queryParameters}) async {
    try {
      final res = await dio.get(path, queryParameters: queryParameters);
      return _extractData(res);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<dynamic> post(String path, {dynamic data, Map<String, dynamic>? queryParameters}) async {
    try {
      final res = await dio.post(path, data: data, queryParameters: queryParameters);
      return _extractData(res);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<dynamic> put(String path, {dynamic data, Map<String, dynamic>? queryParameters}) async {
    try {
      final res = await dio.put(path, data: data, queryParameters: queryParameters);
      return _extractData(res);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<dynamic> delete(String path, {dynamic data, Map<String, dynamic>? queryParameters}) async {
    try {
      final res = await dio.delete(path, data: data, queryParameters: queryParameters);
      return _extractData(res);
    } catch (e) {
      throw _handleError(e);
    }
  }

  dynamic _extractData(Response response) {
    final body = response.data;
    if (body is Map<String, dynamic> && body.containsKey('data')) {
      return body['data'];
    }
    return body;
  }
}
