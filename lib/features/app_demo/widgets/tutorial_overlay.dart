// lib/features/app_demo/widgets/tutorial_overlay.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/demo_provider.dart';

class TutorialOverlay extends StatelessWidget {
  final GlobalKey? highlightKey;
  final String? instructionalText;
  final Alignment textAlignment;
  final VoidCallback onNext;
  final bool hideNextButton;
  final bool showDimmedOverlay;

  final Widget? customInstructionalChild;
  final String nextButtonText;
  final bool hideSkipButton;

  const TutorialOverlay({
    super.key,
    required this.highlightKey,
    this.instructionalText,
    required this.onNext,
    this.textAlignment = Alignment.topCenter,
    this.hideNextButton = false,
    this.showDimmedOverlay = true,
    this.customInstructionalChild,
    this.nextButtonText = 'Next',
    this.hideSkipButton = false,
  }) : assert(instructionalText != null || customInstructionalChild != null,
  'Either instructionalText or a customInstructionalChild must be provided.');

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // This is the background handler that blocks clicks.
        // It's only present when we DON'T want the user to click through.
        if (!hideNextButton)
          GestureDetector(
            onTap: () {
              // Do nothing, just absorb the tap.
            },
            child: CustomPaint(
              size: MediaQuery.of(context).size,
              painter: _HighlightPainter(
                highlightKey: highlightKey,
                context: context,
                overlayColor: Colors.black.withOpacity(0.7),
                // Pass the new property to the painter
                showDimmedOverlay: showDimmedOverlay, // <<< 3. PASS TO PAINTER
              ),
            ),
          ),
        if (hideNextButton)
          IgnorePointer(
            child: CustomPaint(
              size: MediaQuery.of(context).size,
              painter: _HighlightPainter(
                highlightKey: highlightKey,
                context: context,
                overlayColor: Colors.black.withOpacity(0.7),
                showDimmedOverlay: showDimmedOverlay, // <<< 3. PASS TO PAINTER
              ),
            ),
          ),
       Align(
          alignment: textAlignment,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 24.0),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                border: Border.all(color: Colors.white, width: 1.5),
                borderRadius: BorderRadius.circular(16.0),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (customInstructionalChild != null)
                    customInstructionalChild!
                  else
                    Text(
                      instructionalText!, // Use ! to assert it's not null here
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  if (!hideNextButton) ...[
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!hideSkipButton) ...[
                          TextButton(
                            onPressed: () => context.read<DemoProvider>().endDemo(),
                            child: const Text('Skip Demo', style: TextStyle(color: Colors.white70)),
                          ),
                          const SizedBox(width: 20),
                        ],
                        ElevatedButton(
                          onPressed: onNext,
                          child: Text(nextButtonText),
                        ),
                      ],
                    )
                  ]
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
  final Color overlayColor;
  final bool showDimmedOverlay; // <<< 4. RECEIVE NEW PROPERTY

  _HighlightPainter({
    required this.highlightKey,
    required this.context,
    required this.overlayColor,
    required this.showDimmedOverlay, // <<< 5. ADD TO CONSTRUCTOR
  });

  @override
  void paint(Canvas canvas, Size size) {
    // <<< 6. ADD CHECK TO SKIP PAINTING >>>
    if (!showDimmedOverlay) {
      return; // If we don't want the overlay, do nothing.
    }

    if (highlightKey == null) {
      // If there is no key, just draw the dimmed overlay and stop.
      canvas.drawColor(overlayColor, BlendMode.srcOver);
      return;
    }
    final RenderBox? renderBox = highlightKey!.currentContext?.findRenderObject() as RenderBox?;

    if (renderBox == null || !renderBox.hasSize) {
      canvas.drawColor(overlayColor, BlendMode.srcOver);
      return;
    }

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

    canvas.drawPath(overlayPath, Paint()..color = overlayColor);
  }

  @override
  bool shouldRepaint(covariant _HighlightPainter oldDelegate) {
    // Repaint if either color or the visibility flag changes
    return oldDelegate.overlayColor != overlayColor || oldDelegate.showDimmedOverlay != showDimmedOverlay;
  }
}
