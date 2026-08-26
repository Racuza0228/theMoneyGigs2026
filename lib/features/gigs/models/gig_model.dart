// lib/features/gigs/models/gig_model.dart
//
// CHANGE LOG (Impact Event Intelligence update):
//   + Added `impactEvents` field  — List<ImpactEvent>?
//   + Added `lastAssessedAt` field — DateTime?
//   + Updated toJson / fromJson / copyWith / encode / decode accordingly
//   All existing fields and logic unchanged.
//
// CHANGE LOG (Band/Project Expansion v3.0.0 — Sprint Task 1):
//   + Added `bandId` field — String? (null for solo/old gigs; Firestore band doc ID when a band is selected)
//   + Updated constructor / toJson / fromJson / copyWith accordingly
//   bandName is kept as-is for display + backward compatibility. Solo = bandName null AND bandId null.
//   No migration needed — old free-text-only gigs just have bandId == null and render as before.
//
// CHANGE LOG (Band/Project Expansion v3.0.0 — Sprint Task 7):
//   + copyWith's `bandName` / `bandId` switched from plain String? to
//     ValueGetter<String?>? (same wrapper pattern StoredLocation.copyWith
//     already uses in venue_model.dart). Plain `field ?? this.field` can
//     never null out an existing value via copyWith — passing null is
//     indistinguishable from "don't change it." That's now a real bug, not
//     a theoretical one: the booking dialog's band dropdown lets someone
//     switch an edited gig back to "Solo," which needs bandName/bandId to
//     actually clear. Everywhere else in this file already sidesteps the
//     same limitation by using the full Gig(...) constructor instead of
//     copyWith (search "copyWith cannot null out nullable fields") — this
//     is the same bug, just finally fixed at the two fields that needed it
//     fixed rather than worked around again. Every OTHER nullable field
//     here (otherExpenses, notes, etc.) still has the same underlying
//     limitation — not touched, out of scope for this task.

import 'dart:convert';
import 'package:flutter/foundation.dart' show ValueGetter;
import 'package:the_money_gigs/core/models/enums.dart';
import 'package:the_money_gigs/features/gigs/models/gig_rating.dart';
import 'package:the_money_gigs/features/gigs/models/impact_event.dart'; // ← NEW
import 'package:the_money_gigs/core/utils/logger.dart';

class Gig {
  String id;
  String venueName;
  String? bandName;
  String? bandId; // null for solo/old gigs; Firestore band document ID when band selected
  double latitude;
  double longitude;
  String address;
  String? placeId;
  DateTime dateTime;
  double pay;
  double? otherExpenses;
  // --- TIPS ---
  double? tipsAmount;
  double gigLengthHours;
  double driveSetupTimeHours;
  double rehearsalLengthHours;
  bool isJamOpenMic;
  String? notes;
  String? notesUrl;
  String? setlistId;
  // --- RECURRENCE FIELDS ---
  bool isRecurring;
  JamFrequencyType? recurrenceFrequency;
  DayOfWeek? recurrenceDay;
  int? recurrenceNthValue;
  DateTime? recurrenceEndDate;
  bool isFromRecurring;
  List<DateTime>? recurrenceExceptions;
  // --- RETROSPECTIVE FIELDS ---
  List<GigRating>? gigRatings;
  bool? retrospectiveCompleted;
  // --- IMPACT EVENT INTELLIGENCE ---    ← NEW SECTION
  List<ImpactEvent>? impactEvents;
  DateTime? lastAssessedAt;
  // --- JAM ATTENDANCE (GO JAM / jam listing dialog) ---
  // 'going' | 'interested' | null (no status set yet). Only meaningful for
  // isJamOpenMic gigs; ignored elsewhere. Local-only for now — a future
  // pass syncs an aggregate going/interested count to Firestore per
  // venue+session+date for connected/network users.
  String? attendanceStatus;

  Gig({
    required this.id,
    required this.venueName,
    this.bandName,
    this.bandId,
    required this.latitude,
    required this.longitude,
    required this.address,
    this.placeId,
    required this.dateTime,
    required this.pay,
    this.otherExpenses,
    this.tipsAmount,
    required this.gigLengthHours,
    required this.driveSetupTimeHours,
    required this.rehearsalLengthHours,
    this.isJamOpenMic = false,
    this.notes,
    this.notesUrl,
    this.setlistId,
    this.isRecurring = false,
    this.recurrenceFrequency,
    this.recurrenceDay,
    this.recurrenceNthValue,
    this.recurrenceEndDate,
    this.isFromRecurring = false,
    this.recurrenceExceptions,
    this.gigRatings,
    this.retrospectiveCompleted,
    this.impactEvents,       // ← NEW
    this.lastAssessedAt,     // ← NEW
    this.attendanceStatus,
  });

