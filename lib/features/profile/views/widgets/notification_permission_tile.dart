// lib/features/profile/widgets/notification_permission_tile.dart
//
// Drop this widget into your Profile page wherever you want the notification
// opt-in to appear. It shows current status, lets the user request permission,
// and links to Settings if the OS has permanently denied it.
//
// Usage in profile.dart:
//   const NotificationPermissionTile(),

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:the_money_gigs/core/services/notification_service.dart';

class NotificationPermissionTile extends StatefulWidget {
  const NotificationPermissionTile({super.key});

  @override
  State<NotificationPermissionTile> createState() =>
      _NotificationPermissionTileState();
}

class _NotificationPermissionTileState
    extends State<NotificationPermissionTile> with WidgetsBindingObserver {
  // null = unknown (still loading)
  bool? _isGranted;
  bool _isPermanentlyDenied = false;
  bool _isRequesting = false;

  final _plugin = FlutterLocalNotificationsPlugin();

  AndroidFlutterLocalNotificationsPlugin? get _androidPlugin =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Re-check when the user returns from the OS Settings app
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkStatus();
  }

  Future<void> _checkStatus() async {
    final status = await Permission.notification.status;

    bool canScheduleExact = true;
    if (Platform.isAndroid) {
      canScheduleExact =
          await _androidPlugin?.canScheduleExactNotifications() ?? true;
    }

    if (!mounted) return;
    setState(() {
      _isGranted = status.isGranted && canScheduleExact;
      _isPermanentlyDenied = status.isPermanentlyDenied;
    });
    print('🔔 iOS status: isGranted=$_isGranted, isPermanentlyDenied=$_isPermanentlyDenied, isRequesting=$_isRequesting');

  }

  Future<void> _requestPermission() async {
    setState(() => _isRequesting = true);

    try {
      if (_isPermanentlyDenied) {
        // OS won't show a dialog — send them to app settings
        await openAppSettings();
      } else if (Platform.isIOS) {
        try {
          await Permission.notification.request()
              .timeout(const Duration(seconds: 5));
        } catch (_) {
          // Timed out or failed — proceed anyway
        }
        await _checkStatus();
      } else if (Platform.isAndroid) {
        await _androidPlugin?.requestNotificationsPermission();
        await _androidPlugin?.requestExactAlarmsPermission();
        final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
        if (!batteryStatus.isGranted) {
          await Permission.ignoreBatteryOptimizations.request();
        }
        await _checkStatus();
      }
    } finally {
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Loading state
    if (_isGranted == null) {
      return const ListTile(
        leading: Icon(Icons.notifications_outlined),
        title: Text('Gig Reminders'),
        trailing: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          secondary: Icon(
            _isGranted!
                ? Icons.notifications_active
                : Icons.notifications_off_outlined,
            color:
            _isGranted! ? theme.colorScheme.primary : Colors.grey.shade500,
          ),
          title: const Text('Gig Reminders'),
          subtitle: Text(_subtitle),
          value: _isGranted!,
          // Toggling OFF isn't possible programmatically on iOS/Android —
          // direct the user to Settings instead.
          onChanged: _isRequesting ? null : (bool value) async {
            if (_isGranted == true && !value) {
              final bool? confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Turn off reminders?'),
                  content: const Text(
                      'This will cancel all upcoming gig reminders and open your device settings to disable notifications.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('CANCEL')),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('TURN OFF')),
                  ],
                ),
              );
              if (confirm == true) {
                await _plugin.cancelAll();
                await openAppSettings();
                await _checkStatus();
              }
            } else {
              // Toggling ON — request permissions then reschedule all gigs
              await _requestPermission();
              if (_isGranted == true) {
                final notificationService = NotificationService();
                await notificationService.init();
                await notificationService.updateAllGigNotifications();
              }
            }
          },
        ),

        if (_isPermanentlyDenied)
          Padding(
            padding: const EdgeInsets.only(left: 72, right: 16, bottom: 8),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: 14, color: Colors.orange.shade300),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Notifications are blocked. Tap above to open Settings.',
                    style:
                    TextStyle(fontSize: 12, color: Colors.orange.shade300),
                  ),
                ),
              ],
            ),
          ),

        if (_isGranted!)
          Padding(
            padding: const EdgeInsets.only(left: 72, right: 16, bottom: 8),
            child: Text(
              'You\'ll be notified before upcoming gigs. Manage timing in the reminders section below.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
          ),

        Divider(color: Colors.grey.shade700, height: 1),
      ],
    );
  }

  String get _subtitle {
    if (_isPermanentlyDenied) return 'Blocked — tap to open Settings';
    if (_isGranted!) return 'Enabled';
    return 'Tap to enable reminders for upcoming gigs';
  }
}