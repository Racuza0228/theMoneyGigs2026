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
  });

  // --- ADD THE COPYWITH METHOD HERE ---
  Gig copyWith({
    String? id,
    String? venueName,
    double? latitude,
    double? longitude,
    String? address,
    String? placeId, // Keep it nullable to match the class field
    DateTime? dateTime,
    double? pay,
    double? gigLengthHours,
    double? driveSetupTimeHours,
    double? rehearsalLengthHours,
  }) {
    return Gig(
      id: id ?? this.id,
      venueName: venueName ?? this.venueName,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      placeId: placeId ?? this.placeId, // If new placeId is null, use current; allows clearing placeId by passing explicit null
      dateTime: dateTime ?? this.dateTime,
      pay: pay ?? this.pay,
      gigLengthHours: gigLengthHours ?? this.gigLengthHours,
      driveSetupTimeHours: driveSetupTimeHours ?? this.driveSetupTimeHours,
      rehearsalLengthHours: rehearsalLengthHours ?? this.rehearsalLengthHours,
    );
  }
  // --- END OF COPYWITH METHOD ---

  // --- Methods for SharedPreferences (JSON Conversion) ---

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
    };
  }

  factory Gig.fromJson(Map<String, dynamic> json) {
    return Gig(
      id: json['id'] as String,
      venueName: json['venueName'] as String,
      latitude: (json['latitude'] as num).toDouble(), // Added type casting for safety
      longitude: (json['longitude'] as num).toDouble(), // Added type casting for safety
      address: json['address'] as String,
      placeId: json['placeId'] as String?,
      dateTime: DateTime.parse(json['dateTime'] as String),
      pay: (json['pay'] as num).toDouble(), // Added type casting for safety
      gigLengthHours: (json['gigLengthHours'] as num).toDouble(), // Added type casting for safety
      driveSetupTimeHours: (json['driveSetupTimeHours'] ?? 0.0) as double,
      rehearsalLengthHours: (json['rehearsalLengthHours'] as num).toDouble(), // Added type casting for safety
    );
  }

  // --- Static methods for saving and loading a list of Gigs ---
  static String encode(List<Gig> gigs) => json.encode(
    gigs.map<Map<String, dynamic>>((gig) => gig.toJson()).toList(),
  );

  static List<Gig> decode(String gigsString) {
    if (gigsString.isEmpty) return [];
    final List<dynamic> decodedJson = json.decode(gigsString) as List<dynamic>;
    return decodedJson
        .map<Gig>((item) => Gig.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
