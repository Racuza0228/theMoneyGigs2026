import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'venue_model.dart'; // Make sure this path is correct for your StoredLocation and DayOfWeek enum

class JamOpenMicDialogResult {
  final bool settingsChanged;
  final StoredLocation? updatedVenue; // The venue with updated jam night settings

  JamOpenMicDialogResult({required this.settingsChanged, this.updatedVenue});
}

class JamOpenMicDialog extends StatefulWidget {
  final StoredLocation venue;

  const JamOpenMicDialog({super.key, required this.venue});

  @override
  State<JamOpenMicDialog> createState() => _JamOpenMicDialogState();
}

class _JamOpenMicDialogState extends State<JamOpenMicDialog> {
  late bool _hasJamOpenMic;
  DayOfWeek? _selectedDay;
  TimeOfDay? _selectedTime;
  late bool _addJamToGigs;
  late JamFrequencyType _selectedFrequency;
  late TextEditingController _customNthController;
  int? _customNthValue;

  // Default time for Jam/Open Mic if enabling it for the first time
  final TimeOfDay _defaultJamTime = const TimeOfDay(hour: 19, minute: 0); // 7:00 PM

  @override
  void initState() {
    super.initState();
    _hasJamOpenMic = widget.venue.hasJamOpenMic;
    _selectedDay = widget.venue.jamOpenMicDay;
    _selectedTime = widget.venue.jamOpenMicTime ?? (_hasJamOpenMic ? _defaultJamTime : null);
    _addJamToGigs = widget.venue.addJamToGigs;
    _selectedFrequency = widget.venue.jamFrequencyType;
    _customNthValue = widget.venue.customNthValue;
    _customNthController = TextEditingController(text: _customNthValue?.toString() ?? '');

    if (_hasJamOpenMic) {
      _selectedDay ??= DayOfWeek.monday;
      _selectedTime ??= _defaultJamTime;
      if (_selectedFrequency == JamFrequencyType.customNthDay || _selectedFrequency == JamFrequencyType.monthlySameDay) {
        _customNthValue ??= 1; // Default to 1st if not set but frequency requires it
        _customNthController.text = _customNthValue.toString();
      }
    }
  }

  @override
  void dispose() {
    _customNthController.dispose();
    super.dispose();
  }

