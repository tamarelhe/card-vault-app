/// Central place for API configuration.
///
/// Change [baseUrl] to point at staging or production when needed.
class ApiConstants {
  ApiConstants._();

  /// Local development backend.
  static const String baseUrl = 'http://192.168.1.193:8080';

  /// Set to true to print every HTTP request and response to the console.
  static const bool logHttp = true;

  // Auth
  static const String register = '/api/v1/auth/register';
  static const String login = '/api/v1/auth/login';
  static const String refresh = '/api/v1/auth/refresh';
  static const String logout = '/api/v1/auth/logout';

  // Cards
  static const String cardsResolve = '/api/v1/cards/resolve';

  // Collections
  static const String collections = '/api/v1/collections';

  /// Cards endpoint for a specific collection.
  static String collectionCards(String id) => '$collections/$id/cards';

  // Scan sessions
  static const String scanSessions = '/api/v1/scan/sessions';
}
