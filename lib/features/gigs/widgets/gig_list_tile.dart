// lib/features/gigs/widgets/gig_list_tile.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';

/// Defines the visual style/context for the gig tile.
enum GigTileStyle {
  /// Full details with date in avatar, used in main list view
  listView,
  /// Compact style with icon, used in calendar day view
  calendarView,
}

/// A reusable widget that displays a gig as a card/tile.
///
/// Used in both the main gigs list view and the calendar day view.
/// Handles past/future styling, jam sessions, recurring indicators,
/// notes icons, and review badges.
class GigListTile extends StatelessWidget {
  final Gig gig;
  final GigTileStyle style;
  final VoidCallback onTap;
  final VoidCallback onNotesTap;

  const GigListTile({
    super.key,
    required this.gig,
    required this.style,
    required this.onTap,
    required this.onNotesTap,
  });

  bool get _isPast {
    final gigEndTime = gig.dateTime.add(
      Duration(minutes: (gig.gigLengthHours * 60).toInt()),
    );
    return gigEndTime.isBefore(DateTime.now());
  }

  bool get _isJam => gig.isJamOpenMic;

  bool get _hasNotes {
    final hasSetlist = gig.setlistId?.isNotEmpty ?? false;
    return (gig.notes?.isNotEmpty ?? false) ||
        (gig.notesUrl?.isNotEmpty ?? false) ||
        hasSetlist;
  }

  bool get _isRecurring => gig.isRecurring || gig.isFromRecurring;

  bool get _needsReview =>
      _isPast && !_isJam && !(gig.retrospectiveCompleted ?? false);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: _isPast ? 0.5 : (_isJam ? 1.5 : 2),
      color: _getCardColor(context),
      margin: style == GigTileStyle.listView
          ? const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0)
          : const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      child: ListTile(
        leading: _buildLeading(context),
        title: _buildTitle(context),
        subtitle: _buildSubtitle(context),
        trailing: _buildTrailing(context),
        onTap: onTap,
      ),
    );
  }

  Color _getCardColor(BuildContext context) {
    if (_isJam) {
      return Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.7);
    }
    return Theme.of(context).cardColor;
  }

  Widget _buildLeading(BuildContext context) {
    if (style == GigTileStyle.calendarView) {
      // Calendar view: simple icon
      return Icon(
        _isJam ? Icons.music_note : Icons.event,
        color: _isPast
            ? Colors.grey.shade500
            : (_isJam
            ? Theme.of(context).colorScheme.tertiary
            : Theme.of(context).colorScheme.primary),
      );
    }

    // List view: CircleAvatar with date or music note
    return CircleAvatar(
      backgroundColor: _isJam
          ? Theme.of(context).colorScheme.tertiary
          : (_isPast
          ? Colors.grey.shade400
          : Theme.of(context).colorScheme.primary),
      foregroundColor:
      _isJam ? Theme.of(context).colorScheme.onTertiary : Colors.white,
      child: _isJam
          ? const Icon(Icons.music_note, size: 20)
          : Text(DateFormat('d').format(gig.dateTime)),
    );
  }

  Widget _buildTitle(BuildContext context) {
    if (style == GigTileStyle.calendarView) {
      // Calendar view: simple title
      return Text(
        gig.venueName,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: _isPast ? Colors.grey.shade600 : Colors.white,
        ),
      );
    }

    // List view: title with recurring indicator
    return Row(
      children: [
        Expanded(
          child: Text(
            gig.venueName,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _isPast
                  ? Colors.grey.shade700
                  : (_isJam
                  ? Theme.of(context).colorScheme.onSecondaryContainer
                  : Theme.of(context).textTheme.titleLarge?.color),
            ),
          ),
        ),
        if (_isRecurring && !_isJam)
          Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: Icon(
              Icons.event_repeat,
              size: 16,
              color: _isPast
                  ? Colors.grey.shade600
                  : Theme.of(context).colorScheme.secondary,
              semanticLabel: "Recurring Gig",
            ),
          ),
      ],
    );
  }

  Widget _buildSubtitle(BuildContext context) {
    if (style == GigTileStyle.calendarView) {
      // Calendar view: time and pay only
      return Text(
        _isJam
            ? '${DateFormat.jm().format(gig.dateTime)} - Jam/Open Mic'
            : '${DateFormat.jm().format(gig.dateTime)} - \$${gig.pay.toStringAsFixed(0)}',
        style: TextStyle(
          color: _isPast ? Colors.grey.shade500 : Colors.white,
        ),
      );
    }

    // List view: full date, time, pay, and hours
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${DateFormat.yMMMEd().format(gig.dateTime)} at ${DateFormat.jm().format(gig.dateTime)}',
          style: TextStyle(
            color: _isPast
                ? Colors.grey.shade600
                : (_isJam
                ? Theme.of(context)
                .colorScheme
                .onSecondaryContainer
                .withOpacity(0.8)
                : Theme.of(context).textTheme.bodyMedium?.color),
          ),
        ),
        if (!_isJam)
          Text(
            'Pay: \$${gig.pay.toStringAsFixed(0)} - ${gig.gigLengthHours.toStringAsFixed(1)} hrs',
            style: TextStyle(
              color: _isPast
                  ? Colors.grey.shade600
                  : Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.color
                  ?.withOpacity(0.9),
            ),
          )
        else
          const Text(
            "Open Mic / Jam Session",
            style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
          ),
      ],
    );
  }

  Widget? _buildTrailing(BuildContext context) {
    if (_isJam) return null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Show "Review" badge for past unreviewed gigs
        if (_needsReview)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Review',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.orange.shade800,
              ),
            ),
          ),
        IconButton(
          icon: Icon(
            _hasNotes ? Icons.speaker_notes : Icons.speaker_notes_off_outlined,
            color: _hasNotes
                ? Theme.of(context).colorScheme.primary
                : Colors.grey,
          ),
          onPressed: onNotesTap,
          tooltip: 'View/Edit Notes',
        ),
      ],
    );
  }
}