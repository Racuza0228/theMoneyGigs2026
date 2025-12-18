// lib/migrations/jam_session_migration.dart
// ONE-TIME MIGRATION: Run once, then comment out or delete

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:the_money_gigs/core/models/enums.dart';
import 'package:the_money_gigs/features/map_venues/models/jam_session_model.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';

class JamSessionMigration {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Migrates jam sessions from assets/jam_sessions.json to Firestore
  Future<void> migrateJamSessions() async {
    try {
      print('🔄 Starting jam session migration...');

      // 1. Load JSON file
      final String jsonString = await rootBundle.loadString('assets/jam_sessions.json');
      final List<dynamic> jsonData = json.decode(jsonString);
      print('   Loaded ${jsonData.length} venues from JSON');

      int successCount = 0;
      int errorCount = 0;
      int skippedCount = 0;

      // 2. Process each venue
      for (var venueJson in jsonData) {
        try {
          final placeId = venueJson['placeId'] as String;

          // Check if venue already exists
          final venueRef = _firestore.collection('venues').doc(placeId);
          final doc = await venueRef.get();

          if (doc.exists) {
            skippedCount++;
            print('   ⏭️  Skipped (exists): ${venueJson['name']}');
            continue;
          }

          final venue = _parseVenueFromJson(venueJson);
          await _saveVenueToFirestore(venue);
          successCount++;
          print('   ✅ Saved: ${venue.name}');
        } catch (e) {
          errorCount++;
          print('   ❌ Error with ${venueJson['name']}: $e');
        }
      }

      print('✅ Migration complete!');
      print('   Successful: $successCount');
      print('   Skipped: $skippedCount');
      print('   Errors: $errorCount');

    } catch (e) {
      print('❌ Migration failed: $e');
    }
  }

  /// Parse venue from JSON with enum conversion
  StoredLocation _parseVenueFromJson(Map<String, dynamic> json) {
    // Parse jam sessions
    final List<JamSession> jamSessions = (json['jamSessions'] as List?)
        ?.map((js) => _parseJamSession(js))
        .toList() ?? [];

    return StoredLocation(
      placeId: json['placeId'] as String,
      isPublic: true, // These are community venues
      name: json['name'] as String,
      address: json['address'] as String,
      coordinates: LatLng(
        (json['latitude'] as num).toDouble(),
        (json['longitude'] as num).toDouble(),
      ),
      comment: json['comment'] as String?,
      jamSessions: jamSessions,
      averageRating: 0.0,
      totalRatings: 0,
    );
  }

  /// Parse jam session with enum string conversion
  JamSession _parseJamSession(Map<String, dynamic> json) {
    // Parse enum strings like "DayOfWeek.monday" -> DayOfWeek.monday
    final dayString = (json['day'] as String).split('.').last;
    final day = DayOfWeek.values.firstWhere(
          (e) => e.name == dayString,
      orElse: () => DayOfWeek.monday,
    );

    final freqString = (json['frequency'] as String).split('.').last;
    final frequency = JamFrequencyType.values.firstWhere(
          (e) => e.name == freqString,
      orElse: () => JamFrequencyType.weekly,
    );

    final timeMap = json['time'] as Map<String, dynamic>;

    return JamSession(
      id: json['id'] as String,
      style: (json['style'] as String?)?.isEmpty ?? true ? null : json['style'] as String?,
      day: day,
      time: TimeOfDay(
        hour: timeMap['hour'] as int,
        minute: timeMap['minute'] as int,
      ),
      frequency: frequency,
      nthValue: json['nthValue'] as int?,
      showInGigsList: json['showInGigsList'] as bool? ?? false,
    );
  }

  /// Save venue to Firestore with jam sessions
  Future<void> _saveVenueToFirestore(StoredLocation venue) async {
    final venueRef = _firestore.collection('venues').doc(venue.placeId);

    // Prepare venue data
    final Map<String, dynamic> venueData = {
      'name': venue.name,
      'address': venue.address,
      'coordinates': GeoPoint(
        venue.coordinates.latitude,
        venue.coordinates.longitude,
      ),
      'placeId': venue.placeId,
      'averageRating': 0.0,
      'totalRatings': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdBy': 'migration_script', // Mark as migrated
      'jamSessions': venue.jamSessions.map((js) => js.toJson()).toList(),
    };

    // Add comment if present (as metadata, not user rating)
    if (venue.comment != null && venue.comment!.isNotEmpty) {
      venueData['migrationComment'] = venue.comment;
    }

    await venueRef.set(venueData);
  }
}