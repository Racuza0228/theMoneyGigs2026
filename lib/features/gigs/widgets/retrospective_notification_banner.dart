// lib/features/gigs/widgets/retrospective_notification_banner.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';
import 'package:the_money_gigs/features/gigs/widgets/gig_retrospective_wizard.dart';

/// A banner that appears at the top of the app to prompt users to review past gigs
class RetrospectiveNotificationBanner extends StatelessWidget {
  final Gig gig;
  final int totalPendingCount;
  final VoidCallback onDismiss;
  final VoidCallback? onComplete;

  const RetrospectiveNotificationBanner({
    super.key,
    required this.gig,
    required this.totalPendingCount,
    required this.onDismiss,
    this.onComplete,
  });

  /// Returns a human-readable date label with the explicit date in parens.
  /// e.g. "Yesterday (Jun 12)" or "3 days ago (Jun 10)" or "Jun 1"
  String _getRelativeTimeWithDate() {
    final now = DateTime.now();
    final difference = now.difference(gig.dateTime);
    final formatted = DateFormat('MMM d').format(gig.dateTime);

    if (difference.inDays == 0) return 'Earlier today ($formatted)';
    if (difference.inDays == 1) return 'Yesterday ($formatted)';
    if (difference.inDays < 7) return '${difference.inDays} days ago ($formatted)';
    if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return weeks == 1 ? '1 week ago ($formatted)' : '$weeks weeks ago ($formatted)';
    }
    return formatted;
  }

  @override
  Widget build(BuildContext context) {
    print("✅ BANNER_DEBUG: RetrospectiveNotificationBanner build() method CALLED for gig: '${gig.venueName}'");

    return SafeArea(
      bottom: false,
      child: Material(
        elevation: 4,
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.9),
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Icon
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.rate_review,
                    color: Colors.white,
                    size: 24,
                  ),
                ),

                const SizedBox(width: 12),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Title row: "How'd it go?" + pending count badge
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              "How'd it go?",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (totalPendingCount > 1) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '+${totalPendingCount - 1} more',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),

                      const SizedBox(height: 2),

                      // Date line — prominent so user knows which gig this is
                      Text(
                        _getRelativeTimeWithDate(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      // Venue name — secondary, truncated if needed
                      Text(
                        gig.venueName,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Action buttons
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Review button
                    ElevatedButton(
                      onPressed: () async {
                        final result = await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => GigRetrospectiveWizard(
                              gig: gig,
                              onComplete: onComplete,
                            ),
                            fullscreenDialog: true,
                          ),
                        );

                        // If review was completed, dismiss banner
                        if (result != null) {
                          onDismiss();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Theme.of(context).colorScheme.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'REVIEW',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),

                    const SizedBox(width: 4),

                    // Dismiss button
                    IconButton(
                      onPressed: onDismiss,
                      icon: Icon(
                        Icons.close,
                        color: Colors.white.withValues(alpha: 0.8),
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Skip for now',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}