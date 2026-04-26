import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/resolution_result.dart';
import '../../../core/providers.dart';
import '../scan_repository.dart';
import '../scanner_controller.dart';
import '../widgets/candidates_bottom_sheet.dart';
import '../widgets/scan_overlay.dart';
import 'card_confirm_screen.dart';

/// Provider that owns the [ScannerController] for the active scanner session.
final scannerControllerProvider =
    StateNotifierProvider.autoDispose<ScannerController, ScannerState>(
  (ref) => ScannerController(
    ScanRepository(ref.watch(dioProvider)),
  ),
);

/// Full-screen camera scanner.
///
/// The camera preview fills the screen; a [ScanOverlay] is drawn on top.
/// When a stable card reading is detected the screen reacts automatically:
/// - `exact` → pushes [CardConfirmScreen].
/// - `candidates` → shows [CandidatesBottomSheet] and then pushes confirm.
/// - `not_found` → briefly shows an error and resumes scanning.
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  @override
  void initState() {
    super.initState();
    // Kick off camera initialisation after the first frame so the provider
    // is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) => _initCamera());
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (!mounted) return;
    final screenSize = MediaQuery.of(context).size;
    await ref.read(scannerControllerProvider.notifier).initialize(cameras, screenSize);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scannerControllerProvider);
    final controller =
        ref.read(scannerControllerProvider.notifier).cameraController;

    // React to state changes — run in a post-frame callback to avoid
    // calling Navigator during build.
    ref.listen<ScannerState>(scannerControllerProvider, (prev, next) {
      if (next.phase == ScanPhase.resolved && next.result != null) {
        _handleResult(next.result!);
      }
      if (next.phase == ScanPhase.error) {
        _showError(next.errorMessage ?? 'Unknown error');
      }
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview — iOS sensor is landscape so previewSize is (W, H)
          // in landscape order; we swap to fill portrait screen without distortion.
          if (controller != null && controller.value.isInitialized)
            _buildCameraPreview(controller)
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),

          // Viewfinder + status overlay
          ScanOverlay(phase: state.phase),

          // Close button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the camera preview filling the screen without distortion.
  ///
  /// On iOS the sensor reports its native size in landscape (e.g. 1280×720),
  /// so we swap width↔height to get the correct portrait aspect ratio, then
  /// scale to cover the full screen.
  Widget _buildCameraPreview(CameraController controller) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) return CameraPreview(controller);

    // Swap dimensions: iOS native size is landscape; phone is portrait.
    final portraitWidth = previewSize.height;
    final portraitHeight = previewSize.width;

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: portraitWidth,
          height: portraitHeight,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  /// Routes the resolved result to the appropriate UI action.
  Future<void> _handleResult(ResolutionResult result) async {
    switch (result.status) {
      case ResolutionStatus.exact:
        // Navigate to confirmation screen; resume scanning when done.
        final added = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => CardConfirmScreen(card: result.card!),
          ),
        );
        if (added == true && mounted) {
          _showSnackBar('Card added to collection');
        }
        if (mounted) {
          ref.read(scannerControllerProvider.notifier).resumeScanning();
        }

      case ResolutionStatus.candidates:
        final picked = await CandidatesBottomSheet.show(
          context,
          result.candidates,
        );
        if (picked != null && mounted) {
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => CardConfirmScreen(card: picked),
            ),
          );
        }
        if (mounted) {
          ref.read(scannerControllerProvider.notifier).resumeScanning();
        }

      case ResolutionStatus.notFound:
        _showError('Card not found in catalogue');
        if (mounted) {
          ref.read(scannerControllerProvider.notifier).resumeScanning();
        }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    _showSnackBar(message, isError: true);
    ref.read(scannerControllerProvider.notifier).resumeScanning();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
