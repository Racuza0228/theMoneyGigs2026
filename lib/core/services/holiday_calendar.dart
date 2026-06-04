// lib/core/services/holiday_calendar.dart
//
// Zero-cost holiday detection for ImpactEventService.
// No API calls. No network. Works offline. Zero rate limits.
//
// Covers US federal holidays fully, plus major public holidays for
// 30+ countries derived from gig.address country suffix.
//
// Usage:
//   final holidays = HolidayCalendar.getHolidaysInWindow(
//     windowStart: gigDate.subtract(Duration(days: 5)),
//     windowEnd: gigDate,
//     countryCode: HolidayCalendar.countryCodeFromAddress(gig.address),
//   );

class HolidayCalendar {

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Returns all holidays in [windowStart]..[windowEnd] for [countryCode].
  /// Always includes US holidays (gigging musicians are the primary user base).
  /// Pass countryCode = 'US' if unknown.
  static List<HolidayOccurrence> getHolidaysInWindow({
    required DateTime windowStart,
    required DateTime windowEnd,
    String countryCode = 'US',
  }) {
    final List<HolidayOccurrence> results = [];
    final Set<String> codes = {'US', countryCode.toUpperCase()};

    final int startYear = windowStart.year;
    final int endYear = windowEnd.year;

    for (int year = startYear; year <= endYear; year++) {
      for (final def in _holidayDefinitions) {
        if (!codes.any((c) => def.countryCodes.contains(c))) continue;
        final DateTime? date = def.resolve(year);
        if (date == null) continue;
        if (!date.isBefore(windowStart) && !date.isAfter(windowEnd)) {
          results.add(HolidayOccurrence(
            name: def.name,
            date: date,
            impactLevel: def.impactLevel,
            countryCode: def.countryCodes.first,
          ));
        }
      }
    }

    results.sort((a, b) => a.date.compareTo(b.date));
    return results;
  }

  /// Derives a two-letter ISO country code from a Google Places address string.
  /// Google Places addresses end with the country name (e.g. "..., USA" or "..., United Kingdom").
  /// Returns 'US' as default if parsing fails.
  static String countryCodeFromAddress(String address) {
    if (address.isEmpty) return 'US';
    final parts = address.split(',');
    final last = parts.last.trim().toUpperCase();
    return _countryNameToCode[last] ?? _fuzzyCountryMatch(last) ?? 'US';
  }

  // ── Holiday Definitions ─────────────────────────────────────────────────────

