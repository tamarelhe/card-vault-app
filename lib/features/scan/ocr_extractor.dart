import '../../core/models/scan_hints.dart';

/// Parses raw OCR text from a card image into structured [ScanHints].
///
/// MTG card layout (bottom strip):
///   `<set_code> · <lang> · <collector_number>/<total>`
///   Example: `M10 · EN · 149/249`
///
/// The extractor is intentionally lenient — it returns partial hints
/// so the stability check and backend can do the final arbitration.
class OcrExtractor {
  OcrExtractor._();

  // Collector number: 1–4 digits, optionally followed by /total (e.g. "149" or "149/249").
  static final _collectorPattern = RegExp(r'\b(\d{1,4})(?:/\d+)?\b');

  // Set code: 2–5 uppercase alphanumeric characters.
  // Excludes pure language codes (EN, DE, FR, …) and common false positives.
  static final _setCodePattern = RegExp(r'\b([A-Z]{1,5}[0-9]{0,2})\b');

  // Language codes present on almost every card — excluded from set detection.
  static const _languageCodes = {
    'EN', 'DE', 'FR', 'IT', 'PT', 'ES', 'JP', 'KR',
    'RU', 'CS', 'CT', 'PH', 'HE', 'AR',
  };

  // Words that are common MTG card text but not set codes.
  static const _falsePositives = {
    'R', 'W', 'U', 'B', 'G', // mana symbols as text
    'T', // tap symbol as text
    'BB', 'WW', 'UU', // double mana
    'CMC', 'CMR', // sometimes appear in rules text
  };

  /// Extracts [ScanHints] from [ocrText].
  /// Returns null if the text is empty or yields no useful hints.
  static ScanHints? extract(String ocrText) {
    if (ocrText.trim().isEmpty) return null;

    final lines = ocrText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty) return null;

    // Card name heuristic: the first line that looks like a title
    // (not all-caps, not a number, at least 3 chars).
    final name = _extractName(lines);

    // Scan from the bottom — collector number and set code are there.
    String? collectorNumber;
    String? setCode;

    for (final line in lines.reversed) {
      // Collector number
      if (collectorNumber == null) {
        final match = _collectorPattern.firstMatch(line);
        if (match != null) {
          collectorNumber = match.group(1);
        }
      }

      // Set code: first 2–5 uppercase token that is not a language code or
      // mana symbol. Prefer shorter lines (bottom of card) over body text.
      if (setCode == null) {
        for (final match in _setCodePattern.allMatches(line)) {
          final candidate = match.group(1)!;
          if (!_languageCodes.contains(candidate) &&
              !_falsePositives.contains(candidate) &&
              candidate.length >= 2 &&
              candidate.length <= 5) {
            setCode = candidate;
            break;
          }
        }
      }
    }

    final hints = ScanHints(
      name: name,
      setCode: setCode,
      collectorNumber: collectorNumber,
    );

    return hints.hasEnoughData ? hints : null;
  }

  /// Picks the most likely card-name line from the top of the OCR output.
  static String? _extractName(List<String> lines) {
    for (final line in lines.take(5)) {
      // Skip lines that look like mana costs, numbers, or single characters.
      if (line.length < 3) continue;
      if (RegExp(r'^\d').hasMatch(line)) continue;
      if (RegExp(r'^[{}\d\W]+$').hasMatch(line)) continue;
      return line;
    }
    return null;
  }
}
