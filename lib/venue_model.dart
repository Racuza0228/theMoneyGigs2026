// lib/venue_model.dart
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:the_money_gigs/venue_contact.dart';

// ... (Enums DayOfWeek and JamFrequencyType remain unchanged)
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

  // <<< NEW: Flag to hide jam sessions from the gigs list >>>
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
    this.isMuted = false, // <<< NEW
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
    'isMuted': isMuted, // <<< NEW
    'contact': contact?.toJson(),
    'venueNotes': venueNotes,
    'venueNotesUrl': venueNotesUrl,
  };

  factory StoredLocation.fromJson(Map<String, dynamic> json) {
    // ... (parsing logic for time, day, contact etc. is unchanged)
    TimeOfDay? parsedTime;
    if (json['jamOpenMicTime'] != null && json['jamOpenMicTime'] is Map) {
      final timeMap = json['jamOpenMicTime'] as Map<String, dynamic>;
      if (timeMap['hour'] != null && timeMap['minute'] != null) {
        parsedTime = TimeOfDay(hour: timeMap['hour'] as int, minute: timeMap['minute'] as int);
      }
    }
    DayOfWeek? parsedDay;
    if (json['jamOpenMicDay'] != null && json['jamOpenMicDay'] is String) {
      try {
        parsedDay = DayOfWeek.values.byName((json['jamOpenMicDay'] as String).split('.').last);
      } catch (e) {
        parsedDay = null;
      }
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
      isMuted: json['isMuted'] as bool? ?? false, // <<< NEW
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
    bool? isMuted, // <<< NEW
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
      jamOpenMicDay: jamOpenMicDay,
      jamOpenMicTime: jamOpenMicTime,
      addJamToGigs: addJamToGigs ?? this.addJamToGigs,
      jamFrequencyType: jamFrequencyType ?? this.jamFrequencyType,
      customNthValue: customNthValue,
      isMuted: isMuted ?? this.isMuted, // <<< NEW
      contact: contact ?? this.contact,
      venueNotes: venueNotes ?? this.venueNotes,
      venueNotesUrl: venueNotesUrl ?? this.venueNotesUrl,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is StoredLocation &&
              runtimeType == other.runtimeType &&
              placeId == other.placeId &&
              name == other.name &&
              address == other.address &&
              coordinates == other.coordinates &&
              rating == other.rating &&
              comment == other.comment &&
              isArchived == other.isArchived &&
              hasJamOpenMic == other.hasJamOpenMic &&
              jamOpenMicDay == other.jamOpenMicDay &&
              jamOpenMicTime == other.jamOpenMicTime &&
              addJamToGigs == other.addJamToGigs &&
              jamFrequencyType == other.jamFrequencyType &&
              customNthValue == other.customNthValue &&
              isMuted == other.isMuted && // <<< NEW
              contact == other.contact &&
              venueNotes == other.venueNotes &&
              venueNotesUrl == other.venueNotesUrl;

  @override
  int get hashCode =>
      placeId.hashCode ^
      name.hashCode ^
      address.hashCode ^
      coordinates.hashCode ^
      rating.hashCode ^
      comment.hashCode ^
      isArchived.hashCode ^
      hasJamOpenMic.hashCode ^
      jamOpenMicDay.hashCode ^
      jamOpenMicTime.hashCode ^
      addJamToGigs.hashCode ^
      jamFrequencyType.hashCode ^
      customNthValue.hashCode ^
      isMuted.hashCode ^ // <<< NEW
      contact.hashCode ^
      venueNotes.hashCode ^
      venueNotesUrl.hashCode;

  static StoredLocation get addNewVenuePlaceholder => StoredLocation(
    placeId: 'add_new_venue_placeholder',
    name: '--- Add New Venue ---',
    address: '',
    coordinates: const LatLng(0, 0),
  );

  String jamOpenMicDisplayString(BuildContext context) {
    if (!hasJamOpenMic || jamOpenMicDay == null || jamOpenMicTime == null) {
      return 'Not set up';
    }
    String dayString = toBeginningOfSentenceCase(jamOpenMicDay.toString().split('.').last) ?? '';
    return '$dayString at ${jamOpenMicTime!.format(context)}';
  }

  String _ordinal(int number) {
    if (number <= 0) return number.toString();
    if (number % 100 >= 11 && number % 100 <= 13) return '${number}th';
    switch (number % 10) {
      case 1: return '${number}st';
      case 2: return '${number}nd';
      case 3: return '${number}rd';
      default: return '${number}th';
    }
  }
}

