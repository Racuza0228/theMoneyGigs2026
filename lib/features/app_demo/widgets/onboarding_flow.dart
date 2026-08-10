// lib/features/app_demo/widgets/onboarding_flow.dart
//
// Flow:
//   Welcome → Invite Code → Map Tutorial (via any path)
//
// Paths through Invite Code page:
//   A) Has code + connects successfully  → Map Tutorial (skip email entirely)
//   B) Has code + fails / declines       → Map Tutorial (standalone)
//   C) No code + taps "Request a Code"   → opens mailto to cliff@themoneygigs.com
//                                          → returns to Map Tutorial (standalone)
//   D) No code + taps "Use Standalone"   → Map Tutorial (standalone)
//
// Email page RETIRED. Email capture for non-code users now happens
// via the "Request a Code" mailto flow (Cliff gets it in his inbox).
//
// When a valid invite code is submitted we run the exact same sequence as
// ConnectWidget._toggleConnection(true):
//   Sign-in (Google or email/password) → getMember / createMember → subscription check (if needed)
//
// On success:
//   • is_connected_to_network = true  (map shows community venues immediately)
//   • Email already known from sign-in → no separate capture needed
//
// FIX (8/2/26, Trello #300/#313): Google Sign-In used to be the ONLY path
// here, silently locking out any musician without a Gmail account right at
// activation. Email/password is now offered as an equal alternative.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'package:the_money_gigs/core/services/auth_service.dart';
import 'package:the_money_gigs/core/services/network_service.dart';
import 'package:the_money_gigs/core/services/subscription_service.dart';
import 'package:the_money_gigs/core/services/revenuecat_gate.dart'; // ensureRevenueCatConfigured()
import 'package:the_money_gigs/core/utils/logger.dart';
import 'package:the_money_gigs/core/widgets/email_auth_dialog.dart';

// ── Page name constants (Firestore tracking) ──────────────────────────────
abstract class _Page {
  static const welcome    = 'welcome';
  static const inviteCode = 'inviteCode';
}

class OnboardingFlow extends StatefulWidget {
  final VoidCallback onComplete;
  const OnboardingFlow({super.key, required this.onComplete});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // ── Invite code / connect state ───────────────────────────────────────────
  final _codeController = TextEditingController();
  bool _isConnecting = false;
  bool _loadingDialogOpen = false;
  // null | 'connected_founder' | 'connected_member' | 'sign_in_declined'
  // | 'auth_failed' | 'invalid' | 'needs_subscription' | 'error'
  String? _codeStatus;
  // Set alongside _codeStatus whenever a connect attempt succeeds. Not read
  // anywhere yet (that info is currently derived from _codeStatus instead) -
  // kept as a hook for a future explicit "connected" check; safe to delete
  // if it stays unused.
  bool _codeConnectedSuccessfully = false;

  // ── Request-code state ────────────────────────────────────────────────────
  bool _codeRequested = false;

  // ── Firestore tracking ────────────────────────────────────────────────────
  late final String _sessionId;
  DocumentReference? _sessionRef;
  bool _trackingReady = false;
  final List<Map<String, dynamic>> _pendingUpdates = [];

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initTracking();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Tracking
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _initTracking() async {
    _sessionId = const Uuid().v4();
    log('📋 OnboardingTracking: init — session=$_sessionId');
    final ref = FirebaseFirestore.instance
        .collection('onboardingSessions')
        .doc(_sessionId);
    try {
      final prefs = await SharedPreferences.getInstance();
      final isDeveloper = prefs.getBool('is_developer_device') ?? false;

      await ref.set({
        'sessionId':          _sessionId,
        'startedAt':          FieldValue.serverTimestamp(),
        'completed':          false,
        'exitedOnPage':       null,
        'welcomeViewed':      false,
        'inviteCodeViewed':   false,
        'inviteCodeProvided': false,
        'inviteCodeStatus':   null,
        'connectedViaCode':   false,
        'codeRequested':      false,
        // Platform context
        'platform':           Platform.isAndroid ? 'android' : 'ios',
        'osVersion':          Platform.operatingSystemVersion,
        'isDeveloper':        isDeveloper,
      });
      _sessionRef = ref;
      _trackingReady = true;
      log('📋 OnboardingTracking: session document written ✅');
      for (final update in _pendingUpdates) {
        try {
          await _sessionRef!.update(update);
          log('📋 OnboardingTracking: flushed pending update ✅');
        } catch (e) {
          log('📋 OnboardingTracking: flush error ❌ $e');
        }
      }
      _pendingUpdates.clear();
      _trackPageView(_Page.welcome);
    } catch (e, stack) {
      log('📋 OnboardingTracking: init FAILED ❌ $e');
      log('📋 OnboardingTracking: stack — $stack');
    }
  }

