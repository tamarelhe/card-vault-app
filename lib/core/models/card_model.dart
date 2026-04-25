/// Represents a Magic: The Gathering card as returned by the backend API.
class CardModel {
  final String id;
  final String? scryfallId;
  final String name;
  final String setCode;
  final String setName;
  final String collectorNumber;
  final String layout;
  final String rarity;
  final String? manaCost;
  final String? typeLine;
  final String? oracleText;
  final String? imageUri;
  final double? cmc;
  final List<String> colors;
  final String? artist;
  final bool foil;
  final bool nonfoil;
  final double? pricesEur;
  final double? pricesUsd;

  const CardModel({
    required this.id,
    this.scryfallId,
    required this.name,
    required this.setCode,
    required this.setName,
    required this.collectorNumber,
    required this.layout,
    required this.rarity,
    this.manaCost,
    this.typeLine,
    this.oracleText,
    this.imageUri,
    this.cmc,
    required this.colors,
    this.artist,
    required this.foil,
    required this.nonfoil,
    this.pricesEur,
    this.pricesUsd,
  });

  factory CardModel.fromJson(Map<String, dynamic> json) => CardModel(
        id: json['id'] as String,
        scryfallId: json['scryfall_id'] as String?,
        name: json['name'] as String,
        setCode: json['set_code'] as String,
        setName: json['set_name'] as String,
        collectorNumber: json['collector_number'] as String,
        layout: json['layout'] as String,
        rarity: json['rarity'] as String,
        manaCost: json['mana_cost'] as String?,
        typeLine: json['type_line'] as String?,
        oracleText: json['oracle_text'] as String?,
        imageUri: json['image_uri'] as String?,
        cmc: (json['cmc'] as num?)?.toDouble(),
        colors: (json['colors'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        artist: json['artist'] as String?,
        foil: json['foil'] as bool? ?? false,
        nonfoil: json['nonfoil'] as bool? ?? true,
        pricesEur: (json['prices_eur'] as num?)?.toDouble(),
        pricesUsd: (json['prices_usd'] as num?)?.toDouble(),
      );

  /// Human-readable rarity label with initial cap.
  String get rarityLabel =>
      rarity.isEmpty ? '' : rarity[0].toUpperCase() + rarity.substring(1);
}
