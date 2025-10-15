// lib/features/app_demo/widgets/tutorial_overlay.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/demo_provider.dart';

// *** CONVERTED TO A STATEFULWIDGET TO HANDLE LAYOUT CALLBACK ***
class TutorialOverlay extends StatefulWidget {
  final GlobalKey highlightKey;
  final String instructionalText;
  final Alignment textAlignment;
  final VoidCallback onNext;

  const TutorialOverlay({
    super.key,
    required this.highlightKey,
    required this.instructionalText,
    required this.onNext,
    this.textAlignment = Alignment.topCenter,
  });

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay> {
  Rect? _highlightRect; // Store the position and size of the highlight area

  @override
  void initState() {
    super.initState();
    // *** THIS IS THE FIX ***
    // We wait for the frame to finish painting before getting the widget's position.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculateHighlightRect();
    });
  }

  void _calculateHighlightRect() {
    final RenderBox? renderBox =
    widget.highlightKey.currentContext?.findRenderObject() as RenderBox?;

    if (renderBox != null && renderBox.hasSize) {
      final offset = renderBox.localToGlobal(Offset.zero);
      setState(() {
        _highlightRect = Rect.fromPoints(
          offset,
          offset.translate(renderBox.size.width, renderBox.size.height),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // If we haven't calculated the highlight position yet, show a transparent placeholder.
    if (_highlightRect == null) {
      return const Material(color: Colors.transparent);
    }

    // This is the same drawing logic as before, but now using the saved _highlightRect.
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // This is the semi-transparent background
          ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withOpacity(0.7),
              BlendMode.srcOut,
            ),
            child: Stack(
              children: [
                // This is the full-screen block
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.white, // Color does not matter
                    backgroundBlendMode: BlendMode.dstOut,
                  ),
                ),
                // This is the "hole" punched out for the highlight
                Positioned(
                  left: _highlightRect!.left - 8,
                  top: _highlightRect!.top - 8,
                  width: _highlightRect!.width + 16,
                  height: _highlightRect!.height + 16,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white, // Color does not matter
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // This positions the instructional text and buttons
          Align(
            alignment: widget.textAlignment,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.instructionalText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => context.read<DemoProvider>().endDemo(),
                        child: const Text('Skip Demo',
                            style: TextStyle(color: Colors.white70)),
                      ),
                      const SizedBox(width: 20),
                      ElevatedButton(
                        onPressed: widget.onNext,
                        child: const Text('Next'),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
