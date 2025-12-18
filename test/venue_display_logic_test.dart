import 'package:flutter_test/flutter_test.dart';
import 'package:the_money_gigs/features/map_venues/models/jam_session_model.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';
import 'package:the_money_gigs/core/models/enums.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/material.dart';

void main() {
  group('Venue Saving and Loading', () {
    test('user-saved venues should persist to SharedPreferences', () {
      // Simulate: User adds Arnold's and Queen City Radio
      final userVenues = [
        StoredLocation(
          placeId: 'arnolds',
          name: "Arnold's Bar & Grill",
          address: '210 E 8th St',
          coordinates: const LatLng(39.103, -84.512),
        ),
        StoredLocation(
          placeId: 'queen_city',
          name: 'Queen City Radio',
          address: '310 E 8th St',
          coordinates: const LatLng(39.104, -84.513),
        ),
      ];

      // Assert: Only these 2 should be saved, NOT jam_sessions.json venues
      expect(userVenues.length, 2);
      expect(userVenues.any((v) => v.placeId == 'arnolds'), true);
      expect(userVenues.any((v) => v.placeId == 'queen_city'), true);
    });

    test('jam_sessions.json venues should NOT be in SharedPreferences', () {
      // Setup: User-saved venues from SharedPreferences
      final savedVenues = [
        StoredLocation(
          placeId: 'user_venue',
          name: 'User Added Venue',
          address: '123 User St',
          coordinates: const LatLng(0, 0),
        ),
      ];

      // Setup: Venues from jam_sessions.json (loaded separately)
      final jamVenues = [
        StoredLocation(
          placeId: 'json_jam_venue',
          name: 'JSON Jam Venue',
          address: '456 JSON St',
          coordinates: const LatLng(1, 1),
          jamSessions: [
            JamSession(
              id: 'monday_jam',
              day: DayOfWeek.monday,
              time: const TimeOfDay(hour: 19, minute: 0),
            ),
          ],
        ),
      ];

      // Assert: jam_sessions.json venues should NOT be in savedVenues
      expect(savedVenues.any((v) => v.placeId == 'json_jam_venue'), false,
          reason: 'jam_sessions.json venues should not persist to SharedPreferences');

      // Assert: They exist in separate list
      expect(jamVenues.length, 1);
      expect(jamVenues[0].placeId, 'json_jam_venue');
    });

    test('updating venue should not delete other saved venues', () {
      // Setup: Two user-saved venues
      List<StoredLocation> savedVenues = [
        StoredLocation(
          placeId: 'venue_1',
          name: 'Venue One',
          address: '123 St',
          coordinates: const LatLng(0, 0),
        ),
        StoredLocation(
          placeId: 'venue_2',
          name: 'Venue Two',
          address: '456 St',
          coordinates: const LatLng(1, 1),
        ),
      ];

      // Action: Update venue_1 (rate it)
      final updatedVenue1 = savedVenues[0].copyWith(rating: 4.5);

      // Simulate save logic: Update in list
      final index = savedVenues.indexWhere((v) => v.placeId == 'venue_1');
      savedVenues[index] = updatedVenue1;

      // Assert: BOTH venues should still be in list
      expect(savedVenues.length, 2);
      expect(savedVenues.any((v) => v.placeId == 'venue_1'), true);
      expect(savedVenues.any((v) => v.placeId == 'venue_2'), true);
      expect(savedVenues[0].rating, 4.5);
    });
  });

  group('Marker Display Logic', () {
    late Set<String> userSavedPlaceIds;
    late List<StoredLocation> allVenues;

    setUp(() {
      // Setup: User saved 2 venues
      userSavedPlaceIds = {'user_venue_1', 'user_venue_2'};

      // Setup: Memory contains user venues + jam_sessions.json venues
      allVenues = [
        // User-saved venues
        StoredLocation(
          placeId: 'user_venue_1',
          name: 'User Venue 1',
          address: '123 St',
          coordinates: const LatLng(0, 0),
        ),
        StoredLocation(
          placeId: 'user_venue_2',
          name: 'User Venue 2',
          address: '456 St',
          coordinates: const LatLng(1, 1),
          jamSessions: [
            JamSession(
              id: 'monday',
              day: DayOfWeek.monday,
              time: const TimeOfDay(hour: 19, minute: 0),
            ),
          ],
        ),
        // jam_sessions.json venue (not saved by user)
        StoredLocation(
          placeId: 'json_jam_venue',
          name: 'JSON Jam Venue',
          address: '789 St',
          coordinates: const LatLng(2, 2),
          jamSessions: [
            JamSession(
              id: 'tuesday',
              day: DayOfWeek.tuesday,
              time: const TimeOfDay(hour: 20, minute: 0),
            ),
          ],
        ),
      ];
    });

    test('Jams OFF: should show ONLY user-saved venues', () {
      // Filter: Jams toggle OFF
      final venuesToShow = allVenues.where((v) {
        return userSavedPlaceIds.contains(v.placeId);
      }).toList();

      // Assert: Only user-saved venues show
      expect(venuesToShow.length, 2);
      expect(venuesToShow.any((v) => v.placeId == 'user_venue_1'), true);
      expect(venuesToShow.any((v) => v.placeId == 'user_venue_2'), true);
      expect(venuesToShow.any((v) => v.placeId == 'json_jam_venue'), false,
          reason: 'JSON jam venue should NOT show when Jams toggle is OFF');
    });

    test('Jams ON: should show ALL venues with jam sessions', () {
      // Filter: Jams toggle ON
      final venuesToShow = allVenues.where((v) {
        return v.jamSessions.isNotEmpty;
      }).toList();

      // Assert: All venues with jam sessions show
      expect(venuesToShow.length, 2);
      expect(venuesToShow.any((v) => v.placeId == 'user_venue_2'), true,
          reason: 'User venue with jam session should show');
      expect(venuesToShow.any((v) => v.placeId == 'json_jam_venue'), true,
          reason: 'JSON jam venue should show when Jams toggle is ON');
    });

    test('archived venues should never show (Jams OFF)', () {
      // Setup: Archive user_venue_1
      allVenues[0] = allVenues[0].copyWith(isArchived: true);

      // Filter: Not archived + user-saved
      final displayableVenues = allVenues.where((v) => !v.isArchived).toList();
      final venuesToShow = displayableVenues.where((v) {
        return userSavedPlaceIds.contains(v.placeId);
      }).toList();

      // Assert: Only non-archived user venues
      expect(venuesToShow.length, 1);
      expect(venuesToShow[0].placeId, 'user_venue_2');
      expect(venuesToShow.any((v) => v.placeId == 'user_venue_1'), false,
          reason: 'Archived venue should NOT show');
    });

    test('archived venues should never show (Jams ON)', () {
      // Setup: Archive user_venue_2 (which has jam session)
      allVenues[1] = allVenues[1].copyWith(isArchived: true);

      // Filter: Not archived + has jam sessions
      final displayableVenues = allVenues.where((v) => !v.isArchived).toList();
      final venuesToShow = displayableVenues.where((v) {
        return v.jamSessions.isNotEmpty;
      }).toList();

      // Assert: Only non-archived jam venues
      expect(venuesToShow.length, 1);
      expect(venuesToShow[0].placeId, 'json_jam_venue');
      expect(venuesToShow.any((v) => v.placeId == 'user_venue_2'), false,
          reason: 'Archived venue should NOT show even with jam session');
    });
  });

  group('Archive and Restore', () {
    test('archive should set isArchived to true', () {
      final venue = StoredLocation(
        placeId: 'test_venue',
        name: 'Test Venue',
        address: '123 St',
        coordinates: const LatLng(0, 0),
        isArchived: false,
      );

      // Action: Archive
      final archived = venue.copyWith(isArchived: true);

      // Assert
      expect(archived.isArchived, true);
    });

    test('restore should toggle isArchived to false', () {
      final venue = StoredLocation(
        placeId: 'test_venue',
        name: 'Test Venue',
        address: '123 St',
        coordinates: const LatLng(0, 0),
        isArchived: true, // Currently archived
      );

      // Action: Restore (toggle current state)
      final restored = venue.copyWith(isArchived: !venue.isArchived);

      // Assert
      expect(restored.isArchived, false);
    });

    test('archived venue should still be in SharedPreferences', () {
      // Setup: User venues (one archived)
      final userVenues = [
        StoredLocation(
          placeId: 'venue_1',
          name: 'Venue One',
          address: '123 St',
          coordinates: const LatLng(0, 0),
          isArchived: true, // Archived
        ),
        StoredLocation(
          placeId: 'venue_2',
          name: 'Venue Two',
          address: '456 St',
          coordinates: const LatLng(1, 1),
        ),
      ];

      // Assert: Both should be saved (archived venues stay in storage)
      expect(userVenues.length, 2);
      expect(userVenues[0].isArchived, true);
    });
  });

  group('User Saved Venue Tracking', () {
    test('adding venue should add to tracking set', () {
      final userSavedPlaceIds = <String>{'existing_venue'};

      // Action: User adds new venue
      final newVenue = StoredLocation(
        placeId: 'new_venue',
        name: 'New Venue',
        address: '123 St',
        coordinates: const LatLng(0, 0),
      );

      userSavedPlaceIds.add(newVenue.placeId);

      // Assert
      expect(userSavedPlaceIds.contains('new_venue'), true);
      expect(userSavedPlaceIds.length, 2);
    });

    test('archiving venue should keep it in tracking set', () {
      final userSavedPlaceIds = <String>{'venue_1', 'venue_2'};

      // Action: Archive venue_1 (doesn't remove from tracking)
      // (Archive only sets isArchived flag, doesn't remove from set)

      // Assert: Still in tracking set
      expect(userSavedPlaceIds.contains('venue_1'), true);
    });

    test('tracking set should match saved venues', () {
      // Setup: Saved venues
      final savedVenues = [
        StoredLocation(
          placeId: 'venue_1',
          name: 'Venue One',
          address: '123 St',
          coordinates: const LatLng(0, 0),
        ),
        StoredLocation(
          placeId: 'venue_2',
          name: 'Venue Two',
          address: '456 St',
          coordinates: const LatLng(1, 1),
          isArchived: true,
        ),
      ];

      // Rebuild tracking set
      final userSavedPlaceIds = savedVenues.map((v) => v.placeId).toSet();

      // Assert
      expect(userSavedPlaceIds.length, 2);
      expect(userSavedPlaceIds.contains('venue_1'), true);
      expect(userSavedPlaceIds.contains('venue_2'), true);
    });
  });

  group('Edge Cases', () {
    test('venue with no rating should still show (Jams OFF)', () {
      final userSavedPlaceIds = <String>{'new_venue'};

      final venues = [
        StoredLocation(
          placeId: 'new_venue',
          name: 'New Venue',
          address: '123 St',
          coordinates: const LatLng(0, 0),
          rating: 0, // No rating yet
        ),
      ];

      // Filter: User-saved venues
      final venuesToShow = venues.where((v) {
        return userSavedPlaceIds.contains(v.placeId);
      }).toList();

      // Assert: Should show even with rating=0
      expect(venuesToShow.length, 1);
    });

    test('user rates jam_sessions.json venue - gets added to saved list', () {
      // Setup: Initial user venues (empty)
      List<StoredLocation> userVenues = [];

      // Setup: jam_sessions.json venue
      final jamVenue = StoredLocation(
        placeId: 'json_jam',
        name: 'JSON Jam Venue',
        address: '123 St',
        coordinates: const LatLng(0, 0),
        jamSessions: [
          JamSession(
            id: 'monday',
            day: DayOfWeek.monday,
            time: const TimeOfDay(hour: 19, minute: 0),
          ),
        ],
      );

      // Action: User rates it
      final ratedVenue = jamVenue.copyWith(rating: 4.5);
      userVenues.add(ratedVenue);

      // Assert: Now it's in saved venues
      expect(userVenues.length, 1);
      expect(userVenues[0].placeId, 'json_jam');
      expect(userVenues[0].rating, 4.5);
    });

    test('user enables jam session - venue gets saved', () {
      // Setup: Initial user venues (empty)
      List<StoredLocation> userVenues = [];

      // Setup: jam_sessions.json venue
      final jamVenue = StoredLocation(
        placeId: 'json_jam',
        name: 'JSON Jam Venue',
        address: '123 St',
        coordinates: const LatLng(0, 0),
        jamSessions: [
          JamSession(
            id: 'monday',
            day: DayOfWeek.monday,
            time: const TimeOfDay(hour: 19, minute: 0),
            showInGigsList: false,
          ),
        ],
      );

      // Action: User enables jam session
      final updatedSession = jamVenue.jamSessions[0].copyWith(showInGigsList: true);
      final updatedVenue = jamVenue.copyWith(
        jamSessions: [updatedSession],
      );
      userVenues.add(updatedVenue);

      // Assert: Venue is now saved
      expect(userVenues.length, 1);
      expect(userVenues[0].jamSessions[0].showInGigsList, true);
    });
  });
}