import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:the_money_gigs/core/models/enums.dart'; // <<<--- IMPORT THE SHARED ENUMS
import 'package:the_money_gigs/features/map_venues/models/jam_session_model.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';
import 'package:uuid/uuid.dart';
import 'package:collection/collection.dart';

class JamOpenMicDialogResult {
  final bool settingsChanged;
  final StoredLocation? updatedVenue;

  JamOpenMicDialogResult({required this.settingsChanged, this.updatedVenue});
}

class JamOpenMicDialog extends StatefulWidget {
  final StoredLocation venue;
  const JamOpenMicDialog({super.key, required this.venue});

  @override
  State<JamOpenMicDialog> createState() => _JamOpenMicDialogState();
}

class _JamOpenMicDialogState extends State<JamOpenMicDialog> {
  late List<JamSession> _jamSessions;
  final TimeOfDay _defaultJamTime = const TimeOfDay(hour: 19, minute: 0); // 7:00 PM

  @override
  void initState() {
    super.initState();
    // Make a deep copy of the list to edit safely
    _jamSessions = widget.venue.jamSessions.map((js) => js.copyWith()).toList();
  }

  void _addNewJamSession() {
    setState(() {
      _jamSessions.add(JamSession(
        id: const Uuid().v4(), // Unique ID for keys and editing
        day: DayOfWeek.monday,
        time: _defaultJamTime,
      ));
    });
  }

  void _deleteJamSession(String id) {
    setState(() {
      _jamSessions.removeWhere((js) => js.id == id);
    });
  }

  void _updateJamSession(JamSession updatedSession) {
    final index = _jamSessions.indexWhere((js) => js.id == updatedSession.id);
    if (index != -1) {
      setState(() {
        _jamSessions[index] = updatedSession;
      });
    }
  }

  void _saveChanges() {
    // Create the updated venue object with the new list of jam sessions
    final StoredLocation updatedVenue = widget.venue.copyWith(jamSessions: _jamSessions);

    // A robust check to see if the contents of the list have changed.
    bool changed = const ListEquality().equals(widget.venue.jamSessions, updatedVenue.jamSessions) == false;

    Navigator.of(context).pop(JamOpenMicDialogResult(
      settingsChanged: changed,
      updatedVenue: changed ? updatedVenue : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Jam/Open Mic Settings', style: Theme.of(context).textTheme.titleLarge),
      contentPadding: const EdgeInsets.fromLTRB(0, 16.0, 0, 0),
      content: SizedBox( // Constrain the width of the dialog content
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: ListBody(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Text("Venue: ${widget.venue.name}", style: Theme.of(context).textTheme.titleMedium),
              ),
              const SizedBox(height: 16),

              if (_jamSessions.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Center(child: Text('No jam sessions configured.', style: TextStyle(fontStyle: FontStyle.italic))),
                )
              else
                ListView.builder(
                  shrinkWrap: true, // This is crucial.
                  physics: const NeverScrollableScrollPhysics(), // This is also crucial.
                  itemCount: _jamSessions.length,
                  itemBuilder: (context, index) {
                    return _JamSessionEditor(
                      key: ValueKey(_jamSessions[index].id),
                      session: _jamSessions[index],
                      onUpdate: _updateJamSession,
                      onDelete: () => _deleteJamSession(_jamSessions[index].id),
                    );
                  },
                ),
              // *** END OF FIX ***

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add Jam Session'),
                  onPressed: _addNewJamSession,
                ),
              ),
            ],
          ),
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

// A new private widget to edit a SINGLE jam session
class _JamSessionEditor extends StatefulWidget {
  final JamSession session;
  final VoidCallback onDelete;
  final Function(JamSession) onUpdate;

  const _JamSessionEditor({super.key, required this.session, required this.onDelete, required this.onUpdate});

  @override
  State<_JamSessionEditor> createState() => _JamSessionEditorState();
}

class _JamSessionEditorState extends State<_JamSessionEditor> {
  late JamSession _sessionData;
  late final TextEditingController _styleController;
  late final TextEditingController _nthController;

  @override
  void initState() {
    super.initState();
    _sessionData = widget.session;
    _styleController = TextEditingController(text: _sessionData.style);
    _nthController = TextEditingController(text: _sessionData.nthValue?.toString() ?? '');
  }

  @override
  void dispose() {
    _styleController.dispose();
    _nthController.dispose();
    super.dispose();
  }

  void _handleUpdate() {
    widget.onUpdate(_sessionData);
  }

  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showTimePicker(context: context, initialTime: _sessionData.time);
    if (picked != null) {
      setState(() => _sessionData = _sessionData.copyWith(time: picked));
      _handleUpdate();
    }
  }

  @override
  Widget build(BuildContext context) {
    bool showNthField = _sessionData.frequency == JamFrequencyType.customNthDay || _sessionData.frequency == JamFrequencyType.monthlySameDay;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Jam Session', style: Theme.of(context).textTheme.titleMedium),
                IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: widget.onDelete, tooltip: 'Delete Session'),
              ],
            ),
            const Divider(),
            TextFormField(
              controller: _styleController,
              decoration: const InputDecoration(labelText: 'Style/Genre (Optional)', hintText: 'e.g., Bluegrass, Jazz'),
              onChanged: (value) {
                _sessionData = _sessionData.copyWith(style: value.trim().isNotEmpty ? value.trim() : null);
                _handleUpdate();
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<DayOfWeek>(
              decoration: const InputDecoration(labelText: 'Day'),
              initialValue: _sessionData.day,
              items: DayOfWeek.values.map((d) => DropdownMenuItem(value: d, child: Text(toBeginningOfSentenceCase(d.name)!))).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _sessionData = _sessionData.copyWith(day: value));
                  _handleUpdate();
                }
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Time: ${_sessionData.time.format(context)}'),
              trailing: TextButton(onPressed: _pickTime, child: const Text('SELECT')),
            ),
            DropdownButtonFormField<JamFrequencyType>(
              decoration: const InputDecoration(labelText: 'Frequency'),
              initialValue: _sessionData.frequency,
              isExpanded: true,
              items: JamFrequencyType.values.map((f) {
                // This makes the dropdown text more readable
                String text;
                switch (f) {
                  case JamFrequencyType.weekly:
                    text = 'Weekly';
                    break;
                  case JamFrequencyType.biWeekly:
                    text = 'Every 2 Weeks';
                    break;
                  case JamFrequencyType.monthlySameDay:
                    text = 'Monthly (By Day)';
                    break;
                  case JamFrequencyType.monthlySameDate:
                    text = 'Monthly (By Date)';
                    break;
                  case JamFrequencyType.customNthDay:
                    text = 'Every Nth Week';
                    break;
                }
                return DropdownMenuItem(value: f, child: Text(text));
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _sessionData = _sessionData.copyWith(frequency: value));
                  _handleUpdate();
                }
              },
            ),
            if (showNthField) ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _nthController,
                decoration: const InputDecoration(labelText: 'Nth Value', hintText: 'e.g., 2 for 2nd Tuesday'),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  _sessionData = _sessionData.copyWith(nthValue: int.tryParse(value));
                  _handleUpdate();
                },
              ),
            ],
            CheckboxListTile(
              title: const Text("Show in Gigs list"),
              value: _sessionData.showInGigsList,
              onChanged: (value) {
                if (value != null) {
                  setState(() => _sessionData = _sessionData.copyWith(showInGigsList: value));
                  _handleUpdate();
                }
              },
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            )
          ],
        ),
      ),
    );
  }
}
