import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show WriteBuffer, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../core/models/resolution_result.dart';
import '../../core/models/scan_hints.dart';
import 'ocr_extractor.dart';
import 'scan_repository.dart';

/// All phases the scanner can be in.
enum ScanPhase {
  /// Camera not yet initialised.
  initializing,

  /// Camera is live, actively sampling frames.
  scanning,

  /// A stable reading was detected; awaiting backend response.
  processing,

  /// Backend returned a result — waiting for user action.
  resolved,

  /// An unrecoverable error occurred.
  error,
}

/// Immutable snapshot of scanner state.
class ScannerState {
  final ScanPhase phase;
  final ResolutionResult? result;
  final ScanHints? lastHints;
  final String? errorMessage;

  const ScannerState({
    this.phase = ScanPhase.initializing,
    this.result,
    this.lastHints,
    this.errorMessage,
  });

  ScannerState copyWith({
    ScanPhase? phase,
    ResolutionResult? result,
    ScanHints? lastHints,
    String? errorMessage,
  }) =>
      ScannerState(
        phase: phase ?? this.phase,
        result: result ?? this.result,
        lastHints: lastHints ?? this.lastHints,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

/// Drives the continuous card-scan loop.
///
/// Frame sampling strategy:
/// 1. One frame every [_frameInterval] ms.
/// 2. Run ML Kit OCR on the full frame.
/// 3. Filter [TextBlock]s to those whose bounding box falls inside the
///    on-screen viewfinder rectangle — this is the ROI, and it works for
///    any camera format (NV12, BGRA, NV21, …).
/// 4. Parse OCR output into [ScanHints] via [OcrExtractor].
/// 5. Require [_stabilityThreshold] consecutive identical readings.
/// 6. On stable → call [ScanRepository.resolve], transition to [ScanPhase.resolved].
class ScannerController extends StateNotifier<ScannerState> {
  final ScanRepository _repository;

  /// ML Kit text recogniser; re-used across frames to avoid object churn.
  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  CameraController? _camera;
  Size? _screenSize;

  bool _isProcessing = false;
  DateTime _lastSampleAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Sample one frame every 350 ms — fast enough to feel live, slow enough
  // to not saturate the ML Kit pipeline.
  static const _frameInterval = Duration(milliseconds: 350);

  // Three consecutive identical readings before triggering a resolve call.
  static const _stabilityThreshold = 3;
  ScanHints? _candidateHints;
  int _consecutiveCount = 0;

  // Viewfinder geometry constants — must stay in sync with scan_overlay.dart.
  static const _kCardAspect = 63.0 / 88.0;
  static const _kViewfinderWidth = 0.75;
  // Extra height at the bottom so the bottom strip is fully captured.
  static const _kBottomPadding = 0.03;

  ScannerController(this._repository) : super(const ScannerState());

  /// Initialises the camera and starts the image stream.
  ///
  /// [screenSize] is used to map the on-screen viewfinder rect to image
  /// coordinates for post-OCR bounding-box filtering.
  Future<void> initialize(List<CameraDescription> cameras, Size screenSize) async {
    _screenSize = screenSize;
    // Prefer the back camera for card scanning.
    final description = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    _camera = CameraController(
      description,
      // High gives ~1920×1080; the extra resolution helps with the small
      // set-code / collector-number text at the bottom of the card.
      ResolutionPreset.high,
      enableAudio: false,
    );

    await _camera!.initialize();
    state = state.copyWith(phase: ScanPhase.scanning);
    _camera!.startImageStream(_onFrame);
  }

  /// Exposes the camera controller so the UI can render the preview.
  CameraController? get cameraController => _camera;

  /// Called on every camera frame; throttled to [_frameInterval].
  void _onFrame(CameraImage image) {
    final now = DateTime.now();
    if (now.difference(_lastSampleAt) < _frameInterval) return;
    if (_isProcessing) return;
    if (state.phase != ScanPhase.scanning) return;

    _lastSampleAt = now;
    _isProcessing = true;
    debugPrint('[Scanner] ▶ frame — ${image.width}×${image.height} fmt=${image.format.raw} planes=${image.planes.length}');
    _analyseFrame(image).whenComplete(() => _isProcessing = false);
  }

  Future<void> _analyseFrame(CameraImage image) async {
    final inputImage = _toInputImage(image);
    if (inputImage == null) {
      debugPrint('[Scanner] ✗ _toInputImage returned null');
      return;
    }

    final recognizedText = await _recognizer.processImage(inputImage);

    if (recognizedText.blocks.isEmpty) {
      debugPrint('[Scanner] ~ OCR: (no blocks)');
      _resetStability();
      return;
    }

    // Log every block with its bounding box.  Compare bbox coordinates against
    // image dimensions to confirm whether ML Kit returns native-image coords
    // (x ≤ image.width, y ≤ image.height) or portrait-rotated coords.
    for (final block in recognizedText.blocks) {
      debugPrint('[Scanner] block bbox=${block.boundingBox} '
          '"${block.text.trim().replaceAll('\n', '↵')}"');
    }

    // Compute the viewfinder ROIs in native image coordinates.
    // On iOS the sensor is landscape (sensorOrientation=90); ML Kit returns
    // bounding boxes in the pre-rotation (native) coordinate space.
    final roi = _viewfinderInNativeCoords(image);
    final bottomRoi = _bottomStripInNativeCoords(image);
    debugPrint('[Scanner] ROI native=$roi  bottomROI=$bottomRoi  img=${image.width}×${image.height}');

    // Blocks inside the full viewfinder (for name extraction).
    final mainText = _textsInRect(recognizedText.blocks, roi).join('\n').trim();

    // Blocks inside the bottom strip (for set code + collector number).
    final bottomText = _textsInRect(recognizedText.blocks, bottomRoi).join('\n').trim();

    debugPrint('[Scanner] OCR main:\n"""\n$mainText\n"""');
    debugPrint('[Scanner] OCR bottom:\n"""\n$bottomText\n"""');

    if (mainText.isEmpty && bottomText.isEmpty) {
      _resetStability();
      return;
    }

    final hints = OcrExtractor.extractWithPriority(mainText, bottomText);

    if (hints == null) {
      debugPrint('[Scanner] ~ OcrExtractor: no usable hints');
      _resetStability();
      return;
    }

    debugPrint('[Scanner] hints → $hints');

    if (hints.matches(_candidateHints)) {
      _consecutiveCount++;
      debugPrint('[Scanner] stability: $_consecutiveCount/$_stabilityThreshold');
    } else {
      _candidateHints = hints;
      _consecutiveCount = 1;
      debugPrint('[Scanner] new candidate: $hints (reset counter)');
    }

    if (_consecutiveCount >= _stabilityThreshold) {
      debugPrint('[Scanner] ✓ stable — calling resolve');
      final stable = _candidateHints!;
      _resetStability();
      await _resolveCard(stable);
    }
  }

  Future<void> _resolveCard(ScanHints hints) async {
    debugPrint('[Scanner] → POST /cards/resolve  hints=$hints');
    state = state.copyWith(phase: ScanPhase.processing, lastHints: hints);

    try {
      final result = await _repository.resolve(hints);
      debugPrint('[Scanner] ← resolve status=${result.status.name}');
      state = state.copyWith(phase: ScanPhase.resolved, result: result);
    } catch (e) {
      debugPrint('[Scanner] ✗ resolve error: $e');
      state = state.copyWith(
        phase: ScanPhase.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// Clears the current result and resumes scanning.
  void resumeScanning() {
    _resetStability();
    state = state.copyWith(
      phase: ScanPhase.scanning,
      result: null,
      errorMessage: null,
    );
  }

  void _resetStability() {
    _candidateHints = null;
    _consecutiveCount = 0;
  }

  // ---------------------------------------------------------------------------
  // Image conversion
  // ---------------------------------------------------------------------------

  /// Converts a raw [CameraImage] to an [InputImage] for ML Kit.
  ///
  /// The full frame is passed; ROI filtering is applied after OCR by examining
  /// [TextBlock.boundingBox] values.  This avoids format-specific byte
  /// manipulation and works for both NV12 (iOS) and NV21 (Android).
  InputImage? _toInputImage(CameraImage image) {
    if (_camera == null) return null;

    final rotation =
        InputImageRotationValue.fromRawValue(
              _camera!.description.sensorOrientation,
            ) ??
            InputImageRotation.rotation0deg;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) {
      debugPrint('[Scanner] ✗ unknown image format raw=${image.format.raw}');
      return null;
    }

    final Uint8List bytes;
    if (image.planes.length == 1) {
      bytes = image.planes[0].bytes;
    } else {
      final buffer = WriteBuffer();
      for (final plane in image.planes) {
        buffer.putUint8List(plane.bytes);
      }
      bytes = buffer.done().buffer.asUint8List();
    }

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ROI helpers
  // ---------------------------------------------------------------------------

  /// Returns the texts from [blocks] whose bounding boxes overlap [roi].
  ///
  /// If [roi] is null every block's text is included (no filtering).
  List<String> _textsInRect(List<TextBlock> blocks, Rect? roi) {
    if (roi == null) return blocks.map((b) => b.text).toList();
    return blocks
        .where((b) => roi.overlaps(b.boundingBox))
        .map((b) => b.text)
        .toList();
  }

  /// Returns the viewfinder rectangle in portrait image coordinates
  /// (the coordinate space of the image after the sensor rotation is applied).
  ///
  /// Inverts the [FittedBox.cover] transform used in [_buildCameraPreview]
  /// and applies [_kBottomPadding] to capture the bottom strip.
  Rect? _viewfinderPortraitRect(CameraImage image) {
    if (_screenSize == null || _camera == null) return null;
    final previewSize = _camera!.value.previewSize;
    if (previewSize == null) return null;

    final screenW = _screenSize!.width;
    final screenH = _screenSize!.height;

    // The preview widget swaps width↔height so the landscape sensor fills a
    // portrait screen (see _buildCameraPreview in scanner_screen.dart).
    final portraitW = previewSize.height;
    final portraitH = previewSize.width;

    final scale = math.max(screenW / portraitW, screenH / portraitH);
    final imgOriginX = (screenW - portraitW * scale) / 2;
    final imgOriginY = (screenH - portraitH * scale) / 2;

    // Viewfinder rect in screen coords (mirrors _VignettePainter).
    final cardWScreen = screenW * _kViewfinderWidth;
    final cardHScreen = cardWScreen / _kCardAspect * (1 + _kBottomPadding);
    final cardLeftScreen = (screenW - cardWScreen) / 2;
    final cardTopScreen = (screenH - cardHScreen) / 2;

    // Map screen → portrait image pixel coords.
    final lp = (cardLeftScreen - imgOriginX) / scale;
    final tp = (cardTopScreen - imgOriginY) / scale;
    final rp = lp + cardWScreen / scale;
    final bp = tp + cardHScreen / scale;

    final l = lp.clamp(0.0, portraitW).round();
    final t = tp.clamp(0.0, portraitH).round();
    final r = rp.clamp(0.0, portraitW).round();
    final b = bp.clamp(0.0, portraitH).round();

    if (l >= r || t >= b) return null;
    return Rect.fromLTRB(l.toDouble(), t.toDouble(), r.toDouble(), b.toDouble());
  }

  /// Maps a rectangle from portrait image coordinates to native (pre-rotation)
  /// image coordinates based on the sensor orientation.
  ///
  /// ML Kit on iOS returns [TextBlock.boundingBox] in the native (landscape)
  /// coordinate space of the bytes that were passed in.
  Rect? _portraitRectToNative(Rect portrait, CameraImage image) {
    if (_camera == null) return null;
    final wn = image.width;
    final hn = image.height;

    final l = portrait.left.round();
    final t = portrait.top.round();
    final r = portrait.right.round();
    final b = portrait.bottom.round();

    final int nl, nt, nr, nb;

    switch (_camera!.description.sensorOrientation) {
      case 90:
        // portrait (xp,yp) → native (wn-1-yp, xp)
        nl = (wn - b).clamp(0, wn - 1);
        nt = l.clamp(0, hn - 1);
        nr = (wn - t).clamp(nl + 1, wn);
        nb = r.clamp(nt + 1, hn);
      case 270:
        // portrait (xp,yp) → native (yp, hn-1-xp)
        nl = t.clamp(0, wn - 1);
        nt = (hn - r).clamp(0, hn - 1);
        nr = b.clamp(nl + 1, wn);
        nb = (hn - l).clamp(nt + 1, hn);
      case 0:
        nl = l.clamp(0, wn - 1);
        nt = t.clamp(0, hn - 1);
        nr = r.clamp(nl + 1, wn);
        nb = b.clamp(nt + 1, hn);
      case 180:
        nl = (wn - r).clamp(0, wn - 1);
        nt = (hn - b).clamp(0, hn - 1);
        nr = (wn - l).clamp(nl + 1, wn);
        nb = (hn - t).clamp(nt + 1, hn);
      default:
        return null;
    }

    return Rect.fromLTRB(nl.toDouble(), nt.toDouble(), nr.toDouble(), nb.toDouble());
  }

  /// Full viewfinder rectangle in native image coordinates.
  Rect? _viewfinderInNativeCoords(CameraImage image) {
    final portrait = _viewfinderPortraitRect(image);
    if (portrait == null) return null;
    return _portraitRectToNative(portrait, image);
  }

  /// Bottom 18 % of the viewfinder in native image coordinates.
  ///
  /// This region tightly covers the bottom strip where the set code and
  /// collector number are printed, giving OcrExtractor a cleaner input.
  Rect? _bottomStripInNativeCoords(CameraImage image) {
    final portrait = _viewfinderPortraitRect(image);
    if (portrait == null) return null;
    final strip = Rect.fromLTRB(
      portrait.left,
      portrait.bottom - portrait.height * 0.18,
      portrait.right,
      portrait.bottom,
    );
    return _portraitRectToNative(strip, image);
  }

  @override
  void dispose() {
    _camera?.dispose();
    _recognizer.close();
    super.dispose();
  }
}
