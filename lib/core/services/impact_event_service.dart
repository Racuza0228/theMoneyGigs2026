// lib/core/services/impact_event_service.dart
//
// Fetches nearby events that may impact gig crowd size.
//
// LAYER 1 — Holidays (this update): zero-cost, zero-API, pure Dart.
//   Uses HolidayCalendar to detect public holidays in the gig window.
//   Country derived automatically from gig.address.
//
// LAYER 2 — Ticketmaster Discovery API (existing): concerts + sports.
//   Free tier: 5000 calls/day. Register at developer.ticketmaster.com.
//
// LAYER 3 — SerpApi Google Events (future): city events + live music.
//   Planned next sprint.
//
// API key injection:
//   --dart-define=TICKETMASTER_API_KEY=your_key_here

import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/core/utils/logger.dart';
import 'package:the_money_gigs/core/services/holiday_calendar.dart'; // ← NEW
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';
import 'package:the_money_gigs/features/gigs/models/impact_event.dart';

// ── Configuration ─────────────────────────────────────────────────────────────

const int kImpactWindowDaysBefore = 5;
const int kImpactWindowDaysAfter = 0;
const double kImpactRadiusMiles = 5.0;  // API fetch radius
const double kImpactFilterMiles = 5.0;   // Client-side filter — drop anything beyond this
const Duration kImpactCacheTtl = Duration(hours: 24);

// ── Service ───────────────────────────────────────────────────────────────────

class ImpactEventService {
  static const String _cacheKeyPrefix = 'impact_events_v4_';
  static const String _lastAssessedKeyPrefix = 'impact_assessed_v4_';
  static const String _tmBaseUrl =
      'https://app.ticketmaster.com/discovery/v2/events.json';

  final http.Client _httpClient;
  final String _apiKey;

  ImpactEventService({
    http.Client? httpClient,
    String? apiKey,
  })  : _httpClient = httpClient ?? http.Client(),
        _apiKey = apiKey ??
            const String.fromEnvironment('TICKETMASTER_API_KEY');

  bool get _isConfigured => _apiKey.isNotEmpty;

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Fetch all impact events for a gig.
  ///
  /// Always runs the holiday layer (zero cost).
  /// Runs the Ticketmaster layer only when an API key is configured.
  /// Falls back to mock data when no key is present (dev mode).
  Future<List<ImpactEvent>> fetchImpactEvents({
    required Gig gig,
    bool forceRefresh = false,
  }) async {
    final cacheKey = _cacheKeyFor(gig);

    if (!forceRefresh) {
      final cached = await _readCache(cacheKey);
      if (cached != null) {
        log('⚡ [ImpactEventService] Cache hit for ${gig.id}.');
        return cached;
      }
    }

    final windowStart =
    gig.dateTime.subtract(Duration(days: kImpactWindowDaysBefore));
    final windowEnd =
    gig.dateTime.add(Duration(days: kImpactWindowDaysAfter + 1));

    // ── Layer 1: Holidays (always runs) ────────────────────────────────────
    final List<ImpactEvent> holidayEvents = _checkHolidays(
      address: gig.address,
      windowStart: windowStart,
      windowEnd: windowEnd,
    );
    log('⚡ [ImpactEventService] Holiday layer: ${holidayEvents.length} hits for ${gig.venueName}.');

    // ── Layer 2: Ticketmaster / mock ────────────────────────────────────────
    final List<ImpactEvent> apiEvents;
    if (_isConfigured) {
      apiEvents = await _fetchTicketmaster(
        latitude: gig.latitude,
        longitude: gig.longitude,
        windowStart: windowStart,
        windowEnd: windowEnd,
      );
    } else {
      log('⚡ [ImpactEventService] No API key — using mock data for dev.');
      apiEvents = _mockEvents(gig.dateTime);
    }

    // ── Merge, deduplicate, sort ────────────────────────────────────────────
    final all = [...holidayEvents, ...apiEvents];
    final deduped = _deduplicateAndSort(all);

    await _writeCache(cacheKey, deduped);
    await _writeLastAssessed(gig.id);
    log('⚡ [ImpactEventService] Total: ${deduped.length} events for ${gig.id} '
        '(${holidayEvents.length} holidays, ${apiEvents.length} from API).');
    return deduped;
  }

