// lib/gig_model.dart
import 'dart:convert'; // For jsonEncode and jsonDecode

class Gig {
  String id; // Unique identifier for the gig
  String venueName; // A user-friendly name for the venue/location
  double latitude;
  double longitude;
  String address; // Formatted address from Google Maps
  String? placeId; // Optional: Google Maps Place ID for precise location reference
  DateTime dateTime; // Date and time of the gig
  double pay; // Pay for the gig, supports two decimals
  double gigLengthHours; // Length of the gig in hours, supports two decimals
  double driveSetupTimeHours;
  double rehearsalLengthHours; // Length of rehearsal in hours, supports two decimals
  bool isJamOpenMic; // <<< NEW: True if this is a placeholder for a Jam/Open Mic night

  Gig({
    required this.id,
    required this.venueName,
    required this.latitude,
    required this.longitude,
    required this.address,
    this.placeId,
    required this.dateTime,
    required this.pay,
    required this.gigLengthHours,
    required this.driveSetupTimeHours,
    required this.rehearsalLengthHours,
    this.isJamOpenMic = false, // <<< Initialize with a default
  });

  Gig copyWith({
    String? id,
    String? venueName,
    double? latitude,
    double? longitude,
    String? address,
    String? placeId,
    DateTime? dateTime,
    double? pay,
    double? gigLengthHours,
    double? driveSetupTimeHours,
    double? rehearsalLengthHours,
    bool? isJamOpenMic, // <<< ADDED
  }) {
    return Gig(
      id: id ?? this.id,
      venueName: venueName ?? this.venueName,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      placeId: placeId ?? this.placeId,
      dateTime: dateTime ?? this.dateTime,
      pay: pay ?? this.pay,
      gigLengthHours: gigLengthHours ?? this.gigLengthHours,
      driveSetupTimeHours: driveSetupTimeHours ?? this.driveSetupTimeHours,
      rehearsalLengthHours: rehearsalLengthHours ?? this.rehearsalLengthHours,
      isJamOpenMic: isJamOpenMic ?? this.isJamOpenMic, // <<< ADDED
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'venueName': venueName,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'placeId': placeId,
      'dateTime': dateTime.toIso8601String(),
      'pay': pay,
      'gigLengthHours': gigLengthHours,
      'driveSetupTimeHours': driveSetupTimeHours,
      'rehearsalLengthHours': rehearsalLengthHours,
      'isJamOpenMic': isJamOpenMic, // <<< ADDED to JSON
    };
  }

  factory Gig.fromJson(Map<String, dynamic> json) {
    return Gig(
      id: json['id'] as String,
      venueName: json['venueName'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      address: json['address'] as String,
      placeId: json['placeId'] as String?,
      dateTime: DateTime.parse(json['dateTime'] as String),
      pay: (json['pay'] as num).toDouble(),
      gigLengthHours: (json['gigLengthHours'] as num).toDouble(),
      driveSetupTimeHours: (json['driveSetupTimeHours'] as num?)?.toDouble() ?? 0.0, // Keep existing null safety
      rehearsalLengthHours: (json['rehearsalLengthHours'] as num).toDouble(),
      isJamOpenMic: json['isJamOpenMic'] as bool? ?? false, // <<< ADDED from JSON (default to false if missing)
    );
  }

  // --- Static methods for saving and loading a list of Gigs ---
  // These don't need to change as they operate on the instance methods toJson/fromJson
  static String encode(List<Gig> gigs) => json.encode(
    gigs.map<Map<String, dynamic>>((gig) => gig.toJson()).toList(),
  );

  static List<Gig> decode(String gigsString) {
    if (gigsString.isEmpty) return [];
    try {
      final List<dynamic> decodedJson = json.decode(gigsString) as List<dynamic>;
      return decodedJson
          .map<Gig?>((item) { // <<< MODIFICATION: Allow map to return Gig? (nullable Gig)
        try {
          // Ensure item is actually a Map before attempting to cast and parse
          if (item is Map<String, dynamic>) {
            return Gig.fromJson(item);
          } else {
            print("Error decoding a single gig: Item is not a Map - $item.");
            return null; // Item is not in the expected format
          }
        } catch (e) {
          print("Error decoding a single gig: $item. Error: $e");
          return null; // Return null if fromJson throws an error
        }
      })
          .whereType<Gig>() // <<< This correctly filters out any nulls
          .toList();
    } catch (e) {
      // This catch block is for errors in decoding the top-level list structure
      print("Error decoding gigs list: $gigsString. Error: $e");
      return []; // Return empty list on major decoding error
    }
  }

  // --- Equality Operators ---
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is Gig &&
              runtimeType == other.runtimeType &&
              id == other.id &&
              venueName == other.venueName &&
              latitude == other.latitude &&
              longitude == other.longitude &&
              address == other.address &&
              placeId == other.placeId &&
              dateTime == other.dateTime &&
              pay == other.pay &&
              gigLengthHours == other.gigLengthHours &&
              driveSetupTimeHours == other.driveSetupTimeHours &&
              rehearsalLengthHours == other.rehearsalLengthHours &&
              isJamOpenMic == other.isJamOpenMic; // <<< ADDED

  @override
  int get hashCode =>
      id.hashCode ^
      venueName.hashCode ^
      latitude.hashCode ^
      longitude.hashCode ^
      address.hashCode ^
      placeId.hashCode ^
      dateTime.hashCode ^
      pay.hashCode ^
      gigLengthHours.hashCode ^
      driveSetupTimeHours.hashCode ^
      rehearsalLengthHours.hashCode ^
      isJamOpenMic.hashCode; // <<< ADDED
}

