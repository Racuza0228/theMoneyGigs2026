// widgets/email_venue_button.dart
//
// Drop this widget into the Booking tab of venue_details_page,
// below Booking Contact section, above Booking Details.
//
// Handles all four visibility states from the handoff spec:
//   1. Email stored               → active button
//   2. No email, pref = text/call → active button + advisory banner
//   3. No email, no pref          → grayed button + tap-to-prompt
//   4. No email at all            → grayed button + tap-to-prompt
//
// Also handles the "no music link" nudge before launching.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/email_template_builder.dart';

class EmailVenueButton extends StatelessWidget {
  /// Venue-side data needed for template assembly.
  final VenueEmailData venue;

  /// Profile data for the logged-in musician.
  final ProfileEmailData profile;

  /// Called when the user taps the grayed button and we need them to add
  /// a booking email to the venue record. Supply a callback that opens
  /// the venue edit flow focused on the Booking email field.
  final VoidCallback? onAddBookingEmail;

  const EmailVenueButton({
    super.key,
    required this.venue,
    required this.profile,
    this.onAddBookingEmail,
  });

  // --------------------------------------------------------------------------
  // State derivation
  // --------------------------------------------------------------------------

  bool get _hasEmail =>
      venue.bookingEmail != null && venue.bookingEmail!.trim().isNotEmpty;

  bool get _prefersNonEmail =>
      venue.preferredContact != null &&
          (venue.preferredContact == 'text' || venue.preferredContact == 'call');

  String get _preferredContactLabel =>
      venue.preferredContact == 'text' ? 'Text' : 'Phone';

  // --------------------------------------------------------------------------
  // Build
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Advisory banner — only when email exists but venue prefers another method
        if (_hasEmail && _prefersNonEmail) _PreferredContactBanner(label: _preferredContactLabel),
        if (_hasEmail && _prefersNonEmail) const SizedBox(height: 8),

        // The button itself
        _EmailButton(
          enabled: _hasEmail,
          onTap: _hasEmail
              ? () => _handleTap(context)
              : () => _handleGrayedTap(context),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // Tap handlers
  // --------------------------------------------------------------------------

  Future<void> _handleTap(BuildContext context) async {
    final draft = EmailTemplateBuilder.build(venue: venue, profile: profile);
    final uri = Uri.parse(draft.toMailtoUri());
    final success = await canLaunchUrl(uri) && await launchUrl(uri);

    if (!context.mounted) return;
    if (!success) {
      _showNoEmailAppSnackbar(context, draft.toAddress);
    }
  }

  void _handleGrayedTap(BuildContext context) {
    _showAddEmailPrompt(context);
  }

  // --------------------------------------------------------------------------
  // Dialogs & snackbars
  // --------------------------------------------------------------------------

  void _showAddEmailPrompt(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'No booking email on file',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Add a booking email to this venue to use the email feature.',
          style: TextStyle(color: Color(0xFFB3B3B3)),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onAddBookingEmail?.call();
            },
            child: const Text('Add email'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Not now',
              style: TextStyle(color: Color(0xFFB3B3B3)),
            ),
          ),
        ],
      ),
    );
  }

  void _showNoEmailAppSnackbar(BuildContext context, String address) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          address.isNotEmpty
              ? 'No email app found. Copy the address and open your email manually: $address'
              : 'No email app found on this device.',
        ),
        duration: const Duration(seconds: 5),
        action: address.isNotEmpty
            ? SnackBarAction(
          label: 'Copy',
          onPressed: () {
            // Clipboard.setData(ClipboardData(text: address));
            // Uncomment and import flutter/services.dart
          },
        )
            : null,
      ),
    );
  }
}

// --------------------------------------------------------------------------
// Private sub-widgets
// --------------------------------------------------------------------------

class _EmailButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;

  const _EmailButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: enabled ? Colors.white : Colors.white38,
        side: BorderSide(
          color: enabled ? Colors.white70 : Colors.white24,
        ),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      icon: Icon(
        Icons.email_outlined,
        color: enabled ? Colors.white : Colors.white38,
        size: 18,
      ),
      label: const Text(
        'EMAIL VENUE',
        style: TextStyle(
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _PreferredContactBanner extends StatelessWidget {
  final String label;

  const _PreferredContactBanner({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 16, color: Color(0xFFB3B3B3)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'This venue prefers to be contacted by $label. You can still send an email, but you may get a faster response another way.',
              style: const TextStyle(
                color: Color(0xFFB3B3B3),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}