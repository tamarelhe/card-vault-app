import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../api/api_constants.dart';
import '../auth/token_storage.dart';

/// Builds and configures the singleton Dio HTTP client.
///
/// The [AuthInterceptor] automatically:
/// - Attaches `Authorization: Bearer <token>` to every request.
/// - On 401, attempts a token refresh and retries the original request once.
Dio buildDio(TokenStorage storage) {
  final dio = Dio(
    BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  dio.interceptors.add(_AuthInterceptor(dio, storage));
  if (ApiConstants.logHttp) dio.interceptors.add(_LoggingInterceptor());

  return dio;
}

/// Logs every HTTP request and response when [ApiConstants.logHttp] is true.
class _LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    debugPrint('[HTTP] → ${options.method} ${options.uri}');
    if (options.data != null) debugPrint('[HTTP]   body: ${options.data}');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    debugPrint('[HTTP] ← ${response.statusCode} ${response.requestOptions.uri}');
    debugPrint('[HTTP]   body: ${response.data}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    debugPrint('[HTTP] ✗ ${err.response?.statusCode} ${err.requestOptions.uri}');
    if (err.response?.data != null) debugPrint('[HTTP]   error: ${err.response?.data}');
    handler.next(err);
  }
}

/// Intercepts every request to inject the Bearer token, and retries once on 401.
class _AuthInterceptor extends Interceptor {
  final Dio _dio;
  final TokenStorage _storage;

  _AuthInterceptor(this._dio, this._storage);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _storage.readAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // Only retry on 401 and only once (guard against refresh loop).
    if (err.response?.statusCode != 401 ||
        err.requestOptions.extra['retried'] == true) {
      handler.next(err);
      return;
    }

    final refreshToken = await _storage.readRefreshToken();
    if (refreshToken == null) {
      handler.next(err);
      return;
    }

    try {
      // Perform token refresh without going through this interceptor again.
      final refreshDio = Dio(BaseOptions(baseUrl: ApiConstants.baseUrl));
      final resp = await refreshDio.post<Map<String, dynamic>>(
        ApiConstants.refresh,
        data: {'refresh_token': refreshToken},
      );
      await _storage.save(
        accessToken: resp.data!['access_token'] as String,
        refreshToken: resp.data!['refresh_token'] as String,
      );

      // Retry the original request with the new token.
      final opts = err.requestOptions
        ..headers['Authorization'] =
            'Bearer ${resp.data!["access_token"]}'
        ..extra['retried'] = true;

      final retryResponse = await _dio.fetch<dynamic>(opts);
      handler.resolve(retryResponse);
    } catch (_) {
      // Refresh failed — propagate the original 401.
      await _storage.clear();
      handler.next(err);
    }
  }
}