  Gig copyWith({
    String? id,
    String? venueName,
    ValueGetter<String?>? bandName,
    ValueGetter<String?>? bandId,
    double? latitude,
    double? longitude,
    String? address,
    String? placeId,
    DateTime? dateTime,
    double? pay,
    double? otherExpenses,
    double? tipsAmount,
    double? gigLengthHours,
    double? driveSetupTimeHours,
    double? rehearsalLengthHours,
    bool? isJamOpenMic,
    String? notes,
    String? notesUrl,
    String? setlistId,
    bool? isRecurring,
    JamFrequencyType? recurrenceFrequency,
    DayOfWeek? recurrenceDay,
    int? recurrenceNthValue,
    DateTime? recurrenceEndDate,
    bool? isFromRecurring,
    List<DateTime>? recurrenceExceptions,
    List<GigRating>? gigRatings,
    bool? retrospectiveCompleted,
    List<ImpactEvent>? impactEvents,   // ← NEW
    DateTime? lastAssessedAt,          // ← NEW
    String? attendanceStatus,
  }) {
    return Gig(
      id: id ?? this.id,
      venueName: venueName ?? this.venueName,
      bandName: bandName != null ? bandName() : this.bandName,
      bandId: bandId != null ? bandId() : this.bandId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      placeId: placeId ?? this.placeId,
      dateTime: dateTime ?? this.dateTime,
      pay: pay ?? this.pay,
      otherExpenses: otherExpenses ?? this.otherExpenses,
      tipsAmount: tipsAmount ?? this.tipsAmount,
      gigLengthHours: gigLengthHours ?? this.gigLengthHours,
      driveSetupTimeHours: driveSetupTimeHours ?? this.driveSetupTimeHours,
      rehearsalLengthHours: rehearsalLengthHours ?? this.rehearsalLengthHours,
      isJamOpenMic: isJamOpenMic ?? this.isJamOpenMic,
      notes: notes ?? this.notes,
      notesUrl: notesUrl ?? this.notesUrl,
      setlistId: setlistId ?? this.setlistId,
      isRecurring: isRecurring ?? this.isRecurring,
      recurrenceFrequency: recurrenceFrequency ?? this.recurrenceFrequency,
      recurrenceDay: recurrenceDay ?? this.recurrenceDay,
      recurrenceNthValue: recurrenceNthValue ?? this.recurrenceNthValue,
      recurrenceEndDate: recurrenceEndDate ?? this.recurrenceEndDate,
      isFromRecurring: isFromRecurring ?? this.isFromRecurring,
      recurrenceExceptions: recurrenceExceptions ?? this.recurrenceExceptions,
      gigRatings: gigRatings ?? this.gigRatings,
      retrospectiveCompleted: retrospectiveCompleted ?? this.retrospectiveCompleted,
      impactEvents: impactEvents ?? this.impactEvents,       // ← NEW
      lastAssessedAt: lastAssessedAt ?? this.lastAssessedAt, // ← NEW
      attendanceStatus: attendanceStatus ?? this.attendanceStatus,
    );
  }

  double get trueHourlyRate {
    final double totalHours =
        gigLengthHours + driveSetupTimeHours + rehearsalLengthHours;
    final double effectivePay =
        pay + (tipsAmount ?? 0.0) - (otherExpenses ?? 0.0);
    if (effectivePay <= 0 || totalHours <= 0) return 0.0;
    return effectivePay / totalHours;
  }

  bool get hasEnded {
    final endTime =
    dateTime.add(Duration(minutes: (gigLengthHours * 60).toInt()));
    return endTime.isBefore(DateTime.now());
  }

  bool get needsRetrospective {
    return hasEnded && !(retrospectiveCompleted ?? false) && !isJamOpenMic;
  }

  // ── Impact Event Intelligence helpers ───────────────────────────────────────

  /// True if this gig has any medium or high impact events in its window.
  bool get hasSignificantImpactEvents =>
      impactEvents?.any((e) => e.impactLevel == 'high' || e.impactLevel == 'medium') ?? false;

  /// Count of all impact events (for badge display).
  int get impactEventCount => impactEvents?.length ?? 0;

  /// Count of medium + high impact events only (for notification filtering).
  int get significantImpactEventCount =>
      impactEvents?.where((e) => e.impactLevel != 'low').length ?? 0;

  // ── Retrospective helpers ────────────────────────────────────────────────────

  double? getRatingFor(String dimension) {
    if (gigRatings == null) return null;
    try {
      return gigRatings!.firstWhere((r) => r.dimension == dimension).rating;
    } catch (e) {
      return null;
    }
  }

  double? get averageRating {
    if (gigRatings == null || gigRatings!.isEmpty) return null;
    final total = gigRatings!.fold<double>(0, (sum, r) => sum + r.rating);
    return total / gigRatings!.length;
  }

  String getBaseId() {
    if (isFromRecurring && id.contains('_')) {
      final parts = id.split('_');
      if (parts.length > 1) {
        return parts.sublist(0, parts.length - 1).join('_');
      }
    } else if (isJamOpenMic && id.startsWith('jam_')) {
      final parts = id.split('_');
      if (parts.length > 3) {
        return parts.sublist(0, parts.length - 1).join('_');
      }
    }
    return id;
  }

