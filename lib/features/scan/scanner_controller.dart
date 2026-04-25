import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show WriteBuffer;
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
  Future<void> initialize(List<CameraDescription> cameras) async {
    // Prefer the back camera for card scanning.
    final description = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    _camera = CameraController(
      description,
      ResolutionPreset.medium, // balance quality vs. processing speed
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
    _analyseFrame(image).whenComplete(() => _isProcessing = false);
  }

  Future<void> _analyseFrame(CameraImage image) async {
    final inputImage = _toInputImage(image);
    if (inputImage == null) return;

    final recognizedText = await _recognizer.processImage(inputImage);
    final hints = OcrExtractor.extract(recognizedText.text);

    if (hints == null) {
      _resetStability();
      return;
    }

    // Accumulate consecutive readings of the same card.
    if (hints.matches(_candidateHints)) {
      _consecutiveCount++;
    } else {
      _candidateHints = hints;
      _consecutiveCount = 1;
    }

    if (_consecutiveCount >= _stabilityThreshold) {
      // Stable reading detected — stop further processing and resolve.
      final stable = _candidateHints!;
      _resetStability();
      await _resolveCard(stable);
    }
  }

  Future<void> _resolveCard(ScanHints hints) async {
    state = state.copyWith(phase: ScanPhase.processing, lastHints: hints);

    try {
      final result = await _repository.resolve(hints);
      state = state.copyWith(phase: ScanPhase.resolved, result: result);
    } catch (e) {
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
  InputImage? _toInputImage(CameraImage image) {
    if (_camera == null) return null;

    final rotation =
        InputImageRotationValue.fromRawValue(
              _camera!.description.sensorOrientation,
            ) ??
            InputImageRotation.rotation0deg;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    // iOS uses a single BGRA plane; Android NV21 uses two planes.
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

  @override
  void dispose() {
    _camera?.dispose();
    _recognizer.close();
    super.dispose();
  }
}
