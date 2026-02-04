// lib/features/app_demo/widgets/simple_demo_overlay.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:the_money_gigs/features/app_demo/providers/demo_provider.dart';

// The StatefulWidget definition remains the same
class SimpleDemoOverlay extends StatefulWidget {
  final String title;
  final String message;
  final List<GlobalKey> highlightKeys;
  final bool showNextButton;
  final bool showExitButton;
  final bool blockInteraction; // When true, the highlight is visual only — all taps are blocked except the buttons
  final VoidCallback? onNext;

  const SimpleDemoOverlay({
    super.key,
    required this.title,
    required this.message,
    this.highlightKeys = const [],
    this.showNextButton = false,
    this.showExitButton = true,
    this.blockInteraction = false,
    this.onNext,
  });

  @override
  State<SimpleDemoOverlay> createState() => _SimpleDemoOverlayState();
}

class _SimpleDemoOverlayState extends State<SimpleDemoOverlay> {
  List<Rect> _highlightRects = [];
  double? _textYOffset;
  bool _isLayoutCalculated = false;

  @override
  void initState() {
    super.initState();
    _calculateLayout();
  }

  @override
  void didUpdateWidget(covariant SimpleDemoOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlightKeys != oldWidget.highlightKeys || widget.message != oldWidget.message) {
      setState(() {
        _isLayoutCalculated = false;
      });
      _calculateLayout();
    }
  }

  void _calculateLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {if (!mounted) return;

    final RenderBox? pageRenderBox = context.findRenderObject() as RenderBox?;
    if (pageRenderBox == null || !pageRenderBox.hasSize) {
      setState(() {
        _textYOffset = MediaQuery.of(context).size.height * 0.6;
        _isLayoutCalculated = true;
      });
      return;
    }

    List<Rect> newRects = [];
    double topMostY = double.infinity;
    Rect? topRect;

    for (var key in widget.highlightKeys) {
      final targetRenderBox = key.currentContext?.findRenderObject() as RenderBox?;

      if (targetRenderBox != null && targetRenderBox.hasSize && targetRenderBox.attached) {
        final offset = pageRenderBox.globalToLocal(targetRenderBox.localToGlobal(Offset.zero));
        final rect = Rect.fromLTWH(
          offset.dx,
          offset.dy,
          targetRenderBox.size.width,
          targetRenderBox.size.height,
        );
        newRects.add(rect);

        if (rect.top < topMostY) {
          topMostY = rect.top;
          topRect = rect;
        }
      }
    }

    setState(() {
      _highlightRects = newRects;
      if (newRects.length > 1 && topRect != null) {
        _textYOffset = topRect!.bottom + 30.0;
      } else if (newRects.isNotEmpty) {
        _textYOffset = newRects.first.bottom + 24.0;
      } else {
        _textYOffset = MediaQuery.of(context).size.height * 0.35;
      }
      _isLayoutCalculated = true;
    });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLayoutCalculated) {
      return const SizedBox.shrink();
    }

    final demoProvider = Provider.of<DemoProvider>(context, listen: false);
    final double yOffset = _textYOffset ?? MediaQuery.of(context).size.height * 0.5;

    // 🎯 THE FIX: Wrap the entire Stack in a Material widget.
    return Material(
      type: MaterialType.transparency, // This makes the Material widget itself invisible.
      child: Stack(
        children: [
          // The CustomPainter and dimming effect
          if (widget.blockInteraction)
            CustomPaint(
              size: MediaQuery.of(context).size,
              painter: _SimpleHighlightPainter(highlightRects: _highlightRects),
            )
          else
            IgnorePointer(
              child: CustomPaint(
                size: MediaQuery.of(context).size,
                painter: _SimpleHighlightPainter(highlightRects: _highlightRects),
              ),
            ),

          // The positioned dialog box
          Positioned(
            top: yOffset,
            left: 24,
            right: 24,
            child: Center(
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
                    Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      // The style now correctly inherits from the new Material ancestor.
                      // The `decoration` property is no longer needed.
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white70,
                      ),
                    ),
                    if (widget.showNextButton || widget.showExitButton) const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.showExitButton)
                          TextButton(
                            onPressed: () => demoProvider.endDemo(),
                            child: const Text(
                              'Exit Demo',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                        if (widget.showExitButton && widget.showNextButton)
                          const SizedBox(width: 16),
                        if (widget.showNextButton)
                          ElevatedButton(
                            onPressed: widget.onNext ?? () => demoProvider.nextStep(),
                            child: const Text('Next'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 🎯 REPLACE THE PAINTER CLASS AS WELL
class _SimpleHighlightPainter extends CustomPainter {
  // It no longer needs keys or a pageRenderBox, just the final rectangles
  final List<Rect> highlightRects;

  _SimpleHighlightPainter({required this.highlightRects});

  @override
  void paint(Canvas canvas, Size size) {
    final fullScreenPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    Path combinedHighlightPath = Path();

    for (final rect in highlightRects) {
      // Inflate the pre-calculated rect and add it to the path
      final highlightRRect = RRect.fromRectAndRadius(
        rect.inflate(8.0),
        const Radius.circular(12.0),
      );
      combinedHighlightPath.addRRect(highlightRRect);
    }

    final overlayPath = Path.combine(PathOperation.difference, fullScreenPath, combinedHighlightPath);
    canvas.drawPath(overlayPath, Paint()..color = Colors.black.withOpacity(0.8));
  }

  @override
  bool shouldRepaint(covariant _SimpleHighlightPainter oldDelegate) {
    // Repaint only if the list of rectangles has changed.
    return oldDelegate.highlightRects != highlightRects;
  }
}