import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';  // NEW: For Clipboard
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';
import 'package:the_money_gigs/features/map_venues/repositories/venue_repository.dart';
import 'package:the_money_gigs/features/profile/views/reconciliation_screen.dart';
import 'package:the_money_gigs/global_refresh_notifier.dart';
import 'package:the_money_gigs/core/services/auth_service.dart';
import 'package:the_money_gigs/core/services/network_service.dart';
import 'package:the_money_gigs/core/services/subscription_service.dart';
import 'package:the_money_gigs/main.dart';

class ConnectWidget extends StatefulWidget {
  const ConnectWidget({super.key});

  @override
  State<ConnectWidget> createState() => _ConnectWidgetState();
}

class _ConnectWidgetState extends State<ConnectWidget> {
  bool _isConnected = false;
  List<String> _myInviteCodes = [];        // CHANGED: User's shareable codes
  bool _hasActiveSubscription = false;
  bool _isFounder = false;

  static const String _isConnectedKey = 'is_connected_to_network';
  static const String _inviteCodeKey = 'network_invite_code';      // Legacy - code user used
  static const String _myInviteCodesKey = 'my_invite_codes';       // NEW - user's codes
  static const String _venuesKey = 'saved_locations';

  @override
  void initState() {
    super.initState();
    _loadConnectionStatus();
    _checkSubscriptionStatus();  // NEW: Check subscription on load
  }

  /// NEW: Computed property for actual network access
  /// Paid subscribers have access even if toggle is off
  bool get _hasNetworkAccess {
    // Founders: respect their toggle preference
    if (_isFounder) {
      return _isConnected;
    }

    // Paid subscribers: always have access (regardless of toggle)
    if (_hasActiveSubscription) {
      return true;
    }

    // Everyone else: respect toggle
    return _isConnected;
  }

