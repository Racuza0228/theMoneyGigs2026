// lib/services/gig_embed_service.dart
import 'package:intl/intl.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';
import 'package:the_money_gigs/core/models/enums.dart';

class GigEmbedService {
  /// Generates an HTML string to be embedded on a website.
  ///
  /// This method takes a list of [Gig] objects, filters for upcoming,
  /// non-jam session gigs, and formats them into an HTML snippet.
  static String generateEmbedCode(List<Gig> allGigs) {
    final now = DateTime.now();

    // 1. Filter for upcoming non-jam gigs.
    //    Recurring gigs use recurrenceEndDate — their base dateTime is the
    //    first occurrence and may be in the past.
    final upcomingGigs = allGigs.where((gig) {
      if (gig.isJamOpenMic) return false;
      if (gig.isRecurring) {
        return gig.recurrenceEndDate == null ||
            gig.recurrenceEndDate!.isAfter(now);
      }
      return gig.dateTime.isAfter(now);
    }).toList();

    // Sort by next display date.
    upcomingGigs.sort((a, b) {
      final aDate = a.isRecurring ? _nextOccurrence(a, now) : a.dateTime;
      final bDate = b.isRecurring ? _nextOccurrence(b, now) : b.dateTime;
      return aDate.compareTo(bDate);
    });

    if (upcomingGigs.isEmpty) {
      return '<div class="gigs-container"><p>No upcoming shows. Check back soon!</p></div>';
    }

    // 2. Generate the HTML for each gig.
    final gigListItems = upcomingGigs.map((gig) {
      // For recurring gigs show the next upcoming occurrence, not the base date.
      final displayDate =
      gig.isRecurring ? _nextOccurrence(gig, now) : gig.dateTime;

      final date = DateFormat.yMMMEd().format(displayDate);
      final time = DateFormat.jm().format(displayDate);
      final recurringLabel = gig.isRecurring ? ' <em>(recurring)</em>' : '';
      final googleMapsUrl =
          'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(gig.address)}';

      return '''
        <div class="gig-item">
            <p class="gig-date"><strong>When:</strong> $date at $time$recurringLabel</p>
            <p class="gig-venue"><strong>Where:</strong> ${gig.venueName}</p>
            <p class="gig-address"><a href="$googleMapsUrl" target="_blank" rel="noopener noreferrer">${gig.address}</a></p>
        </div>''';
    }).join('\n');

    // 3. Combine CSS styles and the gig list into a final HTML block.
    return '''
<style>
    .gigs-container {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
        border: 1px solid #ddd;
        border-radius: 8px;
        padding: 16px;
        max-width: 600px;
        margin: 20px auto;
        background-color: #f9f9f9;
    }
    .gigs-header {
        font-size: 24px;
        font-weight: bold;
        margin-bottom: 16px;
        color: #333;
    }
    .gig-item {
        border-bottom: 1px solid #eee;
        padding: 12px 0;
    }
    .gig-item:last-child {
        border-bottom: none;
    }
    .gig-item p {
        margin: 4px 0;
        color: #555;
    }
    .gig-item .gig-date, .gig-item .gig-venue {
        font-size: 16px;
    }
    .gig-item .gig-address a {
        color: #007bff;
        text-decoration: none;
    }
    .gig-item .gig-address a:hover {
        text-decoration: underline;
    }
</style>
<div class="gigs-container">
    <h2 class="gigs-header">Upcoming Shows</h2>
    \$gigListItems
</div>
''';
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // NEXT OCCURRENCE CALCULATOR
  // ─────────────────────────────────────────────────────────────────────────────

  /// Returns the next future occurrence of a recurring gig on or after [now].
  static DateTime _nextOccurrence(Gig gig, DateTime now) {
    final hour = gig.dateTime.hour;
    final minute = gig.dateTime.minute;

    switch (gig.recurrenceFrequency) {
      case JamFrequencyType.weekly:
      // Next occurrence of the target weekday (DayOfWeek.index 0=Mon matches DateTime.weekday 1=Mon)
        return _nextWeekday(gig.recurrenceDay!.index + 1, hour, minute, now);

      case JamFrequencyType.biWeekly:
      // Advance the base date by 2-week intervals until past now.
        return _advanceByWeeks(gig.dateTime, 2, now);

      case JamFrequencyType.customNthDay:
        final interval = gig.recurrenceNthValue ?? 1;
        return _advanceByWeeks(gig.dateTime, interval, now);

      case JamFrequencyType.monthlySameDay:
        final nth = gig.recurrenceNthValue ?? 1;
        final targetWeekday = gig.recurrenceDay!.index + 1;
        // Try current month first; fall back to next month if already past.
        DateTime candidate =
        _nthWeekdayOfMonth(now.year, now.month, targetWeekday, nth, hour, minute);
        if (candidate.isBefore(now)) {
          final nextMonth = now.month == 12 ? 1 : now.month + 1;
          final nextYear = now.month == 12 ? now.year + 1 : now.year;
          candidate = _nthWeekdayOfMonth(
              nextYear, nextMonth, targetWeekday, nth, hour, minute);
        }
        return candidate;

      default:
      // Unknown frequency — fall back to base date so something is displayed.
        return gig.dateTime;
    }
  }

  /// Returns the next [weekday] (1=Mon…7=Sun) at [hour]:[minute] on or after [now].
  static DateTime _nextWeekday(
      int weekday, int hour, int minute, DateTime now) {
    DateTime candidate =
    DateTime(now.year, now.month, now.day, hour, minute);
    // Advance day-by-day until we land on the right weekday and it's in the future.
    while (candidate.weekday != weekday || !candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  /// Advances [base] by [weeks]-week steps until it is after [now].
  static DateTime _advanceByWeeks(DateTime base, int weeks, DateTime now) {
    DateTime candidate = base;
    final step = Duration(days: 7 * weeks);
    while (!candidate.isAfter(now)) {
      candidate = candidate.add(step);
    }
    return candidate;
  }

  /// Returns the [nth] occurrence of [weekday] in the given month at [hour]:[minute].
  /// If [nth] exceeds the occurrences in the month, returns the last one.
  static DateTime _nthWeekdayOfMonth(
      int year, int month, int weekday, int nth, int hour, int minute) {
    DateTime d = DateTime(year, month, 1, hour, minute);
    int count = 0;
    DateTime last = d;
    while (d.month == month) {
      if (d.weekday == weekday) {
        count++;
        last = d;
        if (count == nth) return d;
      }
      d = d.add(const Duration(days: 1));
    }
    return last; // nth doesn't exist this month — use last occurrence
  }
}