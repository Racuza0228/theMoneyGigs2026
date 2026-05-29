// lib/features/app_demo/services/demo_tracking_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../providers/demo_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:the_money_gigs/core/utils/logger.dart';
class DemoTrackingService {
  static const String _demoSessionIdKey = 'demo_session_id';
  static const String _needsSyncKey = 'demo_needs_sync';
  static const String _cachedStepKey = 'demo_cached_step';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Helper to check if we are truly offline
  Future<bool> _isOffline() async {
    final results = await (Connectivity().checkConnectivity());
    // Connectivity 6.0 returns a List, older versions return a single enum.
    // This handles both cases.
    if (results is List) {
      return results.contains(ConnectivityResult.none) || results.isEmpty;
    }
    return results == ConnectivityResult.none;
  }

  Future<void> syncPendingData() async {
    final prefs = await SharedPreferences.getInstance();
    final needsSync = prefs.getBool(_needsSyncKey) ?? false;

    if (!needsSync) return;

    if (await _isOffline()) return;

    log('📡 Internet detected, syncing pending demo data...');

    final cachedStepString = prefs.getString(_cachedStepKey);
    if (cachedStepString != null) {
      final step = DemoStep.values.firstWhere(
            (e) => e.toString() == cachedStepString,
        orElse: () => DemoStep.coachingIntro,
      );

      // This now works because we added the parameter below
      await updateDemoStep(step, isSyncing: true);
    }
  }

  Future<String> _getOrCreateSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    String? sessionId = prefs.getString(_demoSessionIdKey);
    if (sessionId == null) {
      sessionId = const Uuid().v4();
      await prefs.setString(_demoSessionIdKey, sessionId);
    }
    return sessionId;
  }

  Future<void> startDemoSession() async {
    try {
      final sessionId = await _getOrCreateSessionId();

      if (await _isOffline()) {
        log('📴 Offline: Session started locally, will sync on first step update.');
        return;
      }

      await _firestore.collection('demoSessions').doc(sessionId).set(
        {
          'sessionId': sessionId,
          'startedAt': FieldValue.serverTimestamp(),
          'lastUpdatedAt': FieldValue.serverTimestamp(),
          'lastStepViewed': DemoStep.coachingIntro.toString(),
          'isCompleted': false,
          'onboardingExited': false,
        },
        SetOptions(merge: true),
      );
      log('✅ Demo session started: $sessionId');
    } catch (e) {
      log('❌ Error starting demo session: $e');
    }
  }

  /// ✅ ADDED: {bool isSyncing = false} named parameter
  Future<void> updateDemoStep(DemoStep step, {bool isSyncing = false}) async {
    final prefs = await SharedPreferences.getInstance();

    try {
      // 1. Always save to local storage first as a "Backup"
      await prefs.setString(_cachedStepKey, step.toString());
      await prefs.setBool(_needsSyncKey, true);

      // 2. Check connectivity before trying Firebase
      if (await _isOffline()) {
        log('📴 Offline: Step ${step.toString()} saved locally for later sync.');
        return;
      }

      final sessionId = await _getOrCreateSessionId();
      final isCompleted = (step == DemoStep.complete);

      await _firestore.collection('demoSessions').doc(sessionId).update({
        'lastUpdatedAt': FieldValue.serverTimestamp(),
        'lastStepViewed': step.toString(),
        'isCompleted': isCompleted,
      }).timeout(const Duration(seconds: 5));

      // 3. If successful, clear the "Needs Sync" flag
      await prefs.setBool(_needsSyncKey, false);
      log('✅ Demo step synced to Firebase: ${step.toString()}');

    } catch (e) {
      log('⚠️ Firebase update failed (will retry later): $e');
    }
  }

  Future<void> exitDemoSession(DemoStep lastStep) async {
    try {
      if (await _isOffline()) {
        // Just clear locally if offline; syncPendingData will pick up the last step later
        log('📴 Offline: Exiting demo, cleanup handled locally.');
      } else {
        final sessionId = await _getOrCreateSessionId();
        await _firestore.collection('demoSessions').doc(sessionId).update({
          'lastUpdatedAt': FieldValue.serverTimestamp(),
          'lastStepViewed': lastStep.toString(),
          'onboardingExited': true,
          'isCompleted': false,
        });
        log('✅ Demo session exited at step: ${lastStep.toString()}');
      }
    } catch (e) {
      log('❌ Error marking demo as exited: $e');
    } finally {
      await clearLocalSession();
    }
  }

  Future<void> completeDemoSession() async {
    await clearLocalSession();
    log('✅ Local demo session cleared after completion.');
  }

  Future<void> clearLocalSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_demoSessionIdKey);
    // Also clear sync flags once the session is officially finished/exited
    await prefs.remove(_needsSyncKey);
    await prefs.remove(_cachedStepKey);
  }
}