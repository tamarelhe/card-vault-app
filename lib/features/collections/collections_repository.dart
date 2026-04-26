import 'package:dio/dio.dart';
import '../../core/api/api_constants.dart';
import '../../core/models/collection_card_model.dart';
import '../../core/models/collection_model.dart';

/// Handles all collection-related API calls.
class CollectionsRepository {
  final Dio _dio;

  CollectionsRepository(this._dio);

  /// Lists the authenticated user's collections (page 1, up to 50).
  Future<CollectionListResponse> listCollections({
    int page = 1,
    int pageSize = 50,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiConstants.collections,
      queryParameters: {'page': page, 'page_size': pageSize},
    );
    return CollectionListResponse.fromJson(response.data!);
  }

  /// Creates a new collection and returns it.
  Future<CollectionModel> createCollection({
    required String name,
    String description = '',
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiConstants.collections,
      data: {'name': name, 'description': description},
    );
    return CollectionModel.fromJson(response.data!);
  }

  /// Deletes a collection by ID.
  Future<void> deleteCollection(String id) async {
    await _dio.delete<void>('${ApiConstants.collections}/$id');
  }

  /// Returns a paginated list of cards in [collectionId].
  ///
  /// All filter and sort parameters map directly to the API query params.
  Future<CollectionCardListResponse> listCollectionCards(
    String collectionId, {
    String? query,
    String? setCode,
    String? cardType,
    String sortBy = 'name',
    String sortOrder = 'asc',
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiConstants.collectionCards(collectionId),
      queryParameters: {
        if (query != null && query.isNotEmpty) 'q': query,
        if (setCode != null && setCode.isNotEmpty) 'set_code': setCode,
        if (cardType != null && cardType.isNotEmpty) 'card_type': cardType,
        'sort_by': sortBy,
        'sort_order': sortOrder,
        'page': page,
        'page_size': pageSize,
      },
    );
    return CollectionCardListResponse.fromJson(response.data!);
  }
}
