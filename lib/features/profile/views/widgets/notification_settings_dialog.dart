// lib/features/profile/views/widgets/notification_settings_dialog.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/core/services/notification_service.dart';
import 'package:the_money_gigs/core/utils/logger.dart';

class NotificationSettingsDialog extends StatefulWidget {
  const NotificationSettingsDialog({super.key});

  @override
  State<NotificationSettingsDialog> createState() =>
      _NotificationSettingsDialogState();
}

class _NotificationSettingsDialogState
    extends State<NotificationSettingsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _daysBeforeController = TextEditingController();
  bool _notifyOnDayOfGig = false;
  bool _notifyAfterGig = true; // day-after retrospective, on by default

  static const String _keyNotifyOnDayOfGig = 'notify_on_day_of_gig';
  static const String _keyNotifyDaysBefore = 'notify_days_before';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _daysBeforeController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notifyOnDayOfGig = prefs.getBool(_keyNotifyOnDayOfGig) ?? false;
      _notifyAfterGig   = prefs.getBool('notify_after_gig') ?? true;
      _daysBeforeController.text =
          prefs.getInt(_keyNotifyDaysBefore)?.toString() ?? '';
    });
  }

  Future<void> _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      final prefs = await SharedPreferences.getInstance();

      // ✅ Check if notifications were previously disabled
      final wasDisabled = !(prefs.getBool(_keyNotifyOnDayOfGig) ?? false) &&
          prefs.getInt(_keyNotifyDaysBefore) == null;

      // Save new settings
      await prefs.setBool(_keyNotifyOnDayOfGig, _notifyOnDayOfGig);
      await prefs.setBool('notify_after_gig', _notifyAfterGig);
      final daysBefore = int.tryParse(_daysBeforeController.text);
      if (daysBefore != null) {
        await prefs.setInt(_keyNotifyDaysBefore, daysBefore);
      } else {
        await prefs.remove(_keyNotifyDaysBefore);
      }

      // ✅ Check if notifications are now enabled
      final nowEnabled = _notifyOnDayOfGig || _notifyAfterGig || daysBefore != null;

      // ✅ Always init before scheduling — init() is a no-op if already done.
      // Previously, init() only ran on first-time enable, meaning
      // updateAllGigNotifications() could run without timezone being set.
      // The redundant tz.initializeTimeZones() call is also removed here;
      // NotificationService.init() handles timezone setup internally.
      if (nowEnabled && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return const Dialog(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(width: 20),
                    Text("Updating notifications..."),
                  ],
                ),
              ),
            );
          },
        );

        try {
          final notificationService = NotificationService();
          // init() sets up timezone + plugin. Safe to call every time —
          // no-ops if already initialized.
          await notificationService.init();

          // First-time enable: also request OS permissions.
          if (wasDisabled) {
            log('📬 First-time enable — requesting permissions...');
            await notificationService.requestPermissions();
          }

          await notificationService.updateAllGigNotifications();
          log('✅ Notification update complete.');
        } catch (e) {
          log('❌ Error updating notifications: $e');
        } finally {
          if (mounted) Navigator.of(context, rootNavigator: true).pop();
        }
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Notification settings saved.'),
              backgroundColor: Colors.green),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Notification Settings'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CheckboxListTile(
              title: const Text('Day Of The Gig'),
              subtitle: const Text('Morning reminder on gig day'),
              value: _notifyOnDayOfGig,
              onChanged: (bool? value) {
                setState(() {
                  _notifyOnDayOfGig = value ?? true;
                });
              },
            ),
            CheckboxListTile(
              title: const Text('Day After The Gig'),
              subtitle: const Text('Prompt to reflect on how it went'),
              value: _notifyAfterGig,
              onChanged: (bool? value) {
                setState(() {
                  _notifyAfterGig = value ?? true;
                });
              },
            ),
            TextFormField(
              controller: _daysBeforeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Days Before The Gig',
                hintText: 'e.g., 3',
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return null; // Allow empty
                }
                if (int.tryParse(value) == null) {
                  return 'Please enter a valid number.';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saveSettings,
          child: const Text('Save'),
        ),
      ],
    );
  }
}