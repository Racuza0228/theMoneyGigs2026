// lib/features/map_venues/models/jam_session_model.dart
import 'package:flutter/material.dart';
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

  // ── GO JAM support ──────────────────────────────────────────────────────
  //
  // Returns the next date/time (on or after [now]) this session actually
  // happens.
  //
  // NOTE: unlike the live "Gigs" list generator (GigsPage
  // ._generateJamOpenMicGigs / ._generateOccurrencesForGig in gigs.dart),
  // this always returns the single nearest upcoming date of [day]/[time] —
  // including today, if the time hasn't passed yet — for weekly, biWeekly,
  // and customNthDay alike. Those three frequencies only differ from each
  // other in how *later* recurrences are spaced out, and a JamSession
  // doesn't store a series-start date to anchor that spacing against, so
  // there's no reliable way to know which week a biWeekly/customNthDay
  // series is "on" beyond the very next hit of the day itself — which is
  // exactly what GO JAM (a single one-off add, not a recurring toggle)
  // needs anyway.
  //
  // monthlySameDay is computed properly (nth weekday of month).
  // monthlySameDate has no day-of-month field anywhere in the app (see
  // _JamSessionEditorState.build in jam_open_mic_dialog.dart) and
  // gigs.dart's own generator has no case for it either — so, matching
  // that existing behavior rather than inventing new behavior, it returns
  // null here too.
  DateTime? nextOccurrence({DateTime? now}) {
    final DateTime today = now ?? DateTime.now();
    // DayOfWeek.monday == 0, DateTime.monday == 1 — same offset gigs.dart uses.
    final int targetWeekday = day.index + 1;

    DateTime withSessionTime(DateTime d) =>
        DateTime(d.year, d.month, d.day, time.hour, time.minute);

    DateTime nextDayOfWeekOnOrAfter(DateTime start) {
      DateTime d = DateTime(start.year, start.month, start.day);
      while (d.weekday != targetWeekday || withSessionTime(d).isBefore(today)) {
        d = d.add(const Duration(days: 1));
      }
      return d;
    }

    switch (frequency) {
      case JamFrequencyType.weekly:
      case JamFrequencyType.biWeekly:
      case JamFrequencyType.customNthDay:
        return withSessionTime(nextDayOfWeekOnOrAfter(today));

      case JamFrequencyType.monthlySameDay:
        if (nthValue == null || nthValue! < 1 || nthValue! > 5) return null;

        DateTime? nthWeekdayOfMonth(int year, int month) {
          int occurrences = 0;
          final daysInMonth = DateTime(year, month + 1, 0).day;
          for (int d = 1; d <= daysInMonth; d++) {
            final date = DateTime(year, month, d);
            if (date.weekday == targetWeekday) {
              occurrences++;
              if (occurrences == nthValue) return date;
            }
          }
          return null;
        }

        DateTime monthCursor = DateTime(today.year, today.month, 1);
        // Bounded search — 24 months out is more than enough headroom.
        for (int i = 0; i < 24; i++) {
          final candidate =
          nthWeekdayOfMonth(monthCursor.year, monthCursor.month);
          if (candidate != null) {
            final candidateWithTime = withSessionTime(candidate);
            if (!candidateWithTime.isBefore(today)) return candidateWithTime;
          }
          monthCursor = DateTime(monthCursor.year, monthCursor.month + 1, 1);
        }
        return null;

      case JamFrequencyType.monthlySameDate:
        return null;

      // Unreachable — the switch above is exhaustive over JamFrequencyType.
      default:
        return null;
    }
  }
}
