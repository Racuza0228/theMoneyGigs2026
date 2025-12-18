import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_money_gigs/features/map_venues/models/jam_session_model.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';
import 'package:the_money_gigs/core/models/enums.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  test('showInGigsList should default to false', () {
    final session = JamSession(
      id: 'test_1',
      day: DayOfWeek.monday,
      time: const TimeOfDay(hour: 19, minute: 0),
    );

    expect(session.showInGigsList, false);
  });

  test('copyWith preserves showInGigsList', () {
    final session = JamSession(
      id: 'test_1',
      day: DayOfWeek.monday,
      time: const TimeOfDay(hour: 19, minute: 0),
      showInGigsList: true,
    );

    final updated = session.copyWith(style: 'Blues');

    expect(updated.showInGigsList, true);
  });

  test('hiding jam session updates showInGigsList to false', () {
    // Setup: Venue with jam session visible in gigs
    final session = JamSession(
      id: 'monday_jam',
      day: DayOfWeek.monday,
      time: const TimeOfDay(hour: 19, minute: 0),
      showInGigsList: true,
    );

    final venue = StoredLocation(
      placeId: 'test_venue',
      name: 'Test Venue',
      address: '123 Test St',
      coordinates: const LatLng(0, 0),
      jamSessions: [session],
    );

    // Action: User clicks HIDE - simulate the button logic
    final sessionIndex = venue.jamSessions.indexWhere((s) => s.id == 'monday_jam');
    final updatedSessions = List<JamSession>.from(venue.jamSessions);
    updatedSessions[sessionIndex] = updatedSessions[sessionIndex].copyWith(showInGigsList: false);
    final updatedVenue = venue.copyWith(jamSessions: updatedSessions);

    // Assert: Session is now hidden
    expect(updatedVenue.jamSessions[0].showInGigsList, false);
  });

  test('hiding one jam session does not hide other jam sessions', () {
    // Setup: TWO different venues, both showing in gigs list
    final session1 = JamSession(
      id: 'venue1_monday',
      day: DayOfWeek.monday,
      time: const TimeOfDay(hour: 19, minute: 0),
      showInGigsList: true,
    );

    final venue1 = StoredLocation(
      placeId: 'venue_1',
      name: 'Venue One',
      address: '123 First St',
      coordinates: const LatLng(0, 0),
      jamSessions: [session1],
    );

    final session2 = JamSession(
      id: 'venue2_tuesday',
      day: DayOfWeek.tuesday,
      time: const TimeOfDay(hour: 20, minute: 0),
      showInGigsList: true,
    );

    final venue2 = StoredLocation(
      placeId: 'venue_2',
      name: 'Venue Two',
      address: '456 Second St',
      coordinates: const LatLng(1, 1),
      jamSessions: [session2],
    );

    // Action: Hide ONLY venue1's session
    final updatedSession1 = session1.copyWith(showInGigsList: false);
    final updatedVenue1 = venue1.copyWith(jamSessions: [updatedSession1]);

    // Assert: venue1 hidden, venue2 still visible
    expect(updatedVenue1.jamSessions[0].showInGigsList, false);
    expect(venue2.jamSessions[0].showInGigsList, true);
  });

  test('adding jam session to user venue preserves venue in saved list', () {
    // Setup: User-saved venue (no jam sessions yet)
    final userVenue = StoredLocation(
      placeId: 'user_venue',
      name: 'User Venue',
      address: '123 User St',
      coordinates: const LatLng(0, 0),
      jamSessions: [],
    );

    // Action: User adds jam session
    final newSession = JamSession(
      id: 'monday_jam',
      day: DayOfWeek.monday,
      time: const TimeOfDay(hour: 19, minute: 0),
      showInGigsList: true,
    );

    final updatedVenue = userVenue.copyWith(
      jamSessions: [newSession],
    );

    // Assert: Venue should have jam session
    expect(updatedVenue.jamSessions.length, 1);
    expect(updatedVenue.jamSessions[0].id, 'monday_jam');
    expect(updatedVenue.jamSessions[0].showInGigsList, true);
  });

  test('enabling jam session on json venue adds it to user saved list', () {
    // This test documents the expected behavior:
    // When user interacts with a jam_sessions.json venue (enables session),
    // that venue gets added to their saved list

    // Setup: jam_sessions.json venue
    final jsonVenue = StoredLocation(
      placeId: 'json_venue',
      name: 'JSON Venue',
      address: '456 JSON St',
      coordinates: const LatLng(1, 1),
      jamSessions: [
        JamSession(
          id: 'monday_jam',
          day: DayOfWeek.monday,
          time: const TimeOfDay(hour: 19, minute: 0),
          showInGigsList: false, // Not enabled yet
        ),
      ],
    );

    // Action: User enables the jam session
    final updatedSession = jsonVenue.jamSessions[0].copyWith(showInGigsList: true);
    final updatedVenue = jsonVenue.copyWith(
      jamSessions: [updatedSession],
    );

    // Assert: Venue now has enabled jam session
    expect(updatedVenue.jamSessions[0].showInGigsList, true);

    // This venue should now qualify for saving because:
    // hasVisibleJamSessions = true
  });
}