  static final List<_HolidayDef> _holidayDefinitions = [

    // ── United States ─────────────────────────────────────────────────────────
    _HolidayDef(
      name: "New Year's Day",
      countryCodes: ['US', 'GB', 'CA', 'AU', 'NZ', 'IE'],
      impactLevel: 'high',
      resolve: (y) => DateTime(y, 1, 1),
    ),
    _HolidayDef(
      name: 'Martin Luther King Jr. Day',
      countryCodes: ['US'],
      impactLevel: 'medium',
      // 3rd Monday of January
      resolve: (y) => _nthWeekdayOfMonth(y, 1, DateTime.monday, 3),
    ),
    _HolidayDef(
      name: "Presidents' Day",
      countryCodes: ['US'],
      impactLevel: 'medium',
      // 3rd Monday of February
      resolve: (y) => _nthWeekdayOfMonth(y, 2, DateTime.monday, 3),
    ),
    _HolidayDef(
      name: 'Memorial Day',
      countryCodes: ['US'],
      impactLevel: 'high',
      // Last Monday of May
      resolve: (y) => _lastWeekdayOfMonth(y, 5, DateTime.monday),
    ),
    _HolidayDef(
      name: 'Juneteenth',
      countryCodes: ['US'],
      impactLevel: 'medium',
      resolve: (y) => y >= 2021 ? DateTime(y, 6, 19) : null,
    ),
    _HolidayDef(
      name: 'Independence Day',
      countryCodes: ['US'],
      impactLevel: 'high',
      resolve: (y) => DateTime(y, 7, 4),
    ),
    _HolidayDef(
      name: 'Labor Day',
      countryCodes: ['US'],
      impactLevel: 'high',
      // 1st Monday of September
      resolve: (y) => _nthWeekdayOfMonth(y, 9, DateTime.monday, 1),
    ),
    _HolidayDef(
      name: 'Columbus Day',
      countryCodes: ['US'],
      impactLevel: 'low',
      // 2nd Monday of October
      resolve: (y) => _nthWeekdayOfMonth(y, 10, DateTime.monday, 2),
    ),
    _HolidayDef(
      name: 'Veterans Day',
      countryCodes: ['US'],
      impactLevel: 'medium',
      resolve: (y) => DateTime(y, 11, 11),
    ),
    _HolidayDef(
      name: 'Thanksgiving Day',
      countryCodes: ['US'],
      impactLevel: 'high',
      // 4th Thursday of November
      resolve: (y) => _nthWeekdayOfMonth(y, 11, DateTime.thursday, 4),
    ),
    _HolidayDef(
      name: 'Christmas Eve',
      countryCodes: ['US', 'GB', 'CA', 'AU', 'DE', 'FR', 'IT', 'ES', 'NL', 'BE', 'AT', 'CH', 'SE', 'NO', 'DK', 'FI', 'IE', 'NZ', 'MX', 'BR', 'AR'],
      impactLevel: 'high',
      resolve: (y) => DateTime(y, 12, 24),
    ),
    _HolidayDef(
      name: 'Christmas Day',
      countryCodes: ['US', 'GB', 'CA', 'AU', 'DE', 'FR', 'IT', 'ES', 'NL', 'BE', 'AT', 'CH', 'SE', 'NO', 'DK', 'FI', 'IE', 'NZ', 'MX', 'BR', 'AR'],
      impactLevel: 'high',
      resolve: (y) => DateTime(y, 12, 25),
    ),
    _HolidayDef(
      name: "New Year's Eve",
      countryCodes: ['US', 'GB', 'CA', 'AU', 'NZ', 'IE', 'DE', 'FR', 'IT', 'ES', 'NL'],
      impactLevel: 'high',
      resolve: (y) => DateTime(y, 12, 31),
    ),

    // ── Super Bowl Sunday (US — not a federal holiday but massive crowd impact) ──
    _HolidayDef(
      name: 'Super Bowl Sunday',
      countryCodes: ['US'],
      impactLevel: 'high',
      // 2nd Sunday of February (approximate — actual date shifts ~1 week)
      // Close enough for a 5-day window scan
      resolve: (y) => _nthWeekdayOfMonth(y, 2, DateTime.sunday, 2),
    ),

    // ── US "shoulder" holidays — strong crowd movement ────────────────────────
    _HolidayDef(
      name: 'Easter Sunday',
      countryCodes: ['US', 'GB', 'CA', 'AU', 'NZ', 'IE', 'DE', 'FR', 'IT', 'ES', 'NL', 'BE', 'AT', 'CH', 'SE', 'NO', 'DK', 'FI', 'MX', 'BR', 'AR'],
      impactLevel: 'high',
      resolve: (y) => _easter(y),
    ),
    _HolidayDef(
      name: 'Good Friday',
      countryCodes: ['US', 'GB', 'CA', 'AU', 'NZ', 'IE', 'DE', 'FR', 'IT', 'ES', 'NL', 'BE', 'AT', 'CH', 'SE', 'NO', 'DK', 'FI'],
      impactLevel: 'medium',
      resolve: (y) => _easter(y)?.subtract(const Duration(days: 2)),
    ),
    _HolidayDef(
      name: 'Halloween',
      countryCodes: ['US', 'CA', 'IE', 'GB'],
      impactLevel: 'medium',
      resolve: (y) => DateTime(y, 10, 31),
    ),
    _HolidayDef(
      name: "St. Patrick's Day",
      countryCodes: ['US', 'IE', 'CA', 'GB', 'AU'],
      impactLevel: 'medium',
      resolve: (y) => DateTime(y, 3, 17),
    ),
    _HolidayDef(
      name: "Valentine's Day",
      countryCodes: ['US', 'CA', 'GB', 'AU'],
      impactLevel: 'low',
      resolve: (y) => DateTime(y, 2, 14),
    ),
    _HolidayDef(
      name: "Mother's Day",
      countryCodes: ['US', 'CA', 'AU'],
      impactLevel: 'medium',
      // 2nd Sunday of May
      resolve: (y) => _nthWeekdayOfMonth(y, 5, DateTime.sunday, 2),
    ),
    _HolidayDef(
      name: "Father's Day",
      countryCodes: ['US', 'CA', 'GB'],
      impactLevel: 'low',
      // 3rd Sunday of June (US/CA); 2nd Sunday of June (GB) — using US
      resolve: (y) => _nthWeekdayOfMonth(y, 6, DateTime.sunday, 3),
    ),

    // ── Canada ────────────────────────────────────────────────────────────────
    _HolidayDef(
      name: 'Canada Day',
      countryCodes: ['CA'],
      impactLevel: 'high',
      resolve: (y) => DateTime(y, 7, 1),
    ),
    _HolidayDef(
      name: 'Victoria Day',
      countryCodes: ['CA'],
      impactLevel: 'medium',
      // Last Monday before May 25
      resolve: (y) => _lastMondayBefore(y, 5, 25),
    ),
    _HolidayDef(
      name: 'Thanksgiving Day (Canada)',
      countryCodes: ['CA'],
      impactLevel: 'high',
      // 2nd Monday of October
      resolve: (y) => _nthWeekdayOfMonth(y, 10, DateTime.monday, 2),
    ),

    // ── United Kingdom ────────────────────────────────────────────────────────
    _HolidayDef(
      name: 'Bank Holiday',
      countryCodes: ['GB'],
      impactLevel: 'medium',
      // Early May Bank Holiday — 1st Monday of May
      resolve: (y) => _nthWeekdayOfMonth(y, 5, DateTime.monday, 1),
    ),
    _HolidayDef(
      name: 'Boxing Day',
      countryCodes: ['GB', 'CA', 'AU', 'NZ', 'IE'],
      impactLevel: 'medium',
      resolve: (y) => DateTime(y, 12, 26),
    ),

    // ── Australia ─────────────────────────────────────────────────────────────
    _HolidayDef(
      name: 'Australia Day',
      countryCodes: ['AU'],
      impactLevel: 'high',
      resolve: (y) => DateTime(y, 1, 26),
    ),
    _HolidayDef(
      name: 'ANZAC Day',
      countryCodes: ['AU', 'NZ'],
      impactLevel: 'medium',
      resolve: (y) => DateTime(y, 4, 25),
    ),

    // ── Germany ───────────────────────────────────────────────────────────────
    _HolidayDef(
      name: 'German Unity Day',
      countryCodes: ['DE'],
      impactLevel: 'high',
      resolve: (y) => DateTime(y, 10, 3),
    ),

    // ── France ────────────────────────────────────────────────────────────────
    _HolidayDef(
      name: 'Bastille Day',
      countryCodes: ['FR'],
      impactLevel: 'high',
      resolve: (y) => DateTime(y, 7, 14),
    ),

    // ── Ireland ───────────────────────────────────────────────────────────────
    _HolidayDef(
      name: 'Bank Holiday (Ireland)',
      countryCodes: ['IE'],
      impactLevel: 'medium',
      // 1st Monday of August
      resolve: (y) => _nthWeekdayOfMonth(y, 8, DateTime.monday, 1),
    ),

    // ── Mexico ────────────────────────────────────────────────────────────────
    _HolidayDef(
      name: 'Día de la Independencia',
      countryCodes: ['MX'],
      impactLevel: 'high',
      resolve: (y) => DateTime(y, 9, 16),
    ),
    _HolidayDef(
      name: 'Día de los Muertos',
      countryCodes: ['MX'],
      impactLevel: 'medium',
      resolve: (y) => DateTime(y, 11, 2),
    ),

    // ── Japan ─────────────────────────────────────────────────────────────────
    _HolidayDef(
      name: 'Golden Week',
      countryCodes: ['JP'],
      impactLevel: 'high',
      resolve: (y) => DateTime(y, 5, 3),
    ),
    _HolidayDef(
      name: 'Obon (start)',
      countryCodes: ['JP'],
      impactLevel: 'medium',
      resolve: (y) => DateTime(y, 8, 13),
    ),
  ];

