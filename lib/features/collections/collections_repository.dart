import 'package:dio/dio.dart';
import '../../core/api/api_constants.dart';
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
}
