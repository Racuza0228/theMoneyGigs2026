// lib/features/map_venues/models/jam_session_model.dartimport 'package:flutter/material.dart';
import 'package:the_money_gigs/core/models/enums.dart'; // <<< CORRECT: Imports the shared enums
import 'package:flutter/material.dart'; // <<< ADD THIS IMPORT for TimeOfDay

// The import for venue_model.dart has been removed.

class JamSession {
  final String id;
  final String? style;
  final DayOfWeek day;
  final TimeOfDay time;
  final JamFrequencyType frequency;
  final int? nthValue;
  final bool showInGigsList;

  JamSession({
    required this.id,
    this.style,
    required this.day,
    required this.time,
    this.frequency = JamFrequencyType.weekly,
    this.nthValue,
    this.showInGigsList = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'style': style,
    'day': day.toString(),
    'time': {'hour': time.hour, 'minute': time.minute},
    'frequency': frequency.toString(),
    'nthValue': nthValue,
    'showInGigsList': showInGigsList,
  };

  factory JamSession.fromJson(Map<String, dynamic> json) {
    final timeMap = json['time'] as Map<String, dynamic>;
    return JamSession(
      id: json['id'] ?? DateTime.now().microsecondsSinceEpoch.toString(),
      style: json['style'] as String?,
      day: DayOfWeek.values.firstWhere(
            (e) => e.toString() == json['day'],
        orElse: () => DayOfWeek.monday,
      ),
      time: TimeOfDay(hour: timeMap['hour'], minute: timeMap['minute']),
      frequency: JamFrequencyType.values.firstWhere(
            (e) => e.toString() == json['frequency'],
        orElse: () => JamFrequencyType.weekly,
      ),
      nthValue: json['nthValue'] as int?,
      showInGigsList: json['showInGigsList'] as bool? ?? false,
    );
  }

  JamSession copyWith({
    String? id,
    String? style,
    DayOfWeek? day,
    TimeOfDay? time,
    JamFrequencyType? frequency,
    int? nthValue,
    bool? showInGigsList,
  }) {
    return JamSession(
      id: id ?? this.id,
      style: style ?? this.style,
      day: day ?? this.day,
      time: time ?? this.time,
      frequency: frequency ?? this.frequency,
      nthValue: nthValue ?? this.nthValue,
      showInGigsList: showInGigsList ?? this.showInGigsList,
    );
  }
}
