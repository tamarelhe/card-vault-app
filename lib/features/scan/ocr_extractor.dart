import '../../core/models/scan_hints.dart';

/// Parses raw OCR text from a card image into structured [ScanHints].
///
/// MTG card bottom strip (the primary source of set code + collector number):
///   `<collector_number>/<total> <set_code> · <lang>`
///   Example: `149/249 M10 · EN`
///
/// The preferred entry point is [extractWithPriority], which receives the
/// full-card text and the bottom-strip text separately so the extractor can
/// be more targeted about where to look for each field.
class OcrExtractor {
  OcrExtractor._();

  // Bottom-strip collector number: requires a 3-4 digit total (≥100 cards in
  // a set).  This reliably excludes power/toughness ("3/3", "2/4") and CMC
  // fractions, which never have a 3-digit denominator.
  static final _strictCollector = RegExp(r'\b(\d{1,4})/\d{3,4}\b');

  // Fallback: any 1-4 digit standalone number.
  static final _looseCollector = RegExp(r'\b(\d{1,4})\b');

  // Set code: 2-5 uppercase alphanumeric chars, first char must be a letter.
  // Modern sets use exactly 3 chars; older ones used 2; some special sets
  // use 4-5 (e.g., "PLST", "MB1").
  static final _setCodePattern = RegExp(r'\b([A-Z][A-Z0-9]{1,4})\b');

  // Language codes present on almost every card — not set codes.
  static const _languageCodes = {
    'EN', 'DE', 'FR', 'IT', 'PT', 'ES', 'JP', 'KR',
    'RU', 'CS', 'CT', 'PH', 'HE', 'AR',
  };

  // Common tokens from rules text or card frames that are not set codes.
  static const _falsePositives = {
    'R', 'W', 'U', 'B', 'G',        // mana symbols as text
    'T', 'Q',                         // tap / untap symbols as text
    'BB', 'WW', 'UU', 'RR',          // double mana
    'CMC', 'CMR',                     // sometimes appear in rules text
    'LLC', 'TM',                      // copyright line fragments
    'THE', 'AND', 'FOR', 'NOT', 'ALL',
    'YOU', 'ITS', 'PUT', 'GET', 'HAS',
  };

  /// Extracts [ScanHints] from two OCR regions:
  ///
  /// - [mainText]   — blocks from the full viewfinder (used for card name).
  /// - [bottomText] — blocks from the bottom strip only (used first for set
  ///                  code + collector number; more precise, less noise).
  ///
  /// Falls back to searching [mainText] when the bottom strip yields nothing.
  static ScanHints? extractWithPriority(String mainText, String bottomText) {
    final mainLines = _splitLines(mainText);
    final bottomLines = _splitLines(bottomText);
    final allLines = _splitLines('$mainText\n$bottomText');

    if (allLines.isEmpty) return null;

    final name = _extractName(mainLines.isNotEmpty ? mainLines : allLines);

    String? collectorNumber;
    String? setCode;

    // Pass 1: strict collector pattern in the dedicated bottom strip.
    for (final line in bottomLines.reversed) {
      final m = _strictCollector.firstMatch(line);
      if (m != null) {
        collectorNumber = m.group(1);
        setCode ??= _firstSetCode(line);
        break;
      }
    }

    // Pass 2: strict collector pattern across all lines (bottom-up).
    if (collectorNumber == null) {
      for (final line in allLines.reversed) {
        final m = _strictCollector.firstMatch(line);
        if (m != null) {
          collectorNumber = m.group(1);
          setCode ??= _firstSetCode(line);
          break;
        }
      }
    }

    // Pass 3: lenient fallback — try bottom strip first, then all lines.
    if (collectorNumber == null || setCode == null) {
      for (final line in [...bottomLines.reversed, ...allLines.reversed]) {
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

  /// Convenience wrapper — passes [ocrText] as [mainText] with no bottom strip.
  static ScanHints? extract(String ocrText) =>
      extractWithPriority(ocrText, '');

  // ---------------------------------------------------------------------------

  static List<String> _splitLines(String text) => text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

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
