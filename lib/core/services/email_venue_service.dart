// services/email_template_builder.dart
// Single source of truth for booking email template assembly.
// Accepts Venue and MusicianProfile data; returns a populated EmailDraft.
// All null/missing-field logic lives here — callers never branch on data availability.

import '../models/email_draft.dart';

// ---------------------------------------------------------------------------
// Lightweight data containers — replace with your real Venue / MusicianProfile
// models once you wire this in. Only the fields consumed here are listed.
// ---------------------------------------------------------------------------

class VenueEmailData {
  final String name;
  final String? bookingEmail;
  final String? bookingContactName;
  final String? preferredContact; // 'email' | 'text' | 'call' | null

  const VenueEmailData({
    required this.name,
    this.bookingEmail,
    this.bookingContactName,
    this.preferredContact,
  });
}

class ProfileEmailData {
  final String? musicLink; // URL to promo video or EPK
  final String? city;

  const ProfileEmailData({
    this.musicLink,
    this.city,
  });
}

// ---------------------------------------------------------------------------
// Builder
// ---------------------------------------------------------------------------

class EmailTemplateBuilder {
  /// Assembles a booking inquiry [EmailDraft] from venue + profile data.
  ///
  /// Rules (mirrors the handoff spec exactly):
  /// - Greeting: [bookingContactName] if present, else 'Hi there,'
  /// - Music link: [musicLink] if present, else '[ADD LINK TO YOUR MUSIC HERE]'
  /// - City: [city] if present, else '[YOUR CITY]'
  /// - Venue name: always injected from venue record
  /// - Musician name: manual placeholder '[YOUR NAME]' — not collected at MVP
  static EmailDraft build({
    required VenueEmailData venue,
    required ProfileEmailData profile,
  }) {
    final toAddress = venue.bookingEmail ?? '';

    // --- Subject line ---
    // Format: Live Music Inquiry — [GENRE] | [VENUE NAME] | [MONTH/YEAR]
    final subject =
        'Live Music Inquiry — [GENRE] \u2502 ${venue.name} \u2502 [MONTH/YEAR]';

    // --- Greeting ---
    final greeting = venue.bookingContactName != null &&
        venue.bookingContactName!.trim().isNotEmpty
        ? 'Hi ${venue.bookingContactName!.trim()},'
        : 'Hi there,';

    // --- City ---
    final city = (profile.city != null && profile.city!.trim().isNotEmpty)
        ? profile.city!.trim()
        : '[YOUR CITY]';

    // --- Music link ---
    final musicLink =
    (profile.musicLink != null && profile.musicLink!.trim().isNotEmpty)
        ? profile.musicLink!.trim()
        : '[ADD LINK TO YOUR MUSIC HERE]';

    // --- Body ---
    final body = '''$greeting

My name is [YOUR NAME] and I'm a [GENRE] musician based in $city. I'd love to be considered for a live performance at ${venue.name}.

Dates I'm available:
[ADD YOUR REQUESTED DATES HERE — e.g. Friday evenings in July]

You can hear my music here:
$musicLink

[ADD ONE SENTENCE ABOUT WHY THIS VENUE IS A GOOD FIT FOR YOUR STYLE]

Thank you for your time — I'd love to find a date that works.

[YOUR NAME]''';

    return EmailDraft(
      toAddress: toAddress,
      subject: subject,
      body: body,
    );
  }
}