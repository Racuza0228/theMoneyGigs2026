// lib/features/gigs/widgets/gig_list_tile.dart
//
// INTERACTION MODEL:
//   Left side  → tap to edit gig (booking dialog)
//   Right side → tap to open notes page (always includes impact events)
//
// A vertical divider separates the two zones. The right side has a
// subtle tint so users can see it is a distinct tap target.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';

enum GigTileStyle {
  listView,
  calendarView,
}

class GigListTile extends StatelessWidget {
  final Gig gig;
  final GigTileStyle style;

  /// Left side: opens gig for editing
  final VoidCallback onTap;

  /// Right side: opens notes page (always passes impact events)
  final VoidCallback? onNotesTap;

  const GigListTile({
    super.key,
    required this.gig,
    required this.style,
    required this.onTap,
    this.onNotesTap,
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
  bool get _reviewDone =>
      _isPast && !_isJam && (gig.retrospectiveCompleted ?? false);
  bool get _hasImpactEvents => !_isJam && gig.impactEventCount > 0;
  bool get _hasSignificantImpact => gig.hasSignificantImpactEvents;

  // ── Calendar view stays simple — no divider needed ────────────────────────

  @override
  Widget build(BuildContext context) {
    if (style == GigTileStyle.calendarView) {
      return _buildCalendarTile(context);
    }
    return _buildListTile(context);
  }

  // ── Calendar view (unchanged from original) ───────────────────────────────

  Widget _buildCalendarTile(BuildContext context) {
    return Card(
      elevation: _isPast ? 0.5 : (_isJam ? 1.5 : 2),
      color: _getCardColor(context),
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      child: ListTile(
        leading: Icon(
          _isJam ? Icons.music_note : Icons.event,
          color: _isPast
              ? Colors.grey.shade500
              : (_isJam
              ? Theme.of(context).colorScheme.tertiary
              : Theme.of(context).colorScheme.primary),
        ),
        title: Text(
          gig.bandName != null && gig.bandName!.trim().isNotEmpty
              ? '${gig.venueName} - ${gig.bandName}'
              : gig.venueName,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: _isPast ? Colors.grey.shade600 : Colors.white,
          ),
        ),
        subtitle: Text(
          _isJam
              ? '${DateFormat.jm().format(gig.dateTime)} - Jam/Open Mic'
              : '${DateFormat.jm().format(gig.dateTime)} - \$${gig.pay.toStringAsFixed(0)}',
          style: TextStyle(
            color: _isPast ? Colors.grey.shade500 : Colors.white,
          ),
        ),
        onTap: onTap,
      ),
    );
  }

  // ── List view — split left/right with vertical divider ───────────────────

  Widget _buildListTile(BuildContext context) {
    final bool showRightPanel = !_isJam && onNotesTap != null;

    return Card(
      elevation: _isPast ? 0.5 : (_isJam ? 1.5 : 2),
      color: _getCardColor(context),
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      clipBehavior: Clip.antiAlias, // keeps right-panel tint inside card border
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // ── LEFT: main content — taps to edit ──────────────────────────
            Expanded(
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12.0, vertical: 10.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildLeading(context),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildTitleContent(context),
                            const SizedBox(height: 2),
                            _buildSubtitleContent(context),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── DIVIDER + RIGHT PANEL: notes + badges — taps to open notes ─
            if (showRightPanel) ...[
              // Vertical line
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.12),
              ),

              // Right panel with subtle tint
              InkWell(
                onTap: onNotesTap,
                child: Container(
                  width: 64,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.04),
                  child: _buildRightPanel(context),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Leading avatar ────────────────────────────────────────────────────────

  Widget _buildLeading(BuildContext context) {
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

  // ── Title content ─────────────────────────────────────────────────────────

  Widget _buildTitleContent(BuildContext context) {
    final bool hasBandName =
        gig.bandName != null && gig.bandName!.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                gig.venueName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: _isPast
                      ? Colors.grey.shade700
                      : (_isJam
                      ? Theme.of(context)
                      .colorScheme
                      .onSecondaryContainer
                      : Theme.of(context).textTheme.titleLarge?.color),
                ),
              ),
            ),
            if (_isRecurring && !_isJam)
              Padding(
                padding: const EdgeInsets.only(left: 6.0),
                child: Icon(
                  Icons.event_repeat,
                  size: 16,
                  color: _isPast
                      ? Colors.grey.shade600
                      : Theme.of(context).colorScheme.secondary,
                  semanticLabel: 'Recurring Gig',
                ),
              ),
          ],
        ),
        if (hasBandName)
          Padding(
            padding: const EdgeInsets.only(top: 2.0),
            child: Text(
              gig.bandName!,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _isPast
                    ? Colors.grey.shade500
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
      ],
    );
  }

  // ── Subtitle content ──────────────────────────────────────────────────────

  Widget _buildSubtitleContent(BuildContext context) {
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
                .withValues(alpha: 0.8)
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
                  ?.withValues(alpha: 0.9),
            ),
          )
        else
          const Text(
            'Open Mic / Jam Session',
            style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
          ),
      ],
    );
  }

  // ── Right panel — stacked badges + notes icon ────────────────────────────
  //
  // Centered vertically. Impact badge on top (when present), then
  // REVIEW or star, then notes icon at the bottom.
  // All within the same 64px tap zone.

  Widget _buildRightPanel(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [

        // Impact event badge — gold circle
        if (_hasImpactEvents)
          Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: Tooltip(
              message: '${gig.impactEventCount} nearby event'
                  '${gig.impactEventCount == 1 ? '' : 's'}',
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: _hasSignificantImpact
                      ? const Color(0xFFB8860B) // dark gold
                      : const Color(0xFFCDA535).withValues(alpha: 0.75),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${gig.impactEventCount}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),

        // REVIEW badge
        if (_needsReview)
          Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.orange.shade700,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'REVIEW',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),

        // Review done — amber star
        if (_reviewDone)
          Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: Icon(
              Icons.star_rounded,
              size: 18,
              color: Colors.amber.shade400,
            ),
          ),

        // Notes icon — always present
        Icon(
          _hasNotes ? Icons.note_alt : Icons.note_alt_outlined,
          size: 22,
          color: _hasNotes
              ? Theme.of(context).colorScheme.primary
              : Colors.grey.shade500,
        ),

      ],
    );
  }

  Color _getCardColor(BuildContext context) {
    if (_isJam) {
      return Theme.of(context)
          .colorScheme
          .secondaryContainer
          .withValues(alpha: 0.7);
    }
    return Theme.of(context).cardColor;
  }
}