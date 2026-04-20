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
// Called when a notification action button is tapped while the app is killed.
// For plain notification taps, Android's launch intent opens the app instead.
@pragma('vm:entry-point')
void onBackgroundNotificationResponse(NotificationResponse response) {
  // No-op for now. The OS launch intent handles bringing the app to the
  // foreground. Add deep-link routing here if needed in the future.
}

class NotificationService {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('app_icon');

    const DarwinInitializationSettings initializationSettingsIOS =
    DarwinInitializationSettings();

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      // Fires when a notification is tapped while the app is in the foreground.
      // When the app is in the background or killed, Android's launch intent
      // handles bringing it to the front automatically.
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        print('🔔 Notification tapped (foreground): '
            'id=${response.id}, payload=${response.payload}');
        // Future: use payload to navigate to the right screen
        // e.g. 'retrospective:gig_id' → open retrospective flow
      },
      onDidReceiveBackgroundNotificationResponse: onBackgroundNotificationResponse,
    );

    tz.initializeTimeZones();
    final String currentTimeZone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(currentTimeZone));
  }

  /// Reschedules notifications for every non-jam gig based on current settings.
  /// Call this when notification settings change.
  Future<void> updateAllGigNotifications() async {
    print("--- 🔄 Starting batch update of all gig notifications ---");
    final prefs = await SharedPreferences.getInstance();

    final String? gigsJson = prefs.getString('gigs_list');
    if (gigsJson == null || gigsJson.isEmpty) {
      print("--- No gigs found. Aborting notification update. ---");
      return;
    }
    final List<Gig> allGigs = Gig.decode(gigsJson);

    final bool shouldNotifyOnDay  = prefs.getBool('notify_on_day_of_gig') ?? false;
    final bool shouldNotifyAfter  = prefs.getBool('notify_after_gig') ?? true;
    final int? daysBefore         = prefs.getInt('notify_days_before');

    final now = DateTime.now();
    int scheduledCount = 0;
    int cancelledCount = 0;

    for (final gig in allGigs.where((g) => !g.isJamOpenMic)) {
      if (gig.isRecurring) continue;
      final int base = gig.id.hashCode;
      final gigTime = DateFormat.jm().format(gig.dateTime);
      final gigDay = DateTime(
          gig.dateTime.year, gig.dateTime.month, gig.dateTime.day);

      // ── Day-of (9am on gig day) ──────────────────────────────────────────
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

      // ── Days-before (9am N days before gig) ──────────────────────────────
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

      // ── Day-after retrospective (9am the morning after the gig) ──────────
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

  Future<bool> requestPermissions() async {
    bool allGranted = true;

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    final androidPlugin = flutterLocalNotificationsPlugin
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

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload, // e.g. 'day_of:gig_id', 'retrospective:gig_id'
  }) async {
    try {
      // Check exact alarm permission before attempting to schedule
      final androidPlugin = flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        final bool? canSchedule =
        await androidPlugin.canScheduleExactNotifications();

        if (canSchedule != true) {
          print('  ⚠️ Exact alarms not permitted. Requesting permission...');
          await androidPlugin.requestExactAlarmsPermission();
          // Re-check after request
          final bool? nowCanSchedule =
          await androidPlugin.canScheduleExactNotifications();
          if (nowCanSchedule != true) {
            print('  ❌ Exact alarm permission denied. Skipping notification ID: $id');
            return; // Exit cleanly, no freeze
          }
        }
      }

      print("--- Scheduling notification ---");
      print("  ID: $id | Title: $title");
      print("  At: $scheduledDate | Payload: $payload");

      final tz.TZDateTime scheduledTZDate =
      tz.TZDateTime.from(scheduledDate, tz.local);

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledTZDate,
        const NotificationDetails(
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
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );

      print("  ✅ Scheduled successfully.");
    } catch (e) {
      print("  ❌ Error scheduling notification: $e");
    }
  }

  Future<void> cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
    print("🔔 Cancelled notification ID: $id");
  }

  Future<void> debugPendingNotifications() async {
    final List<PendingNotificationRequest> pendingRequests =
    await flutterLocalNotificationsPlugin.pendingNotificationRequests();

    if (pendingRequests.isEmpty) {
      print("--- 🧐 PENDING NOTIFICATIONS: None found. ---");
      return;
    }

    print("--- 🧐 PENDING NOTIFICATIONS (${pendingRequests.length} found) ---");
    for (final request in pendingRequests) {
      print("  ID: ${request.id} | ${request.title} | ${request.payload}");
    }
    print("------------------------------------------------------");
  }
}