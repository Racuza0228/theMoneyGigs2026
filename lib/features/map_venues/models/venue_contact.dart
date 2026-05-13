// lib/features/map_venues/models/venue_contact.dart

class VenueContact {
  final String name;
  final String phone;
  final String email;

  /// "text" | "call" | "email" | null
  final String? preferredMethod;

  /// Free-form notes: booking process, handoff details, seasonal patterns, etc.
  final String? notes;

  final bool isSharedWithNetwork;

  /// userId of the original sharer — never shown in UI, only used for
  /// ownership rules.
  final String? sharedBy;

  /// Most recent confirmation timestamp (server-side).
  final DateTime? lastConfirmed;
  final String? lastConfirmedBy;

  /// Number of distinct community members who have confirmed this contact.
  /// Read from Firestore; defaults to 0 locally.
  final int confirmationCount;

  const VenueContact({
    this.name = '',
    this.phone = '',
    this.email = '',
    this.preferredMethod,
    this.notes,
    this.isSharedWithNetwork = false,
    this.sharedBy,
    this.lastConfirmed,
    this.lastConfirmedBy,
    this.confirmationCount = 0,
  });

  // ── Convenience ───────────────────────────────────────────────────────────

  bool get isNotEmpty =>
      name.isNotEmpty || phone.isNotEmpty || email.isNotEmpty;

  /// True when lastConfirmed is older than 18 months.
  bool get isStale {
    if (lastConfirmed == null) return false;
    return lastConfirmed!
        .isBefore(DateTime.now().subtract(const Duration(days: 548)));
  }

  // ── Serialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'name': name,
    'phone': phone,
    'email': email,
    'preferredMethod': preferredMethod,
    'notes': notes,
    'isSharedWithNetwork': isSharedWithNetwork,
    'sharedBy': sharedBy,
    'lastConfirmed': lastConfirmed?.toIso8601String(),
    'lastConfirmedBy': lastConfirmedBy,
    'confirmationCount': confirmationCount,
  };

  factory VenueContact.fromJson(Map<String, dynamic> json) {
    DateTime? lastConfirmed;
    final raw = json['lastConfirmed'];
    if (raw is String) {
      lastConfirmed = DateTime.tryParse(raw);
    } else if (raw != null) {
      try {
        lastConfirmed = (raw as dynamic).toDate() as DateTime;
      } catch (_) {}
    }

    return VenueContact(
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      preferredMethod: json['preferredMethod'] as String?,
      notes: json['notes'] as String?,
      isSharedWithNetwork: json['isSharedWithNetwork'] as bool? ?? false,
      sharedBy: json['sharedBy'] as String?,
      lastConfirmed: lastConfirmed,
      lastConfirmedBy: json['lastConfirmedBy'] as String?,
      confirmationCount: json['confirmationCount'] as int? ?? 0,
    );
  }

  VenueContact copyWith({
    String? name,
    String? phone,
    String? email,
    String? preferredMethod,
    String? notes,
    bool? isSharedWithNetwork,
    String? sharedBy,
    DateTime? lastConfirmed,
    String? lastConfirmedBy,
    int? confirmationCount,
  }) {
    return VenueContact(
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      preferredMethod: preferredMethod ?? this.preferredMethod,
      notes: notes ?? this.notes,
      isSharedWithNetwork: isSharedWithNetwork ?? this.isSharedWithNetwork,
      sharedBy: sharedBy ?? this.sharedBy,
      lastConfirmed: lastConfirmed ?? this.lastConfirmed,
      lastConfirmedBy: lastConfirmedBy ?? this.lastConfirmedBy,
      confirmationCount: confirmationCount ?? this.confirmationCount,
    );
  }

  @override
  String toString() => 'VenueContact(name: $name, confirmations: $confirmationCount, '
      'shared: $isSharedWithNetwork)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is VenueContact &&
              name == other.name &&
              phone == other.phone &&
              email == other.email &&
              isSharedWithNetwork == other.isSharedWithNetwork;

  @override
  int get hashCode =>
      name.hashCode ^ phone.hashCode ^ email.hashCode ^ isSharedWithNetwork.hashCode;
}

// ─────────────────────────────────────────────────────────────────────────────

/// Booking logistics — only stored when isSharedWithNetwork is true.
class BookingInfo {
  /// Calendar months in advance the venue typically books. Range: 1–12.
  /// Null means not specified / unknown.
  ///
  /// Stored as "leadsOutMonths" in new records.
  /// Legacy "leadsOutWeeks" values are converted on read (see fromJson).
  final int? leadsOutMonths;

  /// "guarantee" | "door" | "both" | null
  final String? dealType;

  /// General booking notes (separate from contact-level notes).
  final String? notes;

  /// The calendar date the booking window opens (e.g., July 1).
  /// Only month + day are semantically meaningful — year advances each cycle.
  final DateTime? bookingWindowStart;

  const BookingInfo({
    this.leadsOutMonths,
    this.dealType,
    this.notes,
    this.bookingWindowStart,
  });

  // ── Computed ──────────────────────────────────────────────────────────────

  /// The next upcoming date this venue's booking window opens.
  /// Uses calendar-correct month arithmetic — "6 months from July 1"
  /// always lands on January 1, regardless of week count.
  /// Falls back to a 12-month interval if leadsOutMonths is not set.
  /// Returns null if bookingWindowStart is absent.
  DateTime? get nextBookingWindowDate {
    if (bookingWindowStart == null) return null;
    final now = DateTime.now();
    final interval = leadsOutMonths ?? 12;

    var candidate = bookingWindowStart!;
    while (!candidate.isAfter(now)) {
      candidate = DateTime(
        candidate.year,
        candidate.month + interval,
        candidate.day,
      );
    }
    return candidate;
  }

  // ── Serialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'leadsOutMonths': leadsOutMonths,
    'dealType': dealType,
    'notes': notes,
    'bookingWindowStart': bookingWindowStart?.toIso8601String(),
  };

  factory BookingInfo.fromJson(Map<String, dynamic> json) {
    // ── Migration: legacy leadsOutWeeks → leadsOutMonths ──────────────────
    // Old records stored weeks (int). Convert by rounding to nearest month.
    // 0 was a sentinel for "unknown" — treat as null.
    int? months;
    if (json['leadsOutMonths'] != null) {
      months = json['leadsOutMonths'] as int?;
    } else if (json['leadsOutWeeks'] != null) {
      final weeks = json['leadsOutWeeks'] as int;
      months = weeks > 0 ? (weeks / 4.33).round().clamp(1, 12) : null;
    }

    DateTime? windowStart;
    final raw = json['bookingWindowStart'];
    if (raw is String) {
      windowStart = DateTime.tryParse(raw);
    } else if (raw != null) {
      try {
        windowStart = (raw as dynamic).toDate() as DateTime;
      } catch (_) {}
    }

    return BookingInfo(
      leadsOutMonths: (months != null && months > 0) ? months : null,
      dealType: json['dealType'] as String?,
      notes: json['notes'] as String?,
      bookingWindowStart: windowStart,
    );
  }

  BookingInfo copyWith({
    int? leadsOutMonths,
    String? dealType,
    String? notes,
    DateTime? bookingWindowStart,
  }) {
    return BookingInfo(
      leadsOutMonths: leadsOutMonths ?? this.leadsOutMonths,
      dealType: dealType ?? this.dealType,
      notes: notes ?? this.notes,
      bookingWindowStart: bookingWindowStart ?? this.bookingWindowStart,
    );
  }
}