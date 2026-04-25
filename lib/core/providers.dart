import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api/api_client.dart';
import 'auth/auth_repository.dart';
import 'auth/token_storage.dart';

/// Secure storage singleton.
final secureStorageProvider = Provider<FlutterSecureStorage>(
  (_) => const FlutterSecureStorage(),
);

/// Token storage wrapping secure storage.
final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => TokenStorage(ref.watch(secureStorageProvider)),
);

/// Configured Dio client with auth interceptor.
final dioProvider = Provider<Dio>(
  (ref) => buildDio(ref.watch(tokenStorageProvider)),
);

/// Authentication repository.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(dioProvider),
    ref.watch(tokenStorageProvider),
  ),
);

/// Whether the user currently has a valid access token.
/// Used by go_router to decide whether to redirect to login.
final isAuthenticatedProvider = FutureProvider<bool>(
  (ref) => ref.watch(authRepositoryProvider).isAuthenticated(),
);
