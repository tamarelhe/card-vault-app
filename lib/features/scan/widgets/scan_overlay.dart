import 'package:flutter/material.dart';
import '../scanner_controller.dart';

/// Transparent overlay drawn on top of the camera preview.
///
/// Shows a card-shaped viewfinder rectangle and a status message
/// reflecting the current [ScanPhase].
class ScanOverlay extends StatelessWidget {
  final ScanPhase phase;

  const ScanOverlay({super.key, required this.phase});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Dark vignette around the viewfinder
        CustomPaint(painter: _VignettePainter()),

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

/// Paints a semi-transparent vignette with a transparent card-shaped cutout.
class _VignettePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Card aspect ratio ≈ 63 × 88 mm → ~0.716
    const cardAspect = 63.0 / 88.0;
    final cardW = size.width * 0.75;
    final cardH = cardW / cardAspect;
    final cardRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: cardW,
        height: cardH,
      ),
      const Radius.circular(8),
    );

    // Outer dark overlay
    final outer = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    // Cutout
    final inner = Path()..addRRect(cardRect);
    // Subtract the cutout from the overlay
    final vignette = Path.combine(PathOperation.difference, outer, inner);

    canvas.drawPath(
      vignette,
      Paint()..color = Colors.black.withAlpha(140),
    );

    // Draw viewfinder border
    canvas.drawRRect(
      cardRect,
      Paint()
        ..color = Colors.white.withAlpha(200)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_VignettePainter old) => false;
}
