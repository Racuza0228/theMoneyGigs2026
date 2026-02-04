// lib/features/app_demo/widgets/gig_list_demo_overlay.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/demo_provider.dart';
import 'animated_text.dart';

/// Overlay for the gig list page that shows users their demo gig
class GigListDemoOverlay extends StatelessWidget {
  final GlobalKey? demoGigKey;

  const GigListDemoOverlay({
    super.key,
    this.demoGigKey,
  });

  @override
  Widget build(BuildContext context) {
    final demoProvider = context.watch<DemoProvider>();

    if (!demoProvider.isDemoModeActive ||
        demoProvider.currentStep != DemoStep.gigListView) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        // Semi-transparent background
        GestureDetector(
          onTap: () {}, // Block interactions
          child: Container(
            color: Colors.black.withOpacity(0.7),
          ),
        ),

        // Highlight the demo gig if key is provided
        if (demoGigKey != null)
          CustomPaint(
            size: MediaQuery.of(context).size,
            painter: _HighlightPainter(
              highlightKey: demoGigKey,
              context: context,
            ),
          ),

        // Congratulations message
        Align(
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.celebration,
                    size: 64,
                    color: Colors.amber,
                  ),
                  const SizedBox(height: 20),
                  const AnimatedText(
                    text: 'Congratulations! 🎉',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'You\'ve booked your first gig!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your gig now appears in your gig list. You can view details, edit it, or cancel it at any time.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade900.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade700),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'What\'s Next?',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade100,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '• Add more venues from the Map tab\n'
                              '• Book real gigs and track your earnings\n'
                              '• Use the Calculator to evaluate gig offers\n'
                              '• View your profile and update your info',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.blue.shade100,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  ElevatedButton.icon(
                    onPressed: () {
                      demoProvider.endDemo();
                    },
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text(
                      'Get Started!',
                      style: TextStyle(fontSize: 18),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      backgroundColor: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
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
    if (highlightKey == null) return;

    final RenderBox? renderBox = highlightKey!.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final pageRenderBox = context.findRenderObject() as RenderBox?;
    if (pageRenderBox == null) return;

    final pageOffset = pageRenderBox.localToGlobal(Offset.zero);
    final widgetPosition = renderBox.localToGlobal(Offset.zero);
    final widgetSize = renderBox.size;

    final highlightRect = Rect.fromLTWH(
      widgetPosition.dx - pageOffset.dx,
      widgetPosition.dy - pageOffset.dy,
      widgetSize.width,
      widgetSize.height,
    );

    final highlightRRect = RRect.fromRectAndRadius(
      highlightRect.inflate(8.0),
      const Radius.circular(12.0),
    );

    final fullScreenPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final highlightPath = Path()..addRRect(highlightRRect);
    final overlayPath = Path.combine(PathOperation.difference, fullScreenPath, highlightPath);

    canvas.drawPath(overlayPath, Paint()..color = Colors.black.withOpacity(0.7));
  }

  @override
  bool shouldRepaint(covariant _HighlightPainter oldDelegate) {
    return true;
  }
}