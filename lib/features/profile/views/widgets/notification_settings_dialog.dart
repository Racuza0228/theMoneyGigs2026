// lib/features/profile/views/widgets/notification_settings_dialog.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/core/services/notification_service.dart';

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
      _daysBeforeController.text =
          prefs.getInt(_keyNotifyDaysBefore)?.toString() ?? '';
    });
  }

  Future<void> _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool(_keyNotifyOnDayOfGig, _notifyOnDayOfGig);
      final daysBefore = int.tryParse(_daysBeforeController.text);
      if (daysBefore != null) {
        await prefs.setInt(_keyNotifyDaysBefore, daysBefore);
      } else {
        await prefs.remove(_keyNotifyDaysBefore);
      }

      // --- START: TRIGGER THE UPDATE ---
      // Show a loading indicator to the user
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
                  Text("Updating all notifications..."),
                ],
              ),
            ),
          );
        },
      );

      // Call the new service method and wait for it to complete
      try {
        await NotificationService().updateAllGigNotifications();
      } finally {
        // Ensure the loading dialog is closed even if an error occurs
        if(mounted) Navigator.of(context, rootNavigator: true).pop();
      }
      // --- END: TRIGGER THE UPDATE ---

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
              value: _notifyOnDayOfGig,
              onChanged: (bool? value) {
                setState(() {
                  _notifyOnDayOfGig = value ?? true;
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
