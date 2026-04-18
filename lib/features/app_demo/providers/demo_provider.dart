// lib/features/app_demo/providers/demo_provider.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/features/app_demo/services/demo_tracking_service.dart';

enum DemoStep {
  none,

  // ── NEW simple onboarding (3 screens in OnboardingFlow widget) ───────────
  onboardingWelcome,

  // ── Legacy steps kept in enum so overlay files still compile ────────────
  // These are no longer triggered by the default flow but can be
  // re-enabled individually for future feature tours.
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

  static const String demoGigId = 'demo_gig_id_kroger';
  static const String demoVenuePlaceId = 'demo_venue_place_id_kroger';
  static const String hasSeenIntroKey = 'has_seen_intro_v1';

  bool get isDemoModeActive => _isDemoModeActive;
  DemoStep get currentStep => _currentStep;

  final DemoTrackingService _trackingService = DemoTrackingService();

  // ── Start ─────────────────────────────────────────────────────────────────

  Future<void> startDemo({bool force = false}) async {
    if (_isDemoModeActive) return;

    _isDemoModeActive = true;
    _currentStep = DemoStep.onboardingWelcome; // Always start at the new simple onboarding

    await _trackingService.startDemoSession();
    print('🎬 DemoProvider: Starting onboarding');

    Future.microtask(notifyListeners);
  }

  // ── Advance ───────────────────────────────────────────────────────────────

  void nextStep() {
    if (!_isDemoModeActive) return;

    // The OnboardingFlow widget handles its own internal 3-screen paging.
    // When it calls nextStep() it means the entire onboarding is done.
    if (_currentStep == DemoStep.onboardingWelcome) {
      _currentStep = DemoStep.complete;
      _trackingService.updateDemoStep(_currentStep);
      _handleDemoCompletion();
      return;
    }

    // Legacy step advancement (kept for any future guided tours)
    final DemoStep next = _legacyNext(_currentStep);
    _currentStep = next;
    _trackingService.updateDemoStep(_currentStep);

    if (_currentStep == DemoStep.complete) {
      _handleDemoCompletion();
    }

    print('🎬 DemoProvider: Step → $_currentStep');
    notifyListeners();
  }

  DemoStep _legacyNext(DemoStep step) {
    switch (step) {
      case DemoStep.none:              return DemoStep.onboardingWelcome;
      case DemoStep.onboardingWelcome: return DemoStep.complete;
      case DemoStep.coachingIntro:     return DemoStep.mapVenueSearch;
      case DemoStep.mapVenueSearch:    return DemoStep.mapAddVenue;
      case DemoStep.mapAddVenue:       return DemoStep.mapBookGig;
      case DemoStep.mapBookGig:        return DemoStep.bookingFormValue;
      case DemoStep.bookingFormValue:  return DemoStep.bookingFormAction;
      case DemoStep.bookingFormAction: return DemoStep.venueDetailsConfirmation;
      case DemoStep.venueDetailsConfirmation: return DemoStep.gigListView;
      case DemoStep.gigListView:       return DemoStep.profileConnect;
      case DemoStep.profileConnect:    return DemoStep.emailCapture;
      case DemoStep.emailCapture:      return DemoStep.complete;
      case DemoStep.complete:
        _handleDemoCompletion();
        return DemoStep.complete;
    }
  }

  void skipToStep(DemoStep step) {
    if (!_isDemoModeActive) return;
    _currentStep = step;
    _trackingService.updateDemoStep(_currentStep);
    notifyListeners();
  }

  // ── Completion ────────────────────────────────────────────────────────────

  Future<void> _handleDemoCompletion() async {
    if (!_isDemoModeActive) return;
    print('🎬 DemoProvider: Onboarding completed.');

    // Mark intro as seen so we never show it again
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(hasSeenIntroKey, true);

    await _trackingService.completeDemoSession();

    _isDemoModeActive = false;
    _currentStep = DemoStep.none;

    notifyListeners();
  }

  // ── Exit ──────────────────────────────────────────────────────────────────

  Future<void> endDemo() async {
    if (!_isDemoModeActive) return;
    print('🎬 DemoProvider: User exited onboarding at $_currentStep');

    // Mark intro as seen even if they skipped — don't show again
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(hasSeenIntroKey, true);

    await _trackingService.exitDemoSession(_currentStep);

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
    await prefs.remove('email_captured');
    await prefs.remove('captured_email');
    print('🎬 DemoProvider: Reset all onboarding flags for testing');
  }
}