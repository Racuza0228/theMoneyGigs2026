// lib/features/gigs/services/gig_retrospective_service.dart

import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/core/models/enums.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';
import 'package:intl/intl.dart';

class GigRetrospectiveService {
  static const String _keyLastRetrospectiveCheck = 'last_retrospective_check';
  static const String _keySkippedGigs = 'skipped_retrospective_gigs';

  static Future<List<Gig>> getGigsNeedingRetrospective() async {
    final prefs = await SharedPreferences.getInstance();
    final gigsJsonString = prefs.getString('gigs_list') ?? '[]';
    final List<Gig> allGigs = Gig.decode(gigsJsonString);
    if (allGigs.isEmpty) return [];

    final skippedGigIds = prefs.getStringList(_keySkippedGigs) ?? [];
    final now = DateTime.now();

    // Track IDs of already-materialized recurring instances so we don't
    // double-count them when we also generate virtual ones below.
    final materializedInstanceIds = allGigs
        .where((g) => g.isFromRecurring && !g.isRecurring)
        .map((g) => g.id)
        .toSet();

    final List<Gig> candidates = [];

    for (final gig in allGigs) {
      if (gig.isRecurring) {
        // ✅ NEVER check the base template directly.
        // Generate the past virtual instances and check those instead.
        final pastInstances = _generatePastInstances(gig, now);
        for (final instance in pastInstances) {
          if (!materializedInstanceIds.contains(instance.id)) {
            candidates.add(instance);
          }
        }
      } else {
        // Non-recurring gig or already-materialized instance — check directly.
        candidates.add(gig);
      }
    }

    final needsReview = candidates
        .where((g) => g.needsRetrospective && !skippedGigIds.contains(g.id))
        .toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

    return needsReview;
  }

  /// Generates past occurrences of a recurring gig within a 30-day lookback.
  /// Each instance has gigRatings and retrospectiveCompleted reset to null.
  static List<Gig> _generatePastInstances(Gig baseGig, DateTime now) {
    if (!baseGig.isRecurring ||
        baseGig.recurrenceFrequency == null ||
        baseGig.recurrenceDay == null) return [];

    final instances = <Gig>[];
    final lookbackStart = now.subtract(const Duration(days: 30));
    final seriesStart = DateTime(
      baseGig.dateTime.year,
      baseGig.dateTime.month,
      baseGig.dateTime.day,
    );

    // Start from whichever is later: 30 days ago or when the series began
    DateTime current = lookbackStart.isAfter(seriesStart)
        ? DateTime(lookbackStart.year, lookbackStart.month, lookbackStart.day)
        : seriesStart;

    while (!current.isAfter(now)) {
      final gigDateTime = DateTime(
        current.year,
        current.month,
        current.day,
        baseGig.dateTime.hour,
        baseGig.dateTime.minute,
      );

      final isException = baseGig.recurrenceExceptions
          ?.any((e) => _isSameDay(e, current)) ??
          false;
      final afterEndDate = baseGig.recurrenceEndDate != null &&
          current.isAfter(baseGig.recurrenceEndDate!);

      if (!isException &&
          !afterEndDate &&
          gigDateTime.isBefore(now) &&
          _isOccurrenceDate(baseGig, current)) {
        final id =
            '${baseGig.id}_${DateFormat('yyyyMMdd').format(gigDateTime)}';

        // ✅ Full constructor — copyWith cannot null out nullable fields
        instances.add(Gig(
          id: id,
          venueName: baseGig.venueName,
          bandName: baseGig.bandName,
          latitude: baseGig.latitude,
          longitude: baseGig.longitude,
          address: baseGig.address,
          placeId: baseGig.placeId,
          dateTime: gigDateTime,
          pay: baseGig.pay,
          otherExpenses: baseGig.otherExpenses,
          tipsAmount: null,
          gigLengthHours: baseGig.gigLengthHours,
          driveSetupTimeHours: baseGig.driveSetupTimeHours,
          rehearsalLengthHours: baseGig.rehearsalLengthHours,
          isJamOpenMic: baseGig.isJamOpenMic,
          notes: null,
          notesUrl: baseGig.notesUrl,
          setlistId: baseGig.setlistId,
          isRecurring: false,
          isFromRecurring: true,
          recurrenceFrequency: baseGig.recurrenceFrequency,
          recurrenceDay: baseGig.recurrenceDay,
          recurrenceNthValue: baseGig.recurrenceNthValue,
          recurrenceEndDate: baseGig.recurrenceEndDate,
          recurrenceExceptions: [],
          gigRatings: null,             // ✅ Critical — always clean for new instance
          retrospectiveCompleted: null, // ✅ Critical — always clean for new instance
        ));
      }

      current = current.add(const Duration(days: 1));
    }

    return instances;
  }

  static bool _isOccurrenceDate(Gig baseGig, DateTime date) {
    final targetWeekday = baseGig.recurrenceDay!.index + 1; // Mon=1..Sun=7
    if (date.weekday != targetWeekday) return false;

    switch (baseGig.recurrenceFrequency!) {
      case JamFrequencyType.weekly:
        return true;

      case JamFrequencyType.biWeekly:
        final anchor = DateTime(
          baseGig.dateTime.year,
          baseGig.dateTime.month,
          baseGig.dateTime.day,
        );
        final weeksDiff =
            date.difference(anchor).inDays ~/ 7;
        return weeksDiff >= 0 && weeksDiff % 2 == 0;

      case JamFrequencyType.monthlySameDate:
        return date.day == baseGig.dateTime.day;

      case JamFrequencyType.monthlySameDay:
      case JamFrequencyType.customNthDay:
        if (baseGig.recurrenceNthValue == null) return false;
        int count = 0;
        for (int d = 1; d <= date.day; d++) {
          if (DateTime(date.year, date.month, d).weekday == targetWeekday) {
            count++;
          }
        }
        return count == baseGig.recurrenceNthValue;
    }
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // ── All methods below are unchanged ──────────────────────────────────────

  static Future<void> skipGigRetrospective(String gigId) async {
    final prefs = await SharedPreferences.getInstance();
    final skippedGigIds = prefs.getStringList(_keySkippedGigs) ?? [];
    if (!skippedGigIds.contains(gigId)) {
      skippedGigIds.add(gigId);
      await prefs.setStringList(_keySkippedGigs, skippedGigIds);
    }
  }

  static Future<void> clearSkippedGigs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySkippedGigs);
  }

  static Future<bool> shouldShowRetrospectivePrompt() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCheckString = prefs.getString(_keyLastRetrospectiveCheck);
    if (lastCheckString == null) return true;
    final lastCheck = DateTime.parse(lastCheckString);
    final daysSinceLastCheck = DateTime.now().difference(lastCheck).inDays;
    return daysSinceLastCheck >= 1;
  }

  static Future<void> recordRetrospectivePromptShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _keyLastRetrospectiveCheck, DateTime.now().toIso8601String());
  }

  static Future<Gig?> checkForRetrospectiveOnStartup() async {
    if (!await shouldShowRetrospectivePrompt()) return null;
    final gigsNeedingReview = await getGigsNeedingRetrospective();
    if (gigsNeedingReview.isEmpty) return null;
    await recordRetrospectivePromptShown();
    return gigsNeedingReview.first;
  }
}