// lib/gigs.dart
import 'dart:collection'; // For LinkedHashMap (used by TableCalendar for events)
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart'; // Import TableCalendar
import 'package:the_money_gigs/global_refresh_notifier.dart'; // Import the notifier
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

  Map<DateTime, List<Gig>> _calendarEvents = {};

  List<StoredLocation> _allKnownVenues = [];
  List<StoredLocation> _displayableVenues = [];

  bool _isLoadingGigs = true;
  bool _isLoadingVenues = true;

  GigsViewType _gigsViewType = GigsViewType.list;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  List<Gig> _selectedDayGigs = [];
  static const String _keyGigsList = 'gigs_list';
  static const String _keySavedLocations = 'saved_locations';

  final GlobalKey _demoGigTileKey = GlobalKey();
  OverlayEntry? _overlayEntry; // 🎯 ADD THIS VARIABLE

  final ImpactEventService _impactEventService = ImpactEventService();

  //   // gigId → list of impact events; populated after gigs load
  Map<String, List<ImpactEvent>> _impactEventsByGigId = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _scrollController = ScrollController()
      ..addListener(_scrollListener); // Initialize scroll controller
    _selectedDay = _focusedDay;
    _tabController.addListener(_handleTabSelection);
    _loadAllDataForGigsPage();
    globalRefreshNotifier.addListener(_handleGlobalRefresh);

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
    if (!mounted) {
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
      if (!mounted) {
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

      if (mounted) {
        log(
          '🎬 [GigsPage] _tryShowGigListDemoOverlay (post-frame): calling _showGigListOverlay',
        );
        _showGigListOverlay(demoProvider);
      } else {
        log(
          '🎬 [GigsPage] _tryShowGigListDemoOverlay (post-frame): ❌ no longer mounted after scroll, aborting.',
        );
      }
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
      if (mounted)
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
      await prefs.setString(_keyGigsList, Gig.encode(_allGigs));

      final notificationService = NotificationService();
      await notificationService.init();
      await notificationService.updateAllGigNotifications();

      globalRefreshNotifier.notify();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating recurring gig: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _handleGlobalRefresh() {
    if (mounted) {
      // Reset lazy-loading date range on global refresh
      _gigListEndDate = DateTime.now().add(const Duration(days: 90));
      _loadAllDataForGigsPage();
    }
  }

  Future<void> _loadAllDataForGigsPage() async {
    await Future.wait([_loadVenues(), _loadGigs()]);
    for (final gig in _allGigs) {
      log('🎸 [GigsPage] Loaded gig: id=${gig.id} venue="${gig.venueName}"...');
    }
    // Fire impact assessment after gigs are loaded. Non-blocking.
    _runImpactAssessment();
  }

  Future<void> _runImpactAssessment() async {
    final int lookahead = _gigListEndDate.difference(DateTime.now()).inDays + 1;
    final results = await _impactEventService.reassessUpcomingGigs(
      upcomingGigs: _displayedGigs,
      lookAheadDays: lookahead,
    );
    if (mounted && results.isNotEmpty) {
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

    // --- ALWAYS load from the original, correct key ---
    final String? gigsJsonString = prefs.getString(_keyGigsList);

    List<Gig> loadedGigs = [];
    if (gigsJsonString != null && gigsJsonString.isNotEmpty) {
      try {
        loadedGigs = Gig.decode(gigsJsonString);
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error loading gigs: $e')));
      }
    }

    if (mounted) {
      _allGigs = loadedGigs;
      _generateAndSetDisplayedGigs(); // This will handle generation, sorting, and setting state
      setState(() {
        _isLoadingGigs = false;
      });
    }
  }

  Future<void> _loadMoreGigs() async {
    if (!mounted || _isMoreGigsLoading) return;

    setState(() {
      _isMoreGigsLoading = true;
    });

    await Future.delayed(
      const Duration(milliseconds: 500),
    ); // Simulate network latency

    // Extend the date range and regenerate the list
    _gigListEndDate = _gigListEndDate.add(const Duration(days: 14));
    _generateAndSetDisplayedGigs();

    // Assess impact events for gigs now visible in the extended window.
    _runImpactAssessment();

    if (mounted) {
      setState(() {
        _isMoreGigsLoading = false;
      });
    }
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
        if (gig.notes != null && gig.notes!.isNotEmpty)
          processedVenueName += " (${gig.notes})";
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

    if (mounted) {
      setState(() {
        _displayedGigs = sortedGigs;
      });
      _prepareCalendarEvents();
      _onDaySelected(_selectedDay ?? _focusedDay, _focusedDay);
    }
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

    if (mounted)
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
      if (mounted)
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
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error loading some venues: $e')),
          );
      }
    }
    if (mounted) {
      setState(() {
        _allKnownVenues = loadedFromPrefs;
        _displayableVenues = _allKnownVenues
            .where((venue) => !venue.isArchived)
            .toList();
        _isLoadingVenues = false;
      });
    }
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
      final sourceVenue = _allKnownVenues.firstWhere(
        (v) => v.placeId == originalGig?.placeId,
        orElse: () => StoredLocation(
          placeId: '',
          name: '',
          address: '',
          coordinates: const LatLng(0, 0),
        ),
      );
      if (sourceVenue.placeId.isEmpty) return;
      await showDialog(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: Text(sourceVenue.name),
            content: const Text('This is a recurring Jam/Open Mic session.'),
            actions: <Widget>[
              TextButton(
                child: const Text('CLOSE'),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
              TextButton(
                child: const Text('VIEW VENUE DETAILS'),
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _showVenueDetailsDialog(sourceVenue);
                },
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.errorContainer,
                ),
                child: Text(
                  'HIDE FROM MY GIGS',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  if (originalGig == null) return;

                  // --- START OF DEFINITIVE FIX ---
                  log(
                    "--- HIDE BUTTON TAPPED ---",
                  ); // 1. Get the base ID, which correctly removes the date suffix.
                  final String baseGigId = originalGig.getBaseId();
                  log("1. Base Gig ID for processing: $baseGigId");

                  // 2. We have the sourceVenue, so we know its exact placeId.
                  final String knownPlaceId = sourceVenue.placeId;

                  // 3. The session ID is everything in the baseGigId *after* "jam_" and the known placeId.
                  //    We construct the prefix we expect to find.
                  final String prefix = 'jam_${knownPlaceId}_';

                  if (baseGigId.startsWith(prefix)) {
                    // 4. The true session ID is whatever remains after stripping the prefix.
                    //    This is robust and handles underscores in both the placeId and sessionId.
                    final String sessionId = baseGigId.substring(prefix.length);
                    log("2. Extracted TRUE Session ID: $sessionId");

                    final venueIndex = _allKnownVenues.indexWhere(
                      (v) => v.placeId == sourceVenue.placeId,
                    );
                    final sessionIndex = sourceVenue.jamSessions.indexWhere(
                      (s) => s.id == sessionId,
                    );

                    if (venueIndex != -1 && sessionIndex != -1) {
                      log(
                        "3. Found Venue '${sourceVenue.name}' and Session. Proceeding to update.",
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

                      // 4. Update the session's visibility and save the venue.
                      updatedSessions[sessionIndex] =
                          updatedSessions[sessionIndex].copyWith(
                            showInGigsList: false,
                          );
                      final updatedVenue = venueToUpdate.copyWith(
                        jamSessions: updatedSessions,
                      );
                      updatedAllVenues[venueIndex] = updatedVenue;
                      await _updateVenueJamNightSettings(updatedVenue);

                      log(
                        "4. Saved to SharedPreferences. Forcing immediate UI refresh.",
                      );

                      // 5. Force the UI to refresh with the updated in-memory data.
                      if (mounted) {
                        setState(() {
                          // This is the crucial step: update the page's local state immediately.
                          _allKnownVenues = updatedAllVenues;
                        });
                        // Now regenerate the gigs list using the corrected local data.
                        _generateAndSetDisplayedGigs();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Jam session hidden.'),
                            backgroundColor: Colors.blueAccent,
                          ),
                        );
                        log(
                          "5. Refresh complete. The session should now be hidden.",
                        );
                      }
                    } else {
                      log(
                        "Error: Could not find Venue (index: $venueIndex) or Session (index: $sessionIndex). This indicates a logic bug.",
                      );
                    }
                  } else {
                    log(
                      "Error: Could not parse the baseGigId '$baseGigId' using the known placeId '$knownPlaceId'.",
                    );
                  }
                  // --- END OF DEFINITIVE FIX ---
                },
              ),
            ],
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
      builder: (BuildContext dialogContext) {
        return BookingDialog(
          editingGig: gigForDialog,
          googleApiKey: googleApiKey,
          existingGigs: _allGigs.where((g) => !g.isJamOpenMic).toList(),
        );
      },
    );

    if (result is GigEditResult &&
        result.action != GigEditResultAction.noChange) {
      if (result.action == GigEditResultAction.updated && result.gig != null) {
        await _updateGig(result.gig!);
        if (mounted)
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
          if (mounted)
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
        if (mounted && events.isNotEmpty) {
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

      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('New gig "${result.venueName}" booked.'),
            backgroundColor: Colors.green,
          ),
        );
    }
  }

  Future<void> _openNotesPage(Gig gig, {bool scrollToImpact = false}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NotesPage(
          editingGigId: gig.id,
          scrollToImpact: scrollToImpact, // ← new param on NotesPage
          initialImpactEvents: gig.impactEvents ?? [],
        ),
      ),
    );
    if (result is Gig && mounted) {
      final idx = _allGigs.indexWhere((g) => g.id == result.getBaseId());
      if (idx != -1) {
        setState(() {
          _allGigs[idx] = result;
        });
        _generateAndSetDisplayedGigs();
      }
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
        await prefs.setString(_keyGigsList, Gig.encode(_allGigs));

        // 4. CRITICAL: Regenerate the concrete instances for the ListView
        _generateAndSetDisplayedGigs();

        // 5. Notify system to reload
        globalRefreshNotifier.notify();

        // Reschedule notifications with updated gig date/time
        final notificationService = NotificationService();
        await notificationService.init();
        await notificationService.updateAllGigNotifications();

        log("✅ Gig updated and saved successfully to disk.");
      } else {
        log("❌ Error: Could not find gig with ID $baseId to update.");
      }
    } catch (e) {
      log("❌ Error in _updateGig: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating gig: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteGig(Gig gigToDelete) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _allGigs.removeWhere((g) => g.id == gigToDelete.getBaseId());
      await prefs.setString(_keyGigsList, Gig.encode(_allGigs));

      final notificationService = NotificationService();
      await notificationService.init();
      await notificationService.updateAllGigNotifications();

      globalRefreshNotifier.notify();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cancelling gig: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
          builder: (BuildContext dialogContext) {
            return AlertDialog(
              title: Text('Confirm Archive: ${venueToArchive.name}'),
              content: Text(dialogMessage),
              actions: <Widget>[
                TextButton(
                  child: const Text('CANCEL'),
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                ),
                TextButton(
                  child: Text(
                    'ARCHIVE',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                ),
              ],
            );
          },
        ) ??
        false;

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
      if (mounted) {
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
      if (mounted) {
        globalRefreshNotifier.notify();
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
            final newGig = await _launchBookingDialogForVenue(
              venueToSaveAndBook,
            );
            if (newGig != null) {
              await Future.delayed(const Duration(milliseconds: 100));
              if (mounted) {
                Navigator.of(context).pop();
                _showVenueDetailsDialog(venueToSaveAndBook);
              }
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
              final updatedJson = _allKnownVenues
                  .map((v) => jsonEncode(v.toJson()))
                  .toList();
              await prefs.setStringList(_keySavedLocations, updatedJson);
              globalRefreshNotifier.notify();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Contact updated for ${venue.name}.'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
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
      final List<String> locationsJson = updatedAllVenues
          .map((loc) => jsonEncode(loc.toJson()))
          .toList();
      await prefs.setStringList(_keySavedLocations, locationsJson);
      globalRefreshNotifier.notify();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${updatedLocation.name} saved!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving venue: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<Gig?> _launchBookingDialogForVenue(StoredLocation venue) async {
    const String googleApiKey = String.fromEnvironment('GOOGLE_API_KEY');
    return await showDialog<Gig>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
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
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Theme.of(context).colorScheme.primary,
            tabs: const [
              Tab(icon: Icon(Icons.event_note), text: 'Upcoming Gigs'),
              Tab(icon: Icon(Icons.location_city), text: 'Saved Venues'),
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
            ],
          ),
        ),
      ],
    );
  }

  /// Merges public venue data with local user preferences for jam sessions
  /// Preserves showInGigsList setting from local version
  StoredLocation _mergeVenueJamPreferences(
    StoredLocation publicVenue,
    StoredLocation? localVenue,
  ) {
    if (localVenue == null || localVenue.jamSessions.isEmpty) {
      return publicVenue; // No local preferences to preserve
    }

    // Create map of local jam preferences by session ID
    final Map<String, bool> localPreferences = {
      for (var session in localVenue.jamSessions)
        session.id: session.showInGigsList,
    };

    // Merge: Use public jam data but preserve local showInGigsList setting
    final mergedJamSessions = publicVenue.jamSessions.map((publicSession) {
      final localPref = localPreferences[publicSession.id];
      if (localPref != null) {
        // User has a preference for this session, preserve it
        return publicSession.copyWith(showInGigsList: localPref);
      }
      return publicSession; // New session, use public default
    }).toList();

    return publicVenue.copyWith(jamSessions: mergedJamSessions);
  }

  Widget _buildGigsTabContent() {
    bool hasUpcomingGigs = _displayedGigs.any(
      (gig) => !gig.isJamOpenMic && gig.dateTime.isAfter(DateTime.now()),
    );

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
