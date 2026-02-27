import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:the_money_gigs/features/app_demo/providers/demo_provider.dart';

// 🎯 Convert to StatefulWidget to manage its own state and lifecycle
class BookingDemoOverlay extends StatefulWidget {
  final DemoStep? demoStep;
  final Function(DemoStep?) onStepChange;
  final GlobalKey driveSetupKey;
  final GlobalKey rehearsalKey;
  final GlobalKey payKey;
  final GlobalKey lengthKey;
  final GlobalKey otherExpensesKey;
  final GlobalKey rateDisplayKey;
  final GlobalKey dateKey;
  final GlobalKey confirmKey;
  final bool isAddNewVenueMode;

  const BookingDemoOverlay({
    super.key,
    required this.demoStep,
    required this.onStepChange,
    required this.driveSetupKey,
    required this.rehearsalKey,
    required this.payKey,
    required this.lengthKey,
    required this.otherExpensesKey,
    required this.rateDisplayKey,
    required this.dateKey,
    required this.confirmKey,
    required this.isAddNewVenueMode,
  });

  @override
  State<BookingDemoOverlay> createState() => _BookingDemoOverlayState();
}

class _BookingDemoOverlayState extends State<BookingDemoOverlay> {
  // 🎯 State variables to hold calculated values
  List<GlobalKey> _highlightKeys = [];
  String _title = '';
  String _message = '';
  double _textYOffset = 100.0;
  bool _showNextButton = false;
  bool _isReadyToPaint = false; // Flag to prevent painting before calculations are done

