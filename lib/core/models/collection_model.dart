/// A user's card collection.
class CollectionModel {
  final String id;
  final String name;
  final String description;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CollectionModel({
    required this.id,
    required this.name,
    required this.description,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CollectionModel.fromJson(Map<String, dynamic> json) =>
      CollectionModel(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}

/// Paginated list of collections returned by `GET /api/v1/collections`.
class CollectionListResponse {
  final List<CollectionModel> items;
  final int total;
  final int page;
  final int pageSize;

  const CollectionListResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory CollectionListResponse.fromJson(Map<String, dynamic> json) {
    final meta = json['meta'] as Map<String, dynamic>;
    return CollectionListResponse(
      items: (json['items'] as List<dynamic>)
          .map((e) => CollectionModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: meta['total'] as int,
      page: meta['page'] as int,
      pageSize: meta['page_size'] as int,
    );
  }
}
