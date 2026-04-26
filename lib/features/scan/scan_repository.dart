import 'package:dio/dio.dart';
import '../../core/api/api_constants.dart';
import '../../core/models/resolution_result.dart';
import '../../core/models/scan_hints.dart';

/// Communicates with the backend scan and collections endpoints.
class ScanRepository {
  final Dio _dio;

  ScanRepository(this._dio);

  /// Resolves [hints] against the card catalogue.
  ///
  /// Calls `POST /api/v1/cards/resolve` and returns a [ResolutionResult]
  /// containing the matched card(s) or a not-found status.
  Future<ResolutionResult> resolve(ScanHints hints) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiConstants.cardsResolve,
      data: hints.toJson(),
    );
    return ResolutionResult.fromJson(response.data!);
  }

  /// Creates a new scan session and returns its ID.
  ///
  /// A session groups multiple scanned cards before they are imported
  /// into a collection.
  Future<String> createScanSession() async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiConstants.scanSessions,
    );
    return response.data!['id'] as String;
  }

  /// Adds a scanned card to an open session and returns the raw item JSON.
  ///
  /// The backend auto-resolves the item. The caller should inspect
  /// `resolution_status` in the returned map.
  Future<Map<String, dynamic>> addItemToSession(
    String sessionId,
    ScanHints hints,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '${ApiConstants.scanSessions}/$sessionId/items',
      data: {
        ...hints.toJson(),
        'quantity': 1,
        'condition': 'near_mint',
        'language': 'en',
        'foil': false,
        'notes': '',
      },
    );
    return response.data!;
  }

  /// Imports a completed session into [collectionId].
  Future<void> importSession(String sessionId, String collectionId) async {
    await _dio.post<void>(
      '${ApiConstants.scanSessions}/$sessionId/import',
      data: {'collection_id': collectionId},
    );
  }
}
