// lib/features/gigs/widgets/gig_export_dialog.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';
import 'package:the_money_gigs/core/services/gig_embed_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:open_file/open_file.dart';
import 'package:the_money_gigs/core/models/enums.dart';
import 'package:the_money_gigs/features/gigs/services/gig_backup_service.dart';
import 'package:the_money_gigs/global_refresh_notifier.dart';

/// Shows the gig export dialog.
/// Pass [allGigs] (the raw master list from SharedPreferences) and
/// [allKnownVenues] (for privacy filtering on the HTML export).
Future<void> showGigExportDialog({
  required BuildContext context,
  required List<Gig> allGigs,
  required List<StoredLocation> allKnownVenues,
}) {
  return showDialog(
    context: context,
    builder: (_) => GigExportDialog(
      allGigs: allGigs,
      allKnownVenues: allKnownVenues,
    ),
  );
}

class GigExportDialog extends StatelessWidget {
  final List<Gig> allGigs;
  final List<StoredLocation> allKnownVenues;

  const GigExportDialog({
    super.key,
    required this.allGigs,
    required this.allKnownVenues,
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // CSV GENERATORS
  // ─────────────────────────────────────────────────────────────────────────────

  String _buildGigsCsv() {
    final sb = StringBuffer();
    sb.writeln(
      'ID,Venue,Band,Date,Time,Pay,OtherExpenses,EffectivePay,'
          'TrueHourlyRate,GigHours,DriveSetupHours,RehearsalHours,'
          'TotalHours,Address,Notes,IsRecurring,IsJamOpenMic,RetrospectiveDone',
    );

    // Expand all recurring gigs so every occurrence gets a row
    final rows = <Gig>[];
    for (final gig in allGigs) {
      if (!gig.isRecurring) {
        rows.add(gig);
      } else {
        // Include the base template as its own row so recurring series are
        // still represented even if no occurrences fall in the window.
        rows.add(gig);
      }
    }

    final fmt = DateFormat('yyyy-MM-dd');
    final timeFmt = DateFormat('HH:mm');

    for (final gig in rows) {
      final effectivePay = gig.pay - (gig.otherExpenses ?? 0.0);
      final totalHours =
          gig.gigLengthHours + gig.driveSetupTimeHours + gig.rehearsalLengthHours;
      sb.writeln([
        _csvCell(gig.id),
        _csvCell(gig.venueName),
        _csvCell(gig.bandName ?? ''),
        _csvCell(fmt.format(gig.dateTime)),
        _csvCell(timeFmt.format(gig.dateTime)),
        gig.pay.toStringAsFixed(2),
        (gig.otherExpenses ?? 0.0).toStringAsFixed(2),
        effectivePay.toStringAsFixed(2),
        gig.trueHourlyRate.toStringAsFixed(2),
        gig.gigLengthHours.toStringAsFixed(2),
        gig.driveSetupTimeHours.toStringAsFixed(2),
        gig.rehearsalLengthHours.toStringAsFixed(2),
        totalHours.toStringAsFixed(2),
        _csvCell(gig.address),
        _csvCell(gig.notes ?? ''),
        gig.isRecurring ? 'TRUE' : 'FALSE',
        gig.isJamOpenMic ? 'TRUE' : 'FALSE',
        (gig.retrospectiveCompleted ?? false) ? 'TRUE' : 'FALSE',
      ].join(','));
    }
    return sb.toString();
  }

  String _buildRatingsCsv() {
    final sb = StringBuffer();
    sb.writeln('GigID,Venue,Date,Dimension,Category,Rating');

    final fmt = DateFormat('yyyy-MM-dd');

    for (final gig in allGigs) {
      final ratings = gig.gigRatings;
      if (ratings == null || ratings.isEmpty) continue;
      for (final r in ratings) {
        sb.writeln([
          _csvCell(gig.id),
          _csvCell(gig.venueName),
          _csvCell(fmt.format(gig.dateTime)),
          _csvCell(r.dimension),
          _csvCell(r.category ?? ''),
          r.rating.toStringAsFixed(1),
        ].join(','));
      }
    }
    return sb.toString();
  }

  String _buildFinancialCsv() {
    final sb = StringBuffer();
    sb.writeln(
      'Venue,Band,Date,Pay,OtherExpenses,EffectivePay,'
          'GigHours,DriveSetupHours,RehearsalHours,TotalHours,TrueHourlyRate',
    );

    final fmt = DateFormat('yyyy-MM-dd');
    final payableGigs = allGigs.where((g) => !g.isJamOpenMic).toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

    for (final gig in payableGigs) {
      final effectivePay = gig.pay - (gig.otherExpenses ?? 0.0);
      final totalHours =
          gig.gigLengthHours + gig.driveSetupTimeHours + gig.rehearsalLengthHours;
      sb.writeln([
        _csvCell(gig.venueName),
        _csvCell(gig.bandName ?? ''),
        _csvCell(fmt.format(gig.dateTime)),
        gig.pay.toStringAsFixed(2),
        (gig.otherExpenses ?? 0.0).toStringAsFixed(2),
        effectivePay.toStringAsFixed(2),
        gig.gigLengthHours.toStringAsFixed(2),
        gig.driveSetupTimeHours.toStringAsFixed(2),
        gig.rehearsalLengthHours.toStringAsFixed(2),
        totalHours.toStringAsFixed(2),
        gig.trueHourlyRate.toStringAsFixed(2),
      ].join(','));
    }
    return sb.toString();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // ICS GENERATOR
  // ─────────────────────────────────────────────────────────────────────────────

  String _buildIcs() {
    final sb = StringBuffer();
    sb.writeln('BEGIN:VCALENDAR');
    sb.writeln('VERSION:2.0');
    sb.writeln('PRODID:-//The Money Gigs//EN');
    sb.writeln('CALSCALE:GREGORIAN');
    sb.writeln('METHOD:PUBLISH');

    final now = DateTime.now();

    // Only non-jam gigs. Recurring templates are emitted with RRULE;
    // non-recurring gigs that have already ended are skipped.
    final gigsToExport = allGigs.where((g) {
      if (g.isJamOpenMic) return false;
      if (g.isRecurring) return true; // series handled via RRULE regardless of base date
      return g.dateTime.isAfter(now);
    }).toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

    for (final gig in gigsToExport) {
      final endTime = gig.dateTime
          .add(Duration(minutes: (gig.gigLengthHours * 60).toInt()));

      final summary = gig.bandName != null
          ? '${gig.bandName} @ ${gig.venueName}'
          : 'Gig @ ${gig.venueName}';

      final descParts = <String>[
        'Pay: \$${gig.pay.toStringAsFixed(2)}',
        'True Rate: \$${gig.trueHourlyRate.toStringAsFixed(2)}/hr',
        if (gig.notes != null && gig.notes!.isNotEmpty) 'Notes: ${gig.notes}',
      ];

      sb.writeln('BEGIN:VEVENT');
      sb.writeln('UID:${gig.id}@themoneygigs');
      sb.writeln('DTSTAMP:${_icsDateTime(now)}');
      sb.writeln('DTSTART:${_icsDateTime(gig.dateTime)}');
      sb.writeln('DTEND:${_icsDateTime(endTime)}');
      sb.writeln('SUMMARY:${_icsEscape(summary)}');
      sb.writeln('LOCATION:${_icsEscape(gig.address)}');
      sb.writeln('DESCRIPTION:${_icsEscape(descParts.join('\\n'))}');

      // ── Recurrence rule ────────────────────────────────────────────────────
      if (gig.isRecurring &&
          gig.recurrenceFrequency != null &&
          gig.recurrenceDay != null) {
        final rrule = _buildRRule(gig);
        if (rrule != null) sb.writeln('RRULE:$rrule');

        // Exceptions — dates the series skips
        if (gig.recurrenceExceptions != null &&
            gig.recurrenceExceptions!.isNotEmpty) {
          for (final exDate in gig.recurrenceExceptions!) {
            // Use the same time-of-day as the base event so the EXDATE
            // matches the DTSTART timezone handling.
            final exDateTime = DateTime(
              exDate.year, exDate.month, exDate.day,
              gig.dateTime.hour, gig.dateTime.minute,
            );
            sb.writeln('EXDATE:${_icsDateTime(exDateTime)}');
          }
        }
      }

      sb.writeln('END:VEVENT');
    }

    sb.writeln('END:VCALENDAR');
    return sb.toString();
  }

// Maps the app's recurrence model to an RFC 5545 RRULE string (without the
// "RRULE:" prefix — the caller adds that).
  String? _buildRRule(Gig gig) {
    // DayOfWeek.index 0 = Monday, matching DateTime.weekday convention
    // where Monday = 1. ICS day codes in the same order:
    const icsDays = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
    final dayCode = icsDays[gig.recurrenceDay!.index];

    // Optional UNTIL clause
    String untilClause = '';
    if (gig.recurrenceEndDate != null) {
      // UNTIL is inclusive and should be end-of-day UTC
      final until = DateTime(
        gig.recurrenceEndDate!.year,
        gig.recurrenceEndDate!.month,
        gig.recurrenceEndDate!.day,
        23, 59, 59,
      ).toUtc();
      untilClause = ';UNTIL=${_icsDateTime(until)}';
    }

    switch (gig.recurrenceFrequency!) {
      case JamFrequencyType.weekly:
        return 'FREQ=WEEKLY;BYDAY=$dayCode$untilClause';

      case JamFrequencyType.biWeekly:
        return 'FREQ=WEEKLY;INTERVAL=2;BYDAY=$dayCode$untilClause';

      case JamFrequencyType.customNthDay:
        final n = gig.recurrenceNthValue ?? 1;
        return 'FREQ=WEEKLY;INTERVAL=$n;BYDAY=$dayCode$untilClause';

      case JamFrequencyType.monthlySameDay:
        final nth = gig.recurrenceNthValue ?? 1;
        // e.g. 2nd Tuesday = BYDAY=2TU
        return 'FREQ=MONTHLY;BYDAY=$nth$dayCode$untilClause';

      default:
        return null; // Unknown frequency — skip RRULE, emit as one-off
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // OPEN ICS IN DEVICE CALENDAR
  // ─────────────────────────────────────────────────────────────────────────────

  /// Writes the ICS content to a temp file and hands it to the OS.
  /// On iOS this triggers "Add All to Calendar" natively.
  /// On Android it opens whichever app is registered for text/calendar
  /// (Google Calendar, Samsung Calendar, etc.) or the share sheet if none.
  Future<void> _openInCalendar(BuildContext context) async {
    try {
      final icsContent = _buildIcs();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/my_gigs.ics');
      await file.writeAsString(icsContent);

      // ACTION_VIEW fires directly to apps registered as ICS handlers
      // (Google Calendar, etc.) rather than the generic share sheet.
      final result = await OpenFile.open(
        file.path,
        type: 'text/calendar',
      );

      if (result.type == ResultType.noAppToOpen && context.mounted) {
        // Graceful fallback: no calendar app found, offer share sheet instead
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No calendar app found — use Copy ICS to import manually.'),
            action: SnackBarAction(
              label: 'Share Instead',
              onPressed: () async {
                await Share.shareXFiles(
                  [XFile(file.path, mimeType: 'text/calendar', name: 'my_gigs.ics')],
                  subject: 'My Upcoming Gigs',
                );
              },
            ),
          ),
        );
      } else if (result.type == ResultType.done && context.mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open calendar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // ── FULL DEVICE BACKUP ───────────────────────────────────────────────────────
  // Uses GigBackupService which reads all SharedPreferences keys, not just gigs.
  // This captures venues, profile, settings, retrospective dimensions — everything.

  // ─────────────────────────────────────────────────────────────────────────────
  // HTML EMBED (existing functionality, preserved)
  // ─────────────────────────────────────────────────────────────────────────────

  String _buildHtml() {
    final publicGigs = allGigs.where((gig) {
      final sourceVenue = allKnownVenues.firstWhere(
            (v) => v.placeId == gig.placeId,
        orElse: () => StoredLocation(
          placeId: '',
          name: '',
          address: '',
          coordinates: LatLng(0, 0),
        ),
      );
      return !sourceVenue.isPrivate;
    }).toList();
    return GigEmbedService.generateEmbedCode(publicGigs);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────────

  static String _csvCell(String value) {
    // Wrap in quotes and escape any internal quotes
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  static String _icsDateTime(DateTime dt) {
    // Format: 20260401T190000Z  (UTC)
    final utc = dt.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}'
        '${utc.month.toString().padLeft(2, '0')}'
        '${utc.day.toString().padLeft(2, '0')}'
        'T'
        '${utc.hour.toString().padLeft(2, '0')}'
        '${utc.minute.toString().padLeft(2, '0')}'
        '${utc.second.toString().padLeft(2, '0')}'
        'Z';
  }

  static String _icsEscape(String value) =>
      value.replaceAll(',', '\\,').replaceAll(';', '\\;');

  // ─────────────────────────────────────────────────────────────────────────────
  // COPY TO CLIPBOARD + SNACKBAR
  // ─────────────────────────────────────────────────────────────────────────────

  void _copyAndClose(BuildContext context, String data, String label) {
    Clipboard.setData(ClipboardData(text: data));
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final hasGigs = allGigs.isNotEmpty;
    final hasRatings = allGigs.any((g) => g.gigRatings?.isNotEmpty == true);
    final now = DateTime.now();
    final hasUpcoming = allGigs.any((g) {
      if (g.isJamOpenMic) return false;
      // A recurring series whose start date is in the past is still "upcoming"
      // as long as it has no end date or its end date hasn't passed yet.
      if (g.isRecurring) {
        return g.recurrenceEndDate == null || g.recurrenceEndDate!.isAfter(now);
      }
      return g.dateTime.isAfter(now);
    });

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header ──────────────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius:
              const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Icon(Icons.upload_file, color: colorScheme.onPrimary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Export Gig Data',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon:
                  Icon(Icons.close, color: colorScheme.onPrimary),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),

          // ── Scrollable body ─────────────────────────────────────────────────
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── SPREADSHEETS ──────────────────────────────────────────
                  _SectionHeader(
                    icon: Icons.table_chart_outlined,
                    label: 'Spreadsheets',
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 8),

                  _ExportTile(
                    icon: Icons.event_note,
                    iconColor: colorScheme.primary,
                    title: 'All Gigs (CSV)',
                    subtitle:
                    'Every gig with pay, hours, and true hourly rate. '
                        'Import into Excel, Google Sheets, or Numbers.',
                    buttonLabel: 'Copy CSV',
                    enabled: hasGigs,
                    disabledReason: 'No gigs yet',
                    onPressed: () => _copyAndClose(
                      context,
                      _buildGigsCsv(),
                      'Gigs CSV',
                    ),
                  ),

                  _ExportTile(
                    icon: Icons.star_half,
                    iconColor: Colors.amber.shade700,
                    title: 'Retrospective Ratings (CSV)',
                    subtitle:
                    'One row per rated dimension per gig — great for '
                        'spotting venue or crowd trends over time.',
                    buttonLabel: 'Copy CSV',
                    enabled: hasRatings,
                    disabledReason: 'No ratings recorded yet',
                    onPressed: () => _copyAndClose(
                      context,
                      _buildRatingsCsv(),
                      'Ratings CSV',
                    ),
                  ),

                  _ExportTile(
                    icon: Icons.attach_money,
                    iconColor: Colors.green.shade700,
                    title: 'Financial Summary (CSV)',
                    subtitle:
                    'Pre-calculated income view: effective pay, total '
                        'hours, and true rate per gig — useful for taxes.',
                    buttonLabel: 'Copy CSV',
                    enabled: hasGigs,
                    disabledReason: 'No gigs yet',
                    onPressed: () => _copyAndClose(
                      context,
                      _buildFinancialCsv(),
                      'Financial Summary CSV',
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── CALENDAR ──────────────────────────────────────────────
                  _SectionHeader(
                    icon: Icons.calendar_month_outlined,
                    label: 'Calendar',
                    color: Colors.deepPurple,
                  ),
                  const SizedBox(height: 8),

                  _ExportTile(
                    icon: Icons.event,
                    iconColor: Colors.deepPurple,
                    title: 'Upcoming Gigs (ICS / iCal)',
                    subtitle:
                    'Import into Google Calendar, Apple Calendar, or Outlook.',
                    buttonLabel: 'Copy ICS',
                    enabled: hasUpcoming,
                    disabledReason: 'No upcoming gigs',
                    onPressed: () =>
                        _copyAndClose(context, _buildIcs(), 'ICS data'),
                    secondaryButtonLabel: 'Open in Calendar',
                    secondaryIcon: Icons.calendar_month,
                    onSecondaryPressed: () => _openInCalendar(context),
                  ),

                  const SizedBox(height: 16),

                  // ── WEB ───────────────────────────────────────────────────
                  _SectionHeader(
                    icon: Icons.language_outlined,
                    label: 'Web',
                    color: Colors.teal,
                  ),
                  const SizedBox(height: 8),

                  _ExportTile(
                    icon: Icons.code,
                    iconColor: Colors.teal,
                    title: 'Upcoming Gigs (HTML Embed)',
                    subtitle:
                    'Paste into your website to display a live gig list. '
                        'Only shows public venues.',
                    buttonLabel: 'Copy HTML',
                    enabled: hasUpcoming,
                    disabledReason: 'No upcoming gigs',
                    onPressed: () => _copyAndClose(
                      context,
                      _buildHtml(),
                      'HTML embed code',
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── BACKUP & RESTORE ──────────────────────────────────────
                  _SectionHeader(
                    icon: Icons.backup_outlined,
                    label: 'Backup & Restore',
                    color: Colors.blueGrey,
                  ),
                  const SizedBox(height: 8),

                  // Export — full device backup via GigBackupService
                  _ExportTile(
                    icon: Icons.data_object,
                    iconColor: Colors.blueGrey,
                    title: 'Full Device Backup (JSON)',
                    subtitle:
                    'All your data: gigs, venues, profile, settings. '
                        'Copy and save somewhere safe — Notes, Drive, email.',
                    buttonLabel: 'Copy JSON',
                    enabled: hasGigs,
                    disabledReason: 'No data yet',
                    onPressed: () async {
                      try {
                        final json = await GigBackupService.exportAll();
                        if (context.mounted) {
                          _copyAndClose(context, json, 'Full backup');
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Export failed: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),

                  // Restore
                  _ExportTile(
                    icon: Icons.restore,
                    iconColor: Colors.deepOrange,
                    title: 'Restore from Backup',
                    subtitle:
                    'Paste a previously exported JSON backup to '
                        'restore all your data. Replaces current data.',
                    buttonLabel: 'Restore…',
                    enabled: true,
                    disabledReason: '',
                    onPressed: () {
                      Navigator.of(context).pop();
                      _showRestoreDialog(context);
                    },
                  ),

                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── RESTORE DIALOG ──────────────────────────────────────────────────────────

  static void _showRestoreDialog(BuildContext context) {
    final controller = TextEditingController();
    bool isRestoring = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            title: const Text('Restore from Backup'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Warning banner
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Colors.deepOrange.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber,
                            color: Colors.deepOrange, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This will replace all current data. '
                                'Make a backup first if needed.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.deepOrange.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Paste your backup JSON below:',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    maxLines: 8,
                    enabled: !isRestoring,
                    decoration: InputDecoration(
                      hintText: '{ "_meta": { ... }, "data": { ... } }',
                      hintStyle: TextStyle(
                          fontSize: 12, color: Colors.grey.shade500),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isRestoring
                    ? null
                    : () => Navigator.of(ctx).pop(),
                child: const Text('CANCEL'),
              ),
              ElevatedButton(
                onPressed: isRestoring
                    ? null
                    : () async {
                  final text = controller.text.trim();
                  if (text.isEmpty) return;

                  setState(() => isRestoring = true);

                  final result =
                  await GigBackupService.importAll(text);

                  if (!ctx.mounted) return;

                  Navigator.of(ctx).pop();

                  if (result.success) {
                    // Fire global refresh so every page reloads
                    globalRefreshNotifier.notify();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Restored ${result.restoredKeys} items successfully.',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          result.errorMessage ?? 'Restore failed.',
                        ),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 6),
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                ),
                child: isRestoring
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Text('RESTORE',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PRIVATE HELPER WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Divider(color: color.withOpacity(0.3))),
      ],
    );
  }
}

class _ExportTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final bool enabled;
  final String disabledReason;
  final VoidCallback onPressed;

  // Optional second action — rendered as an outlined button to the left of
  // the primary FilledButton.tonal so the hierarchy is visually clear.
  final String? secondaryButtonLabel;
  final IconData? secondaryIcon;
  final VoidCallback? onSecondaryPressed;

  const _ExportTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.enabled,
    required this.disabledReason,
    required this.onPressed,
    this.secondaryButtonLabel,
    this.secondaryIcon,
    this.onSecondaryPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top row: icon + text ──────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: iconColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          enabled ? subtitle : disabledReason,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: enabled
                                ? theme.colorScheme.onSurfaceVariant
                                : theme.colorScheme.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // ── Button row ────────────────────────────────────────────────
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Secondary button (e.g. "Open in Calendar") — shown only
                  // when provided; uses outlined style to feel subordinate.
                  if (secondaryButtonLabel != null) ...[
                    OutlinedButton.icon(
                      onPressed: enabled ? onSecondaryPressed : null,
                      icon: Icon(secondaryIcon ?? Icons.open_in_new, size: 14),
                      label: Text(
                        secondaryButtonLabel!,
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        side: BorderSide(
                          color: enabled
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outline,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

                  // Primary button (always present)
                  FilledButton.tonal(
                    onPressed: enabled ? onPressed : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(buttonLabel, style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}