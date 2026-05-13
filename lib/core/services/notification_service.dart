// lib/core/services/notification_service.dart

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';
import 'package:intl/intl.dart';

// ── Top-level background tap handler ─────────────────────────────────────────
// Must be top-level (not a class method) and annotated for the VM.
@pragma('vm:entry-point')
void onBackgroundNotificationResponse(NotificationResponse response) {
  // No-op for now. Add deep-link routing here if needed in the future.
}

class NotificationService {
  // ── Singleton ───────────────────────────────────────────────────────────────
  // Bug fix: previously every NotificationService() call created a fresh,
  // uninitialized plugin instance. A singleton ensures init() runs exactly once
  // and all callers share the same plugin state.
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // ── init ───────────────────────────────────────────────────────────────────
  Future<void> init() async {
    if (_initialized) return; // safe to call multiple times

    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('app_icon');

    // Bug fix: DarwinInitializationSettings was empty.
    // The defaultPresent* flags are required for iOS to display notifications
    // while the app is in the foreground. Without them iOS silently drops them.
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false, // we request explicitly via requestPermissions()
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

    // Bug fix: v21 requires `settings:` as a named parameter.
    // Previously: initialize(initializationSettings, ...)  ← positional, broken
    // Correct:    initialize(settings: initSettings, ...)  ← named, v21 API
    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        print('🔔 Notification tapped (foreground): '
            'id=${response.id}, payload=${response.payload}');
        // Future: use payload to navigate to the right screen
        // e.g. 'retrospective:gig_id' → open retrospective flow
      },
      onDidReceiveBackgroundNotificationResponse:
      onBackgroundNotificationResponse,
    );

    tz.initializeTimeZones();
    final String currentTimeZone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(currentTimeZone));

    _initialized = true;
    print('✅ NotificationService initialized. Timezone: $currentTimeZone');
  }

  // ── requestPermissions ─────────────────────────────────────────────────────
  Future<bool> requestPermissions() async {
    bool allGranted = true;

    await _plugin
        .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();

    final bool? canScheduleExact =
    await androidPlugin?.canScheduleExactNotifications();

    if (canScheduleExact != true) {
      print('⚠️ Exact alarm permission not granted after request.');
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
      // Check exact alarm permission on Android before scheduling
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        final bool? canSchedule =
        await androidPlugin.canScheduleExactNotifications();
        if (canSchedule != true) {
          print('  ⚠️ Exact alarms not permitted. Requesting...');
          await androidPlugin.requestExactAlarmsPermission();
          final bool? nowCanSchedule =
          await androidPlugin.canScheduleExactNotifications();
          if (nowCanSchedule != true) {
            print(
                '  ❌ Exact alarm permission denied. Skipping ID: $id');
            return;
          }
        }
      }

      print("--- Scheduling notification ---");
      print("  ID: $id | Title: $title");
      print("  At: $scheduledDate | Payload: $payload");

      final tz.TZDateTime scheduledTZDate =
      tz.TZDateTime.from(scheduledDate, tz.local);

      // Bug fix: `uiLocalNotificationDateInterpretation` was removed in v21.
      // It no longer exists as a parameter on zonedSchedule.
      // Bug fix: all parameters are now named in v21.
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

      print("  ✅ Scheduled successfully.");
    } catch (e) {
      print("  ❌ Error scheduling notification: $e");
    }
  }

  // ── cancelNotification ─────────────────────────────────────────────────────
  Future<void> cancelNotification(int id) async {
    // Bug fix: v21 requires `id:` as a named parameter.
    await _plugin.cancel(id: id);
    print("🔔 Cancelled notification ID: $id");
  }

  /// DEBUG ONLY — remove before release.
  /// Schedules all 3 notification types with short delays
  /// so you can verify the full pipeline without waiting for real gig dates.
  Future<void> debugScheduleTestNotifications(Gig gig) async {
    final now = DateTime.now();
    print('🧪 Scheduling test notifications for: ${gig.venueName}');

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
  /// Reschedules notifications for every non-jam gig based on current settings.
  /// Call this when notification settings change in the profile.
  Future<void> updateAllGigNotifications() async {
    print("--- 🔄 Starting batch update of all gig notifications ---");
    final prefs = await SharedPreferences.getInstance();

    final String? gigsJson = prefs.getString('gigs_list');
    if (gigsJson == null || gigsJson.isEmpty) {
      print("--- No gigs found. Aborting notification update. ---");
      return;
    }
    final List<Gig> allGigs = Gig.decode(gigsJson);

    final bool shouldNotifyOnDay = prefs.getBool('notify_on_day_of_gig') ?? false;
    final bool shouldNotifyAfter = prefs.getBool('notify_after_gig') ?? true;
    final int? daysBefore = prefs.getInt('notify_days_before');

    final now = DateTime.now();
    int scheduledCount = 0;
    int cancelledCount = 0;

    for (final gig in allGigs.where((g) => !g.isJamOpenMic)) {
      // TODO: Add support for recurring gig instances once the recurrence
      // expansion logic is available. For now, recurring gigs are skipped
      // to avoid scheduling against stale/incomplete date data.
      if (gig.isRecurring) continue;

      final int base = gig.id.hashCode;
      final gigTime = DateFormat.jm().format(gig.dateTime);
      final gigDay =
      DateTime(gig.dateTime.year, gig.dateTime.month, gig.dateTime.day);

      // ── Day-of (9am on gig day) ────────────────────────────────────────────
      final DateTime dayOfTime =
      DateTime(gigDay.year, gigDay.month, gigDay.day, 9, 0);
      if (shouldNotifyOnDay && dayOfTime.isAfter(now)) {
        await scheduleNotification(
          id: base,
          title: 'You have a gig today!',
          body: 'You have a gig today at ${gig.venueName} at $gigTime!',
          scheduledDate: dayOfTime,
          payload: 'day_of:${gig.id}',
        );
        scheduledCount++;
      } else {
        await cancelNotification(base);
        cancelledCount++;
      }

      // ── Days-before (9am N days before gig) ───────────────────────────────
      if (daysBefore != null && daysBefore > 0) {
        final DateTime beforeDate =
        gig.dateTime.subtract(Duration(days: daysBefore));
        final DateTime beforeTime = DateTime(
            beforeDate.year, beforeDate.month, beforeDate.day, 9, 0);
        if (beforeTime.isAfter(now)) {
          await scheduleNotification(
            id: base + 1,
            title: 'Upcoming gig reminder',
            body: 'Your gig at ${gig.venueName} is in '
                '$daysBefore day${daysBefore > 1 ? 's' : ''} '
                'on ${DateFormat.yMMMEd().format(gig.dateTime)} at $gigTime.',
            scheduledDate: beforeTime,
            payload: 'days_before:${gig.id}',
          );
          scheduledCount++;
        } else {
          await cancelNotification(base + 1);
          cancelledCount++;
        }
      } else {
        await cancelNotification(base + 1);
        cancelledCount++;
      }

      // ── Day-after retrospective (9am the morning after the gig) ───────────
      final DateTime afterGigDate = gigDay.add(const Duration(days: 1));
      final DateTime afterTime = DateTime(
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
      } else {
        await cancelNotification(base + 2);
        cancelledCount++;
      }
    }

    print("--- ✅ Batch update complete. "
        "Scheduled: $scheduledCount, Cancelled: $cancelledCount ---");
  }

  // ── debugPendingNotifications ──────────────────────────────────────────────
  Future<void> debugPendingNotifications() async {
    final List<PendingNotificationRequest> pendingRequests =
    await _plugin.pendingNotificationRequests();

    if (pendingRequests.isEmpty) {
      print("--- 🧐 PENDING NOTIFICATIONS: None found. ---");
      // Note: on iOS, pendingNotificationRequests() only returns notifications
      // scheduled via the plugin in the current app session. This may show
      // empty even when notifications ARE correctly queued in the OS.
      return;
    }

    print(
        "--- 🧐 PENDING NOTIFICATIONS (${pendingRequests.length} found) ---");
    for (final request in pendingRequests) {
      print("  ID: ${request.id} | ${request.title} | ${request.payload}");
    }
    print("------------------------------------------------------");
  }
}