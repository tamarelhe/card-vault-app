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
/// 2. Run ML Kit OCR on the sampled frame.
/// 3. Parse OCR output into [ScanHints] via [OcrExtractor].
/// 4. Require [_stabilityThreshold] consecutive identical readings.
/// 5. On stable → call [ScanRepository.resolve], transition to [ScanPhase.resolved].
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

  ScannerController(this._repository) : super(const ScannerState());

  /// Initialises the camera and starts the image stream.
  ///
  /// [screenSize] is used to map the on-screen viewfinder rect to native
  /// camera coordinates so OCR is restricted to the card area.
  Future<void> initialize(List<CameraDescription> cameras, Size screenSize) async {
    _screenSize = screenSize;
    // Prefer the back camera for card scanning.
    final description = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    _camera = CameraController(
      description,
      // High gives ~1920×1080; the extra resolution is needed for the small
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
    debugPrint('[Scanner] ▶ frame sampled — ${image.width}×${image.height} fmt=${image.format.raw} planes=${image.planes.length}');
    _analyseFrame(image).whenComplete(() => _isProcessing = false);
  }

  Future<void> _analyseFrame(CameraImage image) async {
    final inputImage = _toInputImage(image);
    if (inputImage == null) {
      debugPrint('[Scanner] ✗ _toInputImage returned null (unsupported format?)');
      return;
    }

    final recognizedText = await _recognizer.processImage(inputImage);
    final raw = recognizedText.text.trim();

    if (raw.isEmpty) {
      debugPrint('[Scanner] ~ OCR: (empty)');
      _resetStability();
      return;
    }

    // Print only the first 200 chars to keep logs readable.
    //final preview = raw.length > 200 ? '${raw.substring(0, 200)}…' : raw;
    debugPrint('[Scanner] OCR text:\n"""\n$raw\n"""');

    final hints = OcrExtractor.extract(raw);

    if (hints == null) {
      debugPrint('[Scanner] ~ OcrExtractor: no usable hints extracted');
      _resetStability();
      return;
    }

    debugPrint('[Scanner] hints → $hints');

    // Accumulate consecutive readings of the same card.
    if (hints.matches(_candidateHints)) {
      _consecutiveCount++;
      debugPrint('[Scanner] stability: $_consecutiveCount/$_stabilityThreshold');
    } else {
      _candidateHints = hints;
      _consecutiveCount = 1;
      debugPrint('[Scanner] new candidate: $hints (reset counter)');
    }

    if (_consecutiveCount >= _stabilityThreshold) {
      // Stable reading detected — stop further processing and resolve.
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

  /// Converts a raw [CameraImage] to an [InputImage] for ML Kit.
  ///
  /// For single-plane (BGRA / iOS) images the bytes are cropped to the
  /// viewfinder region before passing to ML Kit, so OCR never sees content
  /// outside the card frame.  Multi-plane (Android NV21) images are passed
  /// whole; cropping NV21 planes is left as a future improvement.
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

    // iOS uses a single BGRA plane; Android NV21 uses two planes.
    if (image.planes.length == 1) {
      final src = image.planes[0].bytes;
      final srcBytesPerRow = image.planes[0].bytesPerRow;
      final crop = _viewfinderInNativeCoords(image);

      if (crop != null) {
        final cropW = (crop.right - crop.left).toInt();
        final cropH = (crop.bottom - crop.top).toInt();
        debugPrint('[Scanner] crop ${image.width}×${image.height} → $cropW×$cropH');
        return InputImage.fromBytes(
          bytes: _cropBgra(src, srcBytesPerRow, crop),
          metadata: InputImageMetadata(
            size: Size(cropW.toDouble(), cropH.toDouble()),
            rotation: rotation,
            format: format,
            bytesPerRow: cropW * 4,
          ),
        );
      }

      return InputImage.fromBytes(
        bytes: src,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: srcBytesPerRow,
        ),
      );
    }

    // Multi-plane path (Android NV21) — full image.
    final buffer = WriteBuffer();
    for (final plane in image.planes) {
      buffer.putUint8List(plane.bytes);
    }
    return InputImage.fromBytes(
      bytes: buffer.done().buffer.asUint8List(),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  /// Returns the viewfinder rectangle in native (sensor) image coordinates.
  ///
  /// Works by inverting the [FittedBox.cover] transform used in the preview
  /// widget, then mapping the resulting portrait-image rect to the native
  /// landscape bytes via the sensor rotation.
  Rect? _viewfinderInNativeCoords(CameraImage image) {
    if (_screenSize == null || _camera == null) return null;
    final previewSize = _camera!.value.previewSize;
    if (previewSize == null) return null;

    final screenW = _screenSize!.width;
    final screenH = _screenSize!.height;

    // The preview widget swaps dimensions so the landscape sensor fills a
    // portrait screen (matches _buildCameraPreview in scanner_screen.dart).
    final portraitW = previewSize.height; // portrait display width
    final portraitH = previewSize.width;  // portrait display height

    // FittedBox.cover scale factor.
    final scale = math.max(screenW / portraitW, screenH / portraitH);

    // Top-left corner of the (possibly overflowing) image in screen coords.
    final imgOriginX = (screenW - portraitW * scale) / 2;
    final imgOriginY = (screenH - portraitH * scale) / 2;

    // Viewfinder rect in screen coords (mirrors _VignettePainter).
    const cardAspect = 63.0 / 88.0;
    final cardWScreen = screenW * 0.75;
    final cardHScreen = cardWScreen / cardAspect;
    final cardLeftScreen = (screenW - cardWScreen) / 2;
    final cardTopScreen = (screenH - cardHScreen) / 2;

    // Map screen coords → portrait image pixel coords.
    final lp = (cardLeftScreen - imgOriginX) / scale;
    final tp = (cardTopScreen - imgOriginY) / scale;
    final rp = lp + cardWScreen / scale;
    final bp = tp + cardHScreen / scale;

    // Clamp and round to integer portrait pixels.
    final l = lp.clamp(0.0, portraitW).round();
    final t = tp.clamp(0.0, portraitH).round();
    final r = rp.clamp(0.0, portraitW).round();
    final b = bp.clamp(0.0, portraitH).round();

    if (l >= r || t >= b) return null;

    // Map portrait image coords → native (landscape) image coords.
    // The mapping depends on the sensor's rotation relative to portrait.
    //
    // sensorOrientation=90  (typical iOS back camera):
    //   portrait (xp,yp) → native (image.width-1-yp, xp)
    // sensorOrientation=270 (some Android front cameras):
    //   portrait (xp,yp) → native (yp, image.height-1-xp)
    final wn = image.width;
    final hn = image.height;
    final int nl, nt, nr, nb;

    switch (_camera!.description.sensorOrientation) {
      case 90:
        nl = (wn - b).clamp(0, wn - 1);
        nt = l.clamp(0, hn - 1);
        nr = (wn - t).clamp(nl + 1, wn);
        nb = r.clamp(nt + 1, hn);
      case 270:
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

  /// Copies a rectangular sub-region from a BGRA (4 bytes/pixel) image buffer.
  Uint8List _cropBgra(Uint8List src, int srcBytesPerRow, Rect crop) {
    final x1 = crop.left.toInt();
    final y1 = crop.top.toInt();
    final w = (crop.right - crop.left).toInt();
    final h = (crop.bottom - crop.top).toInt();
    final dst = Uint8List(w * h * 4);
    for (var row = 0; row < h; row++) {
      final srcOff = (y1 + row) * srcBytesPerRow + x1 * 4;
      final dstOff = row * w * 4;
      dst.setRange(dstOff, dstOff + w * 4, src, srcOff);
    }
    return dst;
  }

  @override
  void dispose() {
    _camera?.dispose();
    _recognizer.close();
    super.dispose();
  }
}
