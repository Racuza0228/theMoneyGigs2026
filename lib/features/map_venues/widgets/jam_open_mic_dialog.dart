import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';


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
  // State variables for dialog controls
  late bool _hasJamOpenMic;
  DayOfWeek? _selectedDay;
  TimeOfDay? _selectedTime;
  late bool _addJamToGigs;
  late JamFrequencyType _selectedFrequency;
  int? _customNthValue;

  // Controllers
  late TextEditingController _customNthController;
  late TextEditingController _jamStyleController; // Controller for the new style field

  // Default time for Jam/Open Mic if enabling it for the first time
  final TimeOfDay _defaultJamTime = const TimeOfDay(hour: 19, minute: 0); // 7:00 PM

  @override
  void initState() {
    super.initState();
    // Initialize state from the passed-in venue object
    _hasJamOpenMic = widget.venue.hasJamOpenMic;
    _selectedDay = widget.venue.jamOpenMicDay;
    _selectedTime = widget.venue.jamOpenMicTime ?? (_hasJamOpenMic ? _defaultJamTime : null);
    _addJamToGigs = widget.venue.addJamToGigs;
    _selectedFrequency = widget.venue.jamFrequencyType;
    _customNthValue = widget.venue.customNthValue;

    // Initialize controllers with data from the venue
    _customNthController = TextEditingController(text: _customNthValue?.toString() ?? '');
    _jamStyleController = TextEditingController(text: widget.venue.jamStyle);

    // Set sensible defaults if a jam night is already enabled
    if (_hasJamOpenMic) {
      _selectedDay ??= DayOfWeek.monday;
      _selectedTime ??= _defaultJamTime;
      if ((_selectedFrequency == JamFrequencyType.customNthDay || _selectedFrequency == JamFrequencyType.monthlySameDay) && _customNthValue == null) {
        _customNthValue = 1; // Default to 1st if not set but frequency requires it
        _customNthController.text = _customNthValue.toString();
      }
    }
  }

  @override
  void dispose() {
    // Dispose all controllers to prevent memory leaks
    _customNthController.dispose();
    _jamStyleController.dispose();
    super.dispose();
  }

  Future<void> _pickTime(BuildContext context) async {
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
        return 'Monthly (Same Date - Not Day Specific)';
      case JamFrequencyType.customNthDay:
        return 'Every Nth Week (e.g., 3rd Tuesday)';
    }
  }

  String _getNthFieldLabel() {
    switch (_selectedFrequency) {
      case JamFrequencyType.customNthDay:
        return 'Repeat every Nth week*';
      case JamFrequencyType.monthlySameDay:
        return 'Which occurrence of the day?*';
      default:
        return '';
    }
  }

  void _saveChanges() {
    // 1. Perform validation if the jam night is enabled
    if (_hasJamOpenMic) {
      if (_selectedDay == null || _selectedTime == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a day and time.'), backgroundColor: Colors.orange),
        );
        return;
      }
      if (_selectedFrequency == JamFrequencyType.customNthDay || _selectedFrequency == JamFrequencyType.monthlySameDay) {
        final parsedNthValue = int.tryParse(_customNthController.text);
        if (parsedNthValue == null || parsedNthValue < 1 || parsedNthValue > 5) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Please enter a valid number (1-5) for "${_getNthFieldLabel()}".'), backgroundColor: Colors.orange),
          );
          return;
        }
        _customNthValue = parsedNthValue;
      } else {
        _customNthValue = null; // Clear Nth value if the frequency doesn't use it
      }
    }

    // 2. Prepare the data for the updated venue object
    final String? newJamStyle = _jamStyleController.text.trim().isNotEmpty ? _jamStyleController.text.trim() : null;

    // 3. Create the updated venue object using the copyWith method
    final StoredLocation updatedVenue = widget.venue.copyWith(
      hasJamOpenMic: _hasJamOpenMic,
      jamOpenMicDay: _hasJamOpenMic ? _selectedDay : null, // Nullify if disabled
      jamOpenMicTime: _hasJamOpenMic ? _selectedTime : null, // Nullify if disabled
      jamStyle: () => newJamStyle, // Use ValueGetter to handle setting to null
      addJamToGigs: _hasJamOpenMic ? _addJamToGigs : false, // Reset if disabled
      jamFrequencyType: _hasJamOpenMic ? _selectedFrequency : JamFrequencyType.weekly, // Reset to default
      customNthValue: _hasJamOpenMic ? _customNthValue : null, // Nullify if disabled or not applicable
    );

    // 4. Check if any data has actually changed
    bool changed = widget.venue.hasJamOpenMic != updatedVenue.hasJamOpenMic ||
        widget.venue.jamOpenMicDay != updatedVenue.jamOpenMicDay ||
        widget.venue.jamOpenMicTime?.hour != updatedVenue.jamOpenMicTime?.hour ||
        widget.venue.jamOpenMicTime?.minute != updatedVenue.jamOpenMicTime?.minute ||
        widget.venue.addJamToGigs != updatedVenue.addJamToGigs ||
        widget.venue.jamFrequencyType != updatedVenue.jamFrequencyType ||
        widget.venue.customNthValue != updatedVenue.customNthValue ||
        widget.venue.jamStyle != updatedVenue.jamStyle; // Check the new field

    // 5. Pop the dialog and return the result
    Navigator.of(context).pop(JamOpenMicDialogResult(
      settingsChanged: changed,
      updatedVenue: changed ? updatedVenue : null, // Only return the venue if changed
    ));
  }

  @override
  Widget build(BuildContext context) {
    bool showNthField = _hasJamOpenMic && (_selectedFrequency == JamFrequencyType.customNthDay || _selectedFrequency == JamFrequencyType.monthlySameDay);

    return AlertDialog(
      title: Text('Jam/Open Mic Settings', style: Theme.of(context).textTheme.titleLarge),
      contentPadding: const EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 0.0),
      content: SingleChildScrollView(
        child: ListBody(
          children: <Widget>[
            Text("Venue: ${widget.venue.name}", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.normal)),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('This venue has a Jam/Open Mic'),
              value: _hasJamOpenMic,
              onChanged: (bool value) {
                setState(() {
                  _hasJamOpenMic = value;
                  if (!_hasJamOpenMic) {
                    // Reset dependent fields when disabling
                    _addJamToGigs = false;
                  } else {
                    // Set defaults when enabling for the first time
                    _selectedDay ??= DayOfWeek.monday;
                    _selectedTime ??= _defaultJamTime;
                    if (showNthField && _customNthValue == null) {
                      _customNthValue = 1;
                      _customNthController.text = "1";
                    }
                  }
                });
              },
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            // Only show the detailed settings if the switch is ON
            if (_hasJamOpenMic) ...[
              const Divider(height: 24),
              TextFormField(
                controller: _jamStyleController,
                decoration: const InputDecoration(
                  labelText: 'Style / Genre (Optional)',
                  hintText: 'e.g., Bluegrass, Jazz, Acoustic',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<DayOfWeek>(
                decoration: const InputDecoration(labelText: 'Day of the Week*'),
                value: _selectedDay,
                items: DayOfWeek.values.map((DayOfWeek day) {
                  return DropdownMenuItem<DayOfWeek>(
                    value: day,
                    child: Text(toBeginningOfSentenceCase(day.toString().split('.').last) ?? ''),
                  );
                }).toList(),
                onChanged: (DayOfWeek? newValue) => setState(() => _selectedDay = newValue),
              ),
              const SizedBox(height: 16),
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
              DropdownButtonFormField<JamFrequencyType>(
                decoration: const InputDecoration(labelText: 'Frequency*'),
                value: _selectedFrequency,
                isExpanded: true,
                items: JamFrequencyType.values.map((JamFrequencyType freq) {
                  return DropdownMenuItem<JamFrequencyType>(
                    value: freq,
                    child: Text(_getFrequencyLabel(freq), overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (JamFrequencyType? newValue) {
                  if (newValue != null) setState(() => _selectedFrequency = newValue);
                },
              ),
              const SizedBox(height: 16),
              if (showNthField) ...[
                TextFormField(
                  controller: _customNthController,
                  decoration: InputDecoration(
                    labelText: _getNthFieldLabel(),
                    border: const OutlineInputBorder(),
                    hintText: 'e.g., 2 for "2nd" or "every 2nd"',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
              ],
              CheckboxListTile(
                title: const Text("Show in 'Upcoming Gigs' list"),
                subtitle: const Text("(Recurring event based on frequency)", style: TextStyle(fontSize: 12)),
                value: _addJamToGigs,
                onChanged: (bool? value) => setState(() => _addJamToGigs = value ?? false),
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
