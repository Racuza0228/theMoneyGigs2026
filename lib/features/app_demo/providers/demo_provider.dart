// lib/features/app_demo/providers/demo_provider.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

      print('🎬 DemoProvider: Starting demo at step $_currentStep');
      Future.microtask(() {
        notifyListeners();
      });
    }
  }

  void nextStep() {
    if (_isDemoModeActive) {
      print('🎬 DemoProvider: Advancing from step $_currentStep');

      // 🎯 THIS IS THE CORRECTED SWITCH STATEMENT
      switch (_currentStep) {
        case DemoStep.none:
          _currentStep = DemoStep.coachingIntro;
          break;
        case DemoStep.coachingIntro:
          _currentStep = DemoStep.mapVenueSearch;
          break;
        case DemoStep.mapVenueSearch:
          _currentStep = DemoStep.mapAddVenue;
          break;
        case DemoStep.mapAddVenue:
          _currentStep = DemoStep.mapBookGig;
          break;
        case DemoStep.mapBookGig:
          _currentStep = DemoStep.bookingFormValue; // -> To the new booking step
          break;
        case DemoStep.bookingFormValue:
          _currentStep = DemoStep.bookingFormAction; // -> To the second booking step
          break;
        case DemoStep.bookingFormAction:
          _currentStep = DemoStep.venueDetailsConfirmation; // -> To the gigs list after booking
          break;
        case DemoStep.venueDetailsConfirmation:
          _currentStep = DemoStep.gigListView; // -> To the gigs list after booking
          break;
        case DemoStep.gigListView: // <<< AFTER THE GIG LIST VIEW...
          _currentStep = DemoStep.profileConnect; // <<< ...GO TO THE NEW PROFILE STEP
          break;
        case DemoStep.profileConnect: // <<< THE NEW STEP...
          _currentStep = DemoStep.emailCapture; // <<< ...LEADS TO COMPLETION
          break;
        case DemoStep.emailCapture:  // 🆕 NEW
          _currentStep = DemoStep.complete;
          break;
        case DemoStep.complete:
          endDemo();
          return;
      }

      print('🎬 DemoProvider: Now at step $_currentStep');
      notifyListeners();
    }
  }

  void skipToStep(DemoStep step) {
    if (_isDemoModeActive) {
      print('🎬 DemoProvider: Skipping to step $step');
      _currentStep = step;
      notifyListeners();
    }
  }

  Future<void> endDemo() async {
    if (_isDemoModeActive) {
      print('🎬 DemoProvider: endDemo() called at step $_currentStep');
      _isDemoModeActive = false;
      _currentStep = DemoStep.none;
      print('🎬 DemoProvider: Demo ended, notifying listeners');
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