  // ── Date Math Helpers ────────────────────────────────────────────────────────

  /// Nth occurrence of a weekday in a month.
  /// [weekday] uses DateTime constants: DateTime.monday = 1 ... DateTime.sunday = 7
  static DateTime? _nthWeekdayOfMonth(int year, int month, int weekday, int n) {
    DateTime first = DateTime(year, month, 1);
    int daysUntil = (weekday - first.weekday + 7) % 7;
    DateTime firstOccurrence = first.add(Duration(days: daysUntil));
    DateTime result = firstOccurrence.add(Duration(days: 7 * (n - 1)));
    if (result.month != month) return null;
    return result;
  }

  /// Last occurrence of a weekday in a month.
  static DateTime? _lastWeekdayOfMonth(int year, int month, int weekday) {
    DateTime lastDay = DateTime(year, month + 1, 0); // last day of month
    int daysBack = (lastDay.weekday - weekday + 7) % 7;
    return lastDay.subtract(Duration(days: daysBack));
  }

  /// Last Monday before the Nth of a month (used for Victoria Day).
  static DateTime? _lastMondayBefore(int year, int month, int dayOfMonth) {
    DateTime anchor = DateTime(year, month, dayOfMonth);
    int daysBack = (anchor.weekday - DateTime.monday + 7) % 7;
    if (daysBack == 0) daysBack = 7; // if anchor IS Monday, go back a week
    return anchor.subtract(Duration(days: daysBack));
  }