  /// Re-assess all upcoming gigs whose cache is stale. Called silently on app open.
  Future<Map<String, List<ImpactEvent>>> reassessUpcomingGigs({
    required List<Gig> upcomingGigs,
    int lookAheadDays = 30,
  }) async {
    final Map<String, List<ImpactEvent>> results = {};
    final DateTime cutoff = DateTime.now().add(Duration(days: lookAheadDays));

    final gigsToCheck = upcomingGigs.where(
          (g) => !g.isJamOpenMic && g.dateTime.isBefore(cutoff) && !g.hasEnded,
    );

    for (final gig in gigsToCheck) {
      final lastAssessed = await _readLastAssessed(gig.id);
      final bool isStale = lastAssessed == null ||
          DateTime.now().difference(lastAssessed) > kImpactCacheTtl;

      if (isStale) {
        await Future.delayed(const Duration(milliseconds: 250));
        final events = await fetchImpactEvents(gig: gig);
        results[gig.id] = events;
      } else {
        final cached = await _readCache(_cacheKeyFor(gig));
        if (cached != null) results[gig.id] = cached;
      }
    }

    return results;
  }

  /// Read cached events without an API call. Returns null if no cache.
  Future<List<ImpactEvent>?> getCachedEvents(Gig gig) =>
      _readCache(_cacheKeyFor(gig));

  // ── Layer 1: Holiday Detection ────────────────────────────────────────────

