// lib/features/map_venues/widgets/map_tutorial_overlay.dart
//
// Shown once to new users after the map finishes loading.
// Three steps explain the core map interactions:
//   1. What the markers mean
//   2. How to tap a marker (ratings, booking, info)
//   3. How to use search to add new venues
//
// Guarded by the 'map_tutorial_shown' SharedPreferences flag.
// Writes session data to the 'mapTutorialSessions' Firestore collection.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

class MapTutorialOverlay extends StatefulWidget {
  /// Called when the user finishes or dismisses the tutorial.
  final VoidCallback onDismiss;
  final GlobalKey searchBarKey;

  const MapTutorialOverlay({
    super.key,
    required this.onDismiss,
    required this.searchBarKey,
  });

  /// Returns true if the tutorial has NOT been shown yet.
  /// Use this before building the overlay to decide whether to show it.
  static Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool('map_tutorial_shown') ?? false);
  }

  static Future<void> markShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('map_tutorial_shown', true);
  }

  @override
  State<MapTutorialOverlay> createState() => _MapTutorialOverlayState();
}

class _MapTutorialOverlayState extends State<MapTutorialOverlay>
    with SingleTickerProviderStateMixin {
  int _step = 0;
  late final AnimationController _fadeController;
  late final Animation<double> _fade;

  static const int _totalSteps = 3;

  // ── Tracking ──────────────────────────────────────────────────────────────
  String? _sessionId;
  DocumentReference? _sessionRef;
  bool _trackingReady = false;

  static const _stepNames = ['markers', 'tapMarker', 'addVenue'];

  // Per-step content
  static const _steps = [
    _TutorialStep(
      icon: Icons.location_on_rounded,
      iconColor: Color(0xFF4CAF50), // green — matches public venue markers
      title: 'Community Venues',
      body: 'Green markers are venues shared by musicians like you — '
          'bars, restaurants, music rooms, and more. '
          'Blue markers are venues you\'ve added privately.',
    ),
    _TutorialStep(
      icon: Icons.touch_app_rounded,
      iconColor: Colors.amber,
      title: 'Tap Any Marker',
      body: 'Tap a marker to see ratings and comments from other musicians, '
          'contact information, and to book a gig there. '
          'Your pay data stays on your device — only ratings are shared.',
    ),
    _TutorialStep(
      icon: Icons.search_rounded,
      iconColor: Colors.lightBlueAccent,
      title: 'Add a Venue',
      body: 'Don\'t see somewhere you play? '
          'Tap the search bar at the top and type the venue name or address. '
          'Select it from the results to add it to your map.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fade = CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);
    _fadeController.forward();
    _initTracking();
  }

  // ── Tracking ──────────────────────────────────────────────────────────────

  Future<void> _initTracking() async {
    _sessionId = const Uuid().v4();
    final ref = FirebaseFirestore.instance
        .collection('mapTutorialSessions')
        .doc(_sessionId);
    try {
      final prefs = await SharedPreferences.getInstance();
      final isDeveloper = prefs.getBool('is_developer_device') ?? false;

      await ref.set({
        'sessionId':    _sessionId,
        'startedAt':    FieldValue.serverTimestamp(),
        'platform':     Platform.isAndroid ? 'android' : 'ios',
        'osVersion':    Platform.operatingSystemVersion,
        'isDeveloper':  isDeveloper,
        'completed':    false,
        'exitedOnStep': null,
        'stepsViewed':  [_stepNames[0]],
        'step1ViewedAt': FieldValue.serverTimestamp(),
      });
      _sessionRef = ref;
      _trackingReady = true;
    } catch (e) {
      debugPrint('📋 MapTutorialTracking: init failed — $e');
    }
  }

  Future<void> _trackStepView(int step) async {
    if (!_trackingReady || _sessionRef == null) return;
    try {
      await _sessionRef!.update({
        'stepsViewed':              FieldValue.arrayUnion([_stepNames[step]]),
        'step${step + 1}ViewedAt':  FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('📋 MapTutorialTracking: step view failed — $e');
    }
  }

  Future<void> _trackExit(int onStep) async {
    if (!_trackingReady || _sessionRef == null) return;
    try {
      await _sessionRef!.update({
        'exitedOnStep': _stepNames[onStep],
        'exitedAt':     FieldValue.serverTimestamp(),
        'completed':    false,
      });
    } catch (e) {
      debugPrint('📋 MapTutorialTracking: exit failed — $e');
    }
  }

  Future<void> _trackCompletion() async {
    if (!_trackingReady || _sessionRef == null) return;
    try {
      await _sessionRef!.update({
        'completed':    true,
        'completedAt':  FieldValue.serverTimestamp(),
        'exitedOnStep': null,
      });
    } catch (e) {
      debugPrint('📋 MapTutorialTracking: completion failed — $e');
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _nextStep() async {
    if (_step < _totalSteps - 1) {
      await _fadeController.reverse();
      setState(() => _step++);
      _fadeController.forward();
      await _trackStepView(_step);
    } else {
      await _trackCompletion();
      await Future.delayed(const Duration(milliseconds: 200));
      await _dismiss(completed: true);
    }
  }

  Future<void> _dismiss({bool completed = false}) async {
    if (!completed) {
      await _trackExit(_step);
      await Future.delayed(const Duration(milliseconds: 200));
    }
    await MapTutorialOverlay.markShown();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_step];
    final isLast = _step == _totalSteps - 1;

    // Position the card just below the search bar.
    // We use `top` (not `bottom`) so the card's top edge is anchored to
    // the search bar's bottom — this stays correct regardless of the AppBar
    // height or extendBodyBehindAppBar being true.
    final searchBox =
    widget.searchBarKey.currentContext?.findRenderObject() as RenderBox?;

    // Global Y coordinate of the bottom of the search bar + a tight gap.
    // 8px keeps the card visually connected to the search bar and maximises
    // vertical space so all content is visible without scrolling.
    // Falls back to just below the AppBar if the search bar isn't laid out yet.
    final double cardTop = (searchBox != null && searchBox.hasSize)
        ? searchBox.localToGlobal(Offset.zero).dy + searchBox.size.height + 8
        : MediaQuery.of(context).padding.top + kToolbarHeight + 16;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Dimmed background — tapping it dismisses
          GestureDetector(
            onTap: () => _dismiss(completed: false),
            child: Container(
              color: Colors.black.withValues(alpha: 0.65),
            ),
          ),

          // Tutorial card — sized to content, not stretched to fill screen.
          // ConstrainedBox provides a safety-net maxHeight so the card never
          // overflows the bottom nav bar on any phone size.
          Positioned(
            left: 20,
            right: 20,
            top: cardTop,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height
                    - cardTop
                    - MediaQuery.of(context).padding.bottom
                    - kBottomNavigationBarHeight
                    - 16,
              ),
              child: FadeTransition(
                opacity: _fade,
                child: _TutorialCard(
                  step: step,
                  currentStep: _step,
                  totalSteps: _totalSteps,
                  isLast: isLast,
                  onNext: _nextStep,
                  onSkip: () => _dismiss(completed: false),
                ),
              ),
            ),
          ),

          // Search bar callout arrow on step 2 (add venue step)
          if (_step == 2 && searchBox != null && searchBox.hasSize)
            _SearchBarArrow(searchBarKey: widget.searchBarKey),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card widget
// ─────────────────────────────────────────────────────────────────────────────

class _TutorialCard extends StatelessWidget {
  final _TutorialStep step;
  final int currentStep;
  final int totalSteps;
  final bool isLast;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _TutorialCard({
    required this.step,
    required this.currentStep,
    required this.totalSteps,
    required this.isLast,
    required this.onNext,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      decoration: BoxDecoration(
        color: const Color(0xF0111111),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      // Column wraps content — card height is driven by content, not Positioned bounds.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Content — scrollable on very small phones ──────────────────
          SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // (Progress dots removed — step count conveyed by Next/Skip labels)

                // Icon
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: step.iconColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: step.iconColor.withValues(alpha: 0.4),
                        width: 1.5),
                  ),
                  child: Icon(step.icon, color: step.iconColor, size: 32),
                ),
                const SizedBox(height: 16),

                // Title
                Text(
                  step.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),

                // Body
                Text(
                  step.body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.white,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),

          // ── Buttons — always visible, never scrolled off ───────────────
          const Divider(color: Colors.white60, height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: onSkip,
                child: Text(
                  isLast ? 'Got it' : 'Skip',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: onNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                  foregroundColor: Colors.white,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  isLast ? 'Start exploring' : 'Next',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Arrow pointing up at the search bar on step 3
// ─────────────────────────────────────────────────────────────────────────────

class _SearchBarArrow extends StatelessWidget {
  final GlobalKey searchBarKey;

  const _SearchBarArrow({required this.searchBarKey});

  @override
  Widget build(BuildContext context) {
    final box =
    searchBarKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return const SizedBox.shrink();

    final pos = box.localToGlobal(Offset.zero);
    final centerX = pos.dx + box.size.width / 2;
    final arrowTop = pos.dy + box.size.height + 2;

    return Positioned(
      left: centerX - 14,
      top: arrowTop,
      child: Column(
        children: [
          Icon(Icons.arrow_drop_up_rounded,
              size: 28, color: Colors.orange.shade400),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data
// ─────────────────────────────────────────────────────────────────────────────

class _TutorialStep {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;

  const _TutorialStep({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
  });
}