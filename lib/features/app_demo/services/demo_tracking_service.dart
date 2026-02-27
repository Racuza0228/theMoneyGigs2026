import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../providers/demo_provider.dart';

class DemoTrackingService {
  static const String _demoSessionIdKey = 'demo_session_id';
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<String> _getOrCreateSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    String? sessionId = prefs.getString(_demoSessionIdKey);
    if (sessionId == null) {
      sessionId = const Uuid().v4();
      await prefs.setString(_demoSessionIdKey, sessionId);
    }
    return sessionId;
  }

  // Called when the demo first starts
  Future<void> startDemoSession() async {
    try {
      final sessionId = await _getOrCreateSessionId();
      await _firestore.collection('demoSessions').doc(sessionId).set(
        {
          'sessionId': sessionId,
          'startedAt': FieldValue.serverTimestamp(),
          'lastUpdatedAt': FieldValue.serverTimestamp(),
          'lastStepViewed': DemoStep.coachingIntro.toString(),
          'isCompleted': false,
          'onboardingExited': false, // Initialize new field
        },
        SetOptions(merge: true),
      );
      print('✅ Demo session started: $sessionId');
    } catch (e) {
      print('❌ Error starting demo session: $e');
    }
  }

  // Called every time the step advances
  Future<void> updateDemoStep(DemoStep step) async {
    try {
      final sessionId = await _getOrCreateSessionId();
      final isCompleted = (step == DemoStep.complete);

      await _firestore.collection('demoSessions').doc(sessionId).update({
        'lastUpdatedAt': FieldValue.serverTimestamp(),
        'lastStepViewed': step.toString(),
        'isCompleted': isCompleted,
      });
      print('✅ Demo step updated: ${step.toString()}');
    } catch (e) {
      print('❌ Error updating demo step: $e');
    }
  }

  // 🎯 CALLED ONLY when a user manually exits (e.g., clicks an "Exit" button)
  Future<void> exitDemoSession(DemoStep lastStep) async {
    try {
      final sessionId = await _getOrCreateSessionId();
      await _firestore.collection('demoSessions').doc(sessionId).update({
        'lastUpdatedAt': FieldValue.serverTimestamp(),
        'lastStepViewed': lastStep.toString(), // Keep the last actual step
        'onboardingExited': true, // Set the exit flag
        'isCompleted': false, // It was not completed
      });
      print('✅ Demo session exited at step: ${lastStep.toString()}');
    } catch (e) {
      print('❌ Error marking demo as exited: $e');
    } finally {
      await clearLocalSession(); // Clear session ID regardless
    }
  }

  // 🎯 CALLED ONLY when the demo finishes naturally
  Future<void> completeDemoSession() async {
    // This method's only job is to clean up the local session ID.
    // The `updateDemoStep(DemoStep.complete)` call already marked it in Firestore.
    await clearLocalSession();
    print('✅ Local demo session cleared after completion.');
  }

  // 🎯 RENAMED and made public to be accessible from multiple methods
  Future<void> clearLocalSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_demoSessionIdKey);
  }
}
