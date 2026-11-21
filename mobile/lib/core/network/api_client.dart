import 'dart:async';
import 'package:dio/dio.dart';
import '../constants/api_constants.dart';
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
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 10),
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
              options.path.contains('/health');

          final token = await tokenStorage.getAccessToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          } else if (!isPublicAuth && !options.headers.containsKey('Authorization')) {
            // Protected request without access token
            // Still let it pass to let backend or mock handle, but ensure no stale header
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) async {
          final isAuthEndpoint = error.requestOptions.path.contains('/auth/login') ||
              error.requestOptions.path.contains('/auth/register') ||
              error.requestOptions.path.contains('/auth/refresh');

          // Automatic token refresh on 401 for protected endpoints
          if (error.response?.statusCode == 401 && !isAuthEndpoint) {
            if (_refreshCompleter != null) {
              // Refresh already in progress: wait for it and retry
              try {
                final newAccess = await _refreshCompleter!.future;
                if (newAccess != null && newAccess.isNotEmpty) {
                  final retryOptions = error.requestOptions;
                  retryOptions.headers['Authorization'] = 'Bearer $newAccess';
                  final retryRes = await dio.fetch(retryOptions);
                  return handler.resolve(retryRes);
                }
              } catch (_) {}
              return handler.next(error);
            }

            final refreshToken = await tokenStorage.getRefreshToken();
            if (refreshToken != null && refreshToken.isNotEmpty) {
              final completer = Completer<String?>();
              _refreshCompleter = completer;
              try {
                final refreshDio = Dio(
                  BaseOptions(
                    baseUrl: ApiConstants.baseUrl,
                    connectTimeout: const Duration(seconds: 10),
                    receiveTimeout: const Duration(seconds: 10),
                  ),
                );
                refreshDio.httpClientAdapter = dio.httpClientAdapter;
                final res = await refreshDio.post(
                  ApiConstants.refresh,
                  data: {'refresh_token': refreshToken},
                );

                if (res.statusCode == 200 && res.data != null) {
                  final data = res.data is Map<String, dynamic> && res.data.containsKey('data')
                      ? res.data['data']
                      : res.data;
                  final newAccess = data['access_token'] as String;
                  final newRefresh = data['refresh_token'] as String;
                  await tokenStorage.saveTokens(accessToken: newAccess, refreshToken: newRefresh);
                  completer.complete(newAccess);

                  // Retry the original request
                  final retryOptions = error.requestOptions;
                  retryOptions.headers['Authorization'] = 'Bearer $newAccess';
                  final retryRes = await dio.fetch(retryOptions);
                  return handler.resolve(retryRes);
                } else {
                  completer.complete(null);
                  await tokenStorage.clearAll();
                  onSessionExpired?.call('Your session has expired. Please sign in again.');
                }
              } catch (_) {
                completer.complete(null);
                await tokenStorage.clearAll();
                onSessionExpired?.call('Your session has expired. Please sign in again.');
              } finally {
                _refreshCompleter = null;
              }
            } else {
              // 401 with no refresh token available
              final hadAccess = await tokenStorage.hasAccessToken();
              if (hadAccess) {
                await tokenStorage.clearAll();
                onSessionExpired?.call('Your session has expired. Please sign in again.');
              }
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