  Future<void> _safeUpdate(Map<String, dynamic> data) async {
    if (!_trackingReady || _sessionRef == null) {
      log('📋 OnboardingTracking: queuing update (not ready) — ${data.keys}');
      _pendingUpdates.add(data);
      return;
    }
    try {
      await _sessionRef!.update(data);
      log('📋 OnboardingTracking: update written ✅ — ${data.keys}');
    } catch (e) {
      log('📋 OnboardingTracking: update FAILED ❌ $e — ${data.keys}');
    }
  }

  Future<void> _trackPageView(String page) async {
    final field = switch (page) {
      _Page.welcome    => 'welcomeViewed',
      _Page.inviteCode => 'inviteCodeViewed',
      _                => null,
    };
    if (field == null) return;
    await _safeUpdate({
      field: true,
      '${page}ViewedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _trackCodeResult(String status, {bool connected = false}) async {
    await _safeUpdate({
      'inviteCodeProvided': true,
      'inviteCodeStatus':   status,
      'connectedViaCode':   connected,
      'codeOutcomeAt':      FieldValue.serverTimestamp(),
    });
  }

  Future<void> _trackCodeRequested() async {
    await _safeUpdate({
      'codeRequested':    true,
      'codeRequestedAt':  FieldValue.serverTimestamp(),
    });
  }

  Future<void> _trackExit() async {
    final pages = [_Page.welcome, _Page.inviteCode];
    final page = _currentPage < pages.length ? pages[_currentPage] : _Page.inviteCode;
    await _safeUpdate({
      'exitedOnPage': page,
      'exitedAt':     FieldValue.serverTimestamp(),
      'completed':    false,
    });
  }

  Future<void> _trackCompletion() async {
    await _safeUpdate({
      'completed':    true,
      'completedAt':  FieldValue.serverTimestamp(),
      'exitedOnPage': null,
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Navigation
  // ─────────────────────────────────────────────────────────────────────────

  void _goToPage(int page) {
    _pageController.animateToPage(page,
        duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    setState(() => _currentPage = page);
    final pages = [_Page.welcome, _Page.inviteCode];
    if (page < pages.length) _trackPageView(pages[page]);
  }

  void _nextPage() {
    if (_currentPage == 0) {
      _goToPage(1);
    } else {
      _finish(userCompleted: true);
    }
  }

  Future<void> _finish({bool userCompleted = false}) async {
    if (userCompleted) {
      await _trackCompletion();
    } else {
      await _trackExit();
    }
    await Future.delayed(const Duration(milliseconds: 300));
    widget.onComplete();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Loading dialog helpers
  // ─────────────────────────────────────────────────────────────────────────

  void _showLoading([String message = 'Connecting…']) {
    if (_loadingDialogOpen || !context.mounted) return;
    _loadingDialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(message),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  void _hideLoading() {
    if (!_loadingDialogOpen || !context.mounted) return;
    _loadingDialogOpen = false;
    Navigator.of(context, rootNavigator: true).pop();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Request a Code — opens mailto
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _requestCode() async {
    final subject = Uri.encodeComponent('MoneyGigs Invite Code Request');
    final body = Uri.encodeComponent(
      'Hi Cliff,\n\n'
          'I\'d like to request an invite code for MoneyGigs.\n\n'
          'Here\'s a little bit about myself and my work as a musician:\n\n'
          '[Your answer here]\n\n'
          'Thanks!',
    );
    final uri = Uri.parse(
      'mailto:cliff@themoneygigs.com?subject=$subject&body=$body',
    );

    // Persist intent immediately — this reflects that the user WANTS a
    // code, independent of whether this device can actually open a mail
    // composer. A missing mail app (common on emulators, not unheard of
    // on real devices either) shouldn't silently swallow that intent.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('invite_code_requested', true);
    await _trackCodeRequested();

    try {
      if (await canLaunchUrl(uri)) {
        log('📧 _requestCode: mailto launched');
        await launchUrl(uri);
        setState(() => _codeRequested = true);
        // Brief pause to show confirmation state, then advance to Map Tutorial
        await Future.delayed(const Duration(milliseconds: 1200));
        if (context.mounted) _finish(userCompleted: true);
      } else {
        log('📧 _requestCode: canLaunchUrl(mailto) returned false — '
            'no mail client on this device; flag still persisted, '
            'advancing standalone');
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No email app found. Email cliff@themoneygigs.com to request a code.',
            ),
            duration: Duration(seconds: 6),
          ),
        );
        setState(() => _codeRequested = true);
        await Future.delayed(const Duration(milliseconds: 1200));
        if (!context.mounted) return;
        _finish(userCompleted: true);
      }
    } catch (e) {
      log('mailto launch error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Invite code — full connect sequence (mirrors ConnectWidget._toggleConnection)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _handleCodeContinue() async {
    final code = _codeController.text.trim().toUpperCase();

    // Empty → go straight to next page (Map Tutorial via standalone)
    if (code.isEmpty) {
      _nextPage();
      return;
    }

    setState(() {
      _isConnecting = true;
      _codeStatus   = null;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_invite_code', code);

    try {
      await _runConnectSequence(code, prefs);
    } finally {
      if (context.mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _runConnectSequence(String code, SharedPreferences prefs) async {
    final authService = AuthService();

    // ── 1. Sign in (Google or email/password) ─────────────────────────────
    if (!authService.isSignedIn) {
      if (!context.mounted) return;

      final signInMethod = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('One quick step'),
          content: const Text(
            'We link your invite code to an account. '
                'Your email stays private — it only identifies you in the network.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Skip for now'),
            ),
            TextButton.icon(
              icon: const Icon(Icons.email_outlined),
              label: const Text('Sign in with Email'),
              onPressed: () => Navigator.pop(ctx, 'email'),
            ),
            if (Platform.isIOS)
              TextButton.icon(
                icon: const Icon(Icons.apple),
                label: const Text('Sign in with Apple'),
                onPressed: () => Navigator.pop(ctx, 'apple'),
              ),
            ElevatedButton.icon(
              icon: const Icon(Icons.login),
              label: const Text('Sign in with Google'),
              onPressed: () => Navigator.pop(ctx, 'google'),
            ),
          ],
        ),
      );

      if (signInMethod == null) {
        setState(() => _codeStatus = 'sign_in_declined');
        await _trackCodeResult('sign_in_declined');
        await Future.delayed(const Duration(milliseconds: 900));
        if (context.mounted) _nextPage();
        return;
      }

      UserCredential? result;

      if (signInMethod == 'email') {
        // EmailAuthDialog handles its own loading state and error display.
        result = await showDialog<UserCredential?>(
          context: context,
          builder: (_) => const EmailAuthDialog(),
        );
      } else if (signInMethod == 'apple') {
        _showLoading('Signing in…');
        result = await authService.signInWithApple();
        _hideLoading();
      } else {
        _showLoading('Signing in…');
        result = await authService.signInWithGoogle();
        _hideLoading();
      }

      if (!context.mounted) return;
      if (result == null) {
        setState(() => _codeStatus = 'auth_failed');
        await _trackCodeResult('auth_failed');
        return;
      }
    }

    // ── 2. Check if already a network member ──────────────────────────────
    _showLoading('Checking membership…');
    final networkService  = NetworkService();
    final userId          = authService.currentUserId;
    final existingMember  = await networkService.getMember(userId);
    _hideLoading();
    if (!context.mounted) return;

    if (existingMember != null) {
      final codeDoc   = await networkService.validateInviteCode(existingMember.inviteCodeUsed);
      final isFounder = codeDoc?.isFounderCode ?? false;

      await prefs.setBool('is_connected_to_network', true);
      await prefs.setStringList('my_invite_codes', existingMember.myInviteCodes);

      final status = isFounder ? 'connected_founder' : 'connected_member';
      setState(() {
        _codeStatus = status;
        _codeConnectedSuccessfully = true;
      });
      await _trackCodeResult(status, connected: true);
      await Future.delayed(const Duration(milliseconds: 1400));
      if (context.mounted) _nextPage();
      return;
    }

    // ── 3. Validate the entered invite code ───────────────────────────────
    _showLoading('Validating code…');
    final inviteCodeDoc = await networkService.validateInviteCode(code);
    _hideLoading();
    if (!context.mounted) return;

    if (inviteCodeDoc == null) {
      setState(() => _codeStatus = 'invalid');
      await _trackCodeResult('invalid');
      return;
    }

    // ── 4. Create member record ───────────────────────────────────────────
    _showLoading('Setting up your account…');
    final success = await networkService.createMemberWithInviteCode(
      userId:     userId,
      email:      authService.currentUser?.email ?? '',
      inviteCode: code,
    );
    _hideLoading();
    if (!context.mounted) return;

    if (!success) {
      setState(() => _codeStatus = 'invalid');
      await _trackCodeResult('creation_failed');
      return;
    }

    // ── 5. Founder (free) vs Regular (subscription) ───────────────────────
    if (inviteCodeDoc.isFounderCode) {
      final member = await networkService.getMember(userId);

      await prefs.setBool('is_connected_to_network', true);
      await prefs.setString('network_invite_code', code);
      await prefs.setStringList('my_invite_codes', member?.myInviteCodes ?? []);

      setState(() {
        _codeStatus = 'connected_founder';
        _codeConnectedSuccessfully = true;
      });
      await _trackCodeResult('connected_founder', connected: true);
      await Future.delayed(const Duration(milliseconds: 1400));
      if (context.mounted) _nextPage();

    } else {
      await ensureRevenueCatConfigured();

      final subscriptionService = SubscriptionService();
      final hasSubscription = await subscriptionService.hasActiveSubscription();

      if (hasSubscription) {
        final member = await networkService.getMember(userId);

        await prefs.setBool('is_connected_to_network', true);
        await prefs.setString('network_invite_code', code);
        await prefs.setStringList('my_invite_codes', member?.myInviteCodes ?? []);

        setState(() {
          _codeStatus = 'connected_member';
          _codeConnectedSuccessfully = true;
        });
        await _trackCodeResult('connected_member', connected: true);
        await Future.delayed(const Duration(milliseconds: 1400));
        if (context.mounted) _nextPage();

      } else {
        if (!context.mounted) return;
        final shouldPurchase = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Almost there'),
            content: const Text(
              'Community Edition is \$2/month.\n\n'
                  'You\'ll get access to shared venues and ratings from other '
                  'musicians. Cancel anytime from your device\'s subscription settings.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Not now'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Subscribe (\$2/month)'),
              ),
            ],
          ),
        );

        if (shouldPurchase != true) {
          await networkService.deleteMember(userId);
          setState(() => _codeStatus = 'needs_subscription');
          await _trackCodeResult('subscription_declined');
          await Future.delayed(const Duration(milliseconds: 900));
          if (context.mounted) _nextPage();
          return;
        }

        _showLoading('Processing subscription…');
        final purchased = await subscriptionService.purchaseMonthlySubscription();
        _hideLoading();
        if (!context.mounted) return;

        if (purchased) {
          final member = await networkService.getMember(userId);

          await prefs.setBool('is_connected_to_network', true);
          await prefs.setString('network_invite_code', code);
          await prefs.setStringList('my_invite_codes', member?.myInviteCodes ?? []);

          setState(() {
            _codeStatus = 'connected_member';
            _codeConnectedSuccessfully = true;
          });
          await _trackCodeResult('connected_member', connected: true);
          await Future.delayed(const Duration(milliseconds: 1400));
          if (context.mounted) _nextPage();

        } else {
          await networkService.deleteMember(userId);
          setState(() => _codeStatus = 'needs_subscription');
          await _trackCodeResult('subscription_failed');
          await Future.delayed(const Duration(milliseconds: 900));
          if (context.mounted) _nextPage();
        }
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildWelcomePage(),
            _buildInviteCodePage(),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PAGE 1 — Welcome
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildWelcomePage() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 60),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              color: Colors.orange.shade700,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.shade900.withValues(alpha: 0.5),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: const Icon(Icons.attach_money_rounded,
                size: 64, color: Colors.white),
          ),
          const SizedBox(height: 36),
          const Text(
            'Welcome to MoneyGigs',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'This app optimizes the gig experience for musicians — from knowing your actual rate, to being better prepared, to reflecting on each gig.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, color: Colors.white70, height: 1.5),
          ),
          const SizedBox(height: 52),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _nextPage,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 4,
              ),
              child: const Text("Let's Go",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 18),
          TextButton(
            onPressed: () => _finish(userCompleted: false),
            child: const Text('Skip setup and go straight to the app',
                style: TextStyle(color: Colors.white60, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PAGE 2 — Invite Code + Connect
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildInviteCodePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Do you have\nan invite code?',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'MoneyGigs is invite-only for the venue database — we want to make sure the people using the system are real working musicians.',
            style: TextStyle(fontSize: 15, color: Colors.white70, height: 1.5),
          ),
          const SizedBox(height: 32),

          // ── Code input ──────────────────────────────────────────────────
          TextField(
            controller: _codeController,
            style: const TextStyle(
                color: Colors.white, fontSize: 20, letterSpacing: 3),
            textCapitalization: TextCapitalization.characters,
            enabled: !_isConnecting,
            onChanged: (_) {
              if (_codeStatus != null) setState(() => _codeStatus = null);
            },
            decoration: InputDecoration(
              hintText: 'ENTER CODE',
              hintStyle: const TextStyle(color: Colors.white, letterSpacing: 3),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                  BorderSide(color: Colors.orange.shade400, width: 2)),
              disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white60)),
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              suffixIcon: _statusIcon,
            ),
          ),

          // ── Status message ──────────────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            child: _codeStatus == null
                ? const SizedBox.shrink()
                : Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _statusMessage,
                style: TextStyle(
                  color: _codeStatus == 'invalid' ||
                      _codeStatus == 'auth_failed'
                      ? Colors.red.shade300
                      : Colors.greenAccent.shade200,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
          ),

          const SizedBox(height: 28),

          // ── Continue / Connect button ────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isConnecting ? null : _handleCodeContinue,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.orange.shade900,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _isConnecting
                  ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white))
                  : const Text('Continue',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 20),

          // ── "Don't have a code?" section ────────────────────────────────
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.lock_open_rounded,
                        color: Colors.white70, size: 18),
                    SizedBox(width: 8),
                    Text(
                      "Don't have a code?",
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Codes are shared through the podcast and musician community. '
                      'You can request one directly from Cliff — just tell him a bit about your work as a musician.',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 16),

                // Request a Code button
                SizedBox(
                  width: double.infinity,
                  child: _codeRequested
                      ? Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.green.shade900.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.greenAccent.shade400),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_rounded,
                            color: Colors.greenAccent.shade400, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Request sent! Taking you to the app…',
                          style: TextStyle(
                              color: Colors.greenAccent.shade200,
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  )
                      : OutlinedButton.icon(
                    onPressed: _requestCode,
                    icon: const Icon(Icons.mail_outline_rounded,
                        size: 18, color: Colors.white),
                    label: const Text(
                      'Request a Code from Cliff',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Colors.white),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                const Divider(color: Colors.white60),
                const SizedBox(height: 14),

                // ── Standalone explanation ─────────────────────────────────
                const Text(
                  "If you're not comfortable sending an email, that's fine. "
                      'You can use the app standalone for now and request a code '
                      'from Cliff using the Question Mark button at the top of any page.',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 14),

                // ── Use Standalone button ──────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isConnecting ? null : _nextPage,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.12),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: const BorderSide(color: Colors.white60)),
                    ),
                    child: const Text(
                      'Use Standalone for Now',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget? get _statusIcon {
    if (_codeStatus == null) return null;
    if (_codeStatus == 'invalid' || _codeStatus == 'auth_failed') {
      return const Icon(Icons.cancel_rounded, color: Colors.red);
    }
    return Icon(Icons.check_circle_rounded,
        color: _codeStatus == 'connected_founder'
            ? Colors.amber
            : Colors.greenAccent);
  }

  String get _statusMessage {
    return switch (_codeStatus) {
      'connected_founder'  => '🎉 Founder access confirmed! You\'re connected.',
      'connected_member'   => '✅ Connected! Community Edition is active.',
      'sign_in_declined'   => '✅ Code saved — connect anytime from Profile.',
      'needs_subscription' => 'No problem — you can subscribe later from the Profile tab.',
      'auth_failed'        => '❌ Sign-in failed. Try again or skip to use Standalone.',
      'invalid'            => '❌ Code not found. Check it and try again, or skip.',
      _                    => '',
    };
  }
}