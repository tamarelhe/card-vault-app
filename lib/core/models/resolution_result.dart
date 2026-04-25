import 'card_model.dart';

/// Possible outcomes from the card resolve endpoint.
enum ResolutionStatus { exact, candidates, notFound }

/// Result returned by `POST /api/v1/cards/resolve`.
///
/// - [ResolutionStatus.exact]: single card matched, see [card].
/// - [ResolutionStatus.candidates]: multiple printings found, see [candidates].
/// - [ResolutionStatus.notFound]: nothing matched.
class ResolutionResult {
  final ResolutionStatus status;

  /// Populated when [status] is [ResolutionStatus.exact].
  final CardModel? card;

  /// Populated when [status] is [ResolutionStatus.candidates].
  final List<CardModel> candidates;

  const ResolutionResult({
    required this.status,
    this.card,
    this.candidates = const [],
  });

  factory ResolutionResult.fromJson(Map<String, dynamic> json) {
    final statusStr = json['status'] as String;
    final status = switch (statusStr) {
      'exact' => ResolutionStatus.exact,
      'candidates' => ResolutionStatus.candidates,
      _ => ResolutionStatus.notFound,
    };

    final cardJson = json['card'] as Map<String, dynamic>?;
    final candidatesJson = json['candidates'] as List<dynamic>?;

    return ResolutionResult(
      status: status,
      card: cardJson != null ? CardModel.fromJson(cardJson) : null,
      candidates: candidatesJson
              ?.map((e) => CardModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
