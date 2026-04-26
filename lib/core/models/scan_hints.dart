/// OCR hints extracted from a camera frame used to identify a card.
class ScanHints {
  final String? name;
  final String? setCode;
  final String? collectorNumber;

  const ScanHints({
    this.name,
    this.setCode,
    this.collectorNumber,
  });

  /// Returns true when there is at least enough information to attempt resolution.
  bool get hasEnoughData =>
      name != null || (setCode != null && collectorNumber != null);

  /// Returns true when this hints object is considered equal to [other] for
  /// stability-check purposes. Exact name match OR set+number match qualifies.
  bool matches(ScanHints? other) {
    if (other == null) return false;
    if (name != null && name == other.name) {
      return true;
    }
    if (setCode != null &&
        collectorNumber != null &&
        setCode == other.setCode &&
        collectorNumber == other.collectorNumber) {
      return true;
    }
    return false;
  }

  /// Returns a new [ScanHints] combining non-null fields from this and [other].
  ///
  /// Prefers non-null values from [other] so that a richer later frame wins.
  ScanHints mergeWith(ScanHints other) => ScanHints(
        name: other.name ?? name,
        setCode: other.setCode ?? setCode,
        collectorNumber: other.collectorNumber ?? collectorNumber,
      );

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (setCode != null) 'set_code': setCode,
        if (collectorNumber != null) 'collector_number': collectorNumber,
      };

  @override
  String toString() =>
      'ScanHints(name: $name, setCode: $setCode, number: $collectorNumber)';
}
