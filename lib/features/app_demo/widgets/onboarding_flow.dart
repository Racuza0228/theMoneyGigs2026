// lib/features/app_demo/widgets/onboarding_flow.dart
//
// Flow:
//   Welcome → Invite Code → [Email — only shown if NOT connected via code]
//
// When a valid invite code is submitted we run the exact same sequence as
// ConnectWidget._toggleConnection(true):
//   Google Sign-In → getMember / createMember → subscription check (if needed)
//
// On success:
//   • is_connected_to_network = true  (map shows community venues immediately)
//   • Email already known from Google → skip the email capture page entirely
//
// On failure / skip:
//   • Email page is shown so we at least have a way to follow up

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:the_money_gigs/core/services/auth_service.dart';
import 'package:the_money_gigs/core/services/network_service.dart';
import 'package:the_money_gigs/core/services/subscription_service.dart';
import 'package:the_money_gigs/main.dart'; // initializeNetworkServices()

// ── Page name constants (Firestore tracking) ──────────────────────────────
abstract class _Page {
  static const welcome    = 'welcome';
  static const inviteCode = 'inviteCode';
  static const email      = 'email';
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
  bool _codeConnectedSuccessfully = false;

  // ── Email state ───────────────────────────────────────────────────────────
  final _emailController = TextEditingController();
  final _emailFormKey    = GlobalKey<FormState>();
  bool _isSubmittingEmail = false;

  // ── Firestore tracking ────────────────────────────────────────────────────
  late final String _sessionId;
  late final DocumentReference _sessionRef;
  bool _trackingReady = false;

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
    _emailController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Tracking
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _initTracking() async {
    _sessionId = const Uuid().v4();
    _sessionRef = FirebaseFirestore.instance
        .collection('onboardingSessions')
        .doc(_sessionId);
    try {
      await _sessionRef.set({
        'sessionId':          _sessionId,
        'startedAt':          FieldValue.serverTimestamp(),
        'completed':          false,
        'exitedOnPage':       null,
        'welcomeViewed':      false,
        'inviteCodeViewed':   false,
        'inviteCodeProvided': false,
        'inviteCodeStatus':   null,
        'connectedViaCode':   false,
        'emailPageViewed':    false,
        'emailProvided':      false,
      });
      _trackingReady = true;
      _trackPageView(_Page.welcome);
    } catch (e) {
      debugPrint('Onboarding tracking init error: $e');
    }
  }