  Future<void> _loadConnectionStatus() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isConnected = prefs.getBool(_isConnectedKey) ?? false;
      // Load cached invite codes
      final codesJson = prefs.getStringList(_myInviteCodesKey);
      _myInviteCodes = codesJson ?? [];
    });

    // If connected, fetch latest codes from Firebase
    if (_isConnected) {
      await _fetchMyInviteCodes();
    }
  }

  /// NEW: Fetch user's invite codes from Firebase
  Future<void> _fetchMyInviteCodes() async {
    try {
      final authService = AuthService();
      if (!authService.isSignedIn) return;

      final networkService = NetworkService();
      final member = await networkService.getMember(authService.currentUserId);

      if (member != null && member.myInviteCodes.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_myInviteCodesKey, member.myInviteCodes);

        setState(() {
          _myInviteCodes = member.myInviteCodes;
        });
      }
    } catch (e) {
      print('Error fetching invite codes: $e');
    }
  }

  /// NEW: Check subscription status on app load
  Future<void> _checkSubscriptionStatus() async {
    final authService = AuthService();
    final networkService = NetworkService();
    final subscriptionService = SubscriptionService();

    // Must be signed in to check
    if (!authService.isSignedIn) {
      setState(() {
        _hasActiveSubscription = false;
        _isFounder = false;
      });
      return;
    }

    try {
      // Check if founder
      final userId = authService.currentUserId;
      final member = await networkService.getMember(userId);

      if (member != null) {
        final inviteCodeDoc = await networkService.validateInviteCode(member.inviteCodeUsed);
        final isFounder = inviteCodeDoc?.isFounderCode ?? false;

        if (isFounder) {
          // Founder = free access, respects toggle
          setState(() {
            _isFounder = true;
            _hasActiveSubscription = false;
          });
          return;
        }
      }

      // Check RevenueCat subscription
      final hasSubscription = await subscriptionService.hasActiveSubscription();

      setState(() {
        _hasActiveSubscription = hasSubscription;
        _isFounder = false;
      });

      // If subscription active, auto-enable network
      if (hasSubscription) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_isConnectedKey, true);
        setState(() {
          _isConnected = true;
        });
      }
    } catch (e) {
      print('Error checking subscription status: $e');
      setState(() {
        _hasActiveSubscription = false;
        _isFounder = false;
      });
    }
  }

  Future<void> _toggleConnection(bool value) async {

    if (value) {
      // ...ensure network services are initialized FIRST.
      await initializeNetworkServices();
    }

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
                'Community Edition requires a Google account to submit ratings and comments.\n\n'
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
        // Already in system - check if founder or needs subscription check
        final inviteCodeDoc = await networkService.validateInviteCode(member.inviteCodeUsed);
        final isFounder = inviteCodeDoc?.isFounderCode ?? false;

        // Enable connection and save user's codes
        await prefs.setBool(_isConnectedKey, true);
        await prefs.setStringList(_myInviteCodesKey, member.myInviteCodes);  // NEW: Save codes

        setState(() {
          _isConnected = true;
          _myInviteCodes = member.myInviteCodes;  // NEW: Set codes
          _isFounder = isFounder;
        });

        // For non-founders, verify subscription
        if (!isFounder) {
          final subscriptionService = SubscriptionService();
          final hasSubscription = await subscriptionService.hasActiveSubscription();
          setState(() {
            _hasActiveSubscription = hasSubscription;
          });
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Community Edition enabled!'),
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
        // Founder gets free access! Fetch their new codes
        final member = await networkService.getMember(userId);
        final userCodes = member?.myInviteCodes ?? [];

        await prefs.setBool(_isConnectedKey, true);
        await prefs.setString(_inviteCodeKey, code);
        await prefs.setStringList(_myInviteCodesKey, userCodes);  // NEW: Save codes

        setState(() {
          _isConnected = true;
          _myInviteCodes = userCodes;      // NEW: Set codes
          _isFounder = true;
          _hasActiveSubscription = false;
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
          // Already subscribed, just enable - fetch their codes
          final member = await networkService.getMember(userId);
          final userCodes = member?.myInviteCodes ?? [];

          await prefs.setBool(_isConnectedKey, true);
          await prefs.setString(_inviteCodeKey, code);
          await prefs.setStringList(_myInviteCodesKey, userCodes);  // NEW: Save codes

          setState(() {
            _isConnected = true;
            _myInviteCodes = userCodes;        // NEW: Set codes
            _hasActiveSubscription = true;
            _isFounder = false;
          });

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Community Edition enabled!'),
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
                  'Community Edition \$2/month.\n\n'
                      'You\'ll get:\n'
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
            // Success! Fetch their new codes
            final member = await networkService.getMember(userId);
            final userCodes = member?.myInviteCodes ?? [];

            await prefs.setBool(_isConnectedKey, true);
            await prefs.setString(_inviteCodeKey, code);
            await prefs.setStringList(_myInviteCodesKey, userCodes);  // NEW: Save codes

            setState(() {
              _isConnected = true;
              _myInviteCodes = userCodes;      // NEW: Set codes
              _hasActiveSubscription = true;
              _isFounder = false;
            });

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Subscription active! Community Edition enabled.'),
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
      // TURNING OFF - Handle Paid Subscriptions
      // ========================================

      // NEW: If paid subscriber, warn them they keep access
      if (_hasActiveSubscription) {
        final shouldContinue = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Active Subscription'),
            content: const Text(
                'You have an active subscription.\n\n'
                    'You\'ll continue to have access to Community Edition features '
                    'until your subscription expires, regardless of this toggle.\n\n'
                    'To cancel your subscription, use your device\'s subscription management.\n\n'
                    'Continue turning off the toggle?'
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                child: const Text('Turn Off Toggle'),
              ),
            ],
          ),
        );

        if (shouldContinue != true) return;

        // Save preference (but subscription keeps access active)
        await prefs.setBool(_isConnectedKey, false);
        setState(() {
          _isConnected = false;
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Toggle disabled (subscription still active - you still have access)'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );

        globalRefreshNotifier.notify();
        return;
      }

      // Original logic for non-paid users (founders, etc.)
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Disable Community Edition?'),
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
          content: Text('Community Edition disabled. Access continues until end of billing period.'),
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

    // Determine subtitle based on state
    String subtitle;
    if (_hasNetworkAccess) {
      if (_isFounder) {
        subtitle = 'Founder Access (Free Forever)';
      } else if (_hasActiveSubscription && !_isConnected) {
        subtitle = 'Active Subscription (toggle off, but you still have access)';
      } else if (_hasActiveSubscription) {
        subtitle = 'Active Subscription';
      } else {
        subtitle = 'Connected';
      }
    } else {
      subtitle = 'Share venues and collaborate';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: const Text('Connect to Community Edition'),
          subtitle: Text(subtitle),
          value: _isConnected,
          onChanged: _toggleConnection,
          secondary: Icon(
            _hasNetworkAccess ? Icons.cloud : Icons.cloud_outlined,
            color: _hasNetworkAccess
                ? theme.colorScheme.primary
                : Colors.grey.shade500,
          ),
          contentPadding: EdgeInsets.zero,
        ),

        // Show access status indicator
        if (_hasNetworkAccess) ...[
          Padding(
            padding: const EdgeInsets.only(left: 56, right: 16, bottom: 8),
            child: Row(
              children: [
                Icon(
                  _hasActiveSubscription ? Icons.check_circle : Icons.stars,
                  color: Colors.green,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isFounder
                        ? 'Network features enabled'
                        : _hasActiveSubscription
                        ? 'Subscription active - Full access'
                        : 'Connected',
                    style: TextStyle(
                      color: Colors.green.shade300,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // NEW: Show user's shareable invite codes
          if (_myInviteCodes.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(left: 56, right: 16, top: 8, bottom: 4),
              child: Text(
                'Your Invite Codes (share with friends):',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            ..._myInviteCodes.map((code) => Padding(
              padding: const EdgeInsets.only(left: 56, right: 16, bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      code,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: theme.colorScheme.secondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: 'Copy to clipboard',
                    onPressed: () => _copyToClipboard(code),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            )),
          ],
        ],

        Divider(color: Colors.grey.shade700, height: 1),
      ],
    );
  }

  /// NEW: Copy invite code to clipboard
  void _copyToClipboard(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ Copied: $code'),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.green,
      ),
    );
  }
}