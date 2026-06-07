// lib/features/app_demo/providers/demo_provider.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/core/utils/logger.dart';

enum DemoStep {
  none,

  // ── Onboarding (shown in OnboardingFlow widget) ───────────────────────────
  onboardingWelcome,

  // ── Map tutorial step — signals map.dart to show the overlay ─────────────
  mapTutorial,

  // ── Legacy steps kept in enum so overlay files still compile ─────────────
  coachingIntro,
  mapVenueSearch,
  mapAddVenue,
  mapBookGig,
  bookingFormValue,
  bookingFormAction,
  venueDetailsConfirmation,
  gigListView,
  profileConnect,
  emailCapture,

  complete,
}

class DemoProvider with ChangeNotifier {
  bool _isDemoModeActive = false;
  DemoStep _currentStep = DemoStep.none;
  bool _isReplay = false;

  static const String demoGigId = 'demo_gig_id_kroger';
  static const String demoVenuePlaceId = 'demo_venue_place_id_kroger';
  static const String hasSeenIntroKey = 'has_seen_intro_v1';

  bool get isDemoModeActive => _isDemoModeActive;
  DemoStep get currentStep => _currentStep;
  bool get isReplay => _isReplay;

  // ── Start ─────────────────────────────────────────────────────────────────

  Future<void> startDemo({bool force = false, bool replay = false}) async {
    if (_isDemoModeActive) return;

    _isDemoModeActive = true;
    _isReplay = replay;
    _currentStep = DemoStep.onboardingWelcome;

    log('🎬 DemoProvider: Starting onboarding (replay=$replay)');
    Future.microtask(notifyListeners);
  }

  // ── Advance ───────────────────────────────────────────────────────────────

  void nextStep() {
    if (!_isDemoModeActive) return;

    if (_currentStep == DemoStep.onboardingWelcome) {
      if (_isReplay) {
        // Replay: proceed to map tutorial after onboarding.
        _currentStep = DemoStep.mapTutorial;
        log('🎬 DemoProvider: Step → mapTutorial (replay)');
        notifyListeners();
      } else {
        // Normal first launch: onboarding complete, enter app.
        _currentStep = DemoStep.complete;
        _handleDemoCompletion();
      }
      return;
    }

    if (_currentStep == DemoStep.mapTutorial) {
      // Map tutorial is handled by map.dart — this step just signals it.
      // Completion comes back via completeMapTutorial().
      return;
    }

    final DemoStep next = _legacyNext(_currentStep);
    _currentStep = next;

    if (_currentStep == DemoStep.complete) {
      _handleDemoCompletion();
    }

    log('🎬 DemoProvider: Step → $_currentStep');
    notifyListeners();
  }

  /// Called by map.dart when the map tutorial overlay is dismissed.
  Future<void> completeMapTutorial() async {
    if (_currentStep != DemoStep.mapTutorial) return;
    log('🎬 DemoProvider: Map tutorial complete — ending demo');
    await _handleDemoCompletion();
  }

  DemoStep _legacyNext(DemoStep step) {
    switch (step) {
      case DemoStep.none:                     return DemoStep.onboardingWelcome;
      case DemoStep.onboardingWelcome:        return DemoStep.complete;
      case DemoStep.mapTutorial:              return DemoStep.complete;
      case DemoStep.coachingIntro:            return DemoStep.mapVenueSearch;
      case DemoStep.mapVenueSearch:           return DemoStep.mapAddVenue;
      case DemoStep.mapAddVenue:              return DemoStep.mapBookGig;
      case DemoStep.mapBookGig:               return DemoStep.bookingFormValue;
      case DemoStep.bookingFormValue:         return DemoStep.bookingFormAction;
      case DemoStep.bookingFormAction:        return DemoStep.venueDetailsConfirmation;
      case DemoStep.venueDetailsConfirmation: return DemoStep.gigListView;
      case DemoStep.gigListView:              return DemoStep.profileConnect;
      case DemoStep.profileConnect:           return DemoStep.emailCapture;
      case DemoStep.emailCapture:             return DemoStep.complete;
      case DemoStep.complete:
        _handleDemoCompletion();
        return DemoStep.complete;
    }
  }

  void skipToStep(DemoStep step) {
    if (!_isDemoModeActive) return;
    _currentStep = step;
    notifyListeners();
  }

  // ── Completion ────────────────────────────────────────────────────────────

  Future<void> _handleDemoCompletion() async {
    if (!_isDemoModeActive) return;
    log('🎬 DemoProvider: Onboarding completed.');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(hasSeenIntroKey, true);

    _isDemoModeActive = false;
    _currentStep = DemoStep.none;

    notifyListeners();
  }

  // ── Exit ──────────────────────────────────────────────────────────────────

  Future<void> endDemo() async {
    if (!_isDemoModeActive) return;
    log('🎬 DemoProvider: User exited onboarding at $_currentStep');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(hasSeenIntroKey, true);

    _isDemoModeActive = false;
    _currentStep = DemoStep.none;

    notifyListeners();
  }

  // ── Debug ─────────────────────────────────────────────────────────────────

  Future<void> resetDemoFlagForTesting() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(hasSeenIntroKey);
    await prefs.remove('pending_invite_code');
    await prefs.remove('pending_code_is_founder');
    await prefs.remove('map_tutorial_shown');
    await prefs.remove('is_connected_to_network');
    await prefs.remove('network_invite_code');
    await prefs.remove('my_invite_codes');
    await prefs.remove('map_tutorial_shown');
    _isReplay = false;
    log('🎬 DemoProvider: Reset all onboarding flags for testing');
  }
}