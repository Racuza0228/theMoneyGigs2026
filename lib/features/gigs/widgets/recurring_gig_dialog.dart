import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:the_money_gigs/core/models/enums.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';

// This dialog returns the updated Gig object on save, or null on cancel.
class RecurringGigDialog extends StatefulWidget {
  final Gig gig;
  const RecurringGigDialog({super.key, required this.gig});

  @override
  State<RecurringGigDialog> createState() => _RecurringGigDialogState();
}

class _RecurringGigDialogState extends State<RecurringGigDialog> {
  late Gig _editableGig;
  late final TextEditingController _nthController;
  late final TextEditingController _endDateController;

  @override
  void initState() {
    super.initState();
    _editableGig = widget.gig.copyWith();
    _nthController = TextEditingController(text: _editableGig.recurrenceNthValue?.toString() ?? '');
    _endDateController = TextEditingController(
      text: _editableGig.recurrenceEndDate != null ? DateFormat.yMd().format(_editableGig.recurrenceEndDate!) : '',
    );
  }

  @override
  void dispose() {
    _nthController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  Future<void> _pickEndDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _editableGig.recurrenceEndDate ?? _editableGig.dateTime.add(const Duration(days: 90)),
      firstDate: _editableGig.dateTime,
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) {
      setState(() {
        _editableGig = _editableGig.copyWith(recurrenceEndDate: picked);
        _endDateController.text = DateFormat.yMd().format(picked);
      });
    }
  }

  void _saveChanges() {
    // Before saving, ensure `recurrenceDay` is set if recurring is true
    if (_editableGig.isRecurring && _editableGig.recurrenceDay == null) {
      _editableGig = _editableGig.copyWith(recurrenceDay: DayOfWeek.values[_editableGig.dateTime.weekday - 1]);
    }
    Navigator.of(context).pop(_editableGig);
  }

  @override
  Widget build(BuildContext context) {
    bool showNthField = _editableGig.recurrenceFrequency == JamFrequencyType.customNthDay || _editableGig.recurrenceFrequency == JamFrequencyType.monthlySameDay;

    return AlertDialog(
      title: Text('Recurring Gig Settings', style: Theme.of(context).textTheme.titleLarge),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              title: const Text("This is a recurring gig"),
              value: _editableGig.isRecurring,
              onChanged: (value) {
                setState(() {
                  _editableGig = _editableGig.copyWith(isRecurring: value ?? false);
                });
              },
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            if (_editableGig.isRecurring) ...[
              const Divider(),
              const SizedBox(height: 8),
              DropdownButtonFormField<DayOfWeek>(
                decoration: const InputDecoration(labelText: 'Day of Week'),
                value: _editableGig.recurrenceDay ?? DayOfWeek.values[_editableGig.dateTime.weekday - 1],
                items: DayOfWeek.values.map((d) => DropdownMenuItem(value: d, child: Text(toBeginningOfSentenceCase(d.name)!))).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _editableGig = _editableGig.copyWith(recurrenceDay: value);
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<JamFrequencyType>(
                decoration: const InputDecoration(labelText: 'Frequency'),
                value: _editableGig.recurrenceFrequency ?? JamFrequencyType.weekly,
                isExpanded: true,
                items: JamFrequencyType.values.map((f) {
                  String text;
                  switch (f) {
                    case JamFrequencyType.weekly: text = 'Weekly'; break;
                    case JamFrequencyType.biWeekly: text = 'Every 2 Weeks'; break;
                    case JamFrequencyType.monthlySameDay: text = 'Monthly (By Day)'; break;
                    case JamFrequencyType.monthlySameDate: text = 'Monthly (By Date)'; break;
                    case JamFrequencyType.customNthDay: text = 'Every Nth Week'; break;
                  }
                  return DropdownMenuItem(value: f, child: Text(text));
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _editableGig = _editableGig.copyWith(recurrenceFrequency: value);
                    });
                  }
                },
              ),
              if (showNthField) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nthController,
                  decoration: const InputDecoration(labelText: 'Nth Value', hintText: 'e.g., 2 for 2nd Tuesday'),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    setState(() {
                      _editableGig = _editableGig.copyWith(recurrenceNthValue: int.tryParse(value));
                    });
                    },
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _endDateController,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: 'End Date (Optional)',
                  hintText: 'Tap to select',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      setState(() {
                        // Special case: setting recurrenceEndDate to null needs a different copyWith approach
                        _editableGig = Gig(
                          id: _editableGig.id,
                          venueName: _editableGig.venueName,
                          latitude: _editableGig.latitude,
                          longitude: _editableGig.longitude,
                          address: _editableGig.address,
                          placeId: _editableGig.placeId,
                          dateTime: _editableGig.dateTime,
                          pay: _editableGig.pay,
                          gigLengthHours: _editableGig.gigLengthHours,
                          driveSetupTimeHours: _editableGig.driveSetupTimeHours,
                          rehearsalLengthHours: _editableGig.rehearsalLengthHours,
                          isJamOpenMic: _editableGig.isJamOpenMic,
                          notes: _editableGig.notes,
                          notesUrl: _editableGig.notesUrl,
                          isRecurring: _editableGig.isRecurring,
                          recurrenceFrequency: _editableGig.recurrenceFrequency,
                          recurrenceDay: _editableGig.recurrenceDay,
                          recurrenceNthValue: _editableGig.recurrenceNthValue,
                          recurrenceEndDate: null, // Explicitly set to null
                        );
                        _endDateController.clear();
                      });
                    },
                  ),
                ),
                onTap: _pickEndDate,
              ),
            ]
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: <Widget>[
        TextButton(
          child: const Text('CANCEL'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        ElevatedButton(
          onPressed: _saveChanges,
          child: const Text('SAVE'),
        ),
      ],
    );
  }
}
