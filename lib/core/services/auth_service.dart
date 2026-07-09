// lib/core/services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:the_money_gigs/core/utils/logger.dart';
import 'package:the_money_gigs/core/services/revenuecat_gate.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  /// Get current user
  User? get currentUser => _auth.currentUser;

  /// Get current user ID (never null after sign-in)
  String get currentUserId => _auth.currentUser?.uid ?? 'anonymous';

  /// Stream of auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Sign in with Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      log("🔵 Starting Google Sign-In...");

      // Trigger Google Sign-In flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        log("⚠️ User cancelled Google Sign-In");
        return null; // User cancelled
      }

      log("✅ Google account selected: ${googleUser.email}");

      // Obtain auth details
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Create credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase
      final userCredential = await _auth.signInWithCredential(credential);

      log("✅ Signed in to Firebase: ${userCredential.user?.email}");

      // Identify user to RevenueCat — wrapped in its own try-catch because
      // a failure here must NOT cancel a successful Firebase sign-in.
      //
      // FIX (7/9/26): this used to assume RevenueCat was already configured
      // by the time sign-in happened, which is false for a brand-new install
      // redeeming an invite code for the first time — that path crashed with
      // "Purchases has not been configured." ensureRevenueCatConfigured()
      // guarantees configure() has run (or just ran) before logIn() fires,
      // regardless of what happened earlier in the session.
      if (userCredential.user != null) {
        try {
          await ensureRevenueCatConfigured();
          await Purchases.logIn(userCredential.user!.uid);
          log('✅ User identified to RevenueCat: ${userCredential.user!.uid}');
        } catch (e) {
          log('⚠️ RevenueCat logIn failed (non-fatal, sign-in still succeeds): $e');
        }
      }

      return userCredential;

    } catch (e) {
      log("❌ Google Sign-In error: $e");
      return null;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    await Future.wait([
      _auth.signOut(),
      _googleSignIn.signOut(),
    ]);
    log("✅ Signed out");
  }

  /// Check if user is signed in
  bool get isSignedIn => _auth.currentUser != null;
}