// lib/core/services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:the_money_gigs/core/utils/logger.dart';

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
      // RevenueCat may not be initialized yet (standalone users). A failure
      // here must NOT cancel a successful Firebase sign-in.
      if (userCredential.user != null) {
        try {
          await Purchases.logIn(userCredential.user!.uid);
          log('✅ User identified to RevenueCat: ${userCredential.user!.uid}');
        } catch (e) {
          // RevenueCat not configured yet — harmless. initializeNetworkServices()
          // will be called before any subscription check is needed.
          log('⚠️ RevenueCat logIn skipped (not yet configured): $e');
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