// lib/features/app_demo/providers/demo_provider.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/features/app_demo/services/demo_tracking_service.dart'; // 🎯 Import the service

enum DemoStep {
  none,                    // Not in demo
  coachingIntro,          // Full-screen coaching flow (instruments, genres, persona, rate)
  mapVenueSearch,         // "Where do you play or where would you like to play?"
  mapAddVenue,            // Guide them to add the venue
  mapBookGig,             // Guide them to book a gig from map
  bookingFormValue,       // "Consider all your time"
  bookingFormAction,      // "Fill in the details and book"
  venueDetailsConfirmation,
  gigListView,            // Show the gig appears in gigs list
  profileConnect,
  emailCapture,
  complete,               // Demo finished
}

class DemoProvider with ChangeNotifier {
  bool _isDemoModeActive = false;
  DemoStep _currentStep = DemoStep.none;

  static const String demoGigId = 'demo_gig_id_kroger';
  static const String demoVenuePlaceId = 'demo_venue_place_id_kroger';
  static const String hasSeenIntroKey = 'has_seen_intro_v1';

  bool get isDemoModeActive => _isDemoModeActive;
  DemoStep get currentStep => _currentStep;

  final DemoTrackingService _trackingService = DemoTrackingService(); // 🎯 Instantiate the service


  // Legacy support - convert step enum to number for existing code
  int get currentStepNumber {
    switch (_currentStep) {
      case DemoStep.none:
        print('🎬 DemoProvider: starting');
        return 0;
      case DemoStep.coachingIntro:
        print('🎬 DemoProvider: coaching intro');
        return 1;
      case DemoStep.mapVenueSearch:
        print('🎬 DemoProvider: mapVenueSearch');
        return 2;
      case DemoStep.mapAddVenue:
        print('🎬 DemoProvider: mapAddVenue');
        return 3;
      case DemoStep.mapBookGig:
        print('🎬 DemoProvider: mapBookGig');
        return 4;
      case DemoStep.bookingFormValue:
        print('🎬 DemoProvider: bookingFormValue');
        return 5;
      case DemoStep.bookingFormAction:
        print('🎬 DemoProvider: bookingFormAction');
        return 6;
      case DemoStep.venueDetailsConfirmation:
        print('🎬 DemoProvider: venueDetailsConfirmation');
        return 7;
      case DemoStep.gigListView:
        print('🎬 DemoProvider: gigListView');
        return 8;
      case DemoStep.profileConnect:
        print('🎬 DemoProvider: profileConnect');
        return 9;
      case DemoStep.emailCapture:  // 🆕 NEW
        print('🎬 DemoProvider: emailCapture');
        return 10;
      case DemoStep.complete:
        print('🎬 DemoProvider: complete');
        return 11;
    }
  }

  Future<void> startDemo({bool force = false}) async {
    if (!_isDemoModeActive) {
      final prefs = await SharedPreferences.getInstance();
      final hasSeenIntro = force ? false : (prefs.getBool(hasSeenIntroKey) ?? false);

      _isDemoModeActive = true;

      // If they haven't seen the intro coaching, start there
      // Otherwise skip to map demo
      if (!hasSeenIntro) {
        _currentStep = DemoStep.coachingIntro;
      } else {
        _currentStep = DemoStep.mapVenueSearch;
      }

      // 🎯 Start tracking the demo session
      await _trackingService.startDemoSession();

      print('🎬 DemoProvider: Starting demo at step $_currentStep');
      Future.microtask(() {
        notifyListeners();
      });
    }
  }

  void nextStep() {
    if (!_isDemoModeActive) return;

    print('🎬 DemoProvider: Advancing from step $_currentStep');

    // 🎯 REFACTORED LOGIC
    DemoStep nextStepValue;
    switch (_currentStep) {
      case DemoStep.none:
        nextStepValue = DemoStep.coachingIntro;
        break;
      case DemoStep.coachingIntro:
        nextStepValue = DemoStep.mapVenueSearch;
        break;
      case DemoStep.mapVenueSearch:
        nextStepValue = DemoStep.mapAddVenue;
        break;
      case DemoStep.mapAddVenue:
        nextStepValue = DemoStep.mapBookGig;
        break;
      case DemoStep.mapBookGig:
        nextStepValue = DemoStep.bookingFormValue;
        break;
      case DemoStep.bookingFormValue:
        nextStepValue = DemoStep.bookingFormAction;
        break;
      case DemoStep.bookingFormAction:
        nextStepValue = DemoStep.venueDetailsConfirmation;
        break;
      case DemoStep.venueDetailsConfirmation:
        nextStepValue = DemoStep.gigListView;
        break;
      case DemoStep.gigListView:
        nextStepValue = DemoStep.profileConnect;
        break;
      case DemoStep.profileConnect:
        nextStepValue = DemoStep.emailCapture;
        break;
      case DemoStep.emailCapture:
        nextStepValue = DemoStep.complete;
        break;
      case DemoStep.complete:
      // If we are already at complete, advancing does nothing more
      // than trigger the completion handler.
        _handleDemoCompletion();
        return; // Exit
    }

    _currentStep = nextStepValue;
    _trackingService.updateDemoStep(_currentStep); // Update Firestore with the new step

    // If the new step IS complete, trigger the final cleanup.
    if (_currentStep == DemoStep.complete) {
      _handleDemoCompletion();
    }

    print('🎬 DemoProvider: Now at step $_currentStep');
    notifyListeners();
  }

  void skipToStep(DemoStep step) {
    if (_isDemoModeActive) {
      print('🎬 DemoProvider: Skipping to step $step');
      _currentStep = step;
      _trackingService.updateDemoStep(_currentStep);
      notifyListeners();
    }
  }

  // 🎯 Handles NATURAL completion of the demo
  Future<void> _handleDemoCompletion() async {
    if (_isDemoModeActive) {
      print('🎬 DemoProvider: Demo completed naturally.');
      // The `updateDemoStep` call in `nextStep` already marked it complete in Firestore.
      // We just need to clean up the local state.
      await _trackingService.completeDemoSession(); // Clears local session ID

      _isDemoModeActive = false;
      _currentStep = DemoStep.none;

      print('🎬 DemoProvider: Demo session ended and cleaned up.');
      notifyListeners();
    }
  }


  // 🎯 Handles PREMATURE exit from the demo (user clicks "Exit")
  Future<void> endDemo() async {
    if (_isDemoModeActive) {
      print('🎬 DemoProvider: endDemo() called at step $_currentStep. User is exiting.');

      // 🎯 Log the exit at the CURRENT step
      await _trackingService.exitDemoSession(_currentStep);

      // Reset local state
      _isDemoModeActive = false;
      _currentStep = DemoStep.none;

      print('🎬 DemoProvider: Demo exited, notifying listeners');
      notifyListeners();
    }
  }

  Future<void> resetDemoFlagForTesting() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(hasSeenIntroKey);
    await prefs.remove('profile_instrument_tags');
    await prefs.remove('profile_genre_tags');
    await prefs.remove('user_persona');
    await prefs.remove('profile_min_hourly_rate');
    print('🎬 DemoProvider: Reset all demo flags for testing');
  }
}
