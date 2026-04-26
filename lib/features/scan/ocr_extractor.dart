import '../../core/models/scan_hints.dart';

/// Parses raw OCR text from a card image into structured [ScanHints].
///
/// MTG card bottom strip (the primary source of set code + collector number):
///   `<collector_number>/<total> <set_code> · <lang>`
///   Example: `149/249 M10 · EN`
///
/// The extractor uses a two-pass strategy:
/// 1. **Bottom-strip pass** — looks for a line containing `digits/3-4digits`
///    (distinguishes "149/249" from "3/3" power/toughness).  If found, the
///    set code is extracted from that same line.
/// 2. **Lenient fallback** — if no bottom-strip line is found (e.g., the total
///    was cropped or OCR missed the slash), scans bottom-up with looser patterns.
class OcrExtractor {
  OcrExtractor._();

  // Bottom-strip collector number: requires a 3-4 digit total (≥100 cards in
  // set).  This reliably excludes power/toughness ("3/3", "2/4") and CMC
  // fractions, which never have a 3-digit denominator.
  static final _strictCollector = RegExp(r'\b(\d{1,4})/\d{3,4}\b');

  // Fallback: any 1-4 digit standalone number.
  static final _looseCollector = RegExp(r'\b(\d{1,4})\b');

  // Set code: 2-5 uppercase alphanumeric characters, first char must be a
  // letter.  Modern sets use exactly 3 chars; older sets used 2; some special
  // sets use 4-5 (e.g., "PLST", "MB1").
  static final _setCodePattern = RegExp(r'\b([A-Z][A-Z0-9]{1,4})\b');

  // Language codes present on almost every card — must not be mistaken for a
  // set code.
  static const _languageCodes = {
    'EN', 'DE', 'FR', 'IT', 'PT', 'ES', 'JP', 'KR',
    'RU', 'CS', 'CT', 'PH', 'HE', 'AR',
  };

  // Common tokens from rules text or card frames that are not set codes.
  static const _falsePositives = {
    'R', 'W', 'U', 'B', 'G', // mana symbols as text
    'T', 'Q',                 // tap / untap symbols as text
    'BB', 'WW', 'UU', 'RR',  // double mana
    'CMC', 'CMR',             // sometimes appear in rules text
    'LLC', 'TM',              // copyright line fragments
    'THE', 'AND', 'FOR', 'NOT', 'ALL', // common English words OCR may emit
    'YOU', 'ITS', 'PUT', 'GET', 'HAS',
  };

  /// Extracts [ScanHints] from [ocrText].
  /// Returns null when there is no usable data.
  static ScanHints? extract(String ocrText) {
    if (ocrText.trim().isEmpty) return null;

    final lines = ocrText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty) return null;

    final name = _extractName(lines);
    String? collectorNumber;
    String? setCode;

    // --- Pass 1: bottom-strip line -------------------------------------------
    // A line that contains `digits/3-4digits` is almost certainly the bottom
    // strip.  Extract both collector number and set code from that line.
    for (final line in lines.reversed) {
      final m = _strictCollector.firstMatch(line);
      if (m != null) {
        collectorNumber = m.group(1);
        setCode = _firstSetCode(line);
        break;
      }
    }

    // --- Pass 2: lenient fallback ---------------------------------------------
    // Used when the bottom strip wasn't captured with a /total (e.g., promos,
    // or OCR dropped the slash).
    if (collectorNumber == null || setCode == null) {
      for (final line in lines.reversed) {
        collectorNumber ??= _looseCollector.firstMatch(line)?.group(1);
        setCode ??= _firstSetCode(line);
        if (collectorNumber != null && setCode != null) break;
      }
    }

    final hints = ScanHints(
      name: name,
      setCode: setCode,
      collectorNumber: collectorNumber,
    );

    return hints.hasEnoughData ? hints : null;
  }

  /// Returns the first valid set-code token found in [line], or null.
  static String? _firstSetCode(String line) {
    for (final m in _setCodePattern.allMatches(line)) {
      final c = m.group(1)!;
      if (c.length < 2) continue;
      if (_languageCodes.contains(c)) continue;
      if (_falsePositives.contains(c)) continue;
      return c;
    }
    return null;
  }

  /// Picks the most likely card-name line from the top of the OCR output.
  static String? _extractName(List<String> lines) {
    for (final line in lines.take(5)) {
      if (line.length < 3) continue;
      if (RegExp(r'^\d').hasMatch(line)) continue;
      if (RegExp(r'^[{}\d\W]+$').hasMatch(line)) continue;
      return line;
    }
    return null;
  }
}
