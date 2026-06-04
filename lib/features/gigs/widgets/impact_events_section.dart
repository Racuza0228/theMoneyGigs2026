// lib/features/gigs/widgets/impact_events_section.dart
//
// A self-contained widget that displays impact events for a gig.
// Drop this into NotesPage as a new section above the notes text field.
//
// Usage in NotesPage build():
//
//   if (_isEditingGig && _currentGig != null && (_currentGig!.impactEventCount > 0)) ...[
//     const SizedBox(height: 20),
//     ImpactEventsSection(gig: _currentGig!),
//   ],

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:the_money_gigs/features/gigs/models/impact_event.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';

class ImpactEventsSection extends StatelessWidget {
  final Gig gig;

  const ImpactEventsSection({super.key, required this.gig});

  @override
  Widget build(BuildContext context) {
    final events = gig.impactEvents ?? [];
    if (events.isEmpty) return const SizedBox.shrink();

    final lastAssessed = gig.lastAssessedAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ────────────────────────────────────────────────────
        Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: Colors.deepOrange.shade600,
            ),
            const SizedBox(width: 6),
            Text(
              'Nearby Events',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.deepOrange.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Events in the ${_windowDescription()} that could affect your crowd.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.6),
          ),
        ),
        const Divider(height: 16),

        // ── Event rows ────────────────────────────────────────────────────────
        ...events.map((event) => _ImpactEventRow(event: event)),

        // ── Last assessed timestamp ───────────────────────────────────────────
        if (lastAssessed != null)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              'Last checked ${_formatRelativeTime(lastAssessed)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.4),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }

  String _windowDescription() {
    const before = 5; // kImpactWindowDaysBefore
    if (before == 1) return '1 day before this gig';
    return '$before days before this gig';
  }

  String _formatRelativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ── Individual event row ───────────────────────────────────────────────────────

class _ImpactEventRow extends StatelessWidget {
  final ImpactEvent event;

  const _ImpactEventRow({required this.event});

  Color _levelColor() {
    switch (event.impactLevel) {
      case 'high':
        return Colors.deepOrange.shade600;
      case 'medium':
        return Colors.orange.shade600;
      default:
        return Colors.grey.shade500;
    }
  }

  String _levelLabel() {
    switch (event.impactLevel) {
      case 'high':
        return 'HIGH';
      case 'medium':
        return 'MED';
      default:
        return 'LOW';
    }
  }

  Future<void> _launchUrl(BuildContext context) async {
    if (event.sourceUrl == null || event.sourceUrl!.isEmpty) return;
    final uri = Uri.tryParse(event.sourceUrl!);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('EEE, MMM d').format(event.eventDate);
    final hasLink = event.sourceUrl?.isNotEmpty ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: InkWell(
        onTap: hasLink ? () => _launchUrl(context) : null,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Event type icon
            Padding(
              padding: const EdgeInsets.only(top: 2.0, right: 10.0),
              child: Icon(
                IconData(event.iconCodePoint, fontFamily: 'MaterialIcons'),
                size: 20,
                color: _levelColor(),
              ),
            ),

            // Name and date
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.eventName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                      if (event.distanceMiles != null) ...[
                        Text(
                          '  ·  ${event.distanceMiles!.toStringAsFixed(1)} mi away',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Impact level pill + optional external link icon
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: _levelColor().withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: _levelColor().withValues(alpha: 0.4), width: 0.8),
                  ),
                  child: Text(
                    _levelLabel(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _levelColor(),
                    ),
                  ),
                ),
                if (hasLink)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Icon(
                      Icons.open_in_new,
                      size: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.35),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}