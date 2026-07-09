// lib/core/services/revenuecat_gate.dart
//
// Single shared gate for RevenueCat configuration. Import this file
// anywhere you're about to call a Purchases.* method — main.dart,
// auth_service.dart, subscription_service.dart, or any future caller —
// and call `await ensureRevenueCatConfigured();` first.
//
// Fixes two bugs found via Crashlytics on 7/9/26:
//   1. main.dart's old flag was set to `true` even when configure()
//      FAILED, permanently blocking retries for the rest of the session.
//   2. RevenueCat was only configured at launch for users who were
//      already "network" users in a PREVIOUS session. A brand-new
//      install redeeming an invite code for the first time never
//      triggered configuration before auth_service.dart / subscription_
//      service.dart called into Purchases — causing:
//      "Fatal error: Purchases has not been configured."
//
// This function is idempotent and safe to call from multiple places,
// including concurrently — repeated calls before success all await the
// same in-flight attempt instead of racing separate configure() calls.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:the_money_gigs/core/utils/logger.dart';

bool _configured = false; // true ONLY after a confirmed successful configure()
Future<bool>? _inFlight; // in-progress attempt, shared by concurrent callers

String _revenueCatApiKey() {
  if (kDebugMode) {
    return 'test_sFBpSvZPjpQyWyuLyPobraUtyfL';
  } else {
    if (Platform.isIOS) {
      return 'appl_epUaEdlDadBKMraKrhAnthTlRen';
    } else {
      return 'goog_yRlYImMZVYNNvyxpsoGSDNsaaaJ';
    }
  }
}

/// Ensures RevenueCat is configured before any Purchases.* call.
/// Call this as the first line of any method that touches Purchases.
/// Returns true if configured (this call or a previous one), false if
/// configuration failed and the caller should treat RevenueCat as
/// unavailable for now (it will retry automatically on the next call).
Future<bool> ensureRevenueCatConfigured() async {
  if (_configured) return true;

  // If another call is already configuring, wait on that same attempt
  // instead of firing a second concurrent Purchases.configure().
  if (_inFlight != null) return _inFlight!;

  final attempt = () async {
    log('🚀 Configuring RevenueCat...');
    try {
      final apiKey = _revenueCatApiKey();
      await Purchases.configure(PurchasesConfiguration(apiKey));
      _configured = true;
      log('✅ RevenueCat configured (${kDebugMode ? 'TEST' : 'PRODUCTION'})');
      return true;
    } catch (e) {
      // Deliberately NOT setting _configured = true here — leaving it
      // false means the very next call anywhere in the app will retry
      // instead of silently assuming RevenueCat is ready.
      log('❌ RevenueCat configure failed, will retry on next call: $e');
      return false;
    } finally {
      _inFlight = null;
    }
  }();

  _inFlight = attempt;
  return attempt;
}