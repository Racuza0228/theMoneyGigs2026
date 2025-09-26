import 'package:flutter/material.dart'; // For TimeOfDay
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart'; // For toBeginningOfSentenceCase

// Enum for day of the week
enum DayOfWeek { monday, tuesday, wednesday, thursday, friday, saturday, sunday }

// Define an enum for frequency types
enum JamFrequencyType {
  weekly,
  biWeekly,
  monthlySameDay,
  monthlySameDate,
  customNthDay
}

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
    this.jamFrequencyType = JamFrequencyType.weekly, // Default value
    this.customNthValue,
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
    'jamFrequencyType': jamFrequencyType.toString(), // <<< ADDED
    'customNthValue': customNthValue,             // <<< ADDED
  };

  factory StoredLocation.fromJson(Map<String, dynamic> json) {
    TimeOfDay? parsedTime;
    if (json['jamOpenMicTime'] != null && json['jamOpenMicTime'] is Map) {
      final timeMap = json['jamOpenMicTime'] as Map<String, dynamic>;
      if (timeMap['hour'] != null && timeMap['minute'] != null) {
        parsedTime = TimeOfDay(
          hour: timeMap['hour'] as int,
          minute: timeMap['minute'] as int,
        );
      }
    }

    DayOfWeek? parsedDay;
    if (json['jamOpenMicDay'] != null && json['jamOpenMicDay'] is String) {
      try {
        parsedDay = DayOfWeek.values.firstWhere(
              (e) => e.toString() == json['jamOpenMicDay'],
        );
      } catch (e) {
        String dayString = (json['jamOpenMicDay'] as String).split('.').last;
        try {
          parsedDay = DayOfWeek.values.byName(dayString.toLowerCase());
        } catch (e) {
          print("Could not parse DayOfWeek from string: ${json['jamOpenMicDay']}");
          parsedDay = null;
        }
      }
    }

    JamFrequencyType parsedFrequency = JamFrequencyType.weekly; // Default
    if (json['jamFrequencyType'] != null && json['jamFrequencyType'] is String) {
      try {
        parsedFrequency = JamFrequencyType.values.firstWhere(
                (e) => e.toString() == json['jamFrequencyType'],
            orElse: () { // Add orElse to handle cases where the string doesn't match any enum value
              print("Unknown JamFrequencyType string: ${json['jamFrequencyType']}. Defaulting to weekly.");
              return JamFrequencyType.weekly;
            }
        );
      } catch (e) { // Catch broader errors from firstWhere if needed, though orElse handles missing
        print("Error parsing JamFrequencyType: ${json['jamFrequencyType']}. Defaulting to weekly. Error: $e");
        parsedFrequency = JamFrequencyType.weekly;
      }
    }


    int? parsedNthValue = json['customNthValue'] as int?;

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
      jamFrequencyType: parsedFrequency,   // <<< ASSIGNED
      customNthValue: parsedNthValue,     // <<< ASSIGNED
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
      jamOpenMicDay: jamOpenMicDay, // Passed value from dialog is already correct (or null)
      jamOpenMicTime: jamOpenMicTime, // Passed value from dialog is already correct (or null)
      addJamToGigs: addJamToGigs ?? this.addJamToGigs,
      jamFrequencyType: jamFrequencyType ?? this.jamFrequencyType,
      customNthValue: customNthValue, // Passed value from dialog is already correct (int or null)
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
              jamFrequencyType == other.jamFrequencyType && // <<< ADDED
              customNthValue == other.customNthValue;     // <<< ADDED

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
      jamFrequencyType.hashCode ^ // <<< ADDED
      customNthValue.hashCode;   // <<< ADDED

  static StoredLocation get addNewVenuePlaceholder => StoredLocation(
    placeId: 'add_new_venue_placeholder',
    name: '--- Add New Venue ---',
    address: '',
    coordinates: const LatLng(0, 0),
    isArchived: false,
    hasJamOpenMic: false,
    jamOpenMicDay: null,
    jamOpenMicTime: null,
    addJamToGigs: false,
    jamFrequencyType: JamFrequencyType.weekly,
    customNthValue: null,
  );

  String jamOpenMicDisplayString(BuildContext context) {
    if (!hasJamOpenMic || jamOpenMicDay == null || jamOpenMicTime == null) {
      return 'Not set up';
    }
    String dayString = toBeginningOfSentenceCase(jamOpenMicDay.toString().split('.').last) ?? jamOpenMicDay.toString().split('.').last ;
    String freqString = "";

    switch (jamFrequencyType) {
      case JamFrequencyType.weekly:
        freqString = "Weekly, ";
        break;
      case JamFrequencyType.biWeekly:
        freqString = "Bi-Weekly, ";
        break;
      case JamFrequencyType.customNthDay:
        if (customNthValue != null && customNthValue! > 0) {
          freqString = "Every ${customNthValue == 1 ? '' : '${_ordinal(customNthValue!)} '}";
        } else {
          freqString = "Weekly, "; // Fallback if customNthValue is missing
        }
        break;
      case JamFrequencyType.monthlySameDay:
        if (customNthValue != null && customNthValue! > 0) {
          freqString = "${_ordinal(customNthValue!)} "; // e.g., "2nd "
        } else {
          freqString = "Monthly, "; // Fallback if customNthValue is missing
        }
        break;
      case JamFrequencyType.monthlySameDate:
        freqString = "Monthly (Date Based), "; // Simple label for this less common type
        break;
    }
    return '$freqString$dayString at ${jamOpenMicTime!.format(context)}';
  }

  // Helper for ordinal numbers (1st, 2nd, 3rd)
  String _ordinal(int number) {
    if (number <= 0) return number.toString(); // Should not happen with validation
    if (number % 100 >= 11 && number % 100 <= 13) {
      return '${number}th';
    }
    switch (number % 10) {
      case 1:
        return '${number}st';
      case 2:
        return '${number}nd';
      case 3:
        return '${number}rd';
      default:
        return '${number}th';
    }
  }
}
