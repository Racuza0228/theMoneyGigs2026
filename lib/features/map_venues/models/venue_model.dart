// lib/features/map_venues/models/venue_model.dart
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:the_money_gigs/core/models/enums.dart'; // <<<--- IMPORT THE SHARED ENUMS
import 'package:the_money_gigs/features/map_venues/models/venue_contact.dart';
import 'package:the_money_gigs/features/map_venues/models/jam_session_model.dart';

class StoredLocation {
  final String placeId;
  final String name;
  final String address;
  final LatLng coordinates;
  double rating;
  String? comment;
  bool isArchived;
  final bool isMuted;
  final bool isPrivate;

  final List<JamSession> jamSessions;

  final VenueContact? contact;
  final String? venueNotes;
  final String? venueNotesUrl;

  final String? driveDuration;
  final String? driveDistance;

  StoredLocation({
    required this.placeId,
    required this.name,
    required this.address,
    required this.coordinates,
    this.rating = 0.0,
    this.comment,
    this.isArchived = false,
    this.jamSessions = const [],
    this.isMuted = false,
    this.isPrivate = false,
    this.contact,
    this.venueNotes,
    this.venueNotesUrl,
    this.driveDuration,
    this.driveDistance,
  });

  bool get hasJamOpenMic => jamSessions.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'placeId': placeId,
    'name': name,
    'address': address,
    'latitude': coordinates.latitude,
    'longitude': coordinates.longitude,
    'rating': rating,
    'comment': comment,
    'isArchived': isArchived,
    'jamSessions': jamSessions.map((js) => js.toJson()).toList(),
    'isMuted': isMuted,
    'isPrivate': isPrivate,
    'contact': contact?.toJson(),
    'venueNotes': venueNotes,
    'venueNotesUrl': venueNotesUrl,
    'driveDuration': driveDuration,
    'driveDistance': driveDistance,
  };

  /// A private helper function to handle backward compatibility for old jam session data.
  static List<JamSession> _migrateOldJamData(Map<String, dynamic> json) {
    if (json['hasJamOpenMic'] != true) {
      return [];
    }
    try {
      final timeMap = json['jamOpenMicTime'] as Map<String, dynamic>;
      return [
        JamSession(
          id: 'migrated_jam_1',
          style: json['jamStyle'] as String?,
          day: DayOfWeek.values.byName((json['jamOpenMicDay'] as String).split('.').last),
          time: TimeOfDay(hour: timeMap['hour'], minute: timeMap['minute']),
          frequency: JamFrequencyType.values.firstWhere(
                (e) => e.toString() == json['jamFrequencyType'],
            orElse: () => JamFrequencyType.weekly,
          ),
          nthValue: json['customNthValue'] as int?,
          showInGigsList: json['addJamToGigs'] as bool? ?? false,
        )
      ];
    } catch (_) {
      // Could not migrate, return an empty list to prevent crashes.
      return [];
    }
  }

  factory StoredLocation.fromJson(Map<String, dynamic> json) {
    List<JamSession> sessions = [];
    if (json['jamSessions'] != null && json['jamSessions'] is List) {
      // New, preferred format: Load directly from the list.
      sessions = (json['jamSessions'] as List)
          .map((js) => JamSession.fromJson(js))
          .toList();
    } else {
      // Old format detected, attempt to migrate the data.
      sessions = _migrateOldJamData(json);
    }

    return StoredLocation(
      placeId: json['placeId'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: json['name'] ?? 'Unnamed Venue',
      address: json['address'] ?? 'No address',
      coordinates: LatLng(
        (json['latitude'] as num?)?.toDouble() ?? 0.0,
        (json['longitude'] as num?)?.toDouble() ?? 0.0,
      ),
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      comment: json['comment'] as String?,
      isArchived: json['isArchived'] as bool? ?? false,
      jamSessions: sessions,
      isMuted: json['isMuted'] as bool? ?? false,
      isPrivate: json['isPrivate'] as bool? ?? false,
      contact: json['contact'] != null ? VenueContact.fromJson(json['contact']) : null,
      venueNotes: json['venueNotes'] as String?,
      venueNotesUrl: json['venueNotesUrl'] as String?,
      driveDuration: json['driveDuration'] as String?,
      driveDistance: json['driveDistance'] as String?,
    );
  }

  StoredLocation copyWith({
    String? placeId,
    String? name,
    String? address,
    LatLng? coordinates,
    double? rating,
    String? comment,
    bool? isArchived,
    List<JamSession>? jamSessions,
    bool? isMuted,
    bool? isPrivate,
    VenueContact? contact,
    ValueGetter<String?>? venueNotes,
    ValueGetter<String?>? venueNotesUrl,
    ValueGetter<String?>? driveDuration,
    ValueGetter<String?>? driveDistance,
  }) {
    return StoredLocation(
      placeId: placeId ?? this.placeId,
      name: name ?? this.name,
      address: address ?? this.address,
      coordinates: coordinates ?? this.coordinates,
      rating: rating ?? this.rating,
      comment: comment ?? this.comment,
      isArchived: isArchived ?? this.isArchived,
      jamSessions: jamSessions ?? this.jamSessions,
      isMuted: isMuted ?? this.isMuted,
      isPrivate: isPrivate ?? this.isPrivate,
      contact: contact ?? this.contact,
      venueNotes: venueNotes != null ? venueNotes() : this.venueNotes,
      venueNotesUrl: venueNotesUrl != null ? venueNotesUrl() : this.venueNotesUrl,
      driveDuration: driveDuration != null ? driveDuration() : this.driveDuration,
      driveDistance: driveDistance != null ? driveDistance() : this.driveDistance,
    );
  }

  // --- REVISED and CORRECTED ---
  // This method now correctly displays all jam sessions without any incorrect filtering.
  String jamOpenMicDisplayString(BuildContext context) {
    if (jamSessions.isEmpty) {
      return 'Not set up';
    }
    // Return a summary of all configured jam sessions.
    return jamSessions.map((session) {
      String dayString = toBeginningOfSentenceCase(session.day.toString().split('.').last) ?? '';
      String timeString = session.time.format(context);
      String styleString = (session.style != null && session.style!.isNotEmpty) ? ' (${session.style})' : '';
      return '$dayString at $timeString$styleString';
    }).join('\n'); // Separate each jam session with a new line
  }

  // --- REMOVED `recurringGigsDisplayString` as it was based on a false premise ---

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StoredLocation && other.placeId == placeId;
  }

  @override
  int get hashCode {
    return placeId.hashCode;
  }
}

