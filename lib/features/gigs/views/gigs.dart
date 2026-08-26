// lib/gigs.dart
import 'dart:async'; // unawaited() — fire-and-forget network attendance mirror
import 'dart:collection'; // For LinkedHashMap (used by TableCalendar for events)
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart'; // Import TableCalendar
import 'package:the_money_gigs/global_refresh_notifier.dart'; // Import the notifier
import 'package:the_money_gigs/active_tab_notifier.dart'; // Gates impact assessment to when My Gigs is actually visible
import 'package:the_money_gigs/core/models/enums.dart'; // <<<--- IMPORT THE SHARED ENUMS
import 'package:the_money_gigs/core/services/notification_service.dart';

// Import your models
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';
import 'package:the_money_gigs/features/gigs/models/monthly_separator.dart';
import 'package:the_money_gigs/features/gigs/widgets/monthly_separator_tile.dart';
import 'package:the_money_gigs/features/gigs/widgets/gig_list_tile.dart';

import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';
import 'package:the_money_gigs/features/map_venues/models/jam_session_model.dart';
import 'package:the_money_gigs/features/gigs/widgets/booking_dialog.dart';
import 'package:the_money_gigs/features/map_venues/widgets/jam_open_mic_dialog.dart';
import 'package:the_money_gigs/features/notes/views/notes_page.dart';
import 'package:the_money_gigs/features/map_venues/widgets/venue_details_page.dart';
import 'package:the_money_gigs/features/profile/views/profile.dart';

// <<< --- REFACTORING: ADD IMPORT FOR THE NEW VENUES TAB WIDGET --- >>>
import 'package:the_money_gigs/features/venues/views/venues_list_tab.dart';
import 'package:the_money_gigs/features/gigs/widgets/gig_export_dialog.dart';
import 'package:the_money_gigs/features/gigs/widgets/gig_insights_dialog.dart';
import 'package:the_money_gigs/features/checklist/gig_checklist_page.dart';

// Band/Project Expansion v3.0.0 — Sprint Task 4
import 'package:the_money_gigs/core/services/auth_service.dart';
import 'package:the_money_gigs/features/bands/models/band_model.dart';
import 'package:the_money_gigs/features/bands/repositories/band_repository.dart';
import 'package:the_money_gigs/features/gigs/repositories/jam_attendance_repository.dart';
import 'package:the_money_gigs/features/bands/views/my_bands_tab.dart';
import 'package:the_money_gigs/features/bands/views/create_band_page.dart';
import 'package:the_money_gigs/features/bands/views/band_detail_page.dart';

import '../../app_demo/providers/demo_provider.dart';
import 'package:the_money_gigs/features/app_demo/widgets/simple_demo_overlay.dart';
import 'package:the_money_gigs/core/utils/logger.dart';
import 'package:the_money_gigs/core/services/impact_event_service.dart';
import 'package:the_money_gigs/features/gigs/models/impact_event.dart';

enum GigsViewType { list, calendar }

class GigsPage extends StatefulWidget {
  const GigsPage({super.key});

  @override
  State<GigsPage> createState() => _GigsPageState();
}

