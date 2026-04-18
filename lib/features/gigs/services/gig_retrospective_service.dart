// lib/features/gigs/services/gig_retrospective_service.dart

import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';

/// Service to manage gig retrospective checks and reminders
class GigRetrospectiveService {
  static const String _keyLastRetrospectiveCheck = 'last_retrospective_check';
  static const String _keySkippedGigs = 'skipped_retrospective_gigs';

  static Future<List<Gig>> getGigsNeedingRetrospective() async {
    print("✅ BANNER_DEBUG: Service: getGigsNeedingRetrospective called.");
    final prefs = await SharedPreferences.getInstance();
    final gigsJsonString = prefs.getString('gigs_list') ?? '[]';
    final List<Gig> allGigs = Gig.decode(gigsJsonString);

    print("✅ BANNER_DEBUG: Service: Found ${allGigs.length} total gigs in storage.");
    if (allGigs.isEmpty) {
      print("✅ BANNER_DEBUG: Service: No gigs to check. Returning empty list.");
      return [];
    }

    // Get list of gigs skipped in this session
    final skippedGigIds = prefs.getStringList(_keySkippedGigs) ?? [];
    print("✅ BANNER_DEBUG: Service: Found ${skippedGigIds.length} skipped gig IDs: $skippedGigIds");

    // Filter to gigs that need retrospective and haven't been skipped
    final needsReview = allGigs.where((gig) {
      final needsRetro = gig.needsRetrospective;
      final isSkipped = skippedGigIds.contains(gig.id);
      print("✅ BANNER_DEBUG: Service: Checking gig '${gig.venueName}' -> needsRetrospective: $needsRetro, isSkipped: $isSkipped");
      return needsRetro && !isSkipped;
    }).toList();

    print("✅ BANNER_DEBUG: Service: Found ${needsReview.length} gigs that need review.");

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
      print("✅ BANNER_DEBUG: Service: Marked gig $gigId as skipped for this session.");

    }
  }

  /// Clear the list of skipped gigs (call when app restarts or after a period)
  static Future<void> clearSkippedGigs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySkippedGigs);
    print("✅ BANNER_DEBUG: Service: Cleared the list of skipped gigs.");
  }

  /// Check if we should show the retrospective prompt
  /// (Don't show more than once per day to avoid annoying the user)
  static Future<bool> shouldShowRetrospectivePrompt() async {
    print("✅ BANNER_DEBUG: Service: shouldShowRetrospectivePrompt called.");
    final prefs = await SharedPreferences.getInstance();
    final lastCheckString = prefs.getString(_keyLastRetrospectiveCheck);

    if (lastCheckString == null) {
      print("✅ BANNER_DEBUG: Service: No last check time found. Returning true.");
      return true;
    }
    final lastCheck = DateTime.parse(lastCheckString);
    final now = DateTime.now();
    final hoursSinceLastCheck = now.difference(lastCheck).inHours; // Using hours for more granular debugging
    final daysSinceLastCheck = now.difference(lastCheck).inDays;

    print("✅ BANNER_DEBUG: Service: Last check was at $lastCheck (${hoursSinceLastCheck} hours ago). Days since: $daysSinceLastCheck.");

    // Show prompt once per day maximum
    if (daysSinceLastCheck >= 1) {
      print("✅ BANNER_DEBUG: Service: It has been >= 1 day. Returning true.");
      return true;
    } else {
      print("✅ BANNER_DEBUG: Service: It has been < 1 day. Returning false.");
      return true;
    }
  }

  /// Record that we've shown the retrospective prompt
  static Future<void> recordRetrospectivePromptShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastRetrospectiveCheck, DateTime.now().toIso8601String());
    print("✅ BANNER_DEBUG: Service: Recorded that prompt has been shown now.");
  }

  /// Check if user should be prompted on app startup
  /// Returns the first gig that needs review, or null if none
  static Future<Gig?> checkForRetrospectiveOnStartup() async {
    print("✅ BANNER_DEBUG: Service: Recorded that prompt has been shown now.");
    // Check if we should show prompt (rate limiting)
    if (!await shouldShowRetrospectivePrompt()) {
      print("✅ BANNER_DEBUG: Service: Rate limit active. Not showing prompt. Returning null.");
      return null;
     }

    // Get gigs needing review
    final gigsNeedingReview = await getGigsNeedingRetrospective();

    if (gigsNeedingReview.isEmpty) {
      print("✅ BANNER_DEBUG: Service: No gigs found needing review. Returning null.");
      return null;
    }

    // Record that we're showing the prompt
    await recordRetrospectivePromptShown();

    print("✅ BANNER_DEBUG: Service: Found ${gigsNeedingReview.length} gigs. Returning the first one: '${gigsNeedingReview.first.venueName}'.");

    // Return the oldest gig needing review
    return gigsNeedingReview.first;
  }
}