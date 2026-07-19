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
import 'package:the_money_gigs/core/utils/logger.dart';

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

  IOSFlutterLocalNotificationsPlugin? get _iOSPlugin =>
      _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

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
    bool granted = false;
    bool permanentlyDenied = false;

    if (Platform.isIOS) {
      final settings = await _iOSPlugin?.checkPermissions();
      granted = settings?.isEnabled ?? false;
      // iOS doesn't reliably surface permanentlyDenied;
      // openAppSettings handles the blocked case gracefully.
      permanentlyDenied = false;
    } else if (Platform.isAndroid) {
      final status = await Permission.notification.status;
      final canScheduleExact =
          await _androidPlugin?.canScheduleExactNotifications() ?? true;
      granted = status.isGranted && canScheduleExact;
      permanentlyDenied = status.isPermanentlyDenied;
    }

    if (!context.mounted) return;
    setState(() {
      _isGranted = granted;
      _isPermanentlyDenied = permanentlyDenied;
    });
    log('🔔 Status check: isGranted=$_isGranted, '
        'isPermanentlyDenied=$_isPermanentlyDenied, '
        'platform=${Platform.isIOS ? "iOS" : "Android"}');
  }

  /// Shows an explanation dialog before redirecting to OS Settings.
  /// Returns true if the user chose to open Settings, false if they dismissed.
  Future<bool> _openSettingsWithExplanation(String reason) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Open Settings?'),
        content: Text(reason),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('NOT NOW'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('OPEN SETTINGS'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await openAppSettings();
      await _checkStatus();
      return true;
    }
    return false;
  }

  Future<void> _requestPermission() async {
    setState(() => _isRequesting = true);

    try {
      if (_isPermanentlyDenied) {
        // OS won't show a dialog — explain and send them to Settings
        await _openSettingsWithExplanation(
          'Notifications are blocked. To enable gig reminders, open Settings '
              'and turn on notifications for MoneyGigs.',
        );
      } else if (Platform.isIOS) {
        final granted = await _iOSPlugin?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        if (granted == true) {
          if (context.mounted) {
            setState(() {
              _isGranted = true;
              _isPermanentlyDenied = false;
            });
          }
          final notificationService = NotificationService();
          await notificationService.init();
          await notificationService.updateAllGigNotifications();
        } else {
          // iOS won't re-show the permission dialog after the user
          // has denied via Settings — explain and send them there.
          await _openSettingsWithExplanation(
            'iOS requires you to enable notifications for MoneyGigs in Settings. '
                'Tap Open Settings, then turn on Allow Notifications.',
          );
        }
      } else if (Platform.isAndroid) {
        await _androidPlugin?.requestNotificationsPermission();
        await _androidPlugin?.requestExactAlarmsPermission();
        final batteryStatus =
        await Permission.ignoreBatteryOptimizations.status;
        if (!batteryStatus.isGranted) {
          await Permission.ignoreBatteryOptimizations.request();
        }
        await _checkStatus();
        if (_isGranted == true) {
          final notificationService = NotificationService();
          await notificationService.init();
          await notificationService.updateAllGigNotifications();
        }
      }
    } finally {
      if (context.mounted) setState(() => _isRequesting = false);
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
            color: _isGranted!
                ? theme.colorScheme.primary
                : Colors.grey.shade500,
          ),
          title: const Text('Gig Reminders'),
          subtitle: Text(_subtitle),
          value: _isGranted!,
          onChanged: _isRequesting
              ? null
              : (bool value) async {
            if (_isGranted == true && !value) {
              // Turning OFF — cancel scheduled notifications then
              // explain that the OS setting must be changed manually.
              final bool? confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Turn off reminders?'),
                  content: const Text(
                    'This will cancel all upcoming gig reminders. '
                        'You\'ll also need to turn off notifications for '
                        'MoneyGigs in your device Settings.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('CANCEL'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('TURN OFF'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await _plugin.cancelAll();
                await _openSettingsWithExplanation(
                  'To fully disable notifications, turn off '
                      'Allow Notifications for MoneyGigs in Settings.',
                );
              }
            } else {
              // Turning ON
              await _requestPermission();
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
                    style: TextStyle(
                        fontSize: 12, color: Colors.orange.shade300),
                  ),
                ),
              ],
            ),
          ),

        if (_isGranted!)
          Padding(
            padding: const EdgeInsets.only(left: 72, right: 16, bottom: 8),
            child: Text(
              'You\'ll be notified before upcoming gigs. '
                  'Manage timing in the reminders section below.',
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