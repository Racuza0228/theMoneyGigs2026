import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';
import 'package:the_money_gigs/features/map_venues/repositories/venue_repository.dart';
import 'package:the_money_gigs/features/profile/views/reconciliation_screen.dart';
import 'package:the_money_gigs/global_refresh_notifier.dart';
import 'package:the_money_gigs/core/services/auth_service.dart';
import 'package:the_money_gigs/core/services/network_service.dart';
import 'package:the_money_gigs/core/services/subscription_service.dart';

class ConnectWidget extends StatefulWidget {
  const ConnectWidget({super.key});

  @override
  State<ConnectWidget> createState() => _ConnectWidgetState();
}

class _ConnectWidgetState extends State<ConnectWidget> {
  bool _isConnected = false;
  String? _inviteCode;
  final _venueRepository = VenueRepository();

  static const String _isConnectedKey = 'is_connected_to_network';
  static const String _inviteCodeKey = 'network_invite_code';
  static const String _venuesKey = 'saved_locations'; // Key for venues in SharedPreferences

  @override
  void initState() {
    super.initState();
    _loadConnectionStatus();
  }

  Future<void> _loadConnectionStatus() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isConnected = prefs.getBool(_isConnectedKey) ?? false;
      _inviteCode = prefs.getString(_inviteCodeKey);
    });
  }

  Future<void> _toggleConnection(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final authService = AuthService();
    final networkService = NetworkService();

    if (value) {
      // ========================================
      // TURNING ON - Complete Onboarding Flow
      // ========================================

      // STEP 1: Ensure user is signed in with Google
      if (!authService.isSignedIn) {
        if (!mounted) return;

        final shouldSignIn = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Sign In Required'),
            content: const Text(
                'Network Edition requires a Google account to sync your data and manage your subscription.\n\n'
                    'Sign in with Google to continue.'
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.login),
                label: const Text('Sign In with Google'),
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        );

        if (shouldSignIn != true) return;

        // Show loading
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator()),
        );

        // Attempt Google sign-in
        final result = await authService.signInWithGoogle();

        // Close loading
        if (!mounted) return;
        Navigator.pop(context);

        if (result == null) {
          // Sign-in failed or cancelled
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sign-in cancelled or failed'),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }

        // Success! Continue to next step...
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Signed in as ${result.user?.email}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // STEP 2: Check if user has network access
      final userId = authService.currentUserId;
      final member = await networkService.getMember(userId);

      if (member != null) {
        // Already in system - just enable
        await prefs.setBool(_isConnectedKey, true);
        setState(() {
          _isConnected = true;
          _inviteCode = member.inviteCodeUsed;
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Network Edition enabled!'),
            backgroundColor: Colors.green,
          ),
        );

        globalRefreshNotifier.notify();
        _promptForReconciliation();
        return;
      }

      // STEP 3: Not in system - request invite code
      final code = await _showInviteCodeDialog();
      if (code == null || code.isEmpty) {
        return; // User cancelled
      }

      // STEP 4: Validate invite code and create member
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final success = await networkService.createMemberWithInviteCode(
        userId: userId,
        email: authService.currentUser?.email ?? '',
        inviteCode: code,
      );

      // Close loading
      if (!mounted) return;
      Navigator.pop(context);

      if (!success) {
        // Invalid code
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Invalid invite code. Please check and try again.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      // STEP 5: Check if founder code (free) or requires subscription
      final inviteCodeDoc = await networkService.validateInviteCode(code);
      final isFreeUser = inviteCodeDoc?.isFounderCode ?? false;
      final subscriptionService = SubscriptionService();

      if (isFreeUser) {
        // Founder gets free access!
        await prefs.setBool(_isConnectedKey, true);
        await prefs.setString(_inviteCodeKey, code);
        setState(() {
          _isConnected = true;
          _inviteCode = code;
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Founder access granted - FREE forever!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );

        globalRefreshNotifier.notify();
        _promptForReconciliation();
      } else {
        // Regular user - needs $2/month subscription

        // Check if already has active subscription
        final hasActiveSubscription = await subscriptionService.hasActiveSubscription();

        if (hasActiveSubscription) {
          // Already subscribed, just enable
          await prefs.setBool(_isConnectedKey, true);
          await prefs.setString(_inviteCodeKey, code);
          setState(() {
            _isConnected = true;
            _inviteCode = code;
          });

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Network Edition enabled!'),
              backgroundColor: Colors.green,
            ),
          );

          globalRefreshNotifier.notify();
          _promptForReconciliation();
        } else {
          // Need to purchase subscription
          final shouldPurchase = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Start Subscription'),
              content: const Text(
                  'Network Edition costs \$2/month.\n\n'
                      'You\'ll get:\n'
                      '• Cloud sync across devices\n'
                      '• Access to 1000+ venues\n'
                      '• Community ratings & reviews\n'
                      'Cancel anytime.'
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Not Now'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Subscribe (\$2/month)'),
                ),
              ],
            ),
          );

          if (shouldPurchase != true) return;

          // Start purchase flow
          if (!mounted) return;
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const Center(child: CircularProgressIndicator()),
          );

          bool purchased = false;
          String errorMessage = '';

          try {
            purchased = await subscriptionService.purchaseMonthlySubscription();
          } catch (e) {
            errorMessage = e.toString();
            print('❌ Purchase exception: $e');
          }

