// lib/features/app_demo/widgets/venue_details_demo_overlay.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:the_money_gigs/features/app_demo/providers/demo_provider.dart';

class VenueDetailsDemoOverlay extends StatelessWidget {
  final GlobalKey bookButtonKey;

  const VenueDetailsDemoOverlay({
    super.key,
    required this.bookButtonKey,
  });

  @override
  Widget build(BuildContext context) {
    // 🎯 THE FIX: Wrap the entire contents in an IgnorePointer
    // This allows taps to pass through the overlay to the buttons underneath.
    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            // This is the semi-transparent backdrop with a hole punched out for the button.
            CustomPaint(
              size: MediaQuery.of(context).size,
              painter: _HighlightPainter(
                highlightKey: bookButtonKey,
                context: context,
              ),
            ),

            // The instructional text box.
            Positioned(
              top: MediaQuery.of(context).size.height * 0.35,
              left: 24,
              right: 24,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.85),
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.edit_document, size: 48, color: Colors.white),
                    const SizedBox(height: 16),
                    const Text(
                      'Here you can enter information about the venue.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "For now, let's book a gig here by clicking Book.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.white70),
                    ),
                    const SizedBox(height: 20),
                    // Note: This button also becomes non-interactive, which is acceptable
                    // as the user's primary action should be to click 'BOOK'.
                    TextButton(
                      onPressed: () {}, // This will now be ignored
                      child: const Text('Exit Demo', style: TextStyle(color: Colors.white70)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// This painter is identical to the one in map_demo_overlay.dart
// It correctly calculates the position of the highlight.
class _HighlightPainter extends CustomPainter {
  final GlobalKey? highlightKey;
  final BuildContext context;

  _HighlightPainter({required this.highlightKey, required this.context});

  @override
  void paint(Canvas canvas, Size size) {
    if (highlightKey?.currentContext == null) return;

    final RenderBox? pageRenderBox = context.findRenderObject() as RenderBox?;
    if (pageRenderBox == null) return;

    final RenderBox? targetRenderBox = highlightKey!.currentContext!.findRenderObject() as RenderBox?;
    if (targetRenderBox == null || !targetRenderBox.hasSize) return;

    final Offset localOffset = pageRenderBox.globalToLocal(targetRenderBox.localToGlobal(Offset.zero));

    final highlightRect = Rect.fromLTWH(
      localOffset.dx,
      localOffset.dy,
      targetRenderBox.size.width,
      targetRenderBox.size.height,
    );

    final highlightRRect = RRect.fromRectAndRadius(
      highlightRect.inflate(8.0),
      const Radius.circular(12.0), // A standard button radius
    );

    final fullScreenPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final highlightPath = Path()..addRRect(highlightRRect);

    final overlayPath = Path.combine(PathOperation.difference, fullScreenPath, highlightPath);

    canvas.drawPath(overlayPath, Paint()..color = Colors.black.withOpacity(0.7));
  }

  @override
  bool shouldRepaint(covariant _HighlightPainter oldDelegate) => true;
}
