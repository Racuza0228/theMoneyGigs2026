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
    return LayoutBuilder(
      builder: (context, constraints) {
        // Default fallback position (30% down the screen)
        double topOffset = MediaQuery.of(context).size.height * 0.3;

        if (searchBarKey?.currentContext != null) {
          final RenderBox? box = searchBarKey!.currentContext!.findRenderObject() as RenderBox?;

          // 🛠️ FIX: Added hasSize check to prevent "RenderBox was not laid out" error
          if (box != null && box.hasSize) {
            final Offset position = box.localToGlobal(Offset.zero);
            // Position below: Top of search bar + height + extra room for the autocomplete height
            topOffset = position.dy + (box.size.height * 2.5) + 20;
          }
        }

        // 🛠️ KEYBOARD SAFETY: If the topOffset is so low it's off-screen (due to keyboard),
        // cap it so it stays visible.
        double screenHeight = MediaQuery.of(context).size.height;
        if (topOffset > screenHeight - 150) {
          topOffset = screenHeight - 160;
        }

        return Stack(
          children: [
            IgnorePointer(
              ignoring: true,
              child: CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: _HighlightPainter(
                  highlightKey: searchBarKey,
                  context: context,
                ),
              ),
            ),

            // Positioned instructions below the search area
            Positioned(
              top: topOffset,
              left: 24,
              right: 24,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.9),
                    border: Border.all(color: Colors.white, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.location_on, size: 24, color: Colors.white),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: AnimatedText(
                              text: 'Where would you like to play?',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Enter a restaurant, bar or place to search.',
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(50, 30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => demoProvider.endDemo(),
                          child: const Text(
                            'Exit Onboarding',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
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

    canvas.drawPath(overlayPath, Paint()..color = Colors.black.withValues(alpha: 0.7));
  }

  @override
  bool shouldRepaint(covariant _HighlightPainter oldDelegate) => true;
}
