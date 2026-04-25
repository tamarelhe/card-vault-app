import 'package:dio/dio.dart';
import '../api/api_constants.dart';
import 'token_storage.dart';

/// Handles authentication with the backend (register, login, refresh, logout).
class AuthRepository {
  final Dio _dio;
  final TokenStorage _storage;

  AuthRepository(this._dio, this._storage);

  /// Registers a new user and stores the returned token pair.
  Future<void> register({
    required String email,
    required String password,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiConstants.register,
      data: {'email': email, 'password': password},
    );
    await _saveTokens(response.data!);
  }

  /// Logs in an existing user and stores the returned token pair.
  Future<void> login({
    required String email,
    required String password,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiConstants.login,
      data: {'email': email, 'password': password},
    );
    await _saveTokens(response.data!);
  }

  /// Exchanges the stored refresh token for a new token pair.
  /// Returns false if the refresh token is missing or expired.
  Future<bool> refreshTokens() async {
    final refreshToken = await _storage.readRefreshToken();
    if (refreshToken == null) return false;

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiConstants.refresh,
        data: {'refresh_token': refreshToken},
      );
      await _saveTokens(response.data!);
      return true;
    } on DioException {
      // Refresh token is expired or revoked — force re-login.
      await _storage.clear();
      return false;
    }
  }

  /// Revokes the current refresh token and clears local storage.
  Future<void> logout() async {
    final refreshToken = await _storage.readRefreshToken();
    if (refreshToken != null) {
      try {
        await _dio.post<void>(
          ApiConstants.logout,
          data: {'refresh_token': refreshToken},
        );
      } catch (_) {
        // Best-effort logout — clear local tokens regardless.
      }
    }
    await _storage.clear();
  }

  /// Returns true when an access token is currently stored.
  Future<bool> isAuthenticated() async {
    return (await _storage.readAccessToken()) != null;
  }

  Future<void> _saveTokens(Map<String, dynamic> data) async {
    await _storage.save(
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String,
    );
  }
}
