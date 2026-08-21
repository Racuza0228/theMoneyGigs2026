// lib/core/services/auth_service.dart
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:the_money_gigs/core/utils/logger.dart';
import 'package:the_money_gigs/core/services/analytics_service.dart';
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
        // Without this, Firebase can't fully validate the token against
        // Apple and throws [firebase_auth/invalid-credential] "Invalid
        // OAuth response from apple.com" — 100% reproducible, not
        // intermittent. Root-caused 8/18 via a matching flutterfire issue
        // (github.com/firebase/flutterfire/issues/18289) after Nashville's
        // 8/14 failure. Do not remove.
        accessToken: appleCredential.authorizationCode,
      );

      final userCredential = await _auth.signInWithCredential(oauthCredential);

      log("✅ Signed in to Firebase: ${userCredential.user?.email}");

      await _identifyToRevenueCat(userCredential.user);

      return userCredential;
    } on SignInWithAppleAuthorizationException catch (e, stack) {
      if (e.code == AuthorizationErrorCode.canceled) {
        log("⚠️ User cancelled Apple Sign-In");
      } else {
        log("❌ Apple Sign-In error: ${e.code} — ${e.message}");
        await _recordAppleSignInFailure(e.code.toString(), e.message, stack);
      }
      return null;
    } catch (e, stack) {
      log("❌ Apple Sign-In error: $e");
      await _recordAppleSignInFailure(e.runtimeType.toString(), e.toString(), stack);
      return null;
    }
  }

  /// Added 8/17/26. Before this, every Apple Sign-In failure only reached
  /// the debug-only log() helper (a no-op in release builds), which is why
  /// the confirmed Nashville failures (8/14, Trello: "Apple Sign-In broken —
  /// cost 2+ conversions at Nashville") left nothing in Crashlytics or
  /// Analytics to diagnose after the fact — the exception is caught here,
  /// so it never reaches main.dart's global handlers either. This sends the
  /// actual error code/message somewhere retrievable: Crashlytics (non-fatal,
  /// reason 'apple_signin_failed') and a matching GA4 event. Both wrapped in
  /// try/catch — a failure here must never break sign-in itself.
  Future<void> _recordAppleSignInFailure(
      String code, String? message, StackTrace stack) async {
    try {
      await FirebaseCrashlytics.instance.recordError(
        'Apple Sign-In failed: $code — ${message ?? ''}',
        stack,
        fatal: false,
        reason: 'apple_signin_failed',
      );
    } catch (_) {}
    try {
      await AnalyticsService.logAppleSignInFailed(
        errorCode: code,
        errorMessage: message,
      );
    } catch (_) {}
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

  /// Public wrapper around _identifyToRevenueCat, for callers that need to
  /// (re)confirm RevenueCat identity WITHOUT going through a fresh sign-in.
  ///
  /// Why this exists (8/17/26): every explicit sign-in method above calls
  /// _identifyToRevenueCat automatically. But onboarding_flow.dart's invite
  /// code path only calls those sign-in methods when authService.isSignedIn
  /// is false — if Firebase's session already persisted (e.g. a reinstall,
  /// where iOS Keychain can survive uninstall), sign-in is skipped entirely
  /// and Purchases.logIn(uid) never fires for that app process. RevenueCat
  /// then falls back to a fresh local anonymous ID for that install, so a
  /// purchase can land under $RCAnonymousID instead of the real Firebase
  /// UID — the same failure class as the "2 anonymous RevenueCat IDs" /
  /// subscriber-count-mismatch bug (see Trello: "RevenueCat ↔ Firestore
  /// sync gap", "Apple Sign-In broken — cost 2+ conversions at Nashville").
  /// Purchases.logIn is idempotent/cheap, so call this unconditionally
  /// before any purchase or entitlement check, signed-in-already or not.
  Future<void> ensureIdentifiedToRevenueCat() => _identifyToRevenueCat(currentUser);

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