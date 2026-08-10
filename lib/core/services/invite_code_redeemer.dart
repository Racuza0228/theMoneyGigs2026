// lib/core/services/invite_code_redeemer.dart
//
// Shared invite-code redemption flow. Extracted from
// OnboardingFlow._runConnectSequence so the same logic can be reused by
// the boot-time InviteCodeReentryDialog (and, as a fast-follow, by
// ConnectWidget) without three copies of the same sign-in/validate/
// subscribe sequence drifting out of sync.
//
// This function owns the loading dialogs and the "sign in?" / "subscribe?"
// confirmation dialogs — same copy and behavior as the existing onboarding
// flow — but it does NOT own page navigation. Callers decide what happens
// after redemption based on the returned result.

import 'dart:io' show Platform;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/core/services/auth_service.dart';
import 'package:the_money_gigs/core/services/network_service.dart';
import 'package:the_money_gigs/core/services/subscription_service.dart';
import 'package:the_money_gigs/core/services/revenuecat_gate.dart';
import 'package:the_money_gigs/core/widgets/email_auth_dialog.dart';
import 'package:the_money_gigs/global_refresh_notifier.dart';
import 'package:the_money_gigs/core/utils/logger.dart';

enum InviteCodeRedeemResult {
  connectedFounder,
  connectedMember,
  invalid,
  signInDeclined,
  authFailed,
  creationFailed,
  subscriptionDeclined,
  subscriptionFailed,
}

extension InviteCodeRedeemResultX on InviteCodeRedeemResult {
  bool get isConnected =>
      this == InviteCodeRedeemResult.connectedFounder ||
          this == InviteCodeRedeemResult.connectedMember;
}

/// Redeems [rawCode] against the network service, handling sign-in,
/// membership checks, and the founder/subscription branch — identical
/// behavior to the onboarding flow's code entry.
///
/// Shows its own loading and confirmation dialogs via [context]. On
/// success, persists the same SharedPreferences keys the rest of the app
/// already reads (`is_connected_to_network`, `network_invite_code`,
/// `my_invite_codes`) and pings [globalRefreshNotifier] so any already-open
/// screens (like an empty map) pick up the change immediately.
Future<InviteCodeRedeemResult> redeemInviteCode(
    BuildContext context,
    String rawCode,
    ) async {
  log('🔑 redeemInviteCode: starting for code="${rawCode.trim()}"');
  try {
    final result = await _redeemInviteCodeInner(context, rawCode);
    log('🔑 redeemInviteCode: finished with result=$result');
    return result;
  } catch (e, st) {
    log('🔑 redeemInviteCode: THREW — $e');
    log('🔑 redeemInviteCode: stack — $st');
    rethrow;
  }
}

Future<InviteCodeRedeemResult> _redeemInviteCodeInner(
    BuildContext context,
    String rawCode,
    ) async {
  final code = rawCode.trim().toUpperCase();
  final prefs = await SharedPreferences.getInstance();
  final authService = AuthService();
  final networkService = NetworkService();

  bool loadingOpen = false;
  void showLoading(String message) {
    if (loadingOpen || !context.mounted) return;
    loadingOpen = true;
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

  void hideLoading() {
    if (!loadingOpen || !context.mounted) return;
    loadingOpen = false;
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> persistConnected({
    required String appliedCode,
    required List<String> myInviteCodes,
  }) async {
    await prefs.setBool('is_connected_to_network', true);
    await prefs.setString('network_invite_code', appliedCode);
    await prefs.setStringList('my_invite_codes', myInviteCodes);
    globalRefreshNotifier.notify();
  }

  // ── 1. Sign in (Google, Apple, or email/password) ───────────────────
  if (!authService.isSignedIn) {
    if (!context.mounted) return InviteCodeRedeemResult.authFailed;

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
      return InviteCodeRedeemResult.signInDeclined;
    }

    UserCredential? result;

    if (signInMethod == 'email') {
      // EmailAuthDialog handles its own loading state and error display.
      result = await showDialog<UserCredential?>(
        context: context,
        builder: (_) => const EmailAuthDialog(),
      );
    } else if (signInMethod == 'apple') {
      showLoading('Signing in…');
      result = await authService.signInWithApple();
      hideLoading();
    } else {
      showLoading('Signing in…');
      result = await authService.signInWithGoogle();
      hideLoading();
    }

    if (!context.mounted) return InviteCodeRedeemResult.authFailed;
    if (result == null) {
      return InviteCodeRedeemResult.authFailed;
    }
  }

  // ── 2. Already a network member? ────────────────────────────────────
  showLoading('Checking membership…');
  final userId = authService.currentUserId;
  final existingMember = await networkService.getMember(userId);
  hideLoading();
  if (!context.mounted) return InviteCodeRedeemResult.authFailed;

  if (existingMember != null) {
    final codeDoc =
    await networkService.validateInviteCode(existingMember.inviteCodeUsed);
    final isFounder = codeDoc?.isFounderCode ?? false;

    await persistConnected(
      appliedCode: existingMember.inviteCodeUsed,
      myInviteCodes: existingMember.myInviteCodes,
    );

    return isFounder
        ? InviteCodeRedeemResult.connectedFounder
        : InviteCodeRedeemResult.connectedMember;
  }

  // ── 3. Validate the entered code ────────────────────────────────────
  showLoading('Validating code…');
  final inviteCodeDoc = await networkService.validateInviteCode(code);
  hideLoading();
  if (!context.mounted) return InviteCodeRedeemResult.authFailed;

  if (inviteCodeDoc == null) {
    return InviteCodeRedeemResult.invalid;
  }

  // ── 4. Create member record ─────────────────────────────────────────
  showLoading('Setting up your account…');
  final success = await networkService.createMemberWithInviteCode(
    userId: userId,
    email: authService.currentUser?.email ?? '',
    inviteCode: code,
  );
  hideLoading();
  if (!context.mounted) return InviteCodeRedeemResult.authFailed;

  if (!success) {
    return InviteCodeRedeemResult.creationFailed;
  }

  // ── 5. Founder (free) vs regular (subscription) ─────────────────────
  if (inviteCodeDoc.isFounderCode) {
    final member = await networkService.getMember(userId);
    await persistConnected(
      appliedCode: code,
      myInviteCodes: member?.myInviteCodes ?? [],
    );
    return InviteCodeRedeemResult.connectedFounder;
  }

  await ensureRevenueCatConfigured();
  final subscriptionService = SubscriptionService();
  final hasSubscription = await subscriptionService.hasActiveSubscription();

  if (hasSubscription) {
    final member = await networkService.getMember(userId);
    await persistConnected(
      appliedCode: code,
      myInviteCodes: member?.myInviteCodes ?? [],
    );
    return InviteCodeRedeemResult.connectedMember;
  }

  if (!context.mounted) return InviteCodeRedeemResult.subscriptionFailed;
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
    return InviteCodeRedeemResult.subscriptionDeclined;
  }

  showLoading('Processing subscription…');
  final purchased = await subscriptionService.purchaseMonthlySubscription();
  hideLoading();
  if (!context.mounted) return InviteCodeRedeemResult.subscriptionFailed;

  if (purchased) {
    final member = await networkService.getMember(userId);
    await persistConnected(
      appliedCode: code,
      myInviteCodes: member?.myInviteCodes ?? [],
    );
    return InviteCodeRedeemResult.connectedMember;
  } else {
    await networkService.deleteMember(userId);
    return InviteCodeRedeemResult.subscriptionFailed;
  }
}