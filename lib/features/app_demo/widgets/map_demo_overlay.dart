// lib/features/app_demo/widgets/map_demo_overlay.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/demo_provider.dart';
import 'animated_text.dart';

class MapDemoOverlay extends StatelessWidget {
  final GlobalKey? searchBarKey;

  const MapDemoOverlay({
    super.key,
    this.searchBarKey,
  });

  @override
  Widget build(BuildContext context) {
    final demoProvider = context.watch<DemoProvider>();

    if (!demoProvider.isDemoModeActive) {
      return const SizedBox.shrink();
    }

    switch (demoProvider.currentStep) {
      case DemoStep.mapVenueSearch:
        return _buildVenueSearchOverlay(context, demoProvider);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildVenueSearchOverlay(BuildContext context, DemoProvider demoProvider) {
    return Stack(
      children: [
        // This allows tap events to pass through the dimmed area to the
        // autocomplete results list underneath.
        IgnorePointer(
          ignoring: true, // It should always ignore pointers.
          child: CustomPaint(
            size: MediaQuery.of(context).size,
            painter: _HighlightPainter(
              highlightKey: searchBarKey,
              context: context,
            ),
          ),
        ),

        // Place the instructional text in the center of the screen.
        // This widget is NOT wrapped in IgnorePointer, so its buttons are still tappable.
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24.0),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.85),
              border: Border.all(color: Colors.white, width: 2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.location_on, size: 36, color: Colors.white),
                const SizedBox(height: 16),
                const AnimatedText(
                  text: 'Where would you like to play?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Use search bar above.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => demoProvider.endDemo(),
                      child: const Text(
                        'Exit Demo',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: () => demoProvider.nextStep(),
                      child: const Text('Skip'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HighlightPainter extends CustomPainter {
  final GlobalKey? highlightKey;
  final BuildContext context;

  _HighlightPainter({
    required this.highlightKey,
    required this.context,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (highlightKey?.currentContext == null) return;

    final RenderBox? pageRenderBox = context.findRenderObject() as RenderBox?;
    if (pageRenderBox == null) return;

    final RenderBox? targetRenderBox = highlightKey!.currentContext!.findRenderObject() as RenderBox?;
    if (targetRenderBox == null || !targetRenderBox.hasSize) return;

    final Offset localOffset = pageRenderBox.globalToLocal(targetRenderBox.localToGlobal(Offset.zero));

    // 🎯 THE CHANGE: Make the highlight rect taller to include the first result.
    final highlightRect = Rect.fromLTWH(
      localOffset.dx,
      localOffset.dy,
      targetRenderBox.size.width,
      targetRenderBox.size.height * 2.2, // Increase height to show the autocomplete card
    );

    // Inflate the rect slightly for padding, but use separate horizontal and vertical values
    final paddedRect = Rect.fromLTRB(
      highlightRect.left - 8,
      highlightRect.top - 8,
      highlightRect.right + 8,
      highlightRect.bottom + 8,
    );

    final highlightRRect = RRect.fromRectAndRadius(
      paddedRect,
      const Radius.circular(32.0), // Rounded corners for the entire shape
    );

    final fullScreenPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final highlightPath = Path()..addRRect(highlightRRect);

    final overlayPath = Path.combine(PathOperation.difference, fullScreenPath, highlightPath);

    canvas.drawPath(overlayPath, Paint()..color = Colors.black.withOpacity(0.7));
  }

  @override
  bool shouldRepaint(covariant _HighlightPainter oldDelegate) => true;
}
