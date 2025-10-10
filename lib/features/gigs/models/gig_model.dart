// lib/gig_model.dart
import 'dart:convert'; // For jsonEncode and jsonDecode

class Gig {
  String id;
  String venueName;
  double latitude;
  double longitude;
  String address;
  String? placeId;
  DateTime dateTime;
  double pay;
  double gigLengthHours;
  double driveSetupTimeHours;
  double rehearsalLengthHours;
  bool isJamOpenMic;
  String? notes;
  String? notesUrl; // <<< NEW: To store a URL for the gig notes

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
    this.isJamOpenMic = false,
    this.notes,
    this.notesUrl, // <<< ADDED to constructor
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
    bool? isJamOpenMic,
    String? notes,
    String? notesUrl, // <<< ADDED
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
      isJamOpenMic: isJamOpenMic ?? this.isJamOpenMic,
      notes: notes ?? this.notes,
      notesUrl: notesUrl ?? this.notesUrl, // <<< ADDED
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
      'isJamOpenMic': isJamOpenMic,
      'notes': notes,
      'notesUrl': notesUrl, // <<< ADDED to JSON
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
      driveSetupTimeHours: (json['driveSetupTimeHours'] as num?)?.toDouble() ?? 0.0,
      rehearsalLengthHours: (json['rehearsalLengthHours'] as num).toDouble(),
      isJamOpenMic: json['isJamOpenMic'] as bool? ?? false,
      notes: json['notes'] as String?,
      notesUrl: json['notesUrl'] as String?, // <<< ADDED from JSON
    );
  }

  // --- Static methods and equality operators are assumed to be updated accordingly ---
  // (Full code omitted for brevity but should include `notesUrl` in equality checks)

  // --- Static methods for saving and loading a list of Gigs ---
  static String encode(List<Gig> gigs) => json.encode(
    gigs.map<Map<String, dynamic>>((gig) => gig.toJson()).toList(),
  );

  static List<Gig> decode(String gigsString) {
    if (gigsString.isEmpty) return [];
    try {
      final List<dynamic> decodedJson = json.decode(gigsString) as List<dynamic>;
      return decodedJson
          .map<Gig?>((item) {
        try {
          if (item is Map<String, dynamic>) {
            return Gig.fromJson(item);
          } else {
            print("Error decoding a single gig: Item is not a Map - $item.");
            return null;
          }
        } catch (e) {
          print("Error decoding a single gig: $item. Error: $e");
          return null;
        }
      })
          .whereType<Gig>()
          .toList();
    } catch (e) {
      print("Error decoding gigs list: $gigsString. Error: $e");
      return [];
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
              address == other.address &&
              dateTime == other.dateTime &&
              pay == other.pay &&
              notes == other.notes &&
              notesUrl == other.notesUrl;

  @override
  int get hashCode =>
      id.hashCode ^
      venueName.hashCode ^
      address.hashCode ^
      dateTime.hashCode ^
      pay.hashCode ^
      notes.hashCode ^
      notesUrl.hashCode;
}
