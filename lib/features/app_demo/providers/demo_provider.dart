// lib/features/app_demo/providers/demo_provider.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';

class DemoProvider with ChangeNotifier {
  bool _isDemoModeActive = false;
  int _currentStep = 0;

  static const String demoGigId = 'demo_gig_id_kroger';
  static const String demoVenuePlaceId = 'demo_venue_place_id_kroger';
  static const String hasSeenIntroKey = 'has_seen_intro_v1';

  bool get isDemoModeActive => _isDemoModeActive;
  int get currentStep => _currentStep;

  void startDemo() {
    if (!_isDemoModeActive) {
      _isDemoModeActive = true;
      _currentStep = 1;
      notifyListeners();
    }
  }

  void nextStep() {
    if (_isDemoModeActive) {
      _currentStep++;
      notifyListeners();
    }
  }

  Future<void> endDemo() async {
    if (_isDemoModeActive) {
      await _cleanUpDemoData(); // This is correct, we still need this.

      _isDemoModeActive = false;
      _currentStep = 0;
      notifyListeners();
    }
  }

  // <<< 2. IMPLEMENT THE MISSING METHOD >>>
  Future<void> resetDemoFlagForTesting() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(hasSeenIntroKey);
    // This method doesn't need to notify listeners, it just changes stored data.
  }

  Future<void> _cleanUpDemoData() async {
    final prefs = await SharedPreferences.getInstance();

    // Clean up the demo gig
    final String? gigsJsonString = prefs.getString('gigs_list');
    if (gigsJsonString != null) {
      List<Gig> allGigs = Gig.decode(gigsJsonString);
      allGigs.removeWhere((gig) => gig.id == demoGigId);
      await prefs.setString('gigs_list', Gig.encode(allGigs));
    }

    // Clean up the demo venue
    final List<String>? locationsJson = prefs.getStringList('saved_locations');
    if (locationsJson != null) {
      List<StoredLocation> allVenues = locationsJson
          .map((json) => StoredLocation.fromJson(jsonDecode(json)))
          .toList();
      allVenues.removeWhere((venue) => venue.placeId == demoVenuePlaceId);
      final List<String> updatedLocationsJson =
      allVenues.map((loc) => jsonEncode(loc.toJson())).toList();
      await prefs.setStringList('saved_locations', updatedLocationsJson);
    }
  }
}
