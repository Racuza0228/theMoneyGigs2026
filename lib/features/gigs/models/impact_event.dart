// lib/features/gigs/models/impact_event.dart
import 'package:flutter/material.dart';
/// A single external event that may impact crowd size at a nearby gig.
///
/// Populated by [ImpactEventService] from Bandsintown, Eventbrite,
/// and the local_events Firestore collection (Phase 2 local calendar data).
class ImpactEvent {
  final String eventName;
  final DateTime eventDate;
  final String eventType; // festival | concert | sporting | holiday | local_music | other
  final double? distanceMiles;
  final String? sourceUrl;
  final String impactLevel; // low | medium | high
  final String apiSource; // bandsintown | eventbrite | local_cincinnati

  const ImpactEvent({
    required this.eventName,
    required this.eventDate,
    required this.eventType,
    this.distanceMiles,
    this.sourceUrl,
    required this.impactLevel,
    required this.apiSource,
  });

  Map<String, dynamic> toJson() => {
    'eventName': eventName,
    'eventDate': eventDate.toIso8601String(),
    'eventType': eventType,
    'distanceMiles': distanceMiles,
    'sourceUrl': sourceUrl,
    'impactLevel': impactLevel,
    'apiSource': apiSource,
  };

  factory ImpactEvent.fromJson(Map<String, dynamic> json) => ImpactEvent(
    eventName: json['eventName'] as String,
    eventDate: DateTime.parse(json['eventDate'] as String),
    eventType: json['eventType'] as String? ?? 'other',
    distanceMiles: (json['distanceMiles'] as num?)?.toDouble(),
    sourceUrl: json['sourceUrl'] as String?,
    impactLevel: json['impactLevel'] as String? ?? 'low',
    apiSource: json['apiSource'] as String? ?? 'unknown',
  );

  /// Human-readable event type label for display in the UI.
  String get eventTypeLabel {
    switch (eventType) {
      case 'festival':
        return 'Festival';
      case 'concert':
        return 'Concert';
      case 'sporting':
        return 'Sporting Event';
      case 'holiday':
        return 'Holiday / Civic Event';
      case 'local_music':
        return 'Live Music';
      default:
        return 'Event';
    }
  }

  /// Returns a const-compatible IconData for tree-shaking safety.
  IconData get icon {
    switch (eventType) {
      case 'festival':
        return Icons.festival;
      case 'concert':
        return Icons.music_note;
      case 'sporting':
        return Icons.sports;
      case 'holiday':
        return Icons.celebration;
      case 'local_music':
        return Icons.music_note;
      default:
        return Icons.event;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is ImpactEvent &&
              eventName == other.eventName &&
              eventDate.year == other.eventDate.year &&
              eventDate.month == other.eventDate.month &&
              eventDate.day == other.eventDate.day;

  @override
  int get hashCode => Object.hash(eventName, eventDate.year, eventDate.month, eventDate.day);
}