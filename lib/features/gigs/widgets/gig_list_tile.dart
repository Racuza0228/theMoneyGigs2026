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

  // ── Jam attendance badge (GOING / INTERESTED) ─────────────────────────────
  String? get _attendanceLabel {
    switch (gig.attendanceStatus) {
      case 'going':
        return 'GOING';
      case 'interested':
        return 'INTERESTED';
      default:
        return null;
    }
  }

  Color get _attendanceColor =>
      gig.attendanceStatus == 'going' ? Colors.green : Colors.amber.shade700;

  // ── Brand palette (8/26 color consolidation) ──────────────────────────────
  // A WCAG pass on this tile turned up two real contrast failures (white
  // text on the purple date circle: 1.71:1; white text on the gold impact
  // badge: ~3.66:1 — both below the 4.5:1 minimum for normal text) plus a
  // color-count problem: this tile alone was pulling in purple and pink
  // that only existed because ColorScheme.fromSeed(Colors.deepPurple) in
  // main.dart auto-generates them — not an intentional design choice, and
  // purple was coincidentally doing double duty as the nav/tab accent too.
  // Consolidated down to neutrals + one orange accent (two weights for
  // hierarchy) + green for GOING status:
  //   - _orangeBold: paid gigs — solid fill, pairs with black text/icons.
  //   - _orangeSoft: jam sessions — lighter weight, same treatment.
  // The old gold impact-count badge is kept as-is (it already reads as a
  // darker weight of this same orange family) but its text flips to black.
  static const MaterialColor _orangeBold = Colors.deepOrange; // shade600/400 below
  static const MaterialColor _orangeSoft = Colors.orange; // shade200/300 below

  Color get _gigAccentColor =>
      _isJam ? (_orangeSoft.shade300) : (_orangeBold.shade400);

  // ── Calendar view stays simple — no divider needed ────────────────────────

  @override
  Widget build(BuildContext context) {
    if (style == GigTileStyle.calendarView) {
      return _buildCalendarTile(context);
    }
    return _buildListTile(context);
  }

  // ── Calendar view — split left/right matching list tile ─────────────────

  Widget _buildCalendarTile(BuildContext context) {
    final bool showRightPanel = !_isJam && onNotesTap != null;

    return Card(
      elevation: _isPast ? 0.5 : (_isJam ? 1.5 : 2),
      color: _getCardColor(context),
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      clipBehavior: Clip.antiAlias,
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
                    children: [
                      Icon(
                        _isJam ? Icons.music_note : Icons.event,
                        color: _isPast ? Colors.grey.shade500 : _gigAccentColor,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              gig.bandName != null &&
                                  gig.bandName!.trim().isNotEmpty
                                  ? '${gig.venueName} - ${gig.bandName}'
                                  : gig.venueName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _isPast
                                    ? Colors.grey.shade600
                                    : Colors.white,
                              ),
                            ),
                            Text(
                              _isJam
                                  ? '${DateFormat.jm().format(gig.dateTime)} - Jam/Open Mic'
                                  '${_attendanceLabel != null ? ' · $_attendanceLabel' : ''}'
                                  : '${DateFormat.jm().format(gig.dateTime)} - \$${gig.pay.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontWeight: _attendanceLabel != null
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: _isPast
                                    ? Colors.grey.shade500
                                    : Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── DIVIDER + RIGHT PANEL ──────────────────────────────────────
            if (showRightPanel) ...[
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.12),
              ),
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
    // Solid-fill circle — black foreground on both weights clears WCAG AA
    // comfortably (the old white-on-purple pairing here measured 1.71:1).
    return CircleAvatar(
      backgroundColor: _isPast
          ? Colors.grey.shade400
          : (_isJam ? _orangeSoft.shade200 : _orangeBold.shade600),
      foregroundColor: Colors.black,
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
                  // Title text stays neutral for both gig types now — the
                  // jam/paid distinction is carried by the leading icon and
                  // card tint alone, not by a separate text color.
                  color: _isPast
                      ? Colors.grey.shade700
                      : Theme.of(context).textTheme.titleLarge?.color,
                ),
              ),
            ),
            if (_isRecurring && !_isJam)
              Padding(
                padding: const EdgeInsets.only(left: 6.0),
                child: Icon(
                  Icons.event_repeat,
                  size: 16,
                  // Neutral — purely decorative metadata, not a brand accent.
                  color: _isPast ? Colors.grey.shade600 : Colors.grey.shade400,
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
                color: _isPast ? Colors.grey.shade500 : _orangeBold.shade400,
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
          // Neutral for both gig types, same reasoning as the title above.
          style: TextStyle(
            color: _isPast
                ? Colors.grey.shade600
                : Theme.of(context).textTheme.bodyMedium?.color,
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
          Row(
            children: [
              const Text(
                'Open Mic / Jam Session',
                style:
                TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
              ),
              if (_attendanceLabel != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _attendanceColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: _attendanceColor, width: 1),
                  ),
                  child: Text(
                    _attendanceLabel!,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _attendanceColor,
                    ),
                  ),
                ),
              ],
            ],
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
                  // Kept as the darker-weight "gold" of the brand orange
                  // family rather than a separate hue (per the palette
                  // note above) — only the text color was actually broken:
                  // white-on-gold measured ~3.66:1, below the 4.5:1 minimum.
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
                    color: Colors.black,
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
              // Bonus fix found during the same pass: white-on-orange.700
              // here only measures ~2.7:1 — also below WCAG minimum. Black
              // clears it at ~7.8:1.
              child: const Text(
                'REVIEW',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
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
          color: _hasNotes ? _orangeBold.shade400 : Colors.grey.shade500,
        ),

      ],
    );
  }

  Color _getCardColor(BuildContext context) {
    if (_isJam) {
      // Soft orange tint over the normal card color — was
      // colorScheme.secondaryContainer, a purple/mauve tone auto-derived
      // from the deepPurple seed. This keeps jam cards visually distinct
      // from paid-gig cards using the same orange family instead of a
      // one-off hue.
      return Color.alphaBlend(
        _orangeSoft.withValues(alpha: 0.14),
        Theme.of(context).cardColor,
      );
    }
    return Theme.of(context).cardColor;
  }
}