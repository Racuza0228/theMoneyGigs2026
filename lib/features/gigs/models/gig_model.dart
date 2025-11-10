// lib/features/gigs/models/gig_model.dart
import 'dart:convert';
import 'package:the_money_gigs/core/models/enums.dart';

class Gig {
  String id;
  String venueName;  double latitude;
  double longitude;
  String address;
  String? placeId;
  DateTime dateTime; // For recurring gigs, this will be the START date
  double pay;
  double gigLengthHours;
  double driveSetupTimeHours;
  double rehearsalLengthHours;
  bool isJamOpenMic;
  String? notes;
  String? notesUrl;

  // --- RECURRENCE FIELDS ---
  bool isRecurring;
  JamFrequencyType? recurrenceFrequency;
  DayOfWeek? recurrenceDay;
  int? recurrenceNthValue;
  DateTime? recurrenceEndDate;
  bool isFromRecurring;
  List<DateTime>? recurrenceExceptions; // <<< NEW FIELD

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
    this.notesUrl,
    this.isRecurring = false,
    this.recurrenceFrequency,
    this.recurrenceDay,
    this.recurrenceNthValue,
    this.recurrenceEndDate,
    this.isFromRecurring = false,
    this.recurrenceExceptions, // <<< ADDED TO CONSTRUCTOR
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
    String? notesUrl,
    bool? isRecurring,
    JamFrequencyType? recurrenceFrequency,
    DayOfWeek? recurrenceDay,
    int? recurrenceNthValue,
    DateTime? recurrenceEndDate,
    bool? isFromRecurring,
    List<DateTime>? recurrenceExceptions, // <<< ADDED TO COPYWITH
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
      notesUrl: notesUrl ?? this.notesUrl,
      isRecurring: isRecurring ?? this.isRecurring,
      recurrenceFrequency: recurrenceFrequency ?? this.recurrenceFrequency,
      recurrenceDay: recurrenceDay ?? this.recurrenceDay,
      recurrenceNthValue: recurrenceNthValue ?? this.recurrenceNthValue,
      recurrenceEndDate: recurrenceEndDate ?? this.recurrenceEndDate,
      isFromRecurring: isFromRecurring ?? this.isFromRecurring,
      recurrenceExceptions: recurrenceExceptions ?? this.recurrenceExceptions, // <<< ADDED TO COPYWITH
    );
  }

  /// Gets the base ID for a gig. For a recurring instance (e.g., 'gig1_20240101'),
  /// it returns the original ID (e.g., 'gig1'). For regular gigs, it returns its own ID.
  String getBaseId() {
    if (isFromRecurring && id.contains('_')) {
      // For a standard recurring gig instance like 'baseid_20251108'
      final parts = id.split('_');
      if (parts.length > 1) {
        // Re-join in case the base ID itself had underscores, though this is unlikely/bad practice.
        return parts.sublist(0, parts.length - 1).join('_');
      }
    } else if (isJamOpenMic && id.startsWith('jam_')) {
      // For a jam session like 'jam_placeId_sessionId_20251108'
      final parts = id.split('_');
      if (parts.length > 3) {
        return parts.sublist(0, parts.length -1).join('_');
      }
    }
    // For a base recurring gig, a non-recurring gig, or if splitting fails
    return id;
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
      'notesUrl': notesUrl,
      'isRecurring': isRecurring,
      'recurrenceFrequency': recurrenceFrequency?.toString(),
      'recurrenceDay': recurrenceDay?.toString(),
      'recurrenceNthValue': recurrenceNthValue,
      'recurrenceEndDate': recurrenceEndDate?.toIso8601String(),
      // <<< ADDED TO TOJSON
      'recurrenceExceptions': recurrenceExceptions?.map((date) => date.toIso8601String()).toList(),
    };
  }

  factory Gig.fromJson(Map<String, dynamic> json) {
    T? safeParseEnum<T>(List<T> enumValues, String? value) {
      if (value == null) return null;
      try {
        return enumValues.firstWhere((e) => e.toString() == value);
      } catch (e) {
        return null;
      }
    }

    // <<< ADDED TO FROMJSON
    List<DateTime>? parseRecurrenceExceptions(dynamic jsonField) {
      if (jsonField is List) {
        return jsonField
            .map((dateString) => DateTime.tryParse(dateString as String))
            .whereType<DateTime>()
            .toList();
      }
      return null;
    }

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
      rehearsalLengthHours: (json['rehearsalLengthHours'] as num?)?.toDouble() ?? 0.0,
      isJamOpenMic: json['isJamOpenMic'] as bool? ?? false,
      notes: json['notes'] as String?,
      notesUrl: json['notesUrl'] as String?,
      isRecurring: json['isRecurring'] as bool? ?? false,
      recurrenceFrequency: safeParseEnum(JamFrequencyType.values, json['recurrenceFrequency'] as String?),
      recurrenceDay: safeParseEnum(DayOfWeek.values, json['recurrenceDay'] as String?),
      recurrenceNthValue: json['recurrenceNthValue'] as int?,
      recurrenceEndDate: json['recurrenceEndDate'] != null ? DateTime.tryParse(json['recurrenceEndDate'] as String) : null,
      recurrenceExceptions: parseRecurrenceExceptions(json['recurrenceExceptions']), // <<< ADDED TO FROMJSON
    );
  }

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
          return Gig.fromJson(item as Map<String, dynamic>);
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is Gig &&
              runtimeType == other.runtimeType &&
              id == other.id;

  @override
  int get hashCode => id.hashCode;
}