  Future<void> _trackPageView(String page) async {
    if (!_trackingReady) return;
    final field = switch (page) {
      _Page.welcome    => 'welcomeViewed',
      _Page.inviteCode => 'inviteCodeViewed',
      _Page.email      => 'emailPageViewed',
      _      => null,
    };
    if (field == null) return;
    try {
      await _sessionRef.update({
        field: true,
        '${page}ViewedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> _trackCodeResult(String status, {bool connected = false}) async {
    if (!_trackingReady) return;
    try {
      await _sessionRef.update({
        'inviteCodeProvided': true,
        'inviteCodeStatus':   status,
        'connectedViaCode':   connected,
        'codeOutcomeAt':      FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> _trackEmailResult(bool provided) async {
    if (!_trackingReady) return;
    try {
      await _sessionRef.update({
        'emailProvided':  provided,
        'emailOutcomeAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> _trackExit() async {
    if (!_trackingReady) return;
    final pages = [_Page.welcome, _Page.inviteCode, _Page.email];
    final page = _currentPage < pages.length ? pages[_currentPage] : _Page.email;
    try {
      await _sessionRef.update({
        'exitedOnPage': page,
        'exitedAt':     FieldValue.serverTimestamp(),
        'completed':    false,
      });
    } catch (_) {}
  }

  Future<void> _trackCompletion() async {
    if (!_trackingReady) return;
    try {
      await _sessionRef.update({
        'completed':    true,
        'completedAt':  FieldValue.serverTimestamp(),
        'exitedOnPage': null,
      });
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Navigation
  // ─────────────────────────────────────────────────────────────────────────

  void _goToPage(int page) {
    _pageController.animateToPage(page,
        duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    setState(() => _currentPage = page);
    final pages = [_Page.welcome, _Page.inviteCode, _Page.email];
    if (page < pages.length) _trackPageView(pages[page]);
  }

  /// Advance from current page.
  /// After the invite-code page, skip email entirely if we connected.
  void _nextPage() {
    if (_currentPage == 1 && _codeConnectedSuccessfully) {
      _finish(userCompleted: true);
    } else if (_currentPage < 2) {
      _goToPage(_currentPage + 1);
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
    widget.onComplete();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Loading dialog helpers
  // ─────────────────────────────────────────────────────────────────────────

  void _showLoading([String message = 'Connecting…']) {
    if (_loadingDialogOpen || !mounted) return;
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
    if (!_loadingDialogOpen || !mounted) return;
    _loadingDialogOpen = false;
    Navigator.of(context, rootNavigator: true).pop();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Invite code — full connect sequence (mirrors ConnectWidget._toggleConnection)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _handleCodeContinue() async {
    final code = _codeController.text.trim().toUpperCase();

    // Empty → skip straight to email page
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
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  /// Mirrors ConnectWidget._toggleConnection(true).
  /// Sets [_codeConnectedSuccessfully] on success.
  Future<void> _runConnectSequence(String code, SharedPreferences prefs) async {
    final authService = AuthService();

    // ── 1. Google Sign-In ─────────────────────────────────────────────────
    // RevenueCat is NOT initialized here. Founders and standalone users
    // never need it. It will be initialized later only if a $2/mo
    // subscription purchase is actually required.
    if (!authService.isSignedIn) {
      if (!mounted) return;

      final shouldSignIn = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('One quick step'),
          content: const Text(
            'We use Google Sign-In to link your invite code to your account. '
                'Your email stays private — it only identifies you in the network.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Skip for now'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.login),
              label: const Text('Sign in with Google'),
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      );

      if (shouldSignIn != true) {
        // Declined — save code for later, go to email page
        setState(() => _codeStatus = 'sign_in_declined');
        await _trackCodeResult('sign_in_declined');
        await Future.delayed(const Duration(milliseconds: 900));
        if (mounted) _nextPage();
        return;
      }

      _showLoading('Signing in…');
      final result = await authService.signInWithGoogle();
      _hideLoading();

      if (!mounted) return;
      if (result == null) {
        setState(() => _codeStatus = 'auth_failed');
        await _trackCodeResult('auth_failed');
        return; // Stay on page — they can retry or skip
      }
    }

    // ── 3. Check if already a network member ──────────────────────────────
    _showLoading('Checking membership…');
    final networkService  = NetworkService();
    final userId          = authService.currentUserId;
    final existingMember  = await networkService.getMember(userId);
    _hideLoading();
    if (!mounted) return;

    if (existingMember != null) {
      // Already in system — just re-enable
      final codeDoc  = await networkService.validateInviteCode(existingMember.inviteCodeUsed);
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
      if (mounted) _nextPage();
      return;
    }

    // ── 4. Validate the entered invite code ───────────────────────────────
    _showLoading('Validating code…');
    final inviteCodeDoc = await networkService.validateInviteCode(code);
    _hideLoading();
    if (!mounted) return;

    if (inviteCodeDoc == null) {
      setState(() => _codeStatus = 'invalid');
      await _trackCodeResult('invalid');
      return; // Stay on page so they can correct it or skip
    }

    // ── 5. Create member record ───────────────────────────────────────────
    _showLoading('Setting up your account…');
    final success = await networkService.createMemberWithInviteCode(
      userId:     userId,
      email:      authService.currentUser?.email ?? '',
      inviteCode: code,
    );
    _hideLoading();
    if (!mounted) return;

    if (!success) {
      setState(() => _codeStatus = 'invalid');
      await _trackCodeResult('creation_failed');
      return;
    }

    // ── 6. Founder (free) vs Regular (subscription) ───────────────────────
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
      if (mounted) _nextPage();

    } else {
      // Regular code — check / purchase subscription.
      // This is the ONLY place RevenueCat is needed. Initialize it now.
      await initializeNetworkServices();

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
        if (mounted) _nextPage();

      } else {
        // Needs to purchase — prompt them
        if (!mounted) return;
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
          // They declined the subscription — clean up the member record
          // and let them continue to email page
          await networkService.deleteMember(userId);
          setState(() => _codeStatus = 'needs_subscription');
          await _trackCodeResult('subscription_declined');
          await Future.delayed(const Duration(milliseconds: 900));
          if (mounted) _nextPage();
          return;
        }

        _showLoading('Processing subscription…');
        final purchased = await subscriptionService.purchaseMonthlySubscription();
        _hideLoading();
        if (!mounted) return;

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
          if (mounted) _nextPage();

        } else {
          // Purchase failed or cancelled — roll back and continue to email
          await networkService.deleteMember(userId);
          setState(() => _codeStatus = 'needs_subscription');
          await _trackCodeResult('subscription_failed');
          await Future.delayed(const Duration(milliseconds: 900));
          if (mounted) _nextPage();
        }
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Email submit (only reached when no code was connected)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _submitEmail() async {
    if (!_emailFormKey.currentState!.validate()) return;
    setState(() => _isSubmittingEmail = true);

    try {
      final email = _emailController.text.trim();
      final prefs = await SharedPreferences.getInstance();

      await FirebaseFirestore.instance
          .collection('emailLeads')
          .doc(email)
          .set({
        'email':              email,
        'inviteCode':         prefs.getString('pending_invite_code'),
        'submittedAt':        FieldValue.serverTimestamp(),
        'source':             'onboarding_v2',
        'onboardingSession':  _sessionId,
      }, SetOptions(merge: true));

      await prefs.setBool('email_captured', true);
      await prefs.setString('captured_email', email);
      await _trackEmailResult(true);
    } catch (e) {
      debugPrint('Email capture error: $e');
      await _trackEmailResult(false);
    } finally {
      if (mounted) setState(() => _isSubmittingEmail = false);
    }

    await _finish(userCompleted: true);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  // How many dots to show depends on whether email page will be reached
  int get _totalPages => _codeConnectedSuccessfully ? 2 : 3;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildWelcomePage(),
                _buildInviteCodePage(),
                _buildEmailPage(),
              ],
            ),
            // Page indicator — shrinks to 2 dots once connected via code
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_totalPages, (i) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentPage == i ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _currentPage == i
                          ? Colors.orange.shade500
                          : Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
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
                  color: Colors.orange.shade900.withOpacity(0.5),
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
                style: TextStyle(color: Colors.white30, fontSize: 13)),
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
            'Enter it to unlock Community Edition — shared venues and ratings from other musicians. We\'ll connect your account right here.',
            style: TextStyle(fontSize: 15, color: Colors.white54, height: 1.5),
          ),
          const SizedBox(height: 32),

          // Code input
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
              hintStyle:
              const TextStyle(color: Colors.white24, letterSpacing: 3),
              filled: true,
              fillColor: Colors.white.withOpacity(0.07),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                  BorderSide(color: Colors.orange.shade400, width: 2)),
              disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white12)),
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              suffixIcon: _statusIcon,
            ),
          ),

          // Status message
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

          // Standalone explanation + skip
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.phone_android_rounded,
                        color: Colors.white54, size: 18),
                    SizedBox(width: 8),
                    Text('No code? No problem.',
                        style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Standalone mode is 100% free. Calculate real gig pay, track your schedule, and add your own venues. Community Edition adds shared venue data and ratings from other musicians.',
                  style: TextStyle(
                      color: Color(0x73FFFFFF), fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: _isConnecting ? null : _nextPage,
                  child: Text(
                    'Skip — use Standalone for now →',
                    style: TextStyle(
                      color: Colors.orange.shade300,
                      fontSize: 14,
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.orange.shade300,
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
      'connected_founder'    => '🎉 Founder access confirmed! You\'re connected.',
      'connected_member'     => '✅ Connected! Community Edition is active.',
      'sign_in_declined'     => '✅ Code saved — connect anytime from Profile.',
      'needs_subscription'   => 'No problem — you can subscribe later from the Profile tab.',
      'auth_failed'          => '❌ Sign-in failed. Try again or skip to use Standalone.',
      'invalid'              => '❌ Code not found. Check it and try again, or skip.',
      _                      => '',
    };
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PAGE 3 — Email (only reached if code was NOT connected)
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildEmailPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 80),
      child: Column(
        children: [
          const Icon(Icons.people_alt_outlined, size: 80, color: Colors.amber),
          const SizedBox(height: 28),
          const Text(
            'Stay in the Loop',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white),
          ),
          const SizedBox(height: 18),
          const Text(
            "We're building this with working musicians. Drop your email and we'll reach out as we add venues, fix things, and improve the app. We won't spam you — that's a promise.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, color: Colors.white70, height: 1.5),
          ),
          const SizedBox(height: 36),
          Form(
            key: _emailFormKey,
            child: TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'your@email.com',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: Colors.white.withOpacity(0.08),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white38)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white38)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                    const BorderSide(color: Colors.amber, width: 2)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 16),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your email';
                }
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                    .hasMatch(value.trim())) {
                  return 'Please enter a valid email address';
                }
                return null;
              },
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmittingEmail ? null : _submitEmail,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
                disabledBackgroundColor: Colors.amber.withOpacity(0.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSubmittingEmail
                  ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.black))
                  : const Text("I'm In",
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () async {
              await _trackEmailResult(false);
              await _finish(userCompleted: false);
            },
            child: const Text('Maybe later',
                style: TextStyle(color: Colors.white30, fontSize: 16)),
          ),
        ],
      ),
    );
  }
}