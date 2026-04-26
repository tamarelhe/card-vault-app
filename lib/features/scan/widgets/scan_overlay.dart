import 'package:flutter/material.dart';
import '../scanner_controller.dart';

/// Transparent overlay drawn on top of the camera preview.
///
/// Shows a status message reflecting the current [ScanPhase].
/// The full screen is available for scanning — no viewfinder rectangle is drawn.
class ScanOverlay extends StatelessWidget {
  final ScanPhase phase;

  const ScanOverlay({super.key, required this.phase});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Status label at the bottom
        Positioned(
          bottom: 48,
          left: 24,
          right: 24,
          child: Center(child: _statusChip(context)),
        ),
      ],
    );
  }

  Widget _statusChip(BuildContext context) {
    final (label, color) = switch (phase) {
      ScanPhase.initializing => ('Initialising camera…', Colors.grey),
      ScanPhase.scanning => ('Point at a card', Colors.white),
      ScanPhase.processing => ('Identifying card…', Colors.amber),
      ScanPhase.resolved => ('Card found!', Colors.green),
      ScanPhase.error => ('Could not read card', Colors.red),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withAlpha(180)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w500),
        textAlign: TextAlign.center,
      ),
    );
  }
}

