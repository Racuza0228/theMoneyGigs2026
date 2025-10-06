// lib/venue_model.dart
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:the_money_gigs/venue_contact.dart';

// ... (Enums remain the same)
enum DayOfWeek { monday, tuesday, wednesday, thursday, friday, saturday, sunday }
enum JamFrequencyType { weekly, biWeekly, monthlySameDay, monthlySameDate, customNthDay }

class StoredLocation {
  final String placeId;
  final String name;
  final String address;
  final LatLng coordinates;
  double rating;
  String? comment;
  bool isArchived;

  // Jam/Open Mic properties
  final bool hasJamOpenMic;
  final DayOfWeek? jamOpenMicDay;
  final TimeOfDay? jamOpenMicTime;
  final bool addJamToGigs;
  final JamFrequencyType jamFrequencyType;
  final int? customNthValue;
  final String? jamStyle; // <<< NEW: Style of the jam (e.g., Bluegrass, Jazz)
  final bool isMuted;

  final VenueContact? contact;
  final String? venueNotes;
  final String? venueNotesUrl;

  StoredLocation({
    required this.placeId,
    required this.name,
    required this.address,
    required this.coordinates,
    this.rating = 0.0,
    this.comment,
    this.isArchived = false,
    this.hasJamOpenMic = false,
    this.jamOpenMicDay,
    this.jamOpenMicTime,
    this.addJamToGigs = false,
    this.jamFrequencyType = JamFrequencyType.weekly,
    this.customNthValue,
    this.jamStyle, // <<< NEW
    this.isMuted = false,
    this.contact,
    this.venueNotes,
    this.venueNotesUrl,
  });

  Map<String, dynamic> toJson() => {
    'placeId': placeId,
    'name': name,
    'address': address,
    'latitude': coordinates.latitude,
    'longitude': coordinates.longitude,
    'rating': rating,
    'comment': comment,
    'isArchived': isArchived,
    'hasJamOpenMic': hasJamOpenMic,
    'jamOpenMicDay': jamOpenMicDay?.toString(),
    'jamOpenMicTime': jamOpenMicTime != null
        ? {'hour': jamOpenMicTime!.hour, 'minute': jamOpenMicTime!.minute}
        : null,
    'addJamToGigs': addJamToGigs,
    'jamFrequencyType': jamFrequencyType.toString(),
    'customNthValue': customNthValue,
    'jamStyle': jamStyle, // <<< NEW
    'isMuted': isMuted,
    'contact': contact?.toJson(),
    'venueNotes': venueNotes,
    'venueNotesUrl': venueNotesUrl,
  };

  factory StoredLocation.fromJson(Map<String, dynamic> json) {
    // ... (parsing logic for time, day, etc. is unchanged)
    TimeOfDay? parsedTime;
    if (json['jamHour'] != null && json['jamMinute'] != null) {
      // This handles the flat JSON structure from your CSV
      parsedTime = TimeOfDay(hour: json['jamHour'] as int, minute: json['jamMinute'] as int);

    } else if (json['jamOpenMicTime'] != null && json['jamOpenMicTime'] is Map) {
      // This part is kept for backward compatibility with the old nested format
      final timeMap = json['jamOpenMicTime'] as Map<String, dynamic>;
      if (timeMap['hour'] != null && timeMap['minute'] != null) {
        parsedTime = TimeOfDay(hour: timeMap['hour'] as int, minute: timeMap['minute'] as int);
      }
    }
    DayOfWeek? parsedDay;
    if (json['jamOpenMicDay'] != null && json['jamOpenMicDay'] is String) {
      try {
        parsedDay = DayOfWeek.values.byName((json['jamOpenMicDay'] as String).split('.').last);
      } catch (e) { parsedDay = null; }
    }
    JamFrequencyType parsedFrequency = JamFrequencyType.values.firstWhere(
            (e) => e.toString() == json['jamFrequencyType'],
        orElse: () => JamFrequencyType.weekly);

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
      hasJamOpenMic: json['hasJamOpenMic'] as bool? ?? false,
      jamOpenMicDay: parsedDay,
      jamOpenMicTime: parsedTime,
      addJamToGigs: json['addJamToGigs'] as bool? ?? false,
      jamFrequencyType: parsedFrequency,
      customNthValue: json['customNthValue'] as int?,
      jamStyle: json['jamStyle'] as String?, // <<< NEW
      isMuted: json['isMuted'] as bool? ?? false,
      contact: json['contact'] != null ? VenueContact.fromJson(json['contact']) : null,
      venueNotes: json['venueNotes'] as String?,
      venueNotesUrl: json['venueNotesUrl'] as String?,
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
    bool? hasJamOpenMic,
    DayOfWeek? jamOpenMicDay,
    TimeOfDay? jamOpenMicTime,
    bool? addJamToGigs,
    JamFrequencyType? jamFrequencyType,
    int? customNthValue,
    ValueGetter<String?>? jamStyle, // Use ValueGetter to allow setting to null
    bool? isMuted,
    VenueContact? contact,
    String? venueNotes,
    String? venueNotesUrl,
  }) {
    return StoredLocation(
      placeId: placeId ?? this.placeId,
      name: name ?? this.name,
      address: address ?? this.address,
      coordinates: coordinates ?? this.coordinates,
      rating: rating ?? this.rating,
      comment: comment ?? this.comment,
      isArchived: isArchived ?? this.isArchived,
      hasJamOpenMic: hasJamOpenMic ?? this.hasJamOpenMic,
      jamOpenMicDay: jamOpenMicDay ?? this.jamOpenMicDay,
      jamOpenMicTime: jamOpenMicTime ?? this.jamOpenMicTime,
      addJamToGigs: addJamToGigs ?? this.addJamToGigs,
      jamFrequencyType: jamFrequencyType ?? this.jamFrequencyType,
      customNthValue: customNthValue ?? this.customNthValue,
      jamStyle: jamStyle != null ? jamStyle() : this.jamStyle, // <<< MODIFIED
      isMuted: isMuted ?? this.isMuted,
      contact: contact ?? this.contact,
      venueNotes: venueNotes ?? this.venueNotes,
      venueNotesUrl: venueNotesUrl ?? this.venueNotesUrl,
    );
  }

  // NOTE: You can also choose to update the copyWith to be simpler if you don't need nullable value differentiation.
  // For example: `String? jamStyle,` and then in the constructor `jamStyle: jamStyle ?? this.jamStyle,`.
  // The ValueGetter is a robust way to handle explicitly setting a value to null.

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is StoredLocation &&
              runtimeType == other.runtimeType &&
              placeId == other.placeId &&
              jamStyle == other.jamStyle && // <<< NEW
              // ... other properties
              isMuted == other.isMuted;

  @override
  int get hashCode =>
      placeId.hashCode ^
      name.hashCode ^
      // ... other properties
      jamStyle.hashCode ^ // <<< NEW
      isMuted.hashCode ^
      contact.hashCode;

  String jamOpenMicDisplayString(BuildContext context) {
    if (!hasJamOpenMic || jamOpenMicDay == null || jamOpenMicTime == null) {
      return 'Not set up';
    }
    String dayString = toBeginningOfSentenceCase(jamOpenMicDay.toString().split('.').last) ?? '';
    String timeString = jamOpenMicTime!.format(context);
    // <<< NEW: Add style to the display string if it exists >>>
    String styleString = (jamStyle != null && jamStyle!.isNotEmpty) ? ' ($jamStyle)' : '';
    return '$dayString at $timeString$styleString';
  }
// ... rest of the file is unchanged
}
