// lib/features/gigs/services/gig_retrospective_service.dart

import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';

/// Service to manage gig retrospective checks and reminders
class GigRetrospectiveService {
  static const String _keyLastRetrospectiveCheck = 'last_retrospective_check';
  static const String _keySkippedGigs = 'skipped_retrospective_gigs';

  /// Check if there are any completed gigs that need retrospectives
  /// Returns a list of gigs that:
  /// - Have ended
  /// - Don't have retrospective completed
  /// - Aren't jam/open mic sessions
  /// - Haven't been skipped in this session
  static Future<List<Gig>> getGigsNeedingRetrospective() async {
    final prefs = await SharedPreferences.getInstance();
    final gigsJsonString = prefs.getString('gigs_list') ?? '[]';
    final List<Gig> allGigs = Gig.decode(gigsJsonString);

    // Get list of gigs skipped in this session
    final skippedGigIds = prefs.getStringList(_keySkippedGigs) ?? [];

    // Filter to gigs that need retrospective and haven't been skipped
    final needsReview = allGigs.where((gig) =>
    gig.needsRetrospective && !skippedGigIds.contains(gig.id)
    ).toList();

    // Sort by date (oldest first) so users review gigs chronologically
    needsReview.sort((a, b) => a.dateTime.compareTo(b.dateTime));

    return needsReview;
  }

  /// Mark a gig as skipped for this session
  static Future<void> skipGigRetrospective(String gigId) async {
    final prefs = await SharedPreferences.getInstance();
    final skippedGigIds = prefs.getStringList(_keySkippedGigs) ?? [];

    if (!skippedGigIds.contains(gigId)) {
      skippedGigIds.add(gigId);
      await prefs.setStringList(_keySkippedGigs, skippedGigIds);
    }
  }

  /// Clear the list of skipped gigs (call when app restarts or after a period)
  static Future<void> clearSkippedGigs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySkippedGigs);
  }

  /// Check if we should show the retrospective prompt
  /// (Don't show more than once per day to avoid annoying the user)
  static Future<bool> shouldShowRetrospectivePrompt() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCheckString = prefs.getString(_keyLastRetrospectiveCheck);

    if (lastCheckString == null) return true;

    final lastCheck = DateTime.parse(lastCheckString);
    final now = DateTime.now();
    final daysSinceLastCheck = now.difference(lastCheck).inDays;

    // Show prompt once per day maximum
    return daysSinceLastCheck >= 1;
  }

  /// Record that we've shown the retrospective prompt
  static Future<void> recordRetrospectivePromptShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastRetrospectiveCheck, DateTime.now().toIso8601String());
  }

  /// Check if user should be prompted on app startup
  /// Returns the first gig that needs review, or null if none
  static Future<Gig?> checkForRetrospectiveOnStartup() async {
    // Check if we should show prompt (rate limiting)
    if (!await shouldShowRetrospectivePrompt()) {
       return null;
     }

    // Get gigs needing review
    final gigsNeedingReview = await getGigsNeedingRetrospective();

    if (gigsNeedingReview.isEmpty) {
      return null;
    }

    // Record that we're showing the prompt
    await recordRetrospectivePromptShown();

    // Return the oldest gig needing review
    return gigsNeedingReview.first;
  }
}