/// Central place for API configuration.
///
/// Change [baseUrl] to point at staging or production when needed.
class ApiConstants {
  ApiConstants._();

  /// Local development backend.
  static const String baseUrl = 'http://localhost:8080';

  // Auth
  static const String register = '/api/v1/auth/register';
  static const String login = '/api/v1/auth/login';
  static const String refresh = '/api/v1/auth/refresh';
  static const String logout = '/api/v1/auth/logout';

  // Cards
  static const String cardsResolve = '/api/v1/cards/resolve';

  // Collections
  static const String collections = '/api/v1/collections';

  // Scan sessions
  static const String scanSessions = '/api/v1/scan/sessions';
}
