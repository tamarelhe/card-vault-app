import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists JWT access and refresh tokens in the device secure store.
class TokenStorage {
  static const _keyAccess = 'access_token';
  static const _keyRefresh = 'refresh_token';

  final FlutterSecureStorage _storage;

  const TokenStorage(this._storage);

  /// Saves both tokens after a successful login or refresh.
  Future<void> save({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _storage.write(key: _keyAccess, value: accessToken),
      _storage.write(key: _keyRefresh, value: refreshToken),
    ]);
  }

  /// Returns the stored access token, or null if not present.
  Future<String?> readAccessToken() => _storage.read(key: _keyAccess);

  /// Returns the stored refresh token, or null if not present.
  Future<String?> readRefreshToken() => _storage.read(key: _keyRefresh);

  /// Deletes both tokens on logout.
  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _keyAccess),
      _storage.delete(key: _keyRefresh),
    ]);
  }
}
