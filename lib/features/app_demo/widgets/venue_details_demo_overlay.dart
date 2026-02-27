// lib/features/app_demo/widgets/venue_details_demo_overlay.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:the_money_gigs/features/app_demo/providers/demo_provider.dart';

class VenueDetailsDemoOverlay extends StatelessWidget {
  final GlobalKey bookButtonKey;
  final VoidCallback onExit;

  const VenueDetailsDemoOverlay({
    super.key,
    required this.bookButtonKey,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    // ❌ REMOVE the root IgnorePointer. We will handle pointers more granularly.
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // ✅ 1. Wrap the backdrop in its OWN IgnorePointer.
          // This makes the semi-transparent part non-tappable, allowing
          // clicks to pass through to the underlying UI (the "Book" button).
          IgnorePointer(
            child: CustomPaint(
              size: MediaQuery.of(context).size,
              painter: _HighlightPainter(
                highlightKey: bookButtonKey,
                context: context,
              ),
            ),
          ),

          // The instructional text box. Since it's NOT wrapped in an
          // IgnorePointer, it will receive taps by default.
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
                  // ✅ 2. Now this button is tappable without needing an AbsorbPointer.
                  TextButton(
                    onPressed: () {
                      // Find the provider and end the demo
                      Provider.of<DemoProvider>(context, listen: false).endDemo();
                      // Call the onExit callback to remove the overlay
                      onExit();
                    },
                    child: const Text('Exit Onboarding', style: TextStyle(color: Colors.white70)),
                  ),
                ],
              ),
            ),
          ),
        ],
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
