// lib/features/app_demo/widgets/invite_code_reentry_dialog.dart
//
// Shown once, on the first app boot after a standalone user (someone who
// tapped "Request a Code" during onboarding, or has no code at all) has
// had a chance to receive a code by email. Lets them redeem it inline,
// or tells them where to find code entry later (Profile).

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/core/services/invite_code_redeemer.dart';
import 'package:the_money_gigs/core/utils/logger.dart';

const String kInviteCodeRequestedKey = 'invite_code_requested';
const String kInviteCodeReentryShownKey = 'invite_code_reentry_shown';

/// Call this from MainPage after first-launch/onboarding checks are done.
/// Shows the reentry dialog at most once, ever, and only for users who
/// requested a code but aren't connected yet.
Future<void> maybeShowInviteCodeReentry(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();

  final requested = prefs.getBool(kInviteCodeRequestedKey) ?? false;
  final alreadyShown = prefs.getBool(kInviteCodeReentryShownKey) ?? false;
  final connected = prefs.getBool('is_connected_to_network') ?? false;

  log('🔑 InviteCodeReentry check — requested=$requested '
      'alreadyShown=$alreadyShown connected=$connected');

  if (!requested || alreadyShown || connected) {
    log('🔑 InviteCodeReentry: skipping (see flags above)');
    return;
  }
  if (!context.mounted) return;

  // Mark shown immediately so a rebuild/hot-reload during the dialog
  // doesn't show it twice.
  await prefs.setBool(kInviteCodeReentryShownKey, true);

  final gotCode = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Got your invite code?'),
      content: const Text(
        "If Cliff sent you a code, enter it now to unlock the shared "
            "venue map. If not yet, no problem — you can add it anytime from "
            "Profile by toggling 'Connect to Community Edition.'",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Not yet'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Enter Code'),
        ),
      ],
    ),
  );

  if (gotCode != true || !context.mounted) return;

  final controller = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Enter Invite Code'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(hintText: 'Your invite code'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: const Text('Submit'),
        ),
      ],
    ),
  );

  if (code == null || code.isEmpty || !context.mounted) return;

  final result = await redeemInviteCode(context, code);
  if (!context.mounted) return;

  final message = switch (result) {
    InviteCodeRedeemResult.connectedFounder =>
    '✅ You\'re connected — founder access unlocked.',
    InviteCodeRedeemResult.connectedMember =>
    '✅ You\'re connected — welcome to the network.',
    InviteCodeRedeemResult.invalid =>
    'That code doesn\'t look right. You can try again anytime from '
        'Profile → Connect to Community Edition.',
    InviteCodeRedeemResult.signInDeclined ||
    InviteCodeRedeemResult.authFailed =>
    'No problem — you can connect anytime from Profile → Connect to '
        'Community Edition.',
    InviteCodeRedeemResult.creationFailed ||
    InviteCodeRedeemResult.subscriptionFailed =>
    'Something went wrong. You can try again from Profile → Connect to '
        'Community Edition.',
    InviteCodeRedeemResult.subscriptionDeclined =>
    'You can subscribe anytime from Profile → Connect to Community '
        'Edition.',
  };

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
  );
}