class _GigsPageState extends State<GigsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late ScrollController _scrollController;
  late DemoProvider _demoProvider;

  List<Gig> _allGigs =
  []; // Raw data from SharedPreferences, including recurring templates
  List<Gig> _displayedGigs =
  []; // Generated, displayable occurrences for the list view
  DateTime _gigListEndDate = DateTime.now().add(const Duration(days: 90));
  bool _isMoreGigsLoading = false;

  // Bottom-nav index for this tab (see main.dart's IndexedStack + activeTabIndexNotifier).
  static const int _kMyGigsTabIndex = 2;
  // Ticketmaster impact assessment only looks a month out by default, even
  // though the gig list itself is generated up to 90 days ahead. It only
  // reaches further once the user actually scrolls to load more gigs.
  static const int _kInitialImpactLookAheadDays = 30;

  Map<DateTime, List<Gig>> _calendarEvents = {};

  List<StoredLocation> _allKnownVenues = [];
  List<StoredLocation> _displayableVenues = [];

  bool _isLoadingGigs = true;
  bool _isLoadingVenues = true;

  // ── Band/Project Expansion v3.0.0 — Sprint Task 4 ─────────────────────────
  // Same 'is_connected_to_network' key used in venue_details_page.dart,
  // map.dart, and connect_widget.dart — this is the established standalone-
  // vs-network flag, not a new one.
  static const String _isConnectedKey = 'is_connected_to_network';
  final BandRepository _bandRepository = BandRepository();
  final JamAttendanceRepository _jamAttendanceRepository =
      JamAttendanceRepository();
  List<BandProject> _allBands = [];
  bool _isLoadingBands = true;
  bool _isConnectedToNetwork = false;

  GigsViewType _gigsViewType = GigsViewType.list;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  List<Gig> _selectedDayGigs = [];
  static const String _keyGigsList = 'gigs_list';
  static const String _keySavedLocations = 'saved_locations';

  final GlobalKey _demoGigTileKey = GlobalKey();
  OverlayEntry? _overlayEntry; // 🎯 ADD THIS VARIABLE

  late final ImpactEventService _impactEventService;

  //   // gigId → list of impact events; populated after gigs load
  Map<String, List<ImpactEvent>> _impactEventsByGigId = {};

  @override
  void initState() {
    super.initState();
    _impactEventService = ImpactEventService(
      onStatusUpdate: (ImpactStatus status) {
        if (!mounted) return;
        final message = status.message;
        final isError = status.type == ImpactStatusType.failure;
        final isLoading = status.type == ImpactStatusType.loading;

        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                if (isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else
                  Icon(
                    isError ? Icons.error : Icons.check_circle,
                    color: isError ? Colors.redAccent : Colors.greenAccent,
                    size: 20,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            duration: Duration(seconds: isLoading ? 2 : 3),
            backgroundColor: isError ? Colors.red.shade900 : null,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 70, left: 20, right: 20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      },
    );
    _tabController = TabController(length: 3, vsync: this);
    _scrollController = ScrollController()
      ..addListener(_scrollListener); // Initialize scroll controller
    _selectedDay = _focusedDay;
    _tabController.addListener(_handleTabSelection);
    _loadAllDataForGigsPage();
    globalRefreshNotifier.addListener(_handleGlobalRefresh);
    // My Gigs is bottom-nav index 2. All four tabs are built eagerly at app
    // launch (kept alive in an IndexedStack), so this widget's initState
    // fires even when a different tab is on screen. Only run the Ticketmaster
    // impact assessment once this tab is actually visible.
    activeTabIndexNotifier.addListener(_handleActiveTabChanged);

    // 🎬 Listen to DemoProvider so we react when the step changes to gigListView.
    _demoProvider = Provider.of<DemoProvider>(context, listen: false);
    _demoProvider.addListener(_handleDemoStepChange);
    log(
      '🎬 [GigsPage] initState: DemoProvider listener registered. Current step = ${_demoProvider.currentStep}',
    );
  }

  @override
  void dispose() {
    _removeOverlay();
    _demoProvider.removeListener(_handleDemoStepChange);

    globalRefreshNotifier.removeListener(_handleGlobalRefresh);
    activeTabIndexNotifier.removeListener(_handleActiveTabChanged);
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    _scrollController.dispose(); // Dispose scroll controller

    super.dispose();
  }

  void _showGigListOverlay(DemoProvider demoProvider) {
    log('🎬 [GigsPage] _showGigListOverlay: ENTERED');
    _removeOverlay();

    final OverlayState? rootOverlay = Navigator.of(context).overlay;
    if (rootOverlay == null) {
      log(
        '🎬 [GigsPage] _showGigListOverlay: ❌ rootOverlay is null — cannot insert.',
      );
      return;
    }

    _overlayEntry = OverlayEntry(
      builder: (context) {
        log(
          '🎬 [GigsPage] OverlayEntry builder called — SimpleDemoOverlay is being built',
        );
        return SimpleDemoOverlay(
          title: "Your Upcoming Gigs",
          message:
          "Each card is a gig where you can edit details, schedule recurring dates, or view notes with that icon on the right. Click Next.",
          highlightKeys: [_demoGigTileKey],
          showNextButton: true,
          // 🎯 ADD THIS: Remove the overlay and end the demo when "Exit" is clicked.
          onExit: () {
            _removeOverlay();
            demoProvider.endDemo();
          },
          onNext: () {
            _removeOverlay();
            demoProvider.nextStep();
          },
        );
      },
    );
    rootOverlay.insert(_overlayEntry!);
    log(
      '🎬 [GigsPage] _showGigListOverlay: ✅ Overlay inserted into rootOverlay',
    );
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // 🎬 Called every time DemoProvider calls notifyListeners (every nextStep / skipToStep).
  void _handleDemoStepChange() {
    if (!context.mounted) {
      log('🎬 [GigsPage] _handleDemoStepChange: not mounted, ignoring.');
      return;
    }
    final demoProvider = Provider.of<DemoProvider>(context, listen: false);
    log(
      '🎬 [GigsPage] _handleDemoStepChange: FIRED. currentStep = ${demoProvider.currentStep}, isDemoActive = ${demoProvider.isDemoModeActive}',
    );

    if (demoProvider.currentStep == DemoStep.gigListView) {
      log(
        '🎬 [GigsPage] _handleDemoStepChange: ✅ Step IS gigListView — calling _tryShowGigListDemoOverlay',
      );
      _tryShowGigListDemoOverlay(demoProvider);
    } else {
      log(
        '🎬 [GigsPage] _handleDemoStepChange: Step is NOT gigListView, skipping.',
      );
    }
  }

  Future<void> _tryShowGigListDemoOverlay(DemoProvider demoProvider) async {
    log(
      '🎬 [GigsPage] _tryShowGigListDemoOverlay: scheduling post-frame callback',
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!context.mounted) {
        log(
          '🎬 [GigsPage] _tryShowGigListDemoOverlay (post-frame): not mounted, aborting.',
        );
        return;
      }

      // Check whether there are any real gigs to highlight at all.
      final hasRealGigs = _displayedGigs.any((g) => !g.isJamOpenMic);
      log(
        '🎬 [GigsPage] _tryShowGigListDemoOverlay (post-frame): _displayedGigs.length = ${_displayedGigs.length}, hasRealGigs = $hasRealGigs',
      );

      if (!hasRealGigs) {
        log(
          '🎬 [GigsPage] _tryShowGigListDemoOverlay (post-frame): ❌ No real gigs in the list — nothing to highlight.',
        );
        return;
      }

      final tileContext = _demoGigTileKey.currentContext;
      log(
        '🎬 [GigsPage] _tryShowGigListDemoOverlay (post-frame): _demoGigTileKey.currentContext = $tileContext',
      );

      if (tileContext == null) {
        log(
          '🎬 [GigsPage] _tryShowGigListDemoOverlay (post-frame): ❌ Key context is null — first gig tile not yet built by ListView. Aborting.',
        );
        return;
      }

      log(
        '🎬 [GigsPage] _tryShowGigListDemoOverlay (post-frame): ✅ tileContext is live, scrolling into view...',
      );

      await Scrollable.ensureVisible(
        tileContext,
        duration: const Duration(milliseconds: 400),
        alignment: 0.5,
      );

      await Future.delayed(const Duration(milliseconds: 150));

      if (!context.mounted) {
        log(
          '🎬 [GigsPage] _tryShowGigListDemoOverlay (post-frame): ❌ no longer mounted after scroll, aborting.',
        );
        return;
      }

      log(
        '🎬 [GigsPage] _tryShowGigListDemoOverlay (post-frame): calling _showGigListOverlay',
      );
      _showGigListOverlay(demoProvider);
    });
  }

  void _scrollListener() {
    // Load more when user is 200 pixels from the bottom of the list
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200 &&
        !_isMoreGigsLoading) {
      _loadMoreGigs();
    }
  }

  Future<void> _handleRecurringGigDeletion(
      Gig gigInstance,
      RecurringCancelChoice choice,
      ) async {
    if (choice == RecurringCancelChoice.doNothing) return;

    final String baseGigId = gigInstance.getBaseId();
    final int index = _allGigs.indexWhere((g) => g.id == baseGigId);

    if (index == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Error: Could not find the original recurring gig to modify.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Gig baseGig = _allGigs[index];
    String message = '';

    if (choice == RecurringCancelChoice.allFutureInstances) {
      DateTime newEndDate = gigInstance.dateTime.subtract(
        const Duration(days: 1),
      );
      if (newEndDate.isBefore(baseGig.dateTime)) {
        _allGigs.removeAt(index);
        message =
        'The entire recurring series for "${baseGig.venueName}" has been cancelled.';
      } else {
        _allGigs[index] = baseGig.copyWith(recurrenceEndDate: newEndDate);
        message =
        'The recurring gig for "${gigInstance.venueName}" on and after ${DateFormat.yMMMEd().format(gigInstance.dateTime)} has been cancelled.';
      }
    } else if (choice == RecurringCancelChoice.thisInstanceOnly) {
      List<DateTime> updatedExceptions = List.from(
        baseGig.recurrenceExceptions ?? [],
      );
      DateTime exceptionDate = DateTime.utc(
        gigInstance.dateTime.year,
        gigInstance.dateTime.month,
        gigInstance.dateTime.day,
      );

      if (!updatedExceptions.any((d) => isSameDay(d, exceptionDate))) {
        updatedExceptions.add(exceptionDate);
      }

      _allGigs[index] = baseGig.copyWith(
        recurrenceExceptions: updatedExceptions,
      );
      message =
      'The gig for "${gigInstance.venueName}" on ${DateFormat.yMMMEd().format(gigInstance.dateTime)} has been cancelled.';
    }

    // --- Save the changes and refresh the UI ---
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      await prefs.setString(_keyGigsList, Gig.encode(_allGigs));
      if (!mounted) return;

      final notificationService = NotificationService();
      await notificationService.init();
      if (!mounted) return;
      await notificationService.updateAllGigNotifications();
      if (!mounted) return;

      globalRefreshNotifier.notify();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.orange),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating recurring gig: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _handleGlobalRefresh() {
    if (!mounted) return;
    // Reset lazy-loading date range on global refresh
    _gigListEndDate = DateTime.now().add(const Duration(days: 90));
    _loadAllDataForGigsPage();
  }

  Future<void> _loadAllDataForGigsPage() async {
    await Future.wait([_loadVenues(), _loadGigs(), _loadBands()]);
    if (!mounted) return;
    for (final gig in _allGigs) {
      log('🎸 [GigsPage] Loaded gig: id=${gig.id} venue="${gig.venueName}"...');
    }
    // Local data (gigs/venues/bands from SharedPreferences) is cheap and can
    // load regardless of tab visibility. The Ticketmaster-backed impact
    // assessment is not — only fire it if My Gigs is the tab actually on
    // screen right now. If it's not, _handleActiveTabChanged() will run it
    // the moment the user switches to this tab.
    if (activeTabIndexNotifier.value == _kMyGigsTabIndex) {
      _runImpactAssessment(lookAheadDays: _kInitialImpactLookAheadDays);
    }
  }

  // Fires once when the user actually navigates to My Gigs. Cheap to call
  // repeatedly — ImpactEventService caches per-gig results for 24h and skips
  // anything still fresh, so re-visiting the tab doesn't re-hit Ticketmaster.
  void _handleActiveTabChanged() {
    if (!mounted) return;
    if (activeTabIndexNotifier.value == _kMyGigsTabIndex) {
      _runImpactAssessment(lookAheadDays: _kInitialImpactLookAheadDays);
    }
  }

  Future<void> _runImpactAssessment({int? lookAheadDays}) async {
    // Default (no override) mirrors the old behavior of reaching as far as
    // the gig list has been scrolled — used by _loadMoreGigs() below.
    final int lookahead =
        lookAheadDays ?? _gigListEndDate.difference(DateTime.now()).inDays + 1;
    final results = await _impactEventService.reassessUpcomingGigs(
      upcomingGigs: _displayedGigs,
      lookAheadDays: lookahead,
    );
    if (!mounted) return;
    if (results.isNotEmpty) {
      setState(() {
        _impactEventsByGigId = results;
        // Attach events back onto displayedGigs so the tile badge renders.
        _displayedGigs = _displayedGigs.map((gig) {
          final events = results[gig.id];
          if (events == null) return gig;
          return gig.copyWith(impactEvents: events);
        }).toList();
      });
    }
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging ||
        (_tabController.animation != null &&
            _tabController.animation!.value !=
                _tabController.index.toDouble())) {
      return;
    }
  }

  Future<void> _loadGigs() async {
    if (!mounted) return;
    setState(() {
      _isLoadingGigs = true;
    });
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    // --- ALWAYS load from the original, correct key ---
    final String? gigsJsonString = prefs.getString(_keyGigsList);

    List<Gig> loadedGigs = [];
    if (gigsJsonString != null && gigsJsonString.isNotEmpty) {
      try {
        loadedGigs = Gig.decode(gigsJsonString);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading gigs: $e')));
      }
    }

    if (!mounted) return;
    _allGigs = loadedGigs;
    _generateAndSetDisplayedGigs(); // This will handle generation, sorting, and setting state
    setState(() {
      _isLoadingGigs = false;
    });
  }

  Future<void> _loadMoreGigs() async {
    if (!context.mounted || _isMoreGigsLoading) return;

    setState(() {
      _isMoreGigsLoading = true;
    });

    await Future.delayed(
      const Duration(milliseconds: 500),
    ); // Simulate network latency

    if (!mounted) return;

    // Extend the date range and regenerate the list
    _gigListEndDate = _gigListEndDate.add(const Duration(days: 14));
    _generateAndSetDisplayedGigs();

    // Assess impact events for gigs now visible in the extended window.
    _runImpactAssessment();

    if (!mounted) return;
    setState(() {
      _isMoreGigsLoading = false;
    });
  }

  void _generateAndSetDisplayedGigs() {
    List<Gig> allOccurrences = [];
    DateTime now = DateTime.now();
    DateTime todayStart = DateTime(now.year, now.month, now.day);

    // 1. Process all gigs from storage
    for (var gig in _allGigs) {
      if (!gig.isRecurring) {
        // One-off gigs or already "materialized" instances
        allOccurrences.add(gig);
      } else {
        // RECURRING TEMPLATE:
        // Instead of adding the template raw, we generate its
        // first instance so the ID matches the 'baseId_date' format.
        _addOccurrenceIfApplicable(allOccurrences, gig, gig.dateTime);

        // Generate future instances
        allOccurrences.addAll(_generateOccurrencesForGig(gig, _gigListEndDate));
      }
    }

    // 2. Add Jam/Open Mic sessions
    allOccurrences.addAll(_generateJamOpenMicGigs(_gigListEndDate));

    // 3. Map and process display logic (Venue names, Band names)
    List<Gig> processedGigs = allOccurrences.map((gig) {
      final sourceVenue = _allKnownVenues.firstWhere(
            (v) => v.placeId == gig.placeId,
        orElse: () => StoredLocation(
          placeId: '',
          name: gig.venueName,
          address: '',
          coordinates: const LatLng(0, 0),
        ),
      );

      String processedVenueName = gig.venueName;
      if (sourceVenue.isPrivate && !gig.venueName.startsWith('[PRIVATE]')) {
        processedVenueName = '[PRIVATE] $processedVenueName';
      }
      if (gig.isJamOpenMic && !gig.venueName.contains('[JAM]')) {
        processedVenueName = '[JAM] $processedVenueName';
        if (gig.notes != null && gig.notes!.isNotEmpty) {
          processedVenueName += " (${gig.notes})";
        }
      }

      return gig.copyWith(venueName: processedVenueName);
    }).toList();

    // 4. De-duplicate based on ID
    // CRITICAL: Standalone/Materialized instances in _allGigs will have
    // the same ID format as virtual ones (baseId_YYYYMMDD).
    // We want the PHYSICAL ones (the ones in the list first) to "win"
    // over the VIRTUAL generated ones.
    final Map<String, Gig> uniqueGigs = {};
    for (var gig in processedGigs) {
      // (or allCalendarGigs)
      if (!uniqueGigs.containsKey(gig.id)) {
        uniqueGigs[gig.id] = gig;
      } else {
        // Only overwrite if incoming has real data the existing one lacks.
        // This ensures materialized instances (real data) always beat virtual ones.
        final existing = uniqueGigs[gig.id]!;
        final incomingHasData =
            gig.retrospectiveCompleted == true ||
                (gig.notes?.isNotEmpty ?? false);
        final existingLacksData =
            existing.retrospectiveCompleted != true &&
                (existing.notes?.isEmpty ?? true);
        if (incomingHasData && existingLacksData) {
          uniqueGigs[gig.id] = gig;
        }
      }
    }

    // 5. Filter for Upcoming list (Gigs that haven't ended yet)
    List<Gig> sortedGigs = uniqueGigs.values.where((gig) {
      DateTime gigEndTime = gig.dateTime.add(
        Duration(minutes: (gig.gigLengthHours * 60).toInt()),
      );
      return !gigEndTime.isBefore(todayStart);
    }).toList();

    sortedGigs.sort((a, b) => a.dateTime.compareTo(b.dateTime));

    if (!mounted) return;
    setState(() {
      _displayedGigs = sortedGigs;
    });
    _prepareCalendarEvents();
    _onDaySelected(_selectedDay ?? _focusedDay, _focusedDay);
  }

  List<Gig> _generateJamOpenMicGigs(DateTime rangeEndDate) {
    List<Gig> jamGigs = [];
    DateTime today = DateTime.now(); // Define 'today' here

    for (var venue in _allKnownVenues) {
      if (venue.isArchived || venue.isMuted) continue;

      for (var session in venue.jamSessions) {
        if (!session.showInGigsList) continue;

        DateTime sessionStartDateTime = DateTime(
          today.year,
          today.month,
          today.day,
          session.time.hour,
          session.time.minute,
        );

        // Create a temporary "Gig" template to use the common generator
        final baseJamGig = Gig(
          id: 'jam_${venue.placeId}_${session.id}',
          // Base ID for the series
          venueName: venue.name,
          latitude: venue.coordinates.latitude,
          longitude: venue.coordinates.longitude,
          address: venue.address,
          placeId: venue.placeId,
          dateTime: sessionStartDateTime,
          // The time of the session is the base time
          pay: 0,
          gigLengthHours: 2,
          driveSetupTimeHours: 0,
          rehearsalLengthHours: 0,
          isJamOpenMic: true,
          notes: session.style,
          // Use notes to pass the style for display
          isRecurring: true,
          recurrenceFrequency: session.frequency,
          recurrenceDay: session.day,
          recurrenceNthValue: session.nthValue,
          recurrenceEndDate: null, // Jams repeat indefinitely within the range
        );

        jamGigs.addAll(_generateOccurrencesForGig(baseJamGig, rangeEndDate));
      }
    }
    return jamGigs;
  }

  List<Gig> _generateOccurrencesForGig(Gig baseGig, DateTime rangeEndDate) {
    List<Gig> occurrences = [];
    if (!baseGig.isRecurring ||
        baseGig.recurrenceFrequency == null ||
        baseGig.recurrenceDay == null) {
      return occurrences;
    }

    //log("\n--- 2. Generating Occurrences for: ${baseGig.venueName} (Base Date: ${baseGig.dateTime}) ---");

    DateTime recurrenceSeriesStart = baseGig.dateTime;

    // The calculation should not exceed the gig's own end date, if it exists.
    DateTime calculationRangeEnd =
    baseGig.recurrenceEndDate != null &&
        baseGig.recurrenceEndDate!.isBefore(rangeEndDate)
        ? baseGig.recurrenceEndDate!
        : rangeEndDate;

    int targetWeekday = baseGig.recurrenceDay!.index + 1;

    // Start the iterator from the day AFTER the base gig. This prevents duplicating the original instance.
    DateTime iteratorDate = DateTime(
      recurrenceSeriesStart.year,
      recurrenceSeriesStart.month,
      recurrenceSeriesStart.day,
    ).add(const Duration(days: 1));

    // --- START OF DEBUGGING PRINT ---
    log(
      "   - Calculation Range: ${DateFormat('yyyy-MM-dd').format(iteratorDate)} to ${DateFormat('yyyy-MM-dd').format(calculationRangeEnd)}",
    );
    // --- END OF DEBUGGING PRINT ---

    switch (baseGig.recurrenceFrequency) {
      case JamFrequencyType.weekly:
      // Find the first valid occurrence on or after the iterator date.
        DateTime testDate = _findNextDayOfWeek(
          iteratorDate,
          targetWeekday,
          sameDayOk: true,
        );
        while (testDate.isBefore(calculationRangeEnd) ||
            isSameDay(testDate, calculationRangeEnd)) {
          // --- START OF DEBUGGING PRINT ---
          //log("     - [Weekly] Found potential date: ${DateFormat('yyyy-MM-dd').format(testDate)}");
          // --- END OF DEBUGGING PRINT ---
          _addOccurrenceIfApplicable(occurrences, baseGig, testDate);
          testDate = testDate.add(
            const Duration(days: 7),
          ); // Simply jump to the next week.
        }
        break;

      case JamFrequencyType.biWeekly:
      // The anchor is always the date of the original event.
        DateTime cycleAnchorDate = _findNextDayOfWeek(
          baseGig.dateTime,
          targetWeekday,
          sameDayOk: true,
        );
        DateTime testDate = _findNextDayOfWeek(
          iteratorDate,
          targetWeekday,
          sameDayOk: true,
        );

        while (testDate.isBefore(calculationRangeEnd) ||
            isSameDay(testDate, calculationRangeEnd)) {
          int weeksDifference =
              testDate.difference(cycleAnchorDate).inDays ~/ 7;
          // Generate an occurrence only for even-numbered week differences (2, 4, 6, etc.)
          if (weeksDifference > 0 && weeksDifference % 2 == 0) {
            _addOccurrenceIfApplicable(occurrences, baseGig, testDate);
          }
          testDate = testDate.add(
            const Duration(days: 7),
          ); // Always check the next week
        }
        break;

      case JamFrequencyType.customNthDay:
        if (baseGig.recurrenceNthValue != null &&
            baseGig.recurrenceNthValue! > 0) {
          int nth = baseGig.recurrenceNthValue!;
          DateTime testDate = _findNextDayOfWeek(
            iteratorDate,
            targetWeekday,
            sameDayOk: true,
          );
          while (testDate.isBefore(calculationRangeEnd) ||
              isSameDay(testDate, calculationRangeEnd)) {
            _addOccurrenceIfApplicable(occurrences, baseGig, testDate);
            testDate = testDate.add(Duration(days: 7 * nth)); // Jump by N weeks
          }
        }
        break;

      case JamFrequencyType.monthlySameDay:
        if (baseGig.recurrenceNthValue != null &&
            baseGig.recurrenceNthValue! > 0) {
          int nthOccurrence = baseGig.recurrenceNthValue!;
          // Start iterating from the month of the start date
          DateTime monthIterator = DateTime(
            iteratorDate.year,
            iteratorDate.month,
            1,
          );

          while (monthIterator.isBefore(calculationRangeEnd) ||
              (monthIterator.year == calculationRangeEnd.year &&
                  monthIterator.month == calculationRangeEnd.month)) {
            DateTime? nthDayInMonth = _findNthSpecificWeekdayOfMonth(
              monthIterator.year,
              monthIterator.month,
              targetWeekday,
              nthOccurrence,
            );
            // Ensure the found day is within the allowed range
            if (nthDayInMonth != null &&
                !nthDayInMonth.isBefore(iteratorDate) &&
                !nthDayInMonth.isAfter(calculationRangeEnd)) {
              _addOccurrenceIfApplicable(occurrences, baseGig, nthDayInMonth);
            }
            // Move to the next month
            monthIterator = DateTime(
              monthIterator.year,
              monthIterator.month + 1,
              1,
            );
          }
        }
        break;

      default:
        break;
    }
    return occurrences;
  }

  void _addOccurrenceIfApplicable(
      List<Gig> occurrences,
      Gig baseGig,
      DateTime dateOfOccurrence,
      ) {
    if (baseGig.recurrenceExceptions != null &&
        baseGig.recurrenceExceptions!.any(
              (exceptionDate) => isSameDay(exceptionDate, dateOfOccurrence),
        )) {
      return;
    }

    DateTime gigDateTime = DateTime(
      dateOfOccurrence.year,
      dateOfOccurrence.month,
      dateOfOccurrence.day,
      baseGig.dateTime.hour,
      baseGig.dateTime.minute,
    );

    final String uniqueId =
        '${baseGig.id}_${DateFormat('yyyyMMdd').format(gigDateTime)}';

    // ✅ USE FULL CONSTRUCTOR — copyWith cannot null out nullable fields
    occurrences.add(
      Gig(
        id: uniqueId,
        venueName: baseGig.venueName,
        bandName: baseGig.bandName,
        latitude: baseGig.latitude,
        longitude: baseGig.longitude,
        address: baseGig.address,
        placeId: baseGig.placeId,
        dateTime: gigDateTime,
        pay: baseGig.pay,
        otherExpenses: baseGig.otherExpenses,
        tipsAmount: null,
        // ✅ Reset — never inherit from template
        gigLengthHours: baseGig.gigLengthHours,
        driveSetupTimeHours: baseGig.driveSetupTimeHours,
        rehearsalLengthHours: baseGig.rehearsalLengthHours,
        isJamOpenMic: baseGig.isJamOpenMic,
        notes: null,
        // ✅ Reset — notes are per-instance
        notesUrl: baseGig.notesUrl,
        setlistId: baseGig.setlistId,
        isRecurring: false,
        isFromRecurring: true,
        recurrenceFrequency: baseGig.recurrenceFrequency,
        recurrenceDay: baseGig.recurrenceDay,
        recurrenceNthValue: baseGig.recurrenceNthValue,
        recurrenceEndDate: baseGig.recurrenceEndDate,
        recurrenceExceptions: [],
        gigRatings: null,
        // ✅ THE CRITICAL FIX
        retrospectiveCompleted: null, // ✅ THE CRITICAL FIX
      ),
    );
  }

  void _prepareCalendarEvents() {
    final events = LinkedHashMap<DateTime, List<Gig>>(
      equals: isSameDay,
      hashCode: getHashCode,
    );
    DateTime today = DateTime.now();
    DateTime calendarRangeEnd = DateTime(
      today.year + 5,
      today.month,
      today.day,
    );

    List<Gig> allCalendarGigs = [];
    for (var gig in _allGigs) {
      if (!gig.isRecurring) {
        allCalendarGigs.add(gig);
      } else {
        // Virtualize the base date for the calendar
        _addOccurrenceIfApplicable(allCalendarGigs, gig, gig.dateTime);
        allCalendarGigs.addAll(
          _generateOccurrencesForGig(gig, calendarRangeEnd),
        );
      }
    }
    allCalendarGigs.addAll(_generateJamOpenMicGigs(calendarRangeEnd));

    // De-duplicate
    final Map<String, Gig> uniqueGigs = {};
    for (var gig in allCalendarGigs) {
      if (!uniqueGigs.containsKey(gig.id)) {
        uniqueGigs[gig.id] = gig;
      } else {
        // Only overwrite if incoming has real data the existing one lacks.
        // This ensures materialized instances (real data) always beat virtual ones.
        final existing = uniqueGigs[gig.id]!;
        final incomingHasData =
            gig.retrospectiveCompleted == true ||
                (gig.notes?.isNotEmpty ?? false);
        final existingLacksData =
            existing.retrospectiveCompleted != true &&
                (existing.notes?.isEmpty ?? true);
        if (incomingHasData && existingLacksData) {
          uniqueGigs[gig.id] = gig;
        }
      }
    }

    for (var gig in uniqueGigs.values) {
      final date = DateTime.utc(
        gig.dateTime.year,
        gig.dateTime.month,
        gig.dateTime.day,
      );
      events.putIfAbsent(date, () => []).add(gig);
    }

    if (!mounted) return;
    setState(() {
      _calendarEvents = events;
    });
  }

  DateTime _findNextDayOfWeek(
      DateTime startDate,
      int targetWeekday, {
        bool sameDayOk = false,
      }) {
    DateTime date = DateTime(startDate.year, startDate.month, startDate.day);
    if (sameDayOk && date.weekday == targetWeekday) {
      return date;
    }
    // If not sameDayOk, or if today doesn't match, start search from tomorrow
    date = date.add(const Duration(days: 1));
    while (date.weekday != targetWeekday) {
      date = date.add(const Duration(days: 1));
    }
    return date;
  }

  DateTime? _findNthSpecificWeekdayOfMonth(
      int year,
      int month,
      int targetWeekday,
      int nth,
      ) {
    if (nth < 1 || nth > 5) return null;
    int occurrences = 0;
    int daysInMonth = DateTime(year, month + 1, 0).day;
    for (int day = 1; day <= daysInMonth; day++) {
      DateTime currentDate = DateTime(year, month, day);
      if (currentDate.weekday == targetWeekday) {
        occurrences++;
        if (occurrences == nth) {
          return currentDate;
        }
      }
    }
    return null;
  }

  int getHashCode(DateTime key) =>
      key.day * 1000000 + key.month * 10000 + key.year;

  List<Gig> _getEventsForDay(DateTime day) {
    final normalizedDay = DateTime.utc(day.year, day.month, day.day);
    return _calendarEvents[normalizedDay] ?? [];
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    final normalizedNewSelectedDay = DateTime.utc(
      selectedDay.year,
      selectedDay.month,
      selectedDay.day,
    );
    final normalizedCurrentSelectedDay = _selectedDay != null
        ? DateTime.utc(
      _selectedDay!.year,
      _selectedDay!.month,
      _selectedDay!.day,
    )
        : null;
    if (!isSameDay(normalizedCurrentSelectedDay, normalizedNewSelectedDay)) {
      if (!mounted) return;
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
        _selectedDayGigs = _getEventsForDay(selectedDay);
      });
    } else {
      if (!mounted) return;
      setState(() {
        _selectedDayGigs = _getEventsForDay(selectedDay);
      });
    }
  }

  Future<void> _loadVenues() async {
    if (!mounted) return;
    setState(() {
      _isLoadingVenues = true;
    });
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final List<String>? venuesJson = prefs.getStringList(_keySavedLocations);
    List<StoredLocation> loadedFromPrefs = [];
    if (venuesJson != null) {
      try {
        loadedFromPrefs = venuesJson
            .map((jsonString) {
          try {
            return StoredLocation.fromJson(jsonDecode(jsonString));
          } catch (e) {
            log("Error decoding a single venue: $jsonString. Error: $e");
            return null;
          }
        })
            .whereType<StoredLocation>()
            .toList();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading some venues: $e')),
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _allKnownVenues = loadedFromPrefs;
      _displayableVenues = _allKnownVenues
          .where((venue) => !venue.isArchived)
          .toList();
      _isLoadingVenues = false;
    });
  }

  // ── Band/Project Expansion v3.0.0 — Sprint Task 4 ─────────────────────────

  Future<void> _loadBands() async {
    if (!mounted) return;
    setState(() {
      _isLoadingBands = true;
    });

    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final bool isConnected = prefs.getBool(_isConnectedKey) ?? false;

    if (!mounted) return;
    setState(() {
      _isConnectedToNetwork = isConnected;
    });

    // Standalone users have no backend connection at all — bands require
    // Firestore, so there's nothing to fetch. Show the gate instead.
    if (!isConnected) {
      if (!mounted) return;
      setState(() {
        _allBands = [];
        _isLoadingBands = false;
      });
      return;
    }

    final authService = AuthService();
    if (!authService.isSignedIn) {
      if (!mounted) return;
      setState(() {
        _allBands = [];
        _isLoadingBands = false;
      });
      return;
    }

    try {
      final bands = await _bandRepository.getBandsForUser(authService.currentUserId);
      if (!mounted) return;
      setState(() {
        _allBands = bands;
        _isLoadingBands = false;
      });
    } catch (e) {
      log('❌ Error loading bands: $e');
      if (!mounted) return;
      setState(() {
        _allBands = [];
        _isLoadingBands = false;
      });
    }
  }

  Future<void> _openCreateBandFlow() async {
    final authService = AuthService();
    if (!authService.isSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Sign in to the network to create a band.')),
      );
      return;
    }

    final result = await Navigator.of(context).push<BandProject>(
      MaterialPageRoute(
        builder: (_) => CreateBandPage(leaderId: authService.currentUserId),
      ),
    );

    if (!mounted) return;
    if (result != null) {
      await _loadBands();
    }
  }

  Future<void> _openBandDetail(BandProject band) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BandDetailPage(
          initialBand: band,
          currentUserId: AuthService().currentUserId,
        ),
      ),
    );
    if (!mounted) return;
    // Membership/rename changes made on Band Detail should reflect in the
    // list immediately on return, not just next global refresh.
    await _loadBands();
  }

  Future<void> _launchBookingDialogForGig(Gig gigToEdit) async {
    String originalGigId = gigToEdit.getBaseId();

    Gig? originalGig;
    if (!gigToEdit.isJamOpenMic) {
      originalGig = _allGigs.firstWhere(
            (g) => g.id == originalGigId,
        orElse: () => gigToEdit,
      );
    } else {
      originalGig = gigToEdit;
    }

    Gig gigForDialog = gigToEdit.copyWith(
      isRecurring: originalGig.isRecurring,
      recurrenceFrequency: originalGig.recurrenceFrequency,
      recurrenceDay: originalGig.recurrenceDay,
      recurrenceNthValue: originalGig.recurrenceNthValue,
      recurrenceEndDate: originalGig.recurrenceEndDate,
      recurrenceExceptions:
      originalGig.recurrenceExceptions, // Pass exceptions too
    );

    if (originalGig.isJamOpenMic) {
      final matchedVenue = _allKnownVenues.firstWhere(
            (v) => v.placeId == originalGig?.placeId,
        orElse: () => StoredLocation(
          placeId: '',
          name: '',
          address: '',
          coordinates: const LatLng(0, 0),
        ),
      );
      // A gig can outlive its venue's local record — e.g. one materialized
      // before GO JAM was fixed to also save the venue, or a venue that's
      // since been un-saved. Rather than silently no-op'ing the whole tap
      // (the old behavior — this listing would just never open), degrade
      // gracefully: fall back to the gig's own stored fields for display,
      // skip "VIEW VENUE DETAILS" (nothing to navigate to), and treat it as
      // not part of any active recurring series so at least "NOT GOING" is
      // offered to clean it up.
      final bool venueResolved = matchedVenue.placeId.isNotEmpty;
      final StoredLocation? sourceVenue = venueResolved ? matchedVenue : null;
      if (!mounted) return;

      // Snapshot originalGig into a genuinely non-nullable local — Dart's
      // null-promotion of a non-final local (originalGig) doesn't survive
      // into the onPressed closures below, so every closure would otherwise
      // need its own `if (originalGig == null) return;` guard (see how the
      // old HIDE FROM MY GIGS handler had to do exactly that).
      final Gig gig = originalGig;

      // Which JamSession this occurrence came from, so we know whether
      // "Show in Gigs list" is currently ON for it (an ongoing recurring
      // series -> only "REMOVE REGULAR JAM" applies) or this is a one-off
      // add, e.g. via GO JAM (-> "NOT GOING" applies instead). Same
      // prefix-stripping the old HIDE handler used, since placeId/sessionId
      // can themselves contain underscores.
      final String baseGigId = gig.getBaseId();
      final String? sessionId = sourceVenue == null
          ? null
          : (baseGigId.startsWith('jam_${sourceVenue.placeId}_')
          ? baseGigId.substring('jam_${sourceVenue.placeId}_'.length)
          : null);
      final int sessionIndex = (sourceVenue == null || sessionId == null)
          ? -1
          : sourceVenue.jamSessions.indexWhere((s) => s.id == sessionId);
      final JamSession? session =
      sessionIndex == -1 ? null : sourceVenue!.jamSessions[sessionIndex];
      final bool isRecurringSeriesActive = session?.showInGigsList ?? false;
      // Only a materialized (really-saved) instance has anything to delete —
      // a still-virtual, never-interacted-with recurring occurrence doesn't
      // exist as a record yet. NOT GOING is offered regardless of state
      // (see onPressed below for how each case is handled) so the user can
      // always change their mind, even after marking GOING/INTERESTED on an
      // occurrence that belongs to an active recurring series.
      final bool isMaterialized = _allGigs.any((g) => g.id == gig.id);

      // Network attendance counts (fast-follow to the local-only feature).
      // Kicked off now, before showDialog, rather than inside the builder,
      // so the fetch is already in flight while the dialog's open animation
      // plays — by the time the user can actually read the buttons it has
      // often already resolved. Standalone (not connected/not signed in)
      // users skip this entirely and just see plain "GOING"/"INTERESTED",
      // same as before.
      int? goingCount;
      int? interestedCount;
      VoidCallback? refreshDialogCounts;
      if (_isConnectedToNetwork && AuthService().isSignedIn) {
        final String userId = AuthService().currentUserId;
        unawaited(() async {
          var counts =
              await _jamAttendanceRepository.getCounts(gig.id, forUserId: userId);

          // Self-heal: bring Firestore in line with the local record when
          // they've drifted apart — e.g. this occurrence was added via GO
          // JAM (which has always set attendanceStatus: 'going' locally)
          // before the network mirror existed, so nobody ever actually
          // wrote it there. Without this, an occurrence the user is
          // already marked GOING on locally would keep showing 0 counts
          // forever, until they happened to re-tap a button here — which
          // reads as "the app forgot I'm going" rather than what it
          // actually is. Only fires on an actual mismatch, so an
          // already-synced occurrence never gets a redundant write.
          if (gig.attendanceStatus != counts.myStatus) {
            await _jamAttendanceRepository.setAttendance(
              occurrenceId: gig.id,
              userId: userId,
              newStatus: gig.attendanceStatus,
            );
            counts = await _jamAttendanceRepository.getCounts(
              gig.id,
              forUserId: userId,
            );
          }

          goingCount = counts.going;
          interestedCount = counts.interested;
          refreshDialogCounts?.call();
        }());
      }

      await showDialog(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            // Deliberately NOT named `context` — this closure encloses every
            // onPressed handler below, several of which call
            // ScaffoldMessenger.of(context)/Theme.of(context) using the
            // OUTER State's context AFTER Navigator.of(dialogContext).pop()
            // has already removed this StatefulBuilder from the tree. A
            // same-named inner `context` parameter would shadow the outer
            // one for all of that code and hand those calls a deactivated
            // context instead.
            builder: (_, setDialogState) {
              // Re-assigned on every build (cheap, idempotent) so the
              // counts fetch above can trigger exactly one dialog repaint
              // whenever it resolves, however long that takes.
              refreshDialogCounts = () => setDialogState(() {});

              return AlertDialog(
            title: Text(sourceVenue?.name ?? gig.venueName),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${DateFormat.yMMMEd().format(gig.dateTime)} at '
                      '${DateFormat.jm().format(gig.dateTime)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text('Jam / Open Mic session'),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: gig.attendanceStatus == 'going'
                              ? Colors.green.withValues(alpha: 0.15)
                              : null,
                          side: BorderSide(
                            color: gig.attendanceStatus == 'going'
                                ? Colors.green
                                : Colors.grey,
                          ),
                        ),
                        onPressed: () async {
                          Navigator.of(dialogContext).pop();
                          await _setJamAttendance(gig, 'going');
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("You're going!")),
                          );
                        },
                        child: Text(
                          goingCount != null
                              ? 'GOING (${goingCount!})'
                              : 'GOING',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor:
                          gig.attendanceStatus == 'interested'
                              ? Colors.amber.withValues(alpha: 0.15)
                              : null,
                          side: BorderSide(
                            color: gig.attendanceStatus == 'interested'
                                ? Colors.amber.shade700
                                : Colors.grey,
                          ),
                        ),
                        onPressed: () async {
                          Navigator.of(dialogContext).pop();
                          await _setJamAttendance(gig, 'interested');
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Marked as interested.')),
                          );
                        },
                        child: Text(
                          interestedCount != null
                              ? 'INTERESTED (${interestedCount!})'
                              : 'INTERESTED',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actions: <Widget>[
              TextButton(
                child: const Text('CLOSE'),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
              if (sourceVenue != null)
                TextButton(
                  child: const Text('VIEW VENUE DETAILS'),
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _showVenueDetailsDialog(sourceVenue);
                  },
                ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                  Theme.of(context).colorScheme.errorContainer,
                ),
                child: Text(
                  'NOT GOING',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  // Nothing materialized yet (a virtual occurrence of an
                  // active series the user never tapped GOING/INTERESTED
                  // on) — there's no record to clear, so just acknowledge.
                  if (!isMaterialized) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content:
                          Text("Okay — you weren't marked as going.")),
                    );
                    return;
                  }
                  await _removeJamInstance(gig);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isRecurringSeriesActive
                            ? "Cleared — you'll still see this on your "
                            "regular jam nights."
                            : 'Removed from your gigs list.',
                      ),
                    ),
                  );
                },
              ),
              if (isRecurringSeriesActive)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                    Theme.of(context).colorScheme.errorContainer,
                  ),
                  child: Text(
                    'REMOVE REGULAR JAM',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();

                    // --- START OF DEFINITIVE FIX ---
                    // (kept intact from the original HIDE FROM MY GIGS
                    // handler — just reusing sessionId/sessionIndex already
                    // resolved above instead of re-deriving them.)
                    log(
                      "--- REMOVE REGULAR JAM TAPPED ---",
                    );
                    // isRecurringSeriesActive (which gates this button) can
                    // only be true when sourceVenue/session/sessionId all
                    // resolved above, but that promotion doesn't carry into
                    // this closure — see the same note on `gig` above.
                    if (sourceVenue == null || sessionId == null) return;
                    final venueIndex = _allKnownVenues.indexWhere(
                          (v) => v.placeId == sourceVenue.placeId,
                    );

                    if (venueIndex != -1 && sessionIndex != -1) {
                      log(
                        "Found Venue '${sourceVenue.name}' and Session. Proceeding to update.",
                      );

                      // Create a mutable copy of the venue list to modify in memory.
                      List<StoredLocation> updatedAllVenues = List.from(
                        _allKnownVenues,
                      );
                      StoredLocation venueToUpdate =
                      updatedAllVenues[venueIndex];
                      List<JamSession> updatedSessions = List.from(
                        venueToUpdate.jamSessions,
                      );

                      // Update the session's visibility and save the venue.
                      updatedSessions[sessionIndex] =
                          updatedSessions[sessionIndex].copyWith(
                            showInGigsList: false,
                          );
                      final updatedVenue = venueToUpdate.copyWith(
                        jamSessions: updatedSessions,
                      );
                      updatedAllVenues[venueIndex] = updatedVenue;
                      await _updateVenueJamNightSettings(updatedVenue);

                      // Turning showInGigsList off only stops FUTURE virtual
                      // occurrences from being generated (_generateJamOpenMicGigs)
                      // — it does nothing for any date that was already
                      // materialized into a real 'gigs_list' record (e.g. via
                      // GO JAM, or by tapping GOING/INTERESTED on it before
                      // removing the series). Those are fully standalone
                      // records at that point (isRecurring: false), so the
                      // list would otherwise keep showing them forever. Sweep
                      // up any of THIS session's still-upcoming standalone
                      // records here — past ones are left alone as real gig
                      // history, not touched by this cleanup.
                      final String seriesBaseId =
                          'jam_${sourceVenue.placeId}_$sessionId';
                      final prefs = await SharedPreferences.getInstance();
                      final gigsJsonString =
                          prefs.getString(_keyGigsList) ?? '[]';
                      final List<Gig> allGigsFromPrefs =
                      Gig.decode(gigsJsonString);
                      final DateTime now = DateTime.now();
                      allGigsFromPrefs.removeWhere((g) =>
                      g.isJamOpenMic &&
                          g.getBaseId() == seriesBaseId &&
                          g.dateTime.isAfter(now));
                      await prefs.setString(
                          _keyGigsList, Gig.encode(allGigsFromPrefs));

                      log(
                        "Saved to SharedPreferences. Forcing immediate UI refresh.",
                      );

                      // Force the UI to refresh with the updated in-memory data
                      // directly, rather than relying on the async reload that
                      // globalRefreshNotifier.notify() (inside
                      // _updateVenueJamNightSettings) kicks off elsewhere —
                      // that reload can land after this synchronous rebuild,
                      // which is why this used to require a full restart to
                      // actually disappear from the list.
                      if (!mounted) return;
                      setState(() {
                        _allKnownVenues = updatedAllVenues;
                        _allGigs = allGigsFromPrefs;
                      });
                      // Now regenerate the gigs list using the corrected local data.
                      _generateAndSetDisplayedGigs();
                      // Tell every other open screen too.
                      globalRefreshNotifier.notify();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Regular jam removed from your gigs.'),
                          backgroundColor: Colors.blueAccent,
                        ),
                      );
                      log(
                        "Refresh complete. The series should now be off.",
                      );
                    } else {
                      log(
                        "Error: Could not find Venue (index: $venueIndex) or Session (index: $sessionIndex). This indicates a logic bug.",
                      );
                    }
                    // --- END OF DEFINITIVE FIX ---
                  },
                ),
            ],
          );
            },
          );
        },
      );
      return;
    }

    if (!mounted) return;
    const String googleApiKey = String.fromEnvironment('GOOGLE_API_KEY');
    final result = await showDialog<dynamic>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return BookingDialog(
          editingGig: gigForDialog,
          googleApiKey: googleApiKey,
          existingGigs: _allGigs.where((g) => !g.isJamOpenMic).toList(),
        );
      },
    );

    if (!mounted) return;

    if (result is GigEditResult &&
        result.action != GigEditResultAction.noChange) {
      if (result.action == GigEditResultAction.updated && result.gig != null) {
        await _updateGig(result.gig!);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gig "${result.gig!.venueName}" updated.'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (result.action == GigEditResultAction.deleted &&
          result.gig != null) {
        if (result.cancelChoice != null &&
            result.cancelChoice != RecurringCancelChoice.doNothing) {
          await _handleRecurringGigDeletion(result.gig!, result.cancelChoice!);
        } else if (result.cancelChoice == null) {
          await _deleteGig(result.gig!);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gig "${result.gig!.venueName}" cancelled.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } else if (result is Gig) {
      globalRefreshNotifier.notify();

      // Assess the newly booked gig immediately
      _impactEventService.fetchImpactEvents(gig: result).then((events) {
        if (!mounted) return;
        if (events.isNotEmpty) {
          setState(() {
            _impactEventsByGigId[result.id] = events;
            final idx = _displayedGigs.indexWhere((g) => g.id == result.id);
            if (idx != -1) {
              _displayedGigs[idx] = _displayedGigs[idx].copyWith(
                impactEvents: events,
              );
            }
          });
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('New gig "${result.venueName}" booked.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // ── Jam attendance (GOING / INTERESTED / NOT GOING) ────────────────────────
  // Both write straight to the same 'gigs_list' prefs key GigsPage itself
  // reads on load (see _loadGigs/_loadAllDataForGigsPage), then ping
  // globalRefreshNotifier so this screen (and any other open screen) picks
  // the change up immediately instead of waiting for the next natural
  // reload. The local write is always the source of truth for this
  // device; when connected to the network the same change is also
  // mirrored to Firestore (see _mirrorJamAttendanceToNetwork) so other
  // attendees can see Going/Interested counts — but that mirror is
  // fire-and-forget and never blocks or gates the local write above it.

  /// Sets Going/Interested on [gigInstance]. If it's still a virtual
  /// (never-saved) occurrence of an ongoing recurring jam, this is what
  /// materializes it into a real 'gigs_list' record — the same
  /// materialize-on-interaction pattern the retrospective wizard already
  /// uses for regular recurring gigs.
  Future<void> _setJamAttendance(Gig gigInstance, String status) async {
    final prefs = await SharedPreferences.getInstance();
    final gigsJsonString = prefs.getString(_keyGigsList) ?? '[]';
    final List<Gig> allGigs = Gig.decode(gigsJsonString);

    final index = allGigs.indexWhere((g) => g.id == gigInstance.id);
    if (index != -1) {
      allGigs[index] = allGigs[index].copyWith(attendanceStatus: status);
    } else {
      allGigs.add(gigInstance.copyWith(attendanceStatus: status));
    }

    await prefs.setString(_keyGigsList, Gig.encode(allGigs));

    // Update this screen's own in-memory copy directly and regenerate now
    // — don't rely solely on the async reload globalRefreshNotifier.notify()
    // kicks off, which can land after the dialog's already closed and
    // leave the tile looking unchanged until the next natural refresh.
    if (!mounted) return;
    setState(() => _allGigs = allGigs);
    _generateAndSetDisplayedGigs();
    globalRefreshNotifier.notify();

    _mirrorJamAttendanceToNetwork(gigInstance, newStatus: status);
  }

  /// Removes a single materialized jam instance from the gigs list (NOT
  /// GOING / change of mind). Always available now regardless of whether
  /// the occurrence belongs to an active recurring series — see the NOT
  /// GOING button in _launchBookingDialogForGig for the visibility/messaging
  /// logic that decides what this actually means to the user in each case.
  Future<void> _removeJamInstance(Gig gigInstance) async {
    final prefs = await SharedPreferences.getInstance();
    final gigsJsonString = prefs.getString(_keyGigsList) ?? '[]';
    final List<Gig> allGigs = Gig.decode(gigsJsonString);

    allGigs.removeWhere((g) => g.id == gigInstance.id);

    await prefs.setString(_keyGigsList, Gig.encode(allGigs));

    if (!mounted) return;
    setState(() => _allGigs = allGigs);
    _generateAndSetDisplayedGigs();
    globalRefreshNotifier.notify();

    _mirrorJamAttendanceToNetwork(gigInstance, newStatus: null);
  }

  /// Mirrors a Going/Interested/cleared change to Firestore when connected
  /// to the network, so other attendees of the same jam session can see
  /// counts. No-ops silently for standalone users or a signed-out session.
  ///
  /// FIX (8/26/26): this used to compute a signed delta from the local
  /// record's PREVIOUS attendanceStatus (decrement whatever it was, then
  /// increment the new one) against a single counter doc. That broke the
  /// first time it hit a gig that already had a local attendanceStatus
  /// from before this feature existed (e.g. a GO JAM add, which has always
  /// set attendanceStatus: 'going' locally) but had never been mirrored to
  /// Firestore — tapping INTERESTED on one read oldStatus == 'going',
  /// decremented a goingCount that was never actually incremented server-
  /// side, and landed on Going (-1) / Interested (1). Any local/server
  /// drift (reinstalls, this exact kind of pre-existing data, a prior
  /// failed write) hit the same failure mode.
  ///
  /// Fixed by dropping delta math entirely: each user's vote is now its
  /// own document at jamAttendance/{occurrenceId}/attendees/{userId} —
  /// GOING/INTERESTED is an idempotent set(), NOT GOING is a delete(). A
  /// stray write can never push a count negative or out of sync, because
  /// there's no counter to drift — see JamAttendanceRepository.getCounts,
  /// which now counts documents in that subcollection directly rather than
  /// reading a maintained aggregate.
  void _mirrorJamAttendanceToNetwork(Gig gigInstance,
      {required String? newStatus}) {
    if (!_isConnectedToNetwork) return;
    final authService = AuthService();
    if (!authService.isSignedIn) return;

    unawaited(_jamAttendanceRepository.setAttendance(
      occurrenceId: gigInstance.id,
      userId: authService.currentUserId,
      newStatus: newStatus,
    ));
  }

  Future<void> _openNotesPage(Gig gig, {bool scrollToImpact = false}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NotesPage(
          editingGigId: gig.id,
          scrollToImpact: scrollToImpact, // ← new param on NotesPage
          initialImpactEvents: gig.impactEvents ?? [],
        ),
      ),
    );
    if (!mounted) return;
    if (result is Gig) {
      // NotesPage._saveGigNotes() already wrote the correct data straight to
      // SharedPreferences (either updating the exact-id record or adding a
      // new materialized instance). Re-syncing _allGigs by finding the slot
      // via result.getBaseId() and overwriting it with `result` was WRONG:
      // for a recurring series that slot holds the TEMPLATE (isRecurring:
      // true), and overwriting it with one occurrence's full data (its own
      // id/date, isRecurring: false, and its ratings/tips) corrupted the
      // template in memory — and permanently on disk the next time any other
      // save path (e.g. _updateGig/_deleteGig) persisted _allGigs. A
      // corrupted template then leaks its stale ratings into every other
      // freshly-opened occurrence of that series (see notes_page.dart fix).
      // Reload from the source of truth instead of hand-patching memory.
      await _loadGigs();
      globalRefreshNotifier.notify();
    }
  }

  Future<void> _updateGig(Gig updatedGig) async {
    try {
      // 1. Get the Base ID (to find the template, not just the specific occurrence)
      final String baseId = updatedGig.getBaseId();
      final index = _allGigs.indexWhere((g) => g.id == baseId);

      log("--- [GigsPage] _updateGig ---");
      log("Updating Base ID: $baseId");
      log("New Band Name: ${updatedGig.bandName}");

      if (index != -1) {
        setState(() {
          // 2. Replace the master template in memory
          // We use copyWith(id: baseId) to ensure we don't accidentally
          // save an occurrence ID (with a date suffix) into the master list
          _allGigs[index] = updatedGig.copyWith(id: baseId);
        });

        // 3. Persist the entire list to SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        if (!mounted) return;
        await prefs.setString(_keyGigsList, Gig.encode(_allGigs));

        // 4. CRITICAL: Regenerate the concrete instances for the ListView
        _generateAndSetDisplayedGigs();

        // 5. Notify system to reload
        globalRefreshNotifier.notify();

        // Reschedule notifications with updated gig date/time
        final notificationService = NotificationService();
        await notificationService.init();
        if (!mounted) return;
        await notificationService.updateAllGigNotifications();

        log("✅ Gig updated and saved successfully to disk.");
      } else {
        log("❌ Error: Could not find gig with ID $baseId to update.");
      }
    } catch (e) {
      log("❌ Error in _updateGig: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating gig: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteGig(Gig gigToDelete) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      _allGigs.removeWhere((g) => g.id == gigToDelete.getBaseId());
      await prefs.setString(_keyGigsList, Gig.encode(_allGigs));

      final notificationService = NotificationService();
      await notificationService.init();
      if (!mounted) return;
      await notificationService.updateAllGigNotifications();

      globalRefreshNotifier.notify();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error cancelling gig: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _archiveVenue(StoredLocation venueToArchive) async {
    if (!mounted) return;
    // Generate gigs far in the future to check for real conflicts
    DateTime futureRange = DateTime.now().add(const Duration(days: 365 * 5));
    List<Gig> upcomingActualGigsAtVenue = [];
    // Check non-recurring gigs
    upcomingActualGigsAtVenue.addAll(
      _allGigs.where(
            (g) =>
        !g.isRecurring &&
            g.placeId == venueToArchive.placeId &&
            !g.isJamOpenMic &&
            g.dateTime.isAfter(DateTime.now()),
      ),
    );
    // Check recurring gigs
    for (var gig in _allGigs.where(
          (g) =>
      g.isRecurring &&
          g.placeId == venueToArchive.placeId &&
          !g.isJamOpenMic,
    )) {
      upcomingActualGigsAtVenue.addAll(
        _generateOccurrencesForGig(gig, futureRange),
      );
    }

    String dialogMessage =
        'Are you sure you want to archive "${venueToArchive.name}"?';
    if (upcomingActualGigsAtVenue.isNotEmpty) {
      dialogMessage +=
      '\n\nThis will also DELETE all upcoming actual gig(s) scheduled here (including all recurring instances).';
    } else {
      dialogMessage +=
      '\nIt will be hidden from lists but not permanently deleted.';
    }

    final bool confirmArchive =
        await showDialog<bool>(
          context: context,
          builder: (_) {
            return AlertDialog(
              title: Text('Confirm Archive: ${venueToArchive.name}'),
              content: Text(dialogMessage),
              actions: <Widget>[
                TextButton(
                  child: const Text('CANCEL'),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                TextButton(
                  child: Text(
                    'ARCHIVE',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            );
          },
        ) ??
            false;

    if (!mounted) return;
    if (confirmArchive) {
      setState(() {
        _isLoadingVenues = true;
        _isLoadingGigs = true;
      });
      final prefs = await SharedPreferences.getInstance();

      // Delete the base gigs associated with the venue
      if (upcomingActualGigsAtVenue.isNotEmpty) {
        final String? gigsJsonString = prefs.getString(_keyGigsList);
        List<Gig> currentAllActualGigs = (gigsJsonString != null)
            ? Gig.decode(gigsJsonString)
            : [];
        currentAllActualGigs.removeWhere(
              (gig) => gig.placeId == venueToArchive.placeId && !gig.isJamOpenMic,
        );
        await prefs.setString(_keyGigsList, Gig.encode(currentAllActualGigs));

        final notificationService = NotificationService();
        await notificationService.init();
        await notificationService.updateAllGigNotifications();
      }

      int index = _allKnownVenues.indexWhere(
            (v) => v.placeId == venueToArchive.placeId,
      );
      if (index != -1) {
        List<StoredLocation> updatedAllVenues = List.from(_allKnownVenues);
        updatedAllVenues[index] = updatedAllVenues[index].copyWith(
          isArchived: true,
        );
        final List<String> updatedVenuesJson = updatedAllVenues
            .map((v) => jsonEncode(v.toJson()))
            .toList();
        await prefs.setStringList(_keySavedLocations, updatedVenuesJson);
      }

      globalRefreshNotifier.notify();
      if (!mounted) return;
      String snackbarMessage = 'Venue "${venueToArchive.name}" archived.';
      if (upcomingActualGigsAtVenue.isNotEmpty) {
        snackbarMessage += ' All associated actual gigs deleted.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(snackbarMessage),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _updateVenueJamNightSettings(StoredLocation updatedVenue) async {
    final prefs = await SharedPreferences.getInstance();
    int index = _allKnownVenues.indexWhere(
          (v) => v.placeId == updatedVenue.placeId,
    );
    if (index != -1) {
      List<StoredLocation> updatedAllVenuesList = List.from(_allKnownVenues);
      updatedAllVenuesList[index] = updatedVenue;

      // FILTER: Only save venues the user has actually interacted with
      // Don't persist read-only JSON jam venues unless user has modified them
      final List<StoredLocation> venuesToSave = updatedAllVenuesList.where((v) {
        final hasVisibleJamSessions = v.jamSessions.any(
              (s) => s.showInGigsList,
        );
        return v.placeId ==
            updatedVenue.placeId || // Always save the venue being updated
            hasVisibleJamSessions ||
            v.rating > 0 ||
            v.isArchived ||
            v.isMuted ||
            v.isPrivate ||
            v.contact != null ||
            v.venueNotes != null;
      }).toList();

      final List<String> updatedVenuesJson = venuesToSave
          .map((v) => jsonEncode(v.toJson()))
          .toList();
      await prefs.setStringList(_keySavedLocations, updatedVenuesJson);
      if (!mounted) return;
      globalRefreshNotifier.notify();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Jam/Open Mic settings updated for ${updatedVenue.name}.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _showVenueDetailsDialog(StoredLocation venue) async {
    if (!mounted) return;

    final upcomingGigs =
    _displayedGigs
        .where(
          (g) =>
      g.placeId == venue.placeId &&
          g.dateTime.isAfter(DateTime.now()) &&
          !g.isJamOpenMic,
    )
        .toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    final nextUpcomingGig = upcomingGigs.isNotEmpty ? upcomingGigs.first : null;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VenueDetailPage(
          venue: venue,
          nextGig: nextUpcomingGig,
          onArchive: () {
            Navigator.of(context).pop();
            _archiveVenue(venue);
          },
          onBook: (venueToSaveAndBook) async {
            await _updateAndSaveLocationReview(venueToSaveAndBook);
            if (!mounted) return;
            final newGig = await _launchBookingDialogForVenue(
              venueToSaveAndBook,
            );
            if (newGig != null) {
              await Future.delayed(const Duration(milliseconds: 100));
              if (!mounted) return;
              Navigator.of(context).pop();
              _showVenueDetailsDialog(venueToSaveAndBook);
            }
          },
          onSave: (updatedVenue) {
            _updateAndSaveLocationReview(updatedVenue);
          },
          onContactSaved: (contact, bookingInfo) async {
            final index = _allKnownVenues.indexWhere(
                  (v) => v.placeId == venue.placeId,
            );
            if (index != -1) {
              _allKnownVenues[index] = _allKnownVenues[index].copyWith(
                contact: contact,
                bookingInfo: bookingInfo,
              );
              final prefs = await SharedPreferences.getInstance();
              if (!mounted) return;
              final updatedJson = _allKnownVenues
                  .map((v) => jsonEncode(v.toJson()))
                  .toList();
              await prefs.setStringList(_keySavedLocations, updatedJson);
              if (!mounted) return;
              globalRefreshNotifier.notify();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Contact updated for ${venue.name}.'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          },
          onEditJamSettings: () async {
            Navigator.of(context).pop();
            final result = await showDialog<JamOpenMicDialogResult>(
              context: context,
              builder: (_) => JamOpenMicDialog(venue: venue),
            );
            if (result != null &&
                result.settingsChanged &&
                result.updatedVenue != null) {
              await _updateVenueJamNightSettings(result.updatedVenue!);
            }
          },
          onDataChanged: () => _loadVenues(),
          onNavigateToProfile: () {
            Navigator.of(context).pop();
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ProfilePage()));
          },
        ),
      ),
    );
  }

  Future<void> _updateAndSaveLocationReview(
      StoredLocation updatedLocation,
      ) async {
    List<StoredLocation> updatedAllVenues = List.from(_allKnownVenues);
    int index = updatedAllVenues.indexWhere(
          (loc) => loc.placeId == updatedLocation.placeId,
    );

    if (index != -1) {
      updatedAllVenues[index] = updatedLocation;
    } else {
      updatedAllVenues.add(updatedLocation);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final List<String> locationsJson = updatedAllVenues
          .map((loc) => jsonEncode(loc.toJson()))
          .toList();
      await prefs.setStringList(_keySavedLocations, locationsJson);
      if (!mounted) return;
      globalRefreshNotifier.notify();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${updatedLocation.name} saved!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving venue: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<Gig?> _launchBookingDialogForVenue(StoredLocation venue) async {
    const String googleApiKey = String.fromEnvironment('GOOGLE_API_KEY');
    if (!mounted) return null;
    return await showDialog<Gig>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return BookingDialog(
          preselectedVenue: venue,
          googleApiKey: googleApiKey,
          existingGigs: _allGigs.where((g) => !g.isJamOpenMic).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 🎯 The build method is now clean again. No Consumer, no Stack.
    return Column(
      children: <Widget>[
        Material(
          color: Theme.of(context).colorScheme.surface,
          elevation: 0,
          child: TabBar(
            controller: _tabController,
            // Brand accent (8/26 color consolidation) — was
            // colorScheme.primary (the deepPurple-derived purple); this is
            // the "tab underline" that was sharing a color with the date
            // circles below purely by ColorScheme coincidence. Orange is
            // now the one intentional accent color.
            labelColor: Colors.deepOrange.shade400,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.deepOrange.shade400,
            tabs: const [
              Tab(icon: Icon(Icons.event_note), text: 'Upcoming Gigs'),
              Tab(icon: Icon(Icons.location_city), text: 'Saved Venues'),
              Tab(icon: Icon(Icons.groups), text: 'My Bands'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildGigsTabContent(),
              VenuesListTab(
                isLoading: _isLoadingVenues,
                displayableVenues: _displayableVenues,
                displayedGigs: _displayedGigs,
                onVenueTapped: _showVenueDetailsDialog,
              ),
              MyBandsTab(
                isLoading: _isLoadingBands,
                isConnected: _isConnectedToNetwork,
                bands: _allBands,
                currentUserId: AuthService().currentUserId,
                onCreateBand: _openCreateBandFlow,
                onBandTapped: _openBandDetail,
              ),
            ],
          ),
        ),
      ],
    );
  }


  Widget _buildGigsTabContent() {
    if (_isLoadingGigs && _displayedGigs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // --- REMOVED: The old "if (!_isLoadingGigs && _displayedGigs.isEmpty)" block that returned a full-screen empty state ---

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(
            top: 8.0,
            left: 8.0,
            right: 8.0,
            bottom: 8.0,
          ),
          child: Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildGigsViewToggle(),
              OutlinedButton.icon(
                icon: const Icon(Icons.insights, size: 18),
                label: const Text('Insights'),
                onPressed: _allGigs.isEmpty
                    ? null
                    : () => showGigInsightsDialog(
                  context: context,
                  allGigs: _allGigs,
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Export'),
                onPressed: () => showGigExportDialog(
                  context: context,
                  allGigs: _allGigs,
                  allKnownVenues: _allKnownVenues,
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.checklist, size: 18),
                label: const Text('Checklist'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const GigChecklistPage(),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_isLoadingGigs && _displayedGigs.isNotEmpty)
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ),
          ),

        // This is now always accessible
        Expanded(
          child: _gigsViewType == GigsViewType.list
              ? _buildGigsListView()
              : _buildGigsCalendarView(),
        ),

        if (_isMoreGigsLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  Widget _buildGigsViewToggle() {
    return SegmentedButton<GigsViewType>(
      segments: const <ButtonSegment<GigsViewType>>[
        ButtonSegment<GigsViewType>(
          value: GigsViewType.list,
          label: Text('List'),
          icon: Icon(Icons.list),
        ),
        ButtonSegment<GigsViewType>(
          value: GigsViewType.calendar,
          label: Text('Calendar'),
          icon: Icon(Icons.calendar_today),
        ),
      ],
      selected: <GigsViewType>{_gigsViewType},
      onSelectionChanged: (Set<GigsViewType> newSelection) {
        if (!mounted) return;
        setState(() {
          _gigsViewType = newSelection.first;
        });
      },
    );
  }

  // lib/features/gigs/views/gigs.dart -> inside _GigsPageState

  Widget _buildGigsListView() {
    // Move the empty state logic here
    if (_displayedGigs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text(
            'No upcoming gigs or jam nights scheduled.\nBook a gig or set up a jam night to see it here!',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ),
      );
    }

    // Use a LinkedHashMap to group gigs by the first day of their month.
    final gigsByMonth = LinkedHashMap<DateTime, List<Gig>>(
      equals: (a, b) => a.year == b.year && a.month == b.month,
      hashCode: (key) => key.month.hashCode ^ key.year.hashCode,
    );

    // *** THE CORE FIX IS HERE ***
    // Group the gigs that are ACTUALLY being displayed (_displayedGigs)
    // instead of the raw data from storage (_allGigs).
    for (final gig in _displayedGigs) {
      final monthKey = DateTime(gig.dateTime.year, gig.dateTime.month, 1);
      gigsByMonth.putIfAbsent(monthKey, () => []).add(gig);
    }

    // 2. Create the final flat list for the ListView builder
    final List<dynamic> listItems = [];
    gigsByMonth.keys.toList()
      ..sort((a, b) => a.compareTo(b)) // Sort months chronologically
      ..forEach((month) {
        // Get the gigs for this month from our new, correct grouping.
        final gigsInMonth = gigsByMonth[month]!;

        // Calculate summary for this month from the correct list of gigs.
        int gigCount = 0;
        double totalPay = 0;
        double sumOfTrueHourlyRates = 0.0;

        for (final gig in gigsInMonth) {
          if (!gig.isJamOpenMic) {
            gigCount++;
            totalPay += gig.pay;
            sumOfTrueHourlyRates += gig.trueHourlyRate;
          }
        }
        final averagePayPerHour = (gigCount > 0)
            ? sumOfTrueHourlyRates / gigCount
            : 0.0;

        // Add the separator with the CORRECT totals.
        listItems.add(
          MonthlySeparator(
            month: month,
            gigCount: gigCount,
            totalPay: totalPay,
            averagePayPerHour: averagePayPerHour,
          ),
        );

        // Add the gigs for this month, ensuring they are sorted chronologically.
        gigsInMonth.sort((a, b) => a.dateTime.compareTo(b.dateTime));
        listItems.addAll(gigsInMonth);
      });

    // 3. Build the ListView.
    // The rest of this method remains the same as it correctly renders the items.
    bool _firstGigKeyAssigned =
    false; // 🎬 Track whether we've assigned the key yet

    return ListView.builder(
      controller: _scrollController,
      itemCount: listItems.length,
      itemBuilder: (context, index) {
        final item = listItems[index];

        if (item is MonthlySeparator) {
          return MonthlySeparatorTile(separator: item);
        }

        if (item is Gig) {
          // 🎬 Assign the demo key to the first real (non-jam) gig card in the list.
          // This works whether or not a demo gig exists — it highlights whatever
          // the user will actually see first.
          bool assignKey = false;
          if (!_firstGigKeyAssigned && !item.isJamOpenMic) {
            assignKey = true;
            _firstGigKeyAssigned = true;
            log(
              '🎬 [GigsPage] ListView itemBuilder: ✅ Assigning _demoGigTileKey to FIRST gig: id="${item.id}" venue="${item.venueName}"',
            );
          }

          return GigListTile(
            key: assignKey ? _demoGigTileKey : null,
            gig: item,
            style: GigTileStyle.listView,
            onTap: () => _launchBookingDialogForGig(item),
            onNotesTap: () => _openNotesPage(item),
          );
        }

        // Fallback for any unexpected item type
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildGigsCalendarView() {
    if (_isLoadingGigs && _calendarEvents.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.only(bottom: 8.0),
          child: TableCalendar<Gig>(
            firstDay: DateTime.utc(DateTime.now().year - 1, 1, 1),
            lastDay: DateTime.utc(DateTime.now().year + 5, 12, 31),
            focusedDay: _focusedDay,
            calendarFormat: _calendarFormat,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            eventLoader: _getEventsForDay,
            startingDayOfWeek: StartingDayOfWeek.sunday,
            calendarStyle: CalendarStyle(
              defaultTextStyle: const TextStyle(color: Colors.black87),
              weekendTextStyle: TextStyle(color: Colors.red.shade700),
              outsideTextStyle: TextStyle(color: Colors.grey.shade400),
              disabledTextStyle: TextStyle(color: Colors.grey.shade300),
              todayDecoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withAlpha(128),
                shape: BoxShape.circle,
              ),
              todayTextStyle: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              selectedDecoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              selectedTextStyle: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary,
              ),
              markerDecoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondary,
                shape: BoxShape.circle,
              ),
            ),
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.bold,
              ),
              weekendStyle: TextStyle(
                color: Colors.red.shade600,
                fontWeight: FontWeight.bold,
              ),
            ),
            headerStyle: HeaderStyle(
              titleTextStyle: const TextStyle(
                color: Colors.black87,
                fontSize: 17.0,
                fontWeight: FontWeight.bold,
              ),
              formatButtonVisible: true,
              titleCentered: true,
              formatButtonShowsNext: false,
              formatButtonTextStyle: TextStyle(
                color: Theme.of(context).colorScheme.primary,
              ),
              formatButtonDecoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                ),
                borderRadius: BorderRadius.circular(12.0),
              ),
              leftChevronIcon: Icon(Icons.chevron_left, color: Colors.black54),
              rightChevronIcon: Icon(
                Icons.chevron_right,
                color: Colors.black54,
              ),
            ),
            onDaySelected: _onDaySelected,
            onFormatChanged: (format) {
              if (_calendarFormat != format) {
                if (!mounted) return;
                setState(() {
                  _calendarFormat = format;
                });
              }
            },
            onPageChanged: (focusedDay) {
              if (!mounted) return;
              setState(() {
                _focusedDay = focusedDay;
              });
              _onDaySelected(focusedDay, focusedDay);
            },
            calendarBuilders: CalendarBuilders<Gig>(
              markerBuilder: (context, date, events) {
                if (events.isEmpty) return null;

                final List<Gig> gigEvents = events.cast<Gig>();
                bool hasActualGig = gigEvents.any(
                      (gig) => !gig.isJamOpenMic && !gig.isRecurring,
                ); // One-off gig
                bool hasRecurringGig = gigEvents.any(
                      (gig) => !gig.isJamOpenMic && gig.isRecurring,
                ); // Recurring gig instance
                bool hasJam = gigEvents.any((gig) => gig.isJamOpenMic);
                List<Widget> markers = [];
                if (hasActualGig) {
                  markers.add(
                    _buildEventsMarker(Theme.of(context).colorScheme.secondary),
                  );
                }
                if (hasRecurringGig) {
                  if (markers.isNotEmpty) markers.add(const SizedBox(width: 2));
                  markers.add(
                    _buildEventsMarker(Colors.blue),
                  ); // Dot for recurring gigs
                }
                if (hasJam) {
                  if (markers.isNotEmpty) markers.add(const SizedBox(width: 2));
                  markers.add(
                    _buildEventsMarker(Theme.of(context).colorScheme.tertiary),
                  ); // Dot for jam sessions
                }
                if (markers.isEmpty) return null;
                return Positioned(
                  bottom: 1,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: markers,
                  ),
                );
              },
            ),
          ),
        ),
        Expanded(
          child: _selectedDayGigs.isNotEmpty
              ? ListView.builder(
            itemCount: _selectedDayGigs.length,
            itemBuilder: (context, index) {
              final gig = _selectedDayGigs[index];
              return GigListTile(
                gig: gig,
                style: GigTileStyle.calendarView,
                onTap: () => _launchBookingDialogForGig(gig),
                onNotesTap: () => _openNotesPage(gig),
              );
            },
          )
              : Center(
            child: Text(
              _selectedDay != null
                  ? 'No events for ${DateFormat.yMMMEd().format(_selectedDay!)}.'
                  : 'Select a day to see events.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white70
                    : Colors.black87,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEventsMarker(Color markerColor) {
    return Container(
      decoration: BoxDecoration(shape: BoxShape.circle, color: markerColor),
      width: 7.0,
      height: 7.0,
      margin: const EdgeInsets.symmetric(horizontal: 0.5),
    );
  }
}