// Close loading
          if (!mounted) return;
          Navigator.pop(context);

          if (purchased) {
            // Success!
            await prefs.setBool(_isConnectedKey, true);
            await prefs.setString(_inviteCodeKey, code);
            setState(() {
              _isConnected = true;
              _inviteCode = code;
            });

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Subscription active! Network Edition enabled.'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );

            globalRefreshNotifier.notify();
            _promptForReconciliation();
          } else {
            // Purchase failed or cancelled
            String message = 'Subscription not started.';

            // Check if it's because products aren't configured
            if (errorMessage.contains('No offerings') ||
                errorMessage.contains('Monthly package not found')) {
              message = '⚠️ Subscriptions not yet configured. Contact support.';
            } else if (errorMessage.contains('cancelled')) {
              message = 'Purchase cancelled. Try again when ready.';
            }

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      }

    } else {
      // ========================================
      // TURNING OFF - Cancel Subscription
      // ========================================

      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Disable Network Edition?'),
          content: const Text(
              'Your subscription will be cancelled, but you\'ll keep access until the end of your current billing period.\n\n'
                  'Your data will remain in the cloud and you can re-enable anytime.'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep Active'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Disable'),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      // Guide user to platform subscription management
      final subscriptionService = SubscriptionService();
      await subscriptionService.manageSubscription();

      await prefs.setBool(_isConnectedKey, false);
      setState(() {
        _isConnected = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Network Edition disabled. Access continues until end of billing period.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );

      globalRefreshNotifier.notify();
    }
  }

  Future<String?> _showInviteCodeDialog() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Invite Code'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Your invite code'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Future<void> _promptForReconciliation() async {
    if (!mounted) return;

    final shouldReconcile = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reconcile Venues'),
        content: const Text('Do you want to reconcile the venues on your device with those in the MoneyGigs system?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    // If "Yes", navigate to the new screen.
    if (shouldReconcile == true && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => const ReconciliationScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: const Text('Connect to Network Edition'),
          subtitle: Text(_isConnected
              ? 'Connected with code: ${_inviteCode ?? "..."}'
              : 'Share venues and collaborate'),
          value: _isConnected,
          onChanged: _toggleConnection,
          secondary: Icon(
            Icons.cloud_outlined,
            color: _isConnected
                ? theme.colorScheme.primary
                : Colors.grey.shade500,
          ),
          contentPadding: EdgeInsets.zero,
        ),
        Divider(color: Colors.grey.shade700, height: 1),
      ],
    );
  }
}