  // ── Serialization ────────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'venueName': venueName,
      'bandName': bandName,
      'bandId': bandId,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'placeId': placeId,
      'dateTime': dateTime.toIso8601String(),
      'pay': pay,
      'otherExpenses': otherExpenses,
      'tipsAmount': tipsAmount,
      'gigLengthHours': gigLengthHours,
      'driveSetupTimeHours': driveSetupTimeHours,
      'rehearsalLengthHours': rehearsalLengthHours,
      'isJamOpenMic': isJamOpenMic,
      'notes': notes,
      'notesUrl': notesUrl,
      'setlistId': setlistId,
      'isRecurring': isRecurring,
      'recurrenceFrequency': recurrenceFrequency?.toString(),
      'recurrenceDay': recurrenceDay?.toString(),
      'recurrenceNthValue': recurrenceNthValue,
      'recurrenceEndDate': recurrenceEndDate?.toIso8601String(),
      'recurrenceExceptions':
      recurrenceExceptions?.map((date) => date.toIso8601String()).toList(),
      'gigRatings': gigRatings?.map((r) => r.toJson()).toList(),
      'retrospectiveCompleted': retrospectiveCompleted,
      'attendanceStatus': attendanceStatus,
      // ← NEW: impact events stored in cache (SharedPreferences), not here.
      // We do NOT persist impactEvents inside the gig JSON to keep gig storage
      // lean. The ImpactEventService has its own cache keyed by gigId.
      // lastAssessedAt is also managed by ImpactEventService.
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

    List<DateTime>? parseRecurrenceExceptions(dynamic jsonField) {
      if (jsonField is List) {
        return jsonField
            .map((dateString) => DateTime.tryParse(dateString as String))
            .whereType<DateTime>()
            .toList();
      }
      return null;
    }

    List<GigRating>? parseGigRatings(dynamic jsonField) {
      if (jsonField is List) {
        return jsonField
            .map((item) => GigRating.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      return null;
    }

    return Gig(
      id: json['id'] as String,
      venueName: json['venueName'] as String,
      bandName: json['bandName'] as String?,
      bandId: json['bandId'] as String?,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      address: json['address'] as String,
      placeId: json['placeId'] as String?,
      dateTime: DateTime.parse(json['dateTime'] as String),
      pay: (json['pay'] as num).toDouble(),
      otherExpenses: (json['otherExpenses'] as num?)?.toDouble() ?? 0.0,
      tipsAmount: (json['tipsAmount'] as num?)?.toDouble(),
      gigLengthHours: (json['gigLengthHours'] as num).toDouble(),
      driveSetupTimeHours:
      (json['driveSetupTimeHours'] as num?)?.toDouble() ?? 0.0,
      rehearsalLengthHours:
      (json['rehearsalLengthHours'] as num?)?.toDouble() ?? 0.0,
      isJamOpenMic: json['isJamOpenMic'] as bool? ?? false,
      notes: json['notes'] as String?,
      notesUrl: json['notesUrl'] as String?,
      setlistId: json['setlistId'] as String?,
      isRecurring: json['isRecurring'] as bool? ?? false,
      recurrenceFrequency: safeParseEnum(
          JamFrequencyType.values, json['recurrenceFrequency'] as String?),
      recurrenceDay:
      safeParseEnum(DayOfWeek.values, json['recurrenceDay'] as String?),
      recurrenceNthValue: json['recurrenceNthValue'] as int?,
      recurrenceEndDate: json['recurrenceEndDate'] != null
          ? DateTime.tryParse(json['recurrenceEndDate'] as String)
          : null,
      recurrenceExceptions:
      parseRecurrenceExceptions(json['recurrenceExceptions']),
      gigRatings: parseGigRatings(json['gigRatings']),
      retrospectiveCompleted: json['retrospectiveCompleted'] as bool?,
      attendanceStatus: json['attendanceStatus'] as String?,
      // impactEvents and lastAssessedAt are not stored in gig JSON —
      // they live in the ImpactEventService cache.
      impactEvents: null,
      lastAssessedAt: null,
    );
  }

  static String encode(List<Gig> gigs) => json.encode(
    gigs.map<Map<String, dynamic>>((gig) => gig.toJson()).toList(),
  );

  static List<Gig> decode(String gigsString) {
    if (gigsString.isEmpty) return [];
    try {
      final List<dynamic> decodedJson =
      json.decode(gigsString) as List<dynamic>;
      return decodedJson
          .map<Gig?>((item) {
        try {
          return Gig.fromJson(item as Map<String, dynamic>);
        } catch (e) {
          log('Error decoding a single gig: $item. Error: $e');
          return null;
        }
      })
          .whereType<Gig>()
          .toList();
    } catch (e) {
      log('Error decoding gigs list: $gigsString. Error: $e');
      return [];
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is Gig && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}