  Future<void> _pickTime(BuildContext context) async {
    // ... (same as before)
    final TimeOfDay initialPickerTime = _selectedTime ?? _defaultJamTime;
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialPickerTime,
      helpText: 'Select Jam/Open Mic Time',
    );
    if (picked != null && picked != _selectedTime) {
      if (mounted) {
        setState(() => _selectedTime = picked);
      }
    }
  }

  String _getFrequencyLabel(JamFrequencyType frequency) {
    switch (frequency) {
      case JamFrequencyType.weekly:
        return 'Weekly';
      case JamFrequencyType.biWeekly:
        return 'Every 2 Weeks (Bi-Weekly)';
      case JamFrequencyType.monthlySameDay:
        return 'Monthly (e.g., 2nd Tuesday)';
      case JamFrequencyType.monthlySameDate:
        return 'Monthly (Same Date - Not Day Specific)'; // Consider if you really need this for day-based jams
      case JamFrequencyType.customNthDay:
        return 'Every Nth Week (e.g., 3rd Tuesday)';
    }
  }

  String _getNthFieldLabel() {
    switch (_selectedFrequency) {
      case JamFrequencyType.customNthDay:
        return 'Repeat every Nth week (1=every, 2=every other, etc.)*';
      case JamFrequencyType.monthlySameDay:
        return 'Which occurrence of the day? (1=1st, 2=2nd, etc.)*';
      default:
        return '';
    }
  }

  void _saveChanges() {
    if (_hasJamOpenMic) {
      if (_selectedDay == null || _selectedTime == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a day and time.'), backgroundColor: Colors.orange),
        );
        return;
      }
      if ((_selectedFrequency == JamFrequencyType.customNthDay || _selectedFrequency == JamFrequencyType.monthlySameDay)) {
        _customNthValue = int.tryParse(_customNthController.text);
        if (_customNthValue == null || _customNthValue! < 1 || _customNthValue! > 5) { // Max 5th week of month or every 5 weeks
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Please enter a valid number (1-5) for "${_getNthFieldLabel()}".'), backgroundColor: Colors.orange),
          );
          return;
        }
      } else {
        _customNthValue = null; // Clear if not applicable
      }
    }


    final StoredLocation updatedVenue = widget.venue.copyWith(
      hasJamOpenMic: _hasJamOpenMic,
      jamOpenMicDay: _hasJamOpenMic ? _selectedDay : null,
      jamOpenMicTime: _hasJamOpenMic ? _selectedTime : null,
      addJamToGigs: _hasJamOpenMic ? _addJamToGigs : false,
      jamFrequencyType: _hasJamOpenMic ? _selectedFrequency : JamFrequencyType.weekly, // Reset to default if disabled
      customNthValue: _hasJamOpenMic ? _customNthValue : null,
    );

    bool changed = widget.venue.hasJamOpenMic != updatedVenue.hasJamOpenMic ||
        widget.venue.jamOpenMicDay != updatedVenue.jamOpenMicDay ||
        widget.venue.jamOpenMicTime?.hour != updatedVenue.jamOpenMicTime?.hour ||
        widget.venue.jamOpenMicTime?.minute != updatedVenue.jamOpenMicTime?.minute ||
        widget.venue.addJamToGigs != updatedVenue.addJamToGigs ||
        widget.venue.jamFrequencyType != updatedVenue.jamFrequencyType ||
        widget.venue.customNthValue != updatedVenue.customNthValue;

    Navigator.of(context).pop(JamOpenMicDialogResult(
      settingsChanged: changed,
      updatedVenue: changed ? updatedVenue : widget.venue,
    ));
  }

  @override
  Widget build(BuildContext context) {
    bool showNthField = _selectedFrequency == JamFrequencyType.customNthDay ||
        _selectedFrequency == JamFrequencyType.monthlySameDay;

    return AlertDialog(
      title: Text('Jam/Open Mic Night Settings', style: Theme.of(context).textTheme.titleLarge),
      contentPadding: const EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 0.0),
      content: SingleChildScrollView(
        child: ListBody(
          children: <Widget>[
            Text("Venue: ${widget.venue.name}", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.normal)),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('This venue has a Jam/Open Mic Night'),
              value: _hasJamOpenMic,
              onChanged: (bool value) {
                setState(() {
                  _hasJamOpenMic = value;
                  if (!_hasJamOpenMic) {
                    _addJamToGigs = false;
                  } else {
                    _selectedDay ??= DayOfWeek.monday;
                    _selectedTime ??= _defaultJamTime;
                    // When enabling, ensure customNthValue has a sensible default if that frequency is selected
                    if ((_selectedFrequency == JamFrequencyType.customNthDay || _selectedFrequency == JamFrequencyType.monthlySameDay) && _customNthValue == null) {
                      _customNthValue = 1;
                      _customNthController.text = "1";
                    }
                  }
                });
              },
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            if (_hasJamOpenMic) ...[
              const SizedBox(height: 16),
              // --- Day of the Week ---
              DropdownButtonFormField<DayOfWeek>(
                decoration: const InputDecoration(
                  labelText: 'Day of the Week*',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(vertical: 12.0, horizontal: 10.0),
                ),
                value: _selectedDay,
                items: DayOfWeek.values.map((DayOfWeek day) {
                  return DropdownMenuItem<DayOfWeek>(
                    value: day,
                    child: Text(toBeginningOfSentenceCase(day.toString().split('.').last) ?? day.toString().split('.').last),
                  );
                }).toList(),
                onChanged: (DayOfWeek? newValue) {
                  setState(() => _selectedDay = newValue);
                },
                validator: (value) => value == null ? 'Please select a day' : null,
              ),
              const SizedBox(height: 16),

              // --- Time Picker ---
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedTime == null ? 'No time selected*' : 'Time: ${_selectedTime!.format(context)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.normal),
                    ),
                  ),
                  TextButton(onPressed: () => _pickTime(context), child: const Text('SELECT TIME')),
                ],
              ),
              const SizedBox(height: 16),

              // --- Frequency Type ---
              DropdownButtonFormField<JamFrequencyType>(
                decoration: const InputDecoration(
                  labelText: 'Frequency*',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(vertical: 12.0, horizontal: 10.0),
                ),
                value: _selectedFrequency,
                isExpanded: true,
                items: JamFrequencyType.values.map((JamFrequencyType freq) {
                  return DropdownMenuItem<JamFrequencyType>(
                    value: freq,
                    child: Text(_getFrequencyLabel(freq), overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (JamFrequencyType? newValue) {
                  if (newValue != null) {
                    setState(() {
                      _selectedFrequency = newValue;
                      // If the new frequency requires Nth value and it's not set, default it
                      if ((newValue == JamFrequencyType.customNthDay || newValue == JamFrequencyType.monthlySameDay) && _customNthValue == null) {
                        _customNthValue = 1;
                        _customNthController.text = "1";
                      }
                    });
                  }
                },
              ),
              const SizedBox(height: 16),

              // --- Custom Nth Value Input (if applicable) ---
              if (showNthField) ...[
                TextFormField(
                  controller: _customNthController,
                  decoration: InputDecoration(
                    labelText: _getNthFieldLabel(),
                    border: const OutlineInputBorder(),
                    hintText: 'e.g., 2 for 2nd or every 2nd',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Value is required for this frequency.';
                    final n = int.tryParse(value);
                    if (n == null || n < 1 || n > 5) return 'Enter a number between 1 and 5.';
                    return null;
                  },
                  onChanged: (value) {
                    // You can choose to update _customNthValue here or only on save
                  },
                ),
                const SizedBox(height: 16),
              ],

              // --- Add to Gigs Checkbox ---
              CheckboxListTile(
                title: const Text("Show as recurring event in 'Upcoming Gigs'"),
                subtitle: const Text("(Uses default values, not a 'booked' gig)", style: TextStyle(fontSize: 12)),
                value: _addJamToGigs,
                onChanged: (bool? value) {
                  if (mounted && value != null) {
                    setState(() => _addJamToGigs = value);
                  }
                },
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ],
            const SizedBox(height: 10),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      actions: <Widget>[
        TextButton(
          child: const Text('CANCEL'),
          onPressed: () => Navigator.of(context).pop(JamOpenMicDialogResult(settingsChanged: false)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
          ),
          onPressed: _saveChanges,
          child: const Text('SAVE SETTINGS'),
        ),
      ],
    );
  }
}