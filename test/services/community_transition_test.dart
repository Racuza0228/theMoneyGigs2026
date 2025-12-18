import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_money_gigs/features/map_venues/models/jam_session_model.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';
import 'package:the_money_gigs/core/models/enums.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// Copy the _mergeJamPreferences function here for testing
StoredLocation _mergeJamPreferences(
    StoredLocation publicVenue,
    StoredLocation localVenue,
    ) {
  if (localVenue.jamSessions.isEmpty) {
    return publicVenue;
  }

  final Map<String, bool> localPrefs = {
    for (var session in localVenue.jamSessions)
      session.id: session.showInGigsList,
  };

  final mergedSessions = publicVenue.jamSessions.map((pubSession) {
    final localPref = localPrefs[pubSession.id];
    if (localPref != null) {
      return pubSession.copyWith(showInGigsList: localPref);
    }
    return pubSession;
  }).toList();

  return publicVenue.copyWith(jamSessions: mergedSessions);
}

void main() {
  group('Standalone → Community Edition transition', () {
    test('preserves user showInGigsList preference when merging', () {
      // Standalone: User has Monday session showing in gigs
      final localSession = JamSession(
        id: 'monday_jam',
        day: DayOfWeek.monday,
        time: const TimeOfDay(hour: 19, minute: 0),
        showInGigsList: true, // User enabled this
      );

      final localVenue = StoredLocation(
        placeId: 'leo_coffeehouse',
        name: 'Leo Coffeehouse (Local)',
        address: '123 Local St',
        coordinates: const LatLng(0, 0),
        jamSessions: [localSession],
      );

      // Firestore: Same venue with Monday + NEW Wednesday session
      final firestoreMonday = JamSession(
        id: 'monday_jam',
        day: DayOfWeek.monday,
        time: const TimeOfDay(hour: 19, minute: 0),
        showInGigsList: false, // Default from migration
      );

      final firestoreWednesday = JamSession(
        id: 'wednesday_jam',
        day: DayOfWeek.wednesday,
        time: const TimeOfDay(hour: 20, minute: 0),
        showInGigsList: false,
      );

      final firestoreVenue = StoredLocation(
        placeId: 'leo_coffeehouse',
        name: 'Leo Coffeehouse',
        address: '123 Local St',
        coordinates: const LatLng(0, 0),
        isPublic: true,
        jamSessions: [firestoreMonday, firestoreWednesday],
      );

      // Merge
      final merged = _mergeJamPreferences(firestoreVenue, localVenue);

      // Assert: Monday kept user's preference, Wednesday uses default
      expect(merged.jamSessions.length, 2);

      final mondayResult = merged.jamSessions.firstWhere((s) => s.id == 'monday_jam');
      expect(mondayResult.showInGigsList, true,
          reason: 'User preference for Monday should be preserved');

      final wednesdayResult = merged.jamSessions.firstWhere((s) => s.id == 'wednesday_jam');
      expect(wednesdayResult.showInGigsList, false,
          reason: 'New Wednesday session should use default (false)');
    });

    test('handles user adding custom session to public venue', () {
      // User added custom Thursday session locally
      final localThursday = JamSession(
        id: 'custom_thursday',
        day: DayOfWeek.thursday,
        time: const TimeOfDay(hour: 18, minute: 0),
        showInGigsList: true,
      );

      final localVenue = StoredLocation(
        placeId: 'leo_coffeehouse',
        name: 'Leo Coffeehouse',
        address: '123 Local St',
        coordinates: const LatLng(0, 0),
        jamSessions: [localThursday],
      );

      // Firestore only has Monday
      final firestoreMonday = JamSession(
        id: 'monday_jam',
        day: DayOfWeek.monday,
        time: const TimeOfDay(hour: 19, minute: 0),
      );

      final firestoreVenue = StoredLocation(
        placeId: 'leo_coffeehouse',
        name: 'Leo Coffeehouse',
        address: '123 Local St',
        coordinates: const LatLng(0, 0),
        isPublic: true,
        jamSessions: [firestoreMonday],
      );

      // Merge
      final merged = _mergeJamPreferences(firestoreVenue, localVenue);

      // Assert: User's custom Thursday session is LOST (expected behavior)
      // Because we use Firestore as source of truth
      expect(merged.jamSessions.length, 1);
      expect(merged.jamSessions[0].id, 'monday_jam');

      // NOTE: This might be a decision point - do we want to preserve custom sessions?
    });
  });
}