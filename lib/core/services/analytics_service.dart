// lib/core/services/analytics_service.dart
//
// Silent, best-effort usage tracking — the direct answer to "are people
// actually opening this app and using it, or just installing it and going
// quiet" (8/9 retro finding).
//
// Two hard rules, per Cliff (8/9):
//   1. Users must never know this exists — no UI, no permission prompt.
//      Firebase Analytics collection doesn't trigger anything like App
//      Tracking Transparency on its own (that's only required for
//      cross-app/cross-site ad attribution, which this isn't), so this is
//      satisfied by default.
//   2. This must never be able to fail the app. Every call below is wrapped
//      in try/catch with nothing rethrown — same pattern already used for
//      FirebaseCrashlytics calls in main.dart. A bad network moment just
//      silently drops the event; it never touches the user-facing flow.
//
// Works for standalone AND network-member installs. Firebase.initializeApp()
// already runs unconditionally at launch for every user (see main.dart) —
// this doesn't require sign-in or an invite code, just Firebase having
// initialized successfully.

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:the_money_gigs/core/utils/logger.dart';

class AnalyticsService {
  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  /// Call once, early in main(), right after Firebase.initializeApp()
  /// succeeds. Tags every subsequent event with whether this install is
  /// standalone or a network member, so usage can be sliced by segment
  /// with no extra plumbing. Reuses the same 'is_connected_to_network' flag
  /// main.dart already reads for RevenueCat setup — no new source of truth.
  static Future<void> setUserType(bool isNetworkMember) async {
    try {
      await _analytics.setUserProperty(
        name: 'user_type',
        value: isNetworkMember ? 'network' : 'standalone',
      );
    } catch (e) {
      log('Analytics setUserType failed (non-fatal): $e');
    }
  }

  /// Fired once per cold start, right after Firebase init succeeds.
  static Future<void> logAppOpen() async {
    try {
      await _analytics.logAppOpen();
    } catch (e) {
      log('Analytics logAppOpen failed (non-fatal): $e');
    }
  }

  /// True app termination isn't reliably observable on mobile (iOS in
  /// particular just suspends without a guaranteed callback). This fires on
  /// AppLifecycleState.paused (backgrounded) — the standard proxy every
  /// analytics SDK uses for "session end."
  static Future<void> logAppClose() async {
    try {
      await _analytics.logEvent(name: 'app_close');
    } catch (e) {
      log('Analytics logAppClose failed (non-fatal): $e');
    }
  }

  /// One event, all four tabs — tab_name is the dimension, not the event
  /// name, so this also covers Gig Calculator / My Gigs / Profile access
  /// without needing a separate call per tab.
  static Future<void> logMainNavAccess(String tabName) async {
    try {
      await _analytics.logEvent(
        name: 'main_nav_access',
        parameters: {'tab_name': tabName},
      );
    } catch (e) {
      log('Analytics logMainNavAccess failed (non-fatal): $e');
    }
  }

  static Future<void> logVenueDetailsAccess({
    required String venueName,
    String? placeId,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'venue_details_access',
        parameters: {
          'venue_name': venueName,
          if (placeId != null) 'place_id': placeId,
        },
      );
    } catch (e) {
      log('Analytics logVenueDetailsAccess failed (non-fatal): $e');
    }
  }

  /// Fired only on a genuinely new booking (not edits) — the BOOK button
  /// specifically, per Cliff (8/9), regardless of which of the three entry
  /// points it came from (map, calculator, or the "+" button/Add Gig flow).
  /// Added 8/17/26 — Apple Sign-In failures at Nashville (8/14) left zero
  /// trace anywhere retrievable (see the recordError note in auth_service.dart
  /// for the full story). This + Crashlytics are the two places that data
  /// will show up going forward.
  static Future<void> logAppleSignInFailed({
    required String errorCode,
    String? errorMessage,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'apple_signin_failed',
        parameters: {
          'error_code': errorCode,
          if (errorMessage != null) 'error_message': errorMessage,
        },
      );
    } catch (e) {
      log('Analytics logAppleSignInFailed failed (non-fatal): $e');
    }
  }

  static Future<void> logGigBooked({
    required String entryPoint, // 'calculator' | 'map' | 'add_button'
    required bool hasBand,
    required bool isRecurring,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'gig_booked',
        parameters: {
          'entry_point': entryPoint,
          'has_band': hasBand,
          'is_recurring': isRecurring,
        },
      );
    } catch (e) {
      log('Analytics logGigBooked failed (non-fatal): $e');
    }
  }
}