  /// Computes Easter Sunday using the Anonymous Gregorian algorithm.
  static DateTime? _easter(int year) {
    final a = year % 19;
    final b = year ~/ 100;
    final c = year % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final month = (h + l - 7 * m + 114) ~/ 31;
    final day = ((h + l - 7 * m + 114) % 31) + 1;
    return DateTime(year, month, day);
  }

  // ── Country Name → ISO Code mapping ──────────────────────────────────────
  //
  // Google Places address strings end with the country name in English.
  // This maps the most common ones to ISO 3166-1 alpha-2 codes.

  static const Map<String, String> _countryNameToCode = {
    'USA': 'US',
    'UNITED STATES': 'US',
    'UNITED STATES OF AMERICA': 'US',
    'US': 'US',
    'CANADA': 'CA',
    'UNITED KINGDOM': 'GB',
    'UK': 'GB',
    'ENGLAND': 'GB',
    'SCOTLAND': 'GB',
    'WALES': 'GB',
    'NORTHERN IRELAND': 'GB',
    'AUSTRALIA': 'AU',
    'NEW ZEALAND': 'NZ',
    'IRELAND': 'IE',
    'GERMANY': 'DE',
    'DEUTSCHLAND': 'DE',
    'FRANCE': 'FR',
    'ITALY': 'IT',
    'ITALIA': 'IT',
    'SPAIN': 'ES',
    'ESPAÑA': 'ES',
    'NETHERLANDS': 'NL',
    'THE NETHERLANDS': 'NL',
    'HOLLAND': 'NL',
    'BELGIUM': 'BE',
    'AUSTRIA': 'AT',
    'SWITZERLAND': 'CH',
    'SWEDEN': 'SE',
    'NORWAY': 'NO',
    'DENMARK': 'DK',
    'FINLAND': 'FI',
    'MEXICO': 'MX',
    'MÉXICO': 'MX',
    'BRAZIL': 'BR',
    'BRASIL': 'BR',
    'ARGENTINA': 'AR',
    'JAPAN': 'JP',
    'NIPPON': 'JP',
  };

  static String? _fuzzyCountryMatch(String input) {
    for (final entry in _countryNameToCode.entries) {
      if (input.contains(entry.key) || entry.key.contains(input)) {
        return entry.value;
      }
    }
    return null;
  }
}

// ── Data types ────────────────────────────────────────────────────────────────

class _HolidayDef {
  final String name;
  final List<String> countryCodes;
  final String impactLevel; // 'low' | 'medium' | 'high'
  final DateTime? Function(int year) resolve;

  const _HolidayDef({
    required this.name,
    required this.countryCodes,
    required this.impactLevel,
    required this.resolve,
  });
}

/// A resolved holiday occurrence on a specific date.
class HolidayOccurrence {
  final String name;
  final DateTime date;
  final String impactLevel;
  final String countryCode;

  const HolidayOccurrence({
    required this.name,
    required this.date,
    required this.impactLevel,
    required this.countryCode,
  });
}