  List<ImpactEvent> _checkHolidays({
    required String address,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) {
    final countryCode = HolidayCalendar.countryCodeFromAddress(address);
    final holidays = HolidayCalendar.getHolidaysInWindow(
      windowStart: windowStart,
      windowEnd: windowEnd,
      countryCode: countryCode,
    );

    return holidays.map((h) => ImpactEvent(
      eventName: h.name,
      eventDate: h.date,
      eventType: 'holiday',
      distanceMiles: null, // holidays are citywide — distance not applicable
      sourceUrl: null,
      impactLevel: h.impactLevel,
      apiSource: 'holiday_calendar',
    )).toList();
  }

  // ── Layer 2: Ticketmaster Discovery API v2 ────────────────────────────────

  Future<List<ImpactEvent>> _fetchTicketmaster({
    required double latitude,
    required double longitude,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async {
    // Capture gig coords for client-side Haversine filtering
    final double gigLat = latitude;
    final double gigLng = longitude;
    try {
      final uri = Uri.parse(_tmBaseUrl).replace(
        queryParameters: {
          'apikey': _apiKey,
          'geoPoint': '${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}',
          'radius': kImpactRadiusMiles.toStringAsFixed(0),
          'unit': 'miles',
          'startDateTime': '${_toIso8601Date(windowStart)}T00:00:00Z',
          'endDateTime': '${_toIso8601Date(windowEnd)}T23:59:59Z',
          'size': '20',
          'sort': 'distance,asc',
          'classificationName': 'Music,Sports,Arts & Theatre',
        },
      );

      log('⚡ [ImpactEventService] Ticketmaster GET (key redacted)');

      final response = await _httpClient
          .get(uri)
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 401) {
        log('⚡ [ImpactEventService] 401 — invalid API key.');
        return [];
      }
      if (response.statusCode == 429) {
        log('⚡ [ImpactEventService] 429 — rate limited.');
        return [];
      }
      if (response.statusCode != 200) {
        log('⚡ [ImpactEventService] HTTP ${response.statusCode}.');
        return [];
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final embedded = body['_embedded'] as Map<String, dynamic>?;
      if (embedded == null) return [];

      final rawEvents = embedded['events'] as List<dynamic>? ?? [];
      return rawEvents
          .map((e) => _normalizeTicketmasterEvent(
        e as Map<String, dynamic>,
        gigLat: gigLat,
        gigLng: gigLng,
      ))
          .whereType<ImpactEvent>()
          .toList();
    } catch (e) {
      log('⚡ [ImpactEventService] Ticketmaster fetch failed: $e');
      return [];
    }
  }

  ImpactEvent? _normalizeTicketmasterEvent(
      Map<String, dynamic> item, {
        required double gigLat,
        required double gigLng,
      }) {
    try {
      final name = item['name'] as String? ?? 'Unknown Event';
      final url = item['url'] as String?;

      // Date/time
      final datesBlock = item['dates'] as Map<String, dynamic>?;
      final startBlock = datesBlock?['start'] as Map<String, dynamic>?;
      final localDate = startBlock?['localDate'] as String?;
      final localTime = startBlock?['localTime'] as String?;
      final dateStr = localDate != null
          ? '$localDate${localTime != null ? 'T$localTime' : 'T00:00:00'}'
          : null;
      final eventDate =
      dateStr != null ? DateTime.tryParse(dateStr) ?? DateTime.now() : DateTime.now();

      // Classification
      final classifications = item['classifications'] as List<dynamic>?;
      final firstClass = classifications?.isNotEmpty == true
          ? classifications!.first as Map<String, dynamic>
          : null;
      final segment =
      (firstClass?['segment'] as Map<String, dynamic>?)?['name'] as String?;
      final genre =
      (firstClass?['genre'] as Map<String, dynamic>?)?['name'] as String?;
      final eventType = _deriveEventType(segment, genre, name);

      // Distance — compute via Haversine from event venue coords to gig coords.
      // Ticketmaster embeds venue location under _embedded.venues[0].location.
      double? distanceMiles;
      final embeddedVenues = item['_embedded']?['venues'] as List<dynamic>?;
      if (embeddedVenues != null && embeddedVenues.isNotEmpty) {
        final venueLocation =
        (embeddedVenues.first as Map<String, dynamic>)['location']
        as Map<String, dynamic>?;
        final evtLatStr = venueLocation?['latitude'] as String?;
        final evtLngStr = venueLocation?['longitude'] as String?;
        if (evtLatStr != null && evtLngStr != null) {
          final evtLat = double.tryParse(evtLatStr);
          final evtLng = double.tryParse(evtLngStr);
          if (evtLat != null && evtLng != null) {
            distanceMiles = _haversineDistanceMiles(gigLat, gigLng, evtLat, evtLng);
          }
        }
      }

      // Filter: drop events beyond the client-side radius
      if (distanceMiles != null && distanceMiles > kImpactFilterMiles) {
        return null;
      }

      return ImpactEvent(
        eventName: name,
        eventDate: eventDate,
        eventType: eventType,
        distanceMiles: distanceMiles,
        sourceUrl: url,
        impactLevel: _deriveImpactLevel(eventType, distanceMiles),
        apiSource: 'ticketmaster',
      );
    } catch (e) {
      log('⚡ [ImpactEventService] Normalize error: $e');
      return null;
    }
  }

  /// Haversine formula — returns distance in miles between two lat/lng points.
  /// Pure math, no API call, no packages.
  static double _haversineDistanceMiles(
      double lat1, double lng1,
      double lat2, double lng2,
      ) {
    const double earthRadiusMiles = 3958.8;
    final double dLat = _toRad(lat2 - lat1);
    final double dLng = _toRad(lng2 - lng1);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadiusMiles * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _toRad(double deg) => deg * math.pi / 180;

  String _deriveEventType(String? segment, String? genre, String name) {
    final seg = segment?.toLowerCase() ?? '';
    final lower = name.toLowerCase();
    if (seg == 'sports') return 'sporting';
    if (seg == 'music') return 'concert';
    if (lower.contains('festival') || lower.contains('fest')) return 'festival';
    if (lower.contains('bengals') || lower.contains('reds') ||
        lower.contains('fc cincinnati') || lower.contains('cyclones')) {
      return 'sporting';
    }
    return 'other';
  }

  String _deriveImpactLevel(String eventType, double? distanceMiles) {
    // All events are now within kImpactFilterMiles (5 miles) —
    // distance thresholds are meaningful and reliable.
    final double d = distanceMiles ?? 99.0;

    if (eventType == 'festival') {
      return d < 2.0 ? 'high' : 'medium';
    }
    if (eventType == 'holiday') return 'high';
    if (eventType == 'sporting') {
      if (d < 1.0) return 'high';
      if (d < 3.0) return 'medium';
      return 'low';
    }
    if (eventType == 'concert') {
      if (d < 0.5) return 'high';   // same block — direct competition
      if (d < 2.0) return 'medium';
      return 'low';
    }
    // other
    if (d < 1.0) return 'medium';
    return 'low';
  }

  // ── Deduplication & Sort ──────────────────────────────────────────────────

  List<ImpactEvent> _deduplicateAndSort(List<ImpactEvent> events) {
    final seen = <ImpactEvent>{};
    final deduped = <ImpactEvent>[];
    for (final e in events) {
      if (seen.add(e)) deduped.add(e);
    }
    final order = {'high': 0, 'medium': 1, 'low': 2};
    deduped.sort((a, b) {
      final lvl = (order[a.impactLevel] ?? 2).compareTo(order[b.impactLevel] ?? 2);
      return lvl != 0 ? lvl : a.eventDate.compareTo(b.eventDate);
    });
    return deduped;
  }

  // ── Cache ─────────────────────────────────────────────────────────────────

  String _cacheKeyFor(Gig gig) =>
      '$_cacheKeyPrefix${gig.id}_${_toIso8601Date(gig.dateTime)}';

  Future<List<ImpactEvent>?> _readCache(String cacheKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(cacheKey);
      if (raw == null) return null;
      final wrapper = jsonDecode(raw) as Map<String, dynamic>;
      final cachedAt = DateTime.tryParse(wrapper['cachedAt'] as String? ?? '');
      if (cachedAt == null ||
          DateTime.now().difference(cachedAt) > kImpactCacheTtl) {
        return null;
      }
      final list = wrapper['events'] as List<dynamic>;
      return list
          .map((e) => ImpactEvent.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      log('⚡ [ImpactEventService] Cache read error: $e');
      return null;
    }
  }

  Future<void> _writeCache(String cacheKey, List<ImpactEvent> events) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        cacheKey,
        jsonEncode({
          'cachedAt': DateTime.now().toIso8601String(),
          'events': events.map((e) => e.toJson()).toList(),
        }),
      );
    } catch (e) {
      log('⚡ [ImpactEventService] Cache write error: $e');
    }
  }

  Future<DateTime?> _readLastAssessed(String gigId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_lastAssessedKeyPrefix$gigId');
      return raw != null ? DateTime.tryParse(raw) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeLastAssessed(String gigId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          '$_lastAssessedKeyPrefix$gigId', DateTime.now().toIso8601String());
    } catch (_) {}
  }

  // ── Utilities ─────────────────────────────────────────────────────────────

  String _toIso8601Date(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  // ── Dev Mock Data ─────────────────────────────────────────────────────────
  //
  // Returned when no API key is set.
  // NOTE: The holiday layer always runs even in mock mode.
  // So on a real gig date near a US holiday, you will see holiday events
  // in the badge even before you have a Ticketmaster key.

  List<ImpactEvent> _mockEvents(DateTime gigDate) => [];
// List<ImpactEvent> _mockEvents(DateTime gigDate) => [
//   ImpactEvent(
//     eventName: 'Taste of Cincinnati',
//     eventDate: gigDate.subtract(const Duration(days: 2)),
//     eventType: 'festival',
//     distanceMiles: 2.1,
//     sourceUrl: 'https://tasteofcincinnati.com',
//     impactLevel: 'high',
//     apiSource: 'mock',
//   ),
//   ImpactEvent(
//     eventName: 'FC Cincinnati vs Columbus Crew',
//     eventDate: gigDate.subtract(const Duration(days: 1)),
//     eventType: 'sporting',
//     distanceMiles: 3.8,
//     sourceUrl: 'https://fccincinnati.com',
//     impactLevel: 'medium',
//     apiSource: 'mock',
//   ),
// ];
}