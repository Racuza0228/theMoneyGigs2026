// lib/core/services/notification_service.dart

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';
import 'package:the_money_gigs/core/models/enums.dart'; // NEW: for JamFrequencyType, DayOfWeek
import 'package:intl/intl.dart';
import 'package:the_money_gigs/core/utils/logger.dart';

// ── Top-level background tap handler ─────────────────────────────────────────
// Must be top-level (not a class method) and annotated for the VM.
@pragma('vm:entry-point')
void onBackgroundNotificationResponse(NotificationResponse response) {
  // No-op for now. Add deep-link routing here if needed in the future.
}

class NotificationService {
  // ── Singleton ─────────────────────────────────────────────────────────────
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // ── Recurrence config ──────────────────────────────────────────────────────
  // Look ahead this many days when expanding recurring gig instances.
  // iOS caps pending notifications at 64; Android at 500.
  // At 8 instances * 3 notifications per gig, 3 recurring gigs = 72
  // (iOS drops farthest-out ones — acceptable; nearest gigs always fire).
  static const int _lookAheadDays = 90;
  static const int _maxInstancesPerRecurringGig = 8;

  // ── init ───────────────────────────────────────────────────────────────────
  Future<void> init() async {
    if (_initialized) return;

    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('app_icon');

    const DarwinInitializationSettings iosSettings =
    DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
      defaultPresentBanner: true,
      defaultPresentList: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        log('🔔 Notification tapped (foreground): '
            'id=${response.id}, payload=${response.payload}');
      },
      onDidReceiveBackgroundNotificationResponse:
      onBackgroundNotificationResponse,
    );

    tz.initializeTimeZones();
    final String currentTimeZone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(currentTimeZone));

    _initialized = true;
    log('✅ NotificationService initialized. Timezone: $currentTimeZone');
  }

  // ── requestPermissions ─────────────────────────────────────────────────────
  Future<bool> requestPermissions() async {
    bool allGranted = true;

    await _plugin
        .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();

    final bool? canScheduleExact =
    await androidPlugin?.canScheduleExactNotifications();

    if (canScheduleExact != true) {
      log('⚠️ Exact alarm permission not granted after request.');
      allGranted = false;
    }

    return allGranted;
  }

  // ── scheduleNotification ───────────────────────────────────────────────────
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
  }) async {
    try {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        final bool? canSchedule =
        await androidPlugin.canScheduleExactNotifications();
        if (canSchedule != true) {
          log('  ⚠️ Exact alarms not permitted. Requesting...');
          await androidPlugin.requestExactAlarmsPermission();
          final bool? nowCanSchedule =
          await androidPlugin.canScheduleExactNotifications();
          if (nowCanSchedule != true) {
            log('  ❌ Exact alarm permission denied. Skipping ID: $id');
            return;
          }
        }
      }

      log("--- Scheduling notification ---");
      log("  ID: $id | Title: $title");
      log("  At: $scheduledDate | Payload: $payload");

      final tz.TZDateTime scheduledTZDate =
      tz.TZDateTime.from(scheduledDate, tz.local);

      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledTZDate,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'gig_channel_id',
            'Gig Reminders',
            channelDescription: 'Notifications for upcoming gigs',
            importance: Importance.max,
            priority: Priority.high,
            ticker: 'ticker',
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        payload: payload,
      );

      log("  ✅ Scheduled successfully.");
    } catch (e) {
      log("  ❌ Error scheduling notification: $e");
    }
  }

  // ── cancelNotification ─────────────────────────────────────────────────────
  Future<void> cancelNotification(int id) async {
    await _plugin.cancel(id: id);
    log("🔔 Cancelled notification ID: $id");
  }

  // ── debugScheduleTestNotifications ────────────────────────────────────────
  /// DEBUG ONLY — remove before release.
  Future<void> debugScheduleTestNotifications(Gig gig) async {
    final now = DateTime.now();
    log('🧪 Scheduling test notifications for: ${gig.venueName}');

    await scheduleNotification(
      id: 9001,
      title: 'You have a gig today! [TEST]',
      body: 'Day-of test for ${gig.venueName}',
      scheduledDate: now.add(const Duration(seconds: 5)),
      payload: 'day_of:${gig.id}',
    );
    await scheduleNotification(
      id: 9002,
      title: 'Upcoming gig reminder [TEST]',
      body: 'Days-before test for ${gig.venueName}',
      scheduledDate: now.add(const Duration(seconds: 10)),
      payload: 'days_before:${gig.id}',
    );
    await scheduleNotification(
      id: 9003,
      title: 'How was the gig? [TEST]',
      body: 'Day-after test for ${gig.venueName}',
      scheduledDate: now.add(const Duration(seconds: 15)),
      payload: 'retrospective:${gig.id}',
    );

    await debugPendingNotifications();
  }

  // ── updateAllGigNotifications ──────────────────────────────────────────────
  /// Clears all existing notifications and reschedules from scratch based on
  /// current settings. Handles both one-off and recurring gigs.
  Future<void> updateAllGigNotifications() async {
    log("--- 🔄 Starting batch update of all gig notifications ---");

    // Cancel everything first — cleanest way to handle setting changes and
    // stale recurring entries without tracking individual IDs.
    await _plugin.cancelAll();
    log("  🗑️ Cleared all existing notifications.");

    final prefs = await SharedPreferences.getInstance();
    final String? gigsJson = prefs.getString('gigs_list');
    if (gigsJson == null || gigsJson.isEmpty) {
      log("--- No gigs found. Aborting. ---");
      return;
    }

    final List<Gig> allGigs = Gig.decode(gigsJson);
    final bool shouldNotifyOnDay =
        prefs.getBool('notify_on_day_of_gig') ?? false;
    final bool shouldNotifyAfter = prefs.getBool('notify_after_gig') ?? true;
    final int? daysBefore = prefs.getInt('notify_days_before');
    final now = DateTime.now();
    int scheduledCount = 0;

    for (final gig in allGigs.where((g) => !g.isJamOpenMic)) {
      // Expand to one entry for one-off gigs, N entries for recurring gigs.
      final List<DateTime> instances = gig.isRecurring
          ? _expandRecurringDates(gig)
          : [gig.dateTime];

      if (gig.isRecurring) {
        log('  🔁 Recurring gig "${gig.venueName}": '
            '${instances.length} instance(s) in window.');
      }

      for (final instanceDate in instances) {
        final gigTime = DateFormat.jm().format(instanceDate);
        final gigDay =
        DateTime(instanceDate.year, instanceDate.month, instanceDate.day);

        // Derive a stable, unique ID for this (gig, instance) pair.
        // Multiplied by 3 to reserve slots +0 (day-of), +1 (before), +2 (after).
        final int base = _notificationBaseId(gig.id, instanceDate);

        // ── Day-of (9 AM on gig day) ─────────────────────────────────────────
        final dayOfTime =
        DateTime(gigDay.year, gigDay.month, gigDay.day, 9, 0);
        if (shouldNotifyOnDay && dayOfTime.isAfter(now)) {
          await scheduleNotification(
            id: base,
            title: 'You have a gig today!',
            body: 'Gig at ${gig.venueName} at $gigTime!',
            scheduledDate: dayOfTime,
            payload: 'day_of:${gig.id}',
          );
          scheduledCount++;
        }

        // ── Days-before (9 AM, N days before gig) ────────────────────────────
        if (daysBefore != null && daysBefore > 0) {
          final beforeDate = instanceDate.subtract(Duration(days: daysBefore));
          final beforeTime = DateTime(
              beforeDate.year, beforeDate.month, beforeDate.day, 9, 0);
          if (beforeTime.isAfter(now)) {
            await scheduleNotification(
              id: base + 1,
              title: 'Upcoming gig reminder',
              body: 'Your gig at ${gig.venueName} is in '
                  '$daysBefore day${daysBefore > 1 ? 's' : ''} '
                  'on ${DateFormat.yMMMEd().format(instanceDate)} at $gigTime.',
              scheduledDate: beforeTime,
              payload: 'days_before:${gig.id}',
            );
            scheduledCount++;
          }
        }

        // ── Day-after retrospective (9 AM the morning after the gig) ─────────
        final afterGigDate = gigDay.add(const Duration(days: 1));
        final afterTime = DateTime(
            afterGigDate.year, afterGigDate.month, afterGigDate.day, 9, 0);
        if (shouldNotifyAfter && afterTime.isAfter(now)) {
          await scheduleNotification(
            id: base + 2,
            title: 'How was the gig?',
            body: 'How did the gig at ${gig.venueName} go?',
            scheduledDate: afterTime,
            payload: 'retrospective:${gig.id}',
          );
          scheduledCount++;
        }
      }
    }

    log("--- ✅ Batch update complete. Scheduled: $scheduledCount ---");
  }

  // ── debugPendingNotifications ──────────────────────────────────────────────
  Future<void> debugPendingNotifications() async {
    final List<PendingNotificationRequest> pendingRequests =
    await _plugin.pendingNotificationRequests();

    if (pendingRequests.isEmpty) {
      log("--- 🧐 PENDING NOTIFICATIONS: None found. ---");
      // Note: on iOS, pendingNotificationRequests() only returns notifications
      // scheduled in the current app session. May show empty even when the OS
      // has them queued correctly.
      return;
    }

    log(
        "--- 🧐 PENDING NOTIFICATIONS (${pendingRequests.length} found) ---");
    for (final request in pendingRequests) {
      log("  ID: ${request.id} | ${request.title} | ${request.payload}");
    }
    log("------------------------------------------------------");
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RECURRENCE EXPANSION
  // ══════════════════════════════════════════════════════════════════════════

  /// Returns a list of future DateTime instances for a recurring gig within
  /// the look-ahead window, capped at [_maxInstancesPerRecurringGig].
  ///
  /// DayOfWeek enum mapping (matches recurring_gig_dialog.dart):
  ///   DayOfWeek.values[dateTime.weekday - 1]
  ///   → index 0 = Monday ... index 6 = Sunday
  ///   → matches DateTime.weekday (Mon=1 ... Sun=7) via index + 1
  List<DateTime> _expandRecurringDates(Gig gig) {
    final now = DateTime.now();
    final horizon = now.add(const Duration(days: _lookAheadDays));

    // Respect the user-set end date if it falls before the horizon.
    final endDate = gig.recurrenceEndDate;
    final cutoff =
    (endDate != null && endDate.isBefore(horizon)) ? endDate : horizon;

    final frequency = gig.recurrenceFrequency ?? JamFrequencyType.weekly;
    final int hour = gig.dateTime.hour;
    final int minute = gig.dateTime.minute;

    final List<DateTime> results = [];

    switch (frequency) {
      case JamFrequencyType.weekly:
        _generateByInterval(
            gig.dateTime, 7, hour, minute, now, cutoff, results);

      case JamFrequencyType.biWeekly:
        _generateByInterval(
            gig.dateTime, 14, hour, minute, now, cutoff, results);

      case JamFrequencyType.customNthDay:
      // "Every Nth week" — recurrenceNthValue holds N.
        final int n = gig.recurrenceNthValue ?? 1;
        _generateByInterval(
            gig.dateTime, 7 * n, hour, minute, now, cutoff, results);

      case JamFrequencyType.monthlySameDate:
      // Same calendar date each month (e.g., always the 14th).
        _generateMonthlySameDate(
            gig.dateTime, hour, minute, now, cutoff, results);

      case JamFrequencyType.monthlySameDay:
      // Nth weekday of each month (e.g., 2nd Tuesday).
      // recurrenceDay  → which weekday
      // recurrenceNthValue → which occurrence in the month (1–4)
        final DayOfWeek day =
            gig.recurrenceDay ?? DayOfWeek.values[gig.dateTime.weekday - 1];
        final int nth =
            gig.recurrenceNthValue ?? _getWeekOfMonth(gig.dateTime);
        _generateMonthlySameDay(
            day, nth, hour, minute, now, cutoff, results);
    }

    return results;
  }

  // ── Interval-based (weekly / biweekly / every-nth-week) ───────────────────
  void _generateByInterval(
      DateTime baseDate,
      int intervalDays,
      int hour,
      int minute,
      DateTime now,
      DateTime cutoff,
      List<DateTime> results,
      ) {
    // Rebuild base at the correct time-of-day (dateTime may carry gig time).
    DateTime current =
    DateTime(baseDate.year, baseDate.month, baseDate.day, hour, minute);

    // Fast-forward to the first future occurrence.
    while (!current.isAfter(now)) {
      current = current.add(Duration(days: intervalDays));
    }

    while (!current.isAfter(cutoff) &&
        results.length < _maxInstancesPerRecurringGig) {
      results.add(current);
      current = current.add(Duration(days: intervalDays));
    }
  }

  // ── Monthly by date (e.g., always the 14th) ───────────────────────────────
  void _generateMonthlySameDate(
      DateTime baseDate,
      int hour,
      int minute,
      DateTime now,
      DateTime cutoff,
      List<DateTime> results,
      ) {
    final int dayOfMonth = baseDate.day;

    // Start scanning from the current month.
    int year = now.year;
    int month = now.month;

    while (results.length < _maxInstancesPerRecurringGig) {
      final int daysInThisMonth = _daysInMonth(year, month);

      if (dayOfMonth <= daysInThisMonth) {
        final candidate = DateTime(year, month, dayOfMonth, hour, minute);
        if (candidate.isAfter(now)) {
          if (candidate.isAfter(cutoff)) break;
          results.add(candidate);
        }
      }
      // Advance one month.
      month++;
      if (month > 12) {
        month = 1;
        year++;
      }
      // Safety: stop if we've gone past the cutoff year.
      if (DateTime(year, month, 1).isAfter(cutoff)) break;
    }
  }

  // ── Monthly by weekday (e.g., 2nd Tuesday) ────────────────────────────────
  void _generateMonthlySameDay(
      DayOfWeek day,
      int nthOccurrence,
      int hour,
      int minute,
      DateTime now,
      DateTime cutoff,
      List<DateTime> results,
      ) {
    // DayOfWeek.index 0=Mon...6=Sun → DateTime.weekday 1=Mon...7=Sun
    final int targetWeekday = day.index + 1;

    int year = now.year;
    int month = now.month;

    while (results.length < _maxInstancesPerRecurringGig) {
      final DateTime? candidate = _getNthWeekdayOfMonth(
          year, month, targetWeekday, nthOccurrence, hour, minute);

      if (candidate != null && candidate.isAfter(now)) {
        if (candidate.isAfter(cutoff)) break;
        results.add(candidate);
      }

      month++;
      if (month > 12) {
        month = 1;
        year++;
      }
      if (DateTime(year, month, 1).isAfter(cutoff)) break;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Returns the DateTime of the [nth] occurrence (1-based) of [targetWeekday]
  /// (1=Mon...7=Sun) within [year]/[month], or null if the month doesn't have
  /// that many occurrences (e.g., asking for the 5th Tuesday in February).
  DateTime? _getNthWeekdayOfMonth(
      int year,
      int month,
      int targetWeekday,
      int nth,
      int hour,
      int minute,
      ) {
    final DateTime firstOfMonth = DateTime(year, month, 1);
    // Days until the first targetWeekday in this month (0 if day 1 matches).
    final int daysUntilFirst =
        (targetWeekday - firstOfMonth.weekday + 7) % 7;
    final DateTime firstOccurrence =
    firstOfMonth.add(Duration(days: daysUntilFirst));

    // Jump to the Nth occurrence.
    final DateTime nthOccurrence =
    firstOccurrence.add(Duration(days: 7 * (nth - 1)));

    // Ensure we haven't rolled into the next month.
    if (nthOccurrence.month != month) return null;

    return DateTime(
        nthOccurrence.year, nthOccurrence.month, nthOccurrence.day,
        hour, minute);
  }

  /// Returns the number of days in a given [year]/[month].
  /// Uses the trick: day 0 of the next month == last day of this month.
  int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  /// Returns which week-of-month (1-based) a date falls in, relative to the
  /// first occurrence of that weekday in the month.
  /// Used to infer [recurrenceNthValue] when not explicitly set.
  int _getWeekOfMonth(DateTime date) {
    final DateTime firstOfMonth = DateTime(date.year, date.month, 1);
    final int daysUntilWeekday =
        (date.weekday - firstOfMonth.weekday + 7) % 7;
    final int firstOccurrenceDay = 1 + daysUntilWeekday;
    return ((date.day - firstOccurrenceDay) ~/ 7) + 1;
  }

  /// Derives a deterministic, unique notification base ID for a (gig, instance)
  /// pair. Multiplied by 3 to reserve consecutive slots for:
  ///   base + 0 → day-of
  ///   base + 1 → days-before
  ///   base + 2 → day-after retrospective
  ///
  /// Range: 0..899_997. Safe for both Android (32-bit int) and iOS.
  int _notificationBaseId(String gigId, DateTime instanceDate) {
    final String key = '${gigId}_${instanceDate.millisecondsSinceEpoch}';
    return (key.hashCode.abs() % 300000) * 3;
  }
}