  @override
  void initState() {
    super.initState();
    // Calculate layout AFTER the first frame is built
    _calculateLayout();
    // 🎯 2. Re-measure after the dialog finishes its entry animation
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _calculateLayout();
    });
  }

  @override
  void didUpdateWidget(covariant BookingDemoOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Recalculate layout whenever the inputs change (e.g., demo step changes)
    if (widget.demoStep != oldWidget.demoStep || widget.isAddNewVenueMode != oldWidget.isAddNewVenueMode) {
      // Reset paint flag to avoid drawing with stale data
      setState(() {
        _isReadyToPaint = false;
      });
      widget.onStepChange(widget.demoStep);

      _calculateLayout();
    }
  }

  void _calculateLayout() {
    if (!mounted) return;

    // Use postFrameCallback to ensure the underlying widgets have rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final demoStep = widget.demoStep;
      if (demoStep == null) return;

      String title = '';
      String message = '';
      List<GlobalKey> highlightKeys = [];
      double textYOffset = MediaQuery.of(context).size.height * 0.1;
      bool showNextButton = false;

      switch (demoStep) {
        case DemoStep.bookingFormValue:
          title = "What's your REAL hourly rate?";
          message = "Fill in all of the time involved to see your true earnings. Then, tap Next to continue.";
          showNextButton = true;

          if (!widget.isAddNewVenueMode) {
            highlightKeys = [
              widget.payKey,
              widget.lengthKey,
              widget.driveSetupKey,
              widget.rehearsalKey,
              widget.otherExpensesKey,
              widget.rateDisplayKey,
            ];
            double lowestInputBottom = _getLowestBottom(highlightKeys);

            // 🎯 3. Improved positioning logic
            if (lowestInputBottom > 0) {
              textYOffset = lowestInputBottom + 16;
            } else {
              // If we measured 0, try again in a moment
              Future.delayed(const Duration(milliseconds: 100), _calculateLayout);
              return;
            }
          } else {
            textYOffset = MediaQuery.of(context).size.height * 0.25;
          }
          break;

        case DemoStep.bookingFormAction:
          title = "Let's Book It";
          message = "Now, SELECT A DATE for the gig and press Confirm & Book to save it to your schedule.";
          showNextButton = false;
          highlightKeys = [widget.dateKey, widget.confirmKey];
          textYOffset = MediaQuery.of(context).size.height * 0.3;
          break;
        default:
          break;
      }

      setState(() {
        _title = title;
        _message = message;
        _highlightKeys = highlightKeys;
        _textYOffset = textYOffset;
        _showNextButton = showNextButton;
        _isReadyToPaint = true;
      });
    });
  }


  double _getLowestBottom(List<GlobalKey> keys) {
    double lowestBottom = 0;
    for (var key in keys) {
      final context = key.currentContext;
      if (context == null) continue;

      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox != null && renderBox.hasSize && renderBox.attached) {
        try {
          final position = renderBox.localToGlobal(Offset.zero);
          // 🎯 4. Log the measurement to verify it's working
          // print('📏 [Overlay] Measured key: ${key.hashCode} at ${position.dy}');

          final bottom = position.dy + renderBox.size.height;
          if (bottom > lowestBottom) {
            lowestBottom = bottom;
          }
        } catch (e) {
          continue;
        }
      }
    }
    return lowestBottom;
  }

  @override
  Widget build(BuildContext context) {
    // 🎯 5. We always return the Stack, but only show the "holes" when measured
    final demoProvider = Provider.of<DemoProvider>(context, listen: false);
    final RenderBox? parentRenderBox = context.findRenderObject() as RenderBox?;

    return Stack(
      children: [
        IgnorePointer(
          child: CustomPaint(
            size: MediaQuery.of(context).size,
            painter: _MultiHighlightPainter(
              // Only pass keys if we have actually measured them (lowestBottom > 0)
              highlightKeys: _isReadyToPaint ? _highlightKeys : [],
              pageRenderBox: parentRenderBox,
            ),
          ),
        ),

        if (_isReadyToPaint && widget.demoStep != null)
          Positioned(
            top: _textYOffset,
            left: 24,
            right: 24,
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.9),
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Text(_message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(
                          onPressed: () => Future.microtask(() => demoProvider.endDemo()),
                          child: const Text('Exit Onboarding', style: TextStyle(color: Colors.white70)),
                        ),
                        if (_showNextButton)
                          ElevatedButton(
                            onPressed: () => demoProvider.nextStep(),
                            child: const Text('Next'),
                          ),
                      ],
                    )
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ... (The top part of the file and the _BookingDemoOverlayState are correct)

class _MultiHighlightPainter extends CustomPainter {
  final List<GlobalKey> highlightKeys;
  final RenderBox? pageRenderBox;

  _MultiHighlightPainter({required this.highlightKeys, required this.pageRenderBox});

  @override
  void paint(Canvas canvas, Size size) {
    final fullScreenPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    Path combinedHighlightPath = Path();

    // 🎯 Safety: If the parent is gone, just draw a solid overlay and exit
    if (pageRenderBox == null || !pageRenderBox!.attached) {
      canvas.drawPath(fullScreenPath, Paint()..color = Colors.black.withOpacity(0.8));
      return;
    }

    for (final key in highlightKeys) {
      try {
        final context = key.currentContext;
        final renderObject = context?.findRenderObject();

        if (renderObject == null || !renderObject.attached || renderObject is! RenderBox || !renderObject.hasSize) {
          continue;
        }

        // 🎯 Final check immediately before math
        if (!pageRenderBox!.attached) continue;

        final offset = pageRenderBox!.globalToLocal(renderObject.localToGlobal(Offset.zero));

        final highlightRect = Rect.fromLTWH(
          offset.dx,
          offset.dy,
          renderObject.size.width,
          renderObject.size.height,
        );

        combinedHighlightPath.addRRect(RRect.fromRectAndRadius(
          highlightRect.inflate(8.0),
          const Radius.circular(12.0),
        ));
      } catch (e) {
        continue; // Widget detached during loop, skip it
      }
    }

    final overlayPath = Path.combine(PathOperation.difference, fullScreenPath, combinedHighlightPath);
    canvas.drawPath(overlayPath, Paint()..color = Colors.black.withOpacity(0.8));
  }

  @override
  bool shouldRepaint(covariant _MultiHighlightPainter oldDelegate) {
    return oldDelegate.highlightKeys != highlightKeys || oldDelegate.pageRenderBox != pageRenderBox;
  }
}


