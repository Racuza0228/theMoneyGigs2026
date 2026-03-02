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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final demoStep = widget.demoStep;
      if (demoStep == null) return;

      // 🎯 Define statusBarHeight inside this method scope
      final double statusBarHeight = MediaQuery.of(context).padding.top;

      String title = '';
      String message = '';
      List<GlobalKey> highlightKeys = [];
      double textYOffset = statusBarHeight; // Default to top
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
          }
          // Offset is handled by the "isBannerStep" logic in build(),
          // but we set it here for consistency.
          textYOffset = statusBarHeight;
          break;

        case DemoStep.bookingFormAction:
          title = "Let's Book It";
          message = "Select a DATE and press Confirm & Book to save to your schedule.";
          showNextButton = false;
          highlightKeys = [widget.dateKey, widget.confirmKey];

          // 🎯 Pin to top banner
          textYOffset = statusBarHeight;
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



  @override
  Widget build(BuildContext context) {
    final demoProvider = Provider.of<DemoProvider>(context, listen: false);
    final RenderBox? parentRenderBox = context.findRenderObject() as RenderBox?;
    final double statusBarHeight = MediaQuery.of(context).padding.top;

    return LayoutBuilder(
      builder: (context, constraints) {
        // We use the Banner style for all steps in this form
        bool isBannerStep = widget.demoStep == DemoStep.bookingFormValue ||
            widget.demoStep == DemoStep.bookingFormAction;

        return Stack(
          children: [
            // 1. VISUAL MASK ONLY
            // We wrap this in IgnorePointer. It draws the "holes" but
            // the finger goes straight through them to the TextFields.
            if (_isReadyToPaint)
              IgnorePointer(
                child: CustomPaint(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                  painter: _MultiHighlightPainter(
                    highlightKeys: _isReadyToPaint ? _highlightKeys : [],
                    pageRenderBox: parentRenderBox,
                  ),
                ),
              ),

            // 2. THE INSTRUCTION BANNER
            // Positioned at the very top, safe from the keyboard.
            if (_isReadyToPaint && widget.demoStep != null)
              Positioned(
                top: statusBarHeight,
                left: 0,
                right: 0,
                child: Material(
                  elevation: 8,
                  color: Colors.black.withOpacity(0.95),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Colors.orangeAccent.shade100, width: 2),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _title,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.orangeAccent.shade100,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton(
                              onPressed: () => demoProvider.endDemo(),
                              child: const Text('Exit Demo',
                                  style: TextStyle(color: Colors.white54, fontSize: 12)),
                            ),
                            if (_showNextButton)
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orangeAccent.shade700,
                                  foregroundColor: Colors.white,
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () {
                                  // This allows the user to progress only when ready
                                  FocusScope.of(context).unfocus();
                                  demoProvider.nextStep();
                                },
                                child: const Text('Next Step',
                                    style: TextStyle(fontWeight: FontWeight.bold)),
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
      },
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


