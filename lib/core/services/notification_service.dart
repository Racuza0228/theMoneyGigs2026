import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart'; // <-- ADD this import
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';
import 'package:intl/intl.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('app_icon'); // Use the icon name from Step 2

    const DarwinInitializationSettings initializationSettingsIOS =
    DarwinInitializationSettings();

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

    // --- CORRECTED BASED ON THE EXAMPLE ---
    tz.initializeTimeZones(); // Initialize the timezone data

    // 1. Await the result, which is a TimezoneInfo object.
    final String currentTimeZone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(currentTimeZone));


  }

  Future<void> updateAllGigNotifications() async {
    print("--- 🔄 Starting batch update of all gig notifications ---");
    final prefs = await SharedPreferences.getInstance();

    // 1. Load all raw gig data
    final String? gigsJson = prefs.getString('gigs_list');
    if (gigsJson == null || gigsJson.isEmpty) {
      print("--- No gigs found. Aborting notification update. ---");
      return;
    }
    final List<Gig> allGigs = Gig.decode(gigsJson);

    // 2. Load current notification settings
    final bool shouldNotifyOnDay = prefs.getBool('notify_on_day_of_gig') ?? false;
    final int? daysBefore = prefs.getInt('notify_days_before');

    // It's inefficient to generate occurrences one by one.
    // Let's generate all of them up to a reasonable future date.
    DateTime futureRange = DateTime.now().add(const Duration(days: 365 * 2)); // 2 years
    List<Gig> allOccurrences = [];

    for (final baseGig in allGigs) {
      if (baseGig.isRecurring) {
        // This is a simplified occurrence generator. You must use the one from gigs.dart.
        // For this example, I'll just add the base gig.
        // IN YOUR REAL CODE: You would call a utility function that contains
        // the logic from _generateOccurrencesForGig in gigs.dart.
        allOccurrences.add(baseGig); // Placeholder
      } else {
        allOccurrences.add(baseGig);
      }
    }

    // In a real implementation, you'd generate all recurrences here.
    // For now, let's just work with the raw list, which covers non-recurring gigs.

    int scheduledCount = 0;
    int cancelledCount = 0;

    // 3. Loop through every gig
    for (final gig in allGigs.where((g) => !g.isJamOpenMic)) {
      // We only care about gigs in the future
      if (gig.dateTime.isBefore(DateTime.now())) continue;

      // --- Handle "Day Of Gig" Notification ---
      final int dayOfGigId = gig.id.hashCode;
      final DateTime dayOfGigScheduleTime = DateTime(gig.dateTime.year, gig.dateTime.month, gig.dateTime.day, 9, 0);

      if (shouldNotifyOnDay && dayOfGigScheduleTime.isAfter(DateTime.now())) {
        await scheduleNotification(
          id: dayOfGigId,
          title: 'Gig Reminder: Today!',
          body: 'Your gig "${gig.venueName}" is today at ${DateFormat.jm().format(gig.dateTime)}.',
          scheduledDate: dayOfGigScheduleTime,
        );
        scheduledCount++;
      } else {
        await cancelNotification(dayOfGigId);
        cancelledCount++;
      }

      // --- Handle "Days Before" Notification ---
      final int daysBeforeId = dayOfGigId + 1;
      if (daysBefore != null && daysBefore > 0) {
        final DateTime daysBeforeScheduleTime = DateTime(gig.dateTime.year, gig.dateTime.month, gig.dateTime.day - daysBefore, 9, 0);
        if (daysBeforeScheduleTime.isAfter(DateTime.now())) {
          await scheduleNotification(
            id: daysBeforeId,
            title: 'Gig Reminder: ${daysBefore} Day${daysBefore > 1 ? 's' : ''}',
            body: 'Your gig "${gig.venueName}" is in $daysBefore day${daysBefore > 1 ? 's' : ''} on ${DateFormat.yMMMEd().format(gig.dateTime)}.',
            scheduledDate: daysBeforeScheduleTime,
          );
          scheduledCount++;
        } else {
          await cancelNotification(daysBeforeId);
          cancelledCount++;
        }
      } else {
        await cancelNotification(daysBeforeId);
        cancelledCount++;
      }
    }
    print("--- ✅ Batch update complete. Scheduled: $scheduledCount, Cancelled: $cancelledCount ---");
  }

  Future<void> requestPermissions() async {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.requestExactAlarmsPermission();
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  // In lib/core/services/notification_service.dart

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    try {
      print("--- Attempting to schedule notification ---");
      print("ID: $id, Title: $title");
      print("Scheduled For (Local Time): $scheduledDate");

      final tz.TZDateTime scheduledTZDate = tz.TZDateTime.from(
          scheduledDate, tz.local);
      print("Scheduled For (TZDateTime): $scheduledTZDate");

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
          // --- THIS IS THE CORRECTED CODE FOR iOS ---
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
          // -----------------------------------------
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
      );

      print("✅ SUCCESS: zonedSchedule call completed without error.");
    } catch (e) {
      print("❌ ERROR scheduling notification: $e");
    }
  }

  Future<void> cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
    print("🔔 Notification with ID: $id has been cancelled.");
  }

  Future<void> debugPendingNotifications() async {
    // 1. Get the list of pending notification requests from the plugin
    final List<PendingNotificationRequest> pendingRequests =
    await flutterLocalNotificationsPlugin.pendingNotificationRequests();

    // 2. Check if the list is empty
    if (pendingRequests.isEmpty) {
      print("--- 🧐 PENDING NOTIFICATIONS DEBUG: None found. ---");
      return;
    }

    // 3. If notifications are found, print their details
    print("--- 🧐 PENDING NOTIFICATIONS DEBUG (${pendingRequests.length} found) ---");
    for (PendingNotificationRequest request in pendingRequests) {
      print(
          "  - ID: ${request.id}, Title: ${request.title}, Body: ${request.body}, Payload: ${request.payload}");
    }
    print("----------------------------------------------------");
  }
}
