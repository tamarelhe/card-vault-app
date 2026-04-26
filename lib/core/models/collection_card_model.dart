/// A card entry within a collection, as returned by
/// `GET /api/v1/collections/{id}/cards`.
class CollectionCardModel {
  final String id;
  final String cardId;
  final String cardName;
  final String setCode;
  final String setName;
  final String collectorNumber;
  final String rarity;
  final String? imageUri;
  final String? manaCost;
  final String? typeLine;
  final int quantity;
  final String condition;
  final String language;
  final bool foil;
  final String? notes;
  final String? priceEur;
  final String? priceUsd;
  final DateTime addedAt;
  final DateTime updatedAt;

  const CollectionCardModel({
    required this.id,
    required this.cardId,
    required this.cardName,
    required this.setCode,
    required this.setName,
    required this.collectorNumber,
    required this.rarity,
    this.imageUri,
    this.manaCost,
    this.typeLine,
    required this.quantity,
    required this.condition,
    required this.language,
    required this.foil,
    this.notes,
    this.priceEur,
    this.priceUsd,
    required this.addedAt,
    required this.updatedAt,
  });

  factory CollectionCardModel.fromJson(Map<String, dynamic> json) =>
      CollectionCardModel(
        id: json['id'] as String,
        cardId: json['card_id'] as String,
        cardName: json['card_name'] as String,
        setCode: json['set_code'] as String,
        setName: json['set_name'] as String,
        collectorNumber: json['collector_number'] as String,
        rarity: json['rarity'] as String,
        imageUri: json['image_uri'] as String?,
        manaCost: json['mana_cost'] as String?,
        typeLine: json['type_line'] as String?,
        quantity: json['quantity'] as int,
        condition: json['condition'] as String,
        language: json['language'] as String,
        foil: json['foil'] as bool? ?? false,
        notes: json['notes'] as String?,
        priceEur: json['price_eur'] as String?,
        priceUsd: json['price_usd'] as String?,
        addedAt: DateTime.parse(json['added_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  /// Short condition code for display (e.g. NM, LP, HP).
  String get conditionLabel => switch (condition) {
        'mint' => 'M',
        'near_mint' => 'NM',
        'lightly_played' => 'LP',
        'moderately_played' => 'MP',
        'heavily_played' => 'HP',
        'damaged' => 'D',
        _ => condition,
      };

  /// Human-readable rarity with initial cap.
  String get rarityLabel =>
      rarity.isEmpty ? '' : rarity[0].toUpperCase() + rarity.substring(1);

  /// EUR price preferred; falls back to USD; null when both absent.
  String? get priceLabel {
    if (priceEur != null) {
      final v = double.tryParse(priceEur!);
      if (v != null) return '€${v.toStringAsFixed(2)}';
    }
    if (priceUsd != null) {
      final v = double.tryParse(priceUsd!);
      if (v != null) return '\$${v.toStringAsFixed(2)}';
    }
    return null;
  }
}

/// Paginated response from `GET /api/v1/collections/{id}/cards`.
class CollectionCardListResponse {
  final List<CollectionCardModel> items;
  final int total;
  final int page;
  final int pageSize;

  const CollectionCardListResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory CollectionCardListResponse.fromJson(Map<String, dynamic> json) {
    final meta = json['meta'] as Map<String, dynamic>;
    return CollectionCardListResponse(
      items: (json['items'] as List<dynamic>)
          .map((e) => CollectionCardModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: meta['total'] as int,
      page: meta['page'] as int,
      pageSize: meta['page_size'] as int,
    );
  }
}
