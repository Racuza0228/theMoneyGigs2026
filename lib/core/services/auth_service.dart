// lib/core/services/auth_service.dart
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
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
      await _identifyToRevenueCat(userCredential.user);

      return userCredential;

    } catch (e) {
      log("❌ Google Sign-In error: $e");
      return null;
    }
  }

  /// Sign in with existing email/password account
  Future<UserCredential?> signInWithEmail(String email, String password) async {
    try {
      log("🔵 Starting email Sign-In...");

      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      log("✅ Signed in to Firebase: ${userCredential.user?.email}");

      await _identifyToRevenueCat(userCredential.user);

      return userCredential;
    } on FirebaseAuthException catch (e) {
      log("❌ Email Sign-In error: ${e.code} — ${e.message}");
      rethrow;
    } catch (e) {
      log("❌ Email Sign-In error: $e");
      return null;
    }
  }

  /// Create a new account with email/password
  Future<UserCredential?> createAccountWithEmail(String email, String password) async {
    try {
      log("🔵 Starting email account creation...");

      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      log("✅ Account created in Firebase: ${userCredential.user?.email}");

      await _identifyToRevenueCat(userCredential.user);

      return userCredential;
    } on FirebaseAuthException catch (e) {
      log("❌ Email account creation error: ${e.code} — ${e.message}");
      rethrow;
    } catch (e) {
      log("❌ Email account creation error: $e");
      return null;
    }
  }

  /// Sign in with Apple (iOS). Requires the "Sign in with Apple" capability
  /// enabled in Xcode + Apple Developer portal, and the Apple provider
  /// enabled in the Firebase console — see Trello #300 for the setup steps.
  Future<UserCredential?> signInWithApple() async {
    try {
      log("🔵 Starting Apple Sign-In...");

      // Firebase requires a raw nonce + its SHA-256 hash to verify the
      // Apple ID token wasn't intercepted/replayed.
      final rawNonce = _generateNonce();
      final hashedNonce = _sha256ofString(rawNonce);

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final oauthCredential = OAuthProvider("apple.com").credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
      );

      final userCredential = await _auth.signInWithCredential(oauthCredential);

      log("✅ Signed in to Firebase: ${userCredential.user?.email}");

      await _identifyToRevenueCat(userCredential.user);

      return userCredential;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        log("⚠️ User cancelled Apple Sign-In");
      } else {
        log("❌ Apple Sign-In error: ${e.code} — ${e.message}");
      }
      return null;
    } catch (e) {
      log("❌ Apple Sign-In error: $e");
      return null;
    }
  }

  /// Cryptographically secure random string, required as the raw nonce
  /// for Sign in with Apple's replay-protection handshake with Firebase.
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
        length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  /// SHA-256 hash (hex) of [input] — Apple requires the hashed nonce in the
  /// authorization request, while Firebase verifies against the raw one.
  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    return sha256.convert(bytes).toString();
  }

  /// Identify user to RevenueCat — wrapped in its own try-catch because
  /// a failure here must NOT cancel a successful Firebase sign-in.
  /// Shared by every sign-in/create-account path (Google, email).
  Future<void> _identifyToRevenueCat(User? user) async {
    if (user == null) return;
    try {
      await ensureRevenueCatConfigured();
      await Purchases.logIn(user.uid);
      log('✅ User identified to RevenueCat: ${user.uid}');
    } catch (e) {
      log('⚠️ RevenueCat logIn failed (non-fatal, sign-in still succeeds): $e');
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