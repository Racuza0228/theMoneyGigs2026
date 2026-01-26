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

// Import your models
import 'package:in_app_review/in_app_review.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';
// <<<--- IMPORT THE NEW MODEL
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';
import 'package:the_money_gigs/features/map_venues/models/jam_session_model.dart';
import 'package:the_money_gigs/features/gigs/widgets/booking_dialog.dart';
import 'package:the_money_gigs/features/map_venues/widgets/jam_open_mic_dialog.dart';
import 'package:the_money_gigs/features/notes/views/notes_page.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_contact.dart';
import 'package:the_money_gigs/core/services/gig_embed_service.dart';
import 'package:the_money_gigs/features/map_venues/widgets/venue_contact_dialog.dart';
import 'package:the_money_gigs/features/map_venues/widgets/venue_details_dialog.dart';
// <<< --- REFACTORING: ADD IMPORT FOR THE NEW VENUES TAB WIDGET --- >>>
import 'package:the_money_gigs/features/venues/views/venues_list_tab.dart';


import '../../app_demo/providers/demo_provider.dart';

class MonthlySeparator {
  final DateTime month;
  final int gigCount;
  final double totalPay;
  final double averagePayPerHour;

  MonthlySeparator({
    required this.month,
    required this.gigCount,
    required this.totalPay,
    required this.averagePayPerHour,
  });
}

enum GigsViewType { list, calendar }

class GigsPage extends StatefulWidget {
  const GigsPage({super.key});

  @override
  State<GigsPage> createState() => _GigsPageState();
}

class _GigsPageState extends State<GigsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late ScrollController _scrollController;

  List<Gig> _allGigs = []; // Raw data from SharedPreferences, including recurring templates
  List<Gig> _displayedGigs = []; // Generated, displayable occurrences for the list view
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

  final Gig _demoGig = Gig(
    id: DemoProvider.demoGigId,
    venueName: 'Kroger Marketplace',
    address: '4613 Marburg Ave, Cincinnati, OH 45209',
    placeId: DemoProvider.demoVenuePlaceId,
    latitude: 39.1602761,
    longitude: -84.429593,
    dateTime: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 20, 0),
    pay: 250,
    gigLengthHours: 3,
    driveSetupTimeHours: 2.5,
    rehearsalLengthHours: 2,
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _scrollController = ScrollController()..addListener(_scrollListener); // Initialize scroll controller
    _selectedDay = _focusedDay;
    _tabController.addListener(_handleTabSelection);
    _loadAllDataForGigsPage();
    globalRefreshNotifier.addListener(_handleGlobalRefresh);

    Provider.of<DemoProvider>(context, listen: false)
        .addListener(_onDemoStateChanged);
  }

  @override
  void dispose() {
    globalRefreshNotifier.removeListener(_handleGlobalRefresh);
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    _scrollController.dispose(); // Dispose scroll controller

    Provider.of<DemoProvider>(context, listen: false)
        .removeListener(_onDemoStateChanged);
    super.dispose();
  }

  void _scrollListener() {
    // Load more when user is 200 pixels from the bottom of the list
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
        !_isMoreGigsLoading) {
      _loadMoreGigs();
    }
  }

  void _onDemoStateChanged() async { // Make async
    final demoProvider = Provider.of<DemoProvider>(context, listen: false);
    if (!mounted) return;

    // --- START OF FIX ---
    // Check if the demo is ending. This is the crucial condition.
    if (!demoProvider.isDemoModeActive) {
      // The demo has just ended. Request the review *before* doing the UI cleanup.
      // We also add a small delay to ensure the review dialog can launch safely
      // before we start removing elements from the UI.
      try {
        final InAppReview inAppReview = InAppReview.instance;
        if (await inAppReview.isAvailable()) {
          // Awaiting this is not necessary as we don't need the result,
          // but it helps ensure the call is initiated.
          inAppReview.requestReview();
        }
      } catch (e) {
        // Silently fail. The review is not critical.
        print("In-app review failed: $e");
      }

      // Add a small buffer to let the native UI call process.
      await Future.delayed(const Duration(milliseconds: 250));
    }
    // --- END OF FIX ---

    // Now, proceed with the UI update state logic.
    if (!mounted) return; // Re-check if the widget is still mounted after the delay.
    setState(() {
      if (demoProvider.isDemoModeActive && demoProvider.currentStep == 13) {
        final bool alreadyExists = _displayedGigs.any((g) => g.id == _demoGig.id);
        if (!alreadyExists) {
          _displayedGigs.insert(0, _demoGig);
          _displayedGigs.sort((a, b) => a.dateTime.compareTo(b.dateTime));
        }
      } else if (!demoProvider.isDemoModeActive) {
        // The logic to remove the gig remains the same.
        _allGigs.removeWhere((g) => g.id == _demoGig.id);
        _displayedGigs.removeWhere((g) => g.id == _demoGig.id);
      }

      _prepareCalendarEvents();
      _onDaySelected(_selectedDay ?? _focusedDay, _focusedDay);
    });
  }

  Future<void> _handleRecurringGigDeletion(Gig gigInstance, RecurringCancelChoice choice) async {
    if (choice == RecurringCancelChoice.doNothing) return;

    final String baseGigId = gigInstance.getBaseId();
    final int index = _allGigs.indexWhere((g) => g.id == baseGigId);

    if (index == -1) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: Could not find the original recurring gig to modify.'), backgroundColor: Colors.red));
      return;
    }

    Gig baseGig = _allGigs[index];
    String message = '';

    if (choice == RecurringCancelChoice.allFutureInstances) {
      DateTime newEndDate = gigInstance.dateTime.subtract(const Duration(days: 1));
      if (newEndDate.isBefore(baseGig.dateTime)) {
        _allGigs.removeAt(index);
        message = 'The entire recurring series for "${baseGig.venueName}" has been cancelled.';
      } else {
        // Otherwise, just truncate the series.
        _allGigs[index] = baseGig.copyWith(recurrenceEndDate: newEndDate);
        message = 'The recurring gig for "${gigInstance.venueName}" on and after ${DateFormat.yMMMEd().format(gigInstance.dateTime)} has been cancelled.';
      }

    } else if (choice == RecurringCancelChoice.thisInstanceOnly) {
      // This logic is correct: Add the specific date to the exceptions list.
      List<DateTime> updatedExceptions = List.from(baseGig.recurrenceExceptions ?? []);
      DateTime exceptionDate = DateTime.utc(gigInstance.dateTime.year, gigInstance.dateTime.month, gigInstance.dateTime.day);

      if (!updatedExceptions.any((d) => isSameDay(d, exceptionDate))) {
        updatedExceptions.add(exceptionDate);
      }

      _allGigs[index] = baseGig.copyWith(recurrenceExceptions: updatedExceptions);
      message = 'The gig for "${gigInstance.venueName}" on ${DateFormat.yMMMEd().format(gigInstance.dateTime)} has been cancelled.';
    }

    // --- Save the changes and refresh the UI ---
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyGigsList, Gig.encode(_allGigs));
      globalRefreshNotifier.notify(); // This will trigger a reload and regeneration of gigs
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.orange));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating recurring gig: ${e.toString()}'), backgroundColor: Colors.red));
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
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging ||
        (_tabController.animation != null && _tabController.animation!.value != _tabController.index.toDouble())) {
      return;
    }
  }

  Future<void> _loadGigs() async {
    if (!mounted) return;
    setState(() { _isLoadingGigs = true; });
    final prefs = await SharedPreferences.getInstance();

    // --- ALWAYS load from the original, correct key ---
    final String? gigsJsonString = prefs.getString(_keyGigsList);

    List<Gig> loadedGigs = [];
    if (gigsJsonString != null && gigsJsonString.isNotEmpty) {
      try {
        loadedGigs = Gig.decode(gigsJsonString);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading gigs: $e')));
      }
    }

    if (mounted) {
      _allGigs = loadedGigs;
      _generateAndSetDisplayedGigs(); // This will handle generation, sorting, and setting state
      setState(() { _isLoadingGigs = false; });
    }
  }

  Future<void> _loadMoreGigs() async {
    if (!mounted || _isMoreGigsLoading) return;

    setState(() { _isMoreGigsLoading = true; });

    await Future.delayed(const Duration(milliseconds: 500)); // Simulate network latency

    // Extend the date range and regenerate the list
    _gigListEndDate = _gigListEndDate.add(const Duration(days: 14));
    _generateAndSetDisplayedGigs();

    if (mounted) {
      setState(() { _isMoreGigsLoading = false; });
    }
  }

  void _generateAndSetDisplayedGigs() {
    List<Gig> allOccurrences = [];
    DateTime now = DateTime.now();
    DateTime todayStart = DateTime(now.year, now.month, now.day);

    // --- START OF REVISED LOGIC ---

    // 1. Add ALL original gigs from storage (both recurring and non-recurring).
    //    This ensures the original "template" for a recurring gig is always in the list
    //    if it hasn't passed yet.
    allOccurrences.addAll(_allGigs);

    // 2. Generate all future occurrences for recurring gigs based on their templates.
    //    This generates the list of "Weekly on Tuesday", etc.
    for (var baseGig in _allGigs.where((g) => g.isRecurring)) {
      allOccurrences.addAll(_generateOccurrencesForGig(baseGig, _gigListEndDate));
    }

    // 3. Generate all Jam/Open Mic session occurrences.
    allOccurrences.addAll(_generateJamOpenMicGigs(_gigListEndDate));

    // 4. Process the gigs (add prefixes, etc.)
    List<Gig> processedGigs = allOccurrences.map((gig) {
      final sourceVenue = _allKnownVenues.firstWhere(
            (v) => v.placeId == gig.placeId,
        orElse: () => StoredLocation(placeId: '', name: gig.venueName, address: '', coordinates: const LatLng(0,0)),
      );

      String processedVenueName = gig.venueName;
      if (sourceVenue.isPrivate && !gig.venueName.startsWith('[PRIVATE]')) {
        processedVenueName = '[PRIVATE] $processedVenueName';
      }

      if (gig.isJamOpenMic && !gig.venueName.contains('[JAM]')) {
        processedVenueName = '[JAM] $processedVenueName';
        if(gig.notes != null && gig.notes!.isNotEmpty){
          processedVenueName += " (${gig.notes})";
        }
      }
      return gig.copyWith(venueName: processedVenueName);
    }).toList();

    // 5. De-duplicate the list. This is the most critical step.
    //    The Map ensures that if a generated occurrence has the same ID as an
    //    original gig (e.g., the very first date), the generated one is kept,
    //    preventing duplicates.
    final Map<String, Gig> uniqueGigs = {};
    for (var gig in processedGigs) {
      uniqueGigs[gig.id] = gig;
    }

    // 6. Filter out gigs that have already ended and then sort the remaining ones.
    List<Gig> sortedGigs = uniqueGigs.values.where((gig) {
      DateTime gigEndTime = gig.dateTime.add(Duration(minutes: (gig.gigLengthHours * 60).toInt()));
      return !gigEndTime.isBefore(todayStart);
    }).toList();

    sortedGigs.sort((a, b) => a.dateTime.compareTo(b.dateTime));

    // --- END OF REVISED LOGIC ---

    if (mounted) {
      // 7. Update the state with the final, correct list.
      setState(() {
        _displayedGigs = sortedGigs;
      });

      // These can now run with the correct data.
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
          id: 'jam_${venue.placeId}_${session.id}', // Base ID for the series
          venueName: venue.name,
          latitude: venue.coordinates.latitude,
          longitude: venue.coordinates.longitude,
          address: venue.address,
          placeId: venue.placeId,
          dateTime: sessionStartDateTime, // The time of the session is the base time
          pay: 0,
          gigLengthHours: 2,
          driveSetupTimeHours: 0,
          rehearsalLengthHours: 0,
          isJamOpenMic: true,
          notes: session.style, // Use notes to pass the style for display
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
    if (!baseGig.isRecurring || baseGig.recurrenceFrequency == null || baseGig.recurrenceDay == null) {
      return occurrences;
    }

    //print("\n--- 2. Generating Occurrences for: ${baseGig.venueName} (Base Date: ${baseGig.dateTime}) ---");

    DateTime recurrenceSeriesStart = baseGig.dateTime;

    // The calculation should not exceed the gig's own end date, if it exists.
    DateTime calculationRangeEnd = baseGig.recurrenceEndDate != null && baseGig.recurrenceEndDate!.isBefore(rangeEndDate)
        ? baseGig.recurrenceEndDate!
        : rangeEndDate;

    int targetWeekday = baseGig.recurrenceDay!.index + 1;

    // Start the iterator from the day AFTER the base gig. This prevents duplicating the original instance.
    DateTime iteratorDate = DateTime(recurrenceSeriesStart.year, recurrenceSeriesStart.month, recurrenceSeriesStart.day).add(const Duration(days: 1));

    // --- START OF DEBUGGING PRINT ---
    print("   - Calculation Range: ${DateFormat('yyyy-MM-dd').format(iteratorDate)} to ${DateFormat('yyyy-MM-dd').format(calculationRangeEnd)}");
    // --- END OF DEBUGGING PRINT ---

    switch (baseGig.recurrenceFrequency) {
      case JamFrequencyType.weekly:
      // Find the first valid occurrence on or after the iterator date.
        DateTime testDate = _findNextDayOfWeek(iteratorDate, targetWeekday, sameDayOk: true);
        while (testDate.isBefore(calculationRangeEnd) || isSameDay(testDate, calculationRangeEnd)) {
          // --- START OF DEBUGGING PRINT ---
          //print("     - [Weekly] Found potential date: ${DateFormat('yyyy-MM-dd').format(testDate)}");
          // --- END OF DEBUGGING PRINT ---
          _addOccurrenceIfApplicable(occurrences, baseGig, testDate);
          testDate = testDate.add(const Duration(days: 7)); // Simply jump to the next week.
        }
        break;

      case JamFrequencyType.biWeekly:
      // The anchor is always the date of the original event.
        DateTime cycleAnchorDate = _findNextDayOfWeek(baseGig.dateTime, targetWeekday, sameDayOk: true);
        DateTime testDate = _findNextDayOfWeek(iteratorDate, targetWeekday, sameDayOk: true);

        while(testDate.isBefore(calculationRangeEnd) || isSameDay(testDate, calculationRangeEnd)){
          int weeksDifference = testDate.difference(cycleAnchorDate).inDays ~/ 7;
          // Generate an occurrence only for even-numbered week differences (2, 4, 6, etc.)
          if (weeksDifference > 0 && weeksDifference % 2 == 0) {
            _addOccurrenceIfApplicable(occurrences, baseGig, testDate);
          }
          testDate = testDate.add(const Duration(days: 7)); // Always check the next week
        }
        break;

      case JamFrequencyType.customNthDay:
        if (baseGig.recurrenceNthValue != null && baseGig.recurrenceNthValue! > 0) {
          int nth = baseGig.recurrenceNthValue!;
          DateTime testDate = _findNextDayOfWeek(iteratorDate, targetWeekday, sameDayOk: true);
          while (testDate.isBefore(calculationRangeEnd) || isSameDay(testDate, calculationRangeEnd)) {
            _addOccurrenceIfApplicable(occurrences, baseGig, testDate);
            testDate = testDate.add(Duration(days: 7 * nth)); // Jump by N weeks
          }
        }
        break;

      case JamFrequencyType.monthlySameDay:
        if (baseGig.recurrenceNthValue != null && baseGig.recurrenceNthValue! > 0) {
          int nthOccurrence = baseGig.recurrenceNthValue!;
          // Start iterating from the month of the start date
          DateTime monthIterator = DateTime(iteratorDate.year, iteratorDate.month, 1);

          while (monthIterator.isBefore(calculationRangeEnd) || (monthIterator.year == calculationRangeEnd.year && monthIterator.month == calculationRangeEnd.month)) {
            DateTime? nthDayInMonth = _findNthSpecificWeekdayOfMonth(monthIterator.year, monthIterator.month, targetWeekday, nthOccurrence);
            // Ensure the found day is within the allowed range
            if (nthDayInMonth != null && !nthDayInMonth.isBefore(iteratorDate) && !nthDayInMonth.isAfter(calculationRangeEnd)) {
              _addOccurrenceIfApplicable(occurrences, baseGig, nthDayInMonth);
            }
            // Move to the next month
            monthIterator = DateTime(monthIterator.year, monthIterator.month + 1, 1);
          }
        }
        break;

      default:
        break;
    }
    return occurrences;
  }

  void _addOccurrenceIfApplicable(List<Gig> occurrences, Gig baseGig, DateTime dateOfOccurrence) {
    // --- FINALIZED EXCEPTION LOGIC ---
    // Check if the specific date of this potential occurrence is in the base gig's exception list.
    if (baseGig.recurrenceExceptions != null &&
        baseGig.recurrenceExceptions!.any((exceptionDate) => isSameDay(exceptionDate, dateOfOccurrence))) {
      //print("  - 🚫 SKIPPING OCCURRENCE on ${DateFormat('yyyy-MM-dd').format(dateOfOccurrence)} due to exception.");
      return; // Do not generate this gig instance.
    }
    // --- END OF EXCEPTION LOGIC ---

    DateTime gigDateTime = DateTime(
      dateOfOccurrence.year,
      dateOfOccurrence.month,
      dateOfOccurrence.day,
      baseGig.dateTime.hour,
      baseGig.dateTime.minute,
    );

    DateTime now = DateTime.now();
    DateTime todayStart = DateTime(now.year, now.month, now.day);
    if (dateOfOccurrence.isBefore(todayStart)) {
      return; // Do not generate occurrences for days before today.
    }

    // Create a unique ID for this specific occurrence to avoid collisions
    final String uniqueId = '${baseGig.id}_${DateFormat('yyyyMMdd').format(gigDateTime)}';

    //print("     ✅ ADDING OCCURRENCE for ${DateFormat('yyyy-MM-dd').format(gigDateTime)}");

    occurrences.add(
      baseGig.copyWith(
        id: uniqueId,
        dateTime: gigDateTime,
        isRecurring: false, // This instance is a concrete event, not a template
        isFromRecurring: true, // This flag identifies it as generated from a series
        recurrenceExceptions: [], // Clear exceptions for the instance itself
      ),
    );
  }



  void _prepareCalendarEvents() {
    final events = LinkedHashMap<DateTime, List<Gig>>(equals: isSameDay, hashCode: getHashCode);
    DateTime today = DateTime.now();
    DateTime calendarRangeEnd = DateTime(today.year + 5, today.month, today.day);

    List<Gig> allCalendarGigs = [];
    // --- START OF FIX ---
    // Add original recurring gigs to the calendar as well
    allCalendarGigs.addAll(_allGigs);
    // --- END OF FIX ---

    for (var baseGig in _allGigs.where((g) => g.isRecurring)) {
      allCalendarGigs.addAll(_generateOccurrencesForGig(baseGig, calendarRangeEnd));
    }
    allCalendarGigs.addAll(_generateJamOpenMicGigs(calendarRangeEnd));

    final uniqueGigs = { for (var g in allCalendarGigs) g.id : g };

    for (var gig in uniqueGigs.values) {
      final date = DateTime.utc(gig.dateTime.year, gig.dateTime.month, gig.dateTime.day);
      events.putIfAbsent(date, () => []).add(gig);
    }

    if (mounted) setState(() { _calendarEvents = events; });
  }

  DateTime _findNextDayOfWeek(DateTime startDate, int targetWeekday, {bool sameDayOk = false}) {
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

  DateTime? _findNthSpecificWeekdayOfMonth(int year, int month, int targetWeekday, int nth) {
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

  int getHashCode(DateTime key) => key.day * 1000000 + key.month * 10000 + key.year;

  List<Gig> _getEventsForDay(DateTime day) {
    final normalizedDay = DateTime.utc(day.year, day.month, day.day);
    return _calendarEvents[normalizedDay] ?? [];
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    final normalizedNewSelectedDay = DateTime.utc(selectedDay.year, selectedDay.month, selectedDay.day);
    final normalizedCurrentSelectedDay = _selectedDay != null ? DateTime.utc(_selectedDay!.year, _selectedDay!.month, _selectedDay!.day) : null;
    if (!isSameDay(normalizedCurrentSelectedDay, normalizedNewSelectedDay)) {
      if (!mounted) return;
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
        _selectedDayGigs = _getEventsForDay(selectedDay);
      });
    } else {
      if (mounted) setState(() { _selectedDayGigs = _getEventsForDay(selectedDay); });
    }
  }

  Future<void> _loadVenues() async {
    if (!mounted) return;
    setState(() { _isLoadingVenues = true; });
    final prefs = await SharedPreferences.getInstance();
    final List<String>? venuesJson = prefs.getStringList(_keySavedLocations);
    List<StoredLocation> loadedFromPrefs = [];
    if (venuesJson != null) {
      try {
        loadedFromPrefs = venuesJson.map((jsonString) {
          try {
            return StoredLocation.fromJson(jsonDecode(jsonString));
          } catch (e) {
            print("Error decoding a single venue: $jsonString. Error: $e");
            return null;
          }
        }).whereType<StoredLocation>().toList();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading some venues: $e')));
      }
    }
    if (mounted) {
      setState(() {
        _allKnownVenues = loadedFromPrefs;
        _displayableVenues = _allKnownVenues.where((venue) => !venue.isArchived).toList();
        _isLoadingVenues = false;
      });
    }
  }

  Future<void> _launchNotesPageForGig(Gig gig) async {
    if (gig.isJamOpenMic) return;

    // --- START DEBUGGING ---
    //print("--- [GigsPage] Debugging _launchNotesPageForGig ---");
    //print("1. Gig Tapped: '${gig.venueName}' (ID: ${gig.id})");
    //print("2. Is it from a recurring series? ${gig.isFromRecurring}");

    final String gigIdForNotes = gig.getBaseId();

    //print("3. Calculated Base ID to pass: $gigIdForNotes");
    //print("----------------------------------------------------");
    // --- END DEBUGGING ---

    final result = await Navigator.of(context).push<Gig>(
      MaterialPageRoute(
        builder: (context) => NotesPage(editingGigId: gigIdForNotes),
      ),
    );

    if (result != null) {
      setState(() {
        final index = _allGigs.indexWhere((g) => g.id == result.id);
        if (index != -1) {
          _allGigs[index] = result;
          _generateAndSetDisplayedGigs();
        }
      });
    }
  }

  Future<void> _launchBookingDialogForGig(Gig gigToEdit) async {
    String originalGigId = gigToEdit.getBaseId();

    Gig? originalGig;
    if (!gigToEdit.isJamOpenMic) {
      originalGig = _allGigs.firstWhere((g) => g.id == originalGigId, orElse: () => gigToEdit);
    } else {
      originalGig = gigToEdit;
    }

    Gig gigForDialog = gigToEdit.copyWith(
      isRecurring: originalGig.isRecurring,
      recurrenceFrequency: originalGig.recurrenceFrequency,
      recurrenceDay: originalGig.recurrenceDay,
      recurrenceNthValue: originalGig.recurrenceNthValue,
      recurrenceEndDate: originalGig.recurrenceEndDate,
      recurrenceExceptions: originalGig.recurrenceExceptions, // Pass exceptions too
    );


    if (originalGig.isJamOpenMic) {
      final sourceVenue = _allKnownVenues.firstWhere(
            (v) => v.placeId == originalGig?.placeId,
        orElse: () => StoredLocation(placeId: '', name: '', address: '', coordinates: const LatLng(0,0)),
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
                style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.errorContainer),
                child: Text('HIDE FROM MY GIGS', style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  if (originalGig == null) return;

                  // --- START OF DEFINITIVE FIX ---
                  print("--- HIDE BUTTON TAPPED ---");  // 1. Get the base ID, which correctly removes the date suffix.
                  final String baseGigId = originalGig.getBaseId();
                  print("1. Base Gig ID for processing: $baseGigId");

                  // 2. We have the sourceVenue, so we know its exact placeId.
                  final String knownPlaceId = sourceVenue.placeId;

                  // 3. The session ID is everything in the baseGigId *after* "jam_" and the known placeId.
                  //    We construct the prefix we expect to find.
                  final String prefix = 'jam_${knownPlaceId}_';

                  if (baseGigId.startsWith(prefix)) {
                    // 4. The true session ID is whatever remains after stripping the prefix.
                    //    This is robust and handles underscores in both the placeId and sessionId.
                    final String sessionId = baseGigId.substring(prefix.length);
                    print("2. Extracted TRUE Session ID: $sessionId");

                    final venueIndex = _allKnownVenues.indexWhere((v) => v.placeId == sourceVenue.placeId);
                    final sessionIndex = sourceVenue.jamSessions.indexWhere((s) => s.id == sessionId);

                    if (venueIndex != -1 && sessionIndex != -1) {
                      print("3. Found Venue '${sourceVenue.name}' and Session. Proceeding to update.");

                      // Create a mutable copy of the venue list to modify in memory.
                      List<StoredLocation> updatedAllVenues = List.from(_allKnownVenues);
                      StoredLocation venueToUpdate = updatedAllVenues[venueIndex];
                      List<JamSession> updatedSessions = List.from(venueToUpdate.jamSessions);

                      // 4. Update the session's visibility and save the venue.
                      updatedSessions[sessionIndex] = updatedSessions[sessionIndex].copyWith(showInGigsList: false);
                      final updatedVenue = venueToUpdate.copyWith(jamSessions: updatedSessions);
                      updatedAllVenues[venueIndex] = updatedVenue;
                      await _updateVenueJamNightSettings(updatedVenue);

                      print("4. Saved to SharedPreferences. Forcing immediate UI refresh.");

                      // 5. Force the UI to refresh with the updated in-memory data.
                      if (mounted) {
                        setState(() {
                          // This is the crucial step: update the page's local state immediately.
                          _allKnownVenues = updatedAllVenues;
                        });
                        // Now regenerate the gigs list using the corrected local data.
                        _generateAndSetDisplayedGigs();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Jam session hidden.'), backgroundColor: Colors.blueAccent),
                        );
                        print("5. Refresh complete. The session should now be hidden.");
                      }
                    } else {
                      print("Error: Could not find Venue (index: $venueIndex) or Session (index: $sessionIndex). This indicates a logic bug.");
                    }
                  } else {
                    print("Error: Could not parse the baseGigId '$baseGigId' using the known placeId '$knownPlaceId'.");
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

    if (result is GigEditResult && result.action != GigEditResultAction.noChange) {
      if (result.action == GigEditResultAction.updated && result.gig != null) {
        await _updateGig(result.gig!);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gig "${result.gig!.venueName}" updated.'), backgroundColor: Colors.green));
      } else if (result.action == GigEditResultAction.deleted && result.gig != null) {
        if (result.cancelChoice != null && result.cancelChoice != RecurringCancelChoice.doNothing) {
          await _handleRecurringGigDeletion(result.gig!, result.cancelChoice!);
        } else if (result.cancelChoice == null) {
          await _deleteGig(result.gig!);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gig "${result.gig!.venueName}" cancelled.'), backgroundColor: Colors.orange));
        }
      }
    } else if (result is Gig) {
      globalRefreshNotifier.notify();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('New gig "${result.venueName}" booked.'), backgroundColor: Colors.green));
    }
  }


  Future<void> _updateGig(Gig updatedGig) async {
    try {
      // Find the index of the old gig in your master list
      final index = _allGigs.indexWhere((g) => g.id == updatedGig.id);
      if (index != -1) {
        // Replace the old gig with the updated one
        _allGigs[index] = updatedGig;

        // Save the entire updated list back to SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        // NOTE: Make sure _keyGigsList is the correct key you use elsewhere for the gigs list.
        await prefs.setString('gigs_list', Gig.encode(_allGigs));

        // Now that the data is saved, notify the app to reload everything.
        globalRefreshNotifier.notify();
        print("Gig updated and saved successfully.");
      } else {
        print("Error: Could not find gig with ID ${updatedGig.id} to update.");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error processing gig update: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteGig(Gig gigToDelete) async {
    // This function now primarily handles deletion of SINGLE, NON-RECURRING gigs.
    // The logic for recurring gigs is handled by _handleRecurringGigDeletion.
    try {
      final prefs = await SharedPreferences.getInstance();
      // We need to operate on the master list, _allGigs
      _allGigs.removeWhere((g) => g.id == gigToDelete.getBaseId());

      await prefs.setString(_keyGigsList, Gig.encode(_allGigs));
      globalRefreshNotifier.notify();

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cancelling gig: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _setVenueMutedState(StoredLocation venue, bool isMuted) async {
    final int index = _allKnownVenues.indexWhere((v) => v.placeId == venue.placeId);
    if (index != -1) {
      _allKnownVenues[index] = _allKnownVenues[index].copyWith(isMuted: isMuted);
      final prefs = await SharedPreferences.getInstance();
      final List<String> updatedVenuesJson = _allKnownVenues.map((v) => jsonEncode(v.toJson())).toList();
      await prefs.setStringList(_keySavedLocations, updatedVenuesJson);
      globalRefreshNotifier.notify();
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isMuted ? 'Jam sessions for ${venue.name} will be hidden from the gigs list.' : 'Jam sessions for ${venue.name} will now be shown in the gigs list.'),
            backgroundColor: Colors.blueAccent,
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
    upcomingActualGigsAtVenue.addAll(_allGigs.where((g) => !g.isRecurring && g.placeId == venueToArchive.placeId && !g.isJamOpenMic && g.dateTime.isAfter(DateTime.now())));
    // Check recurring gigs
    for (var gig in _allGigs.where((g) => g.isRecurring && g.placeId == venueToArchive.placeId && !g.isJamOpenMic)) {
      upcomingActualGigsAtVenue.addAll(_generateOccurrencesForGig(gig, futureRange));
    }


    String dialogMessage = 'Are you sure you want to archive "${venueToArchive.name}"?';
    if (upcomingActualGigsAtVenue.isNotEmpty) {
      dialogMessage += '\n\nThis will also DELETE all upcoming actual gig(s) scheduled here (including all recurring instances).';
    } else {
      dialogMessage += '\nIt will be hidden from lists but not permanently deleted.';
    }

    final bool confirmArchive = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Confirm Archive: ${venueToArchive.name}'),
          content: Text(dialogMessage),
          actions: <Widget>[
            TextButton(child: const Text('CANCEL'), onPressed: () => Navigator.of(dialogContext).pop(false)),
            TextButton(
                child: Text('ARCHIVE', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                onPressed: () => Navigator.of(dialogContext).pop(true)),
          ],
        );
      },
    ) ?? false;

    if (confirmArchive) {
      setState(() { _isLoadingVenues = true; _isLoadingGigs = true; });
      final prefs = await SharedPreferences.getInstance();
      // Delete the base gigs associated with the venue
      if (upcomingActualGigsAtVenue.isNotEmpty) {
        final String? gigsJsonString = prefs.getString(_keyGigsList);
        List<Gig> currentAllActualGigs = (gigsJsonString != null) ? Gig.decode(gigsJsonString) : [];
        // Remove any gig (recurring or not) at this venue that isn't a jam session
        currentAllActualGigs.removeWhere((gig) => gig.placeId == venueToArchive.placeId && !gig.isJamOpenMic);
        await prefs.setString(_keyGigsList, Gig.encode(currentAllActualGigs));
      }
      int index = _allKnownVenues.indexWhere((v) => v.placeId == venueToArchive.placeId);
      if (index != -1) {
        List<StoredLocation> updatedAllVenues = List.from(_allKnownVenues);
        updatedAllVenues[index] = updatedAllVenues[index].copyWith(isArchived: true);
        final List<String> updatedVenuesJson = updatedAllVenues.map((v) => jsonEncode(v.toJson())).toList();
        await prefs.setStringList(_keySavedLocations, updatedVenuesJson);
      }
      globalRefreshNotifier.notify();
      if (mounted) {
        String snackbarMessage = 'Venue "${venueToArchive.name}" archived.';
        if (upcomingActualGigsAtVenue.isNotEmpty) {
          snackbarMessage += ' All associated actual gigs deleted.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(snackbarMessage), backgroundColor: Colors.orange),
        );
      }
    }
  }

  Future<void> _editVenueContact(StoredLocation venue) async {
    final updatedContact = await showDialog<VenueContact>(
      context: context,
      barrierDismissible: false,
      builder: (_) => VenueContactDialog(venue: venue),
    );
    if (updatedContact != null && mounted) {
      final int index = _allKnownVenues.indexWhere((v) => v.placeId == venue.placeId);
      if (index != -1) {
        _allKnownVenues[index] = _allKnownVenues[index].copyWith(contact: updatedContact);
        final prefs = await SharedPreferences.getInstance();
        final List<String> updatedVenuesJson = _allKnownVenues.map((v) => jsonEncode(v.toJson())).toList();
        await prefs.setStringList(_keySavedLocations, updatedVenuesJson);
        globalRefreshNotifier.notify();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Contact updated for ${venue.name}.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _updateVenueJamNightSettings(StoredLocation updatedVenue) async {
    final prefs = await SharedPreferences.getInstance();
    int index = _allKnownVenues.indexWhere((v) => v.placeId == updatedVenue.placeId);
    if (index != -1) {
      List<StoredLocation> updatedAllVenuesList = List.from(_allKnownVenues);
      updatedAllVenuesList[index] = updatedVenue;

      // FILTER: Only save venues the user has actually interacted with
      // Don't persist read-only JSON jam venues unless user has modified them
      final List<StoredLocation> venuesToSave = updatedAllVenuesList.where((v) {
        final hasVisibleJamSessions = v.jamSessions.any((s) => s.showInGigsList);
        return v.placeId == updatedVenue.placeId || // Always save the venue being updated
            hasVisibleJamSessions ||
            v.rating > 0 ||
            v.isArchived ||
            v.isMuted ||
            v.isPrivate ||
            v.contact != null ||
            v.venueNotes != null;
      }).toList();

      final List<String> updatedVenuesJson = venuesToSave.map((v) => jsonEncode(v.toJson())).toList();
      await prefs.setStringList(_keySavedLocations, updatedVenuesJson);
      if (mounted) {
        globalRefreshNotifier.notify();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Jam/Open Mic settings updated for ${updatedVenue.name}.'), backgroundColor: Colors.green),
        );
      }
    }
  }

  Future<void> _showVenueDetailsDialog(StoredLocation venue) async {
    if (!mounted) return;

    List<Gig> upcomingGigsAtVenue = _displayedGigs.where((gig) {
      bool venueMatch = gig.placeId == venue.placeId;
      if (!venueMatch) return false;

      // Check if the gig is in the future
      bool dateMatch = gig.dateTime.isAfter(DateTime.now());

      // Ensure it's not a jam/open mic session
      return dateMatch && !gig.isJamOpenMic;
    }).toList();

    upcomingGigsAtVenue.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    Gig? nextUpcomingGig = upcomingGigsAtVenue.isNotEmpty ? upcomingGigsAtVenue.first : null;

    await showDialog(
        context: context,
        builder: (BuildContext dialogContext) {
          return VenueDetailsDialog(
            venue: venue,
            nextGig: nextUpcomingGig,
            onArchive: () {
              Navigator.of(dialogContext).pop();
              _archiveVenue(venue);
            },
            onBook: (venueToSaveAndBook) async {
              await _updateAndSaveLocationReview(venueToSaveAndBook);

              final newGig = await _launchBookingDialogForVenue(venueToSaveAndBook);

              if(mounted) Navigator.of(dialogContext).pop();

              if (newGig != null) {
                await Future.delayed(const Duration(milliseconds: 100));
                _showVenueDetailsDialog(venueToSaveAndBook);
              }
            },
            onSave: (updatedVenue) {
              _updateAndSaveLocationReview(updatedVenue);
            },
            onEditContact: () {
              Navigator.of(dialogContext).pop();
              _editVenueContact(venue);
            },
            onEditJamSettings: () async {
              Navigator.of(dialogContext).pop();
              final result = await showDialog<JamOpenMicDialogResult>(
                context: context,
                builder: (_) => JamOpenMicDialog(venue: venue),
              );
              if (result != null && result.settingsChanged && result.updatedVenue != null) {
                await _updateVenueJamNightSettings(result.updatedVenue!);
              }
            },
          );
        });
  }

  Future<void> _updateAndSaveLocationReview(StoredLocation updatedLocation) async {
    List<StoredLocation> updatedAllVenues = List.from(_allKnownVenues);
    int index = updatedAllVenues.indexWhere((loc) => loc.placeId == updatedLocation.placeId);

    if (index != -1) {
      updatedAllVenues[index] = updatedLocation;
    } else {
      updatedAllVenues.add(updatedLocation);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> locationsJson = updatedAllVenues.map((loc) => jsonEncode(loc.toJson())).toList();
      await prefs.setStringList(_keySavedLocations, locationsJson);
      globalRefreshNotifier.notify();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${updatedLocation.name} saved!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving venue: $e'), backgroundColor: Colors.red));
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

  void _showEmbedCodeDialog() {
    // Use _allGigs to export all future occurrences of public gigs
    final publicGigs = _allGigs.where((gig) {
      final sourceVenue = _allKnownVenues.firstWhere(
            (v) => v.placeId == gig.placeId,
        orElse: () => StoredLocation(placeId: '', name: '', address: '', coordinates: const LatLng(0,0)),
      );
      return !sourceVenue.isPrivate;
    }).toList();
    final String embedCode = GigEmbedService.generateEmbedCode(publicGigs);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Embed Gigs on Your Website'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Copy the HTML code below and paste it into your website editor. This will display a list of your upcoming public gigs.',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.grey[200],
                  child: SelectableText(
                    embedCode,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.black),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Copy to Clipboard'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: embedCode));
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Embed code copied to clipboard!'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
            ),
            TextButton(
              child: const Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
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
              // <<< --- REFACTORING: REPLACE THE OLD METHOD CALL WITH THE NEW WIDGET --- >>>
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
    bool hasUpcomingGigs = _displayedGigs.any((gig) => !gig.isJamOpenMic && gig.dateTime.isAfter(DateTime.now()));

    if (_isLoadingGigs && _displayedGigs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_isLoadingGigs && _displayedGigs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Wrap(
                spacing: 8.0, runSpacing: 8.0, alignment: WrapAlignment.center,
                children: [ _buildGigsViewToggle(), ],
              ),
            ),
            const Expanded(child: Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text('No upcoming gigs or jam nights scheduled.\nBook a gig or set up a jam night for a venue!', textAlign: TextAlign.center)))),
          ],
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8.0, left: 8.0, right: 8.0, bottom: 8.0),
          child: Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildGigsViewToggle(),
              if (hasUpcomingGigs)
                OutlinedButton.icon(
                  icon: const Icon(Icons.code, size: 18),
                  label: const Text('Export Gigs'),
                  onPressed: _showEmbedCodeDialog,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Theme.of(context).colorScheme.primary),
                  ),
                ),
            ],
          ),
        ),
        if (_isLoadingGigs && _displayedGigs.isNotEmpty)
          const Padding(padding: EdgeInsets.all(8.0), child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)))),
        Expanded(child: _gigsViewType == GigsViewType.list ? _buildGigsListView() : _buildGigsCalendarView()),
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
        ButtonSegment<GigsViewType>(value: GigsViewType.list, label: Text('List'), icon: Icon(Icons.list)),
        ButtonSegment<GigsViewType>(value: GigsViewType.calendar, label: Text('Calendar'), icon: Icon(Icons.calendar_today)),
      ],
      selected: <GigsViewType>{_gigsViewType},
      onSelectionChanged: (Set<GigsViewType> newSelection) { if (!mounted) return; setState(() { _gigsViewType = newSelection.first; }); },
    );
  }

  // lib/features/gigs/views/gigs.dart -> inside _GigsPageState

  Widget _buildGigsListView() {
    if (_displayedGigs.isEmpty) {
      return const Center(
          child: Text('No gigs or jam nights to display.', textAlign: TextAlign.center));
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
        final averagePayPerHour = (gigCount > 0) ? sumOfTrueHourlyRates / gigCount : 0.0;

        // Add the separator with the CORRECT totals.
        listItems.add(MonthlySeparator(
          month: month,
          gigCount: gigCount,
          totalPay: totalPay,
          averagePayPerHour: averagePayPerHour,
        ));

        // Add the gigs for this month, ensuring they are sorted chronologically.
        gigsInMonth.sort((a, b) => a.dateTime.compareTo(b.dateTime));
        listItems.addAll(gigsInMonth);
      });

    // 3. Build the ListView.
    // The rest of this method remains the same as it correctly renders the items.
    return ListView.builder(
      controller: _scrollController,
      itemCount: listItems.length,
      itemBuilder: (context, index) {
        final item = listItems[index];

        // --- RENDER SEPARATOR ---
        if (item is MonthlySeparator) {
          if (item.gigCount == 0) return const SizedBox.shrink();

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            margin: const EdgeInsets.only(top: 16, left: 8, right: 8),
            decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: Theme.of(context).primaryColor.withOpacity(0.2))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat.yMMMM().format(item.month),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Theme.of(context).primaryColorLight,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${item.gigCount} Gigs'),
                    Text(
                      '\$${item.totalPay.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text('Avg. \$${item.averagePayPerHour.toStringAsFixed(2)}/hr'),
                  ],
                ),
              ],
            ),
          );
        }

        // --- RENDER GIG TILE (existing logic) ---
        if (item is Gig) {
          final gig = item;
          bool isPast;
          DateTime gigEndTime = gig.dateTime
              .add(Duration(minutes: (gig.gigLengthHours * 60).toInt()));
          isPast = gigEndTime.isBefore(DateTime.now());

          bool isJam = gig.isJamOpenMic;
          final bool hasSetlist = gig.setlistId?.isNotEmpty ?? false;

          final bool hasNotes = (gig.notes?.isNotEmpty ?? false) ||
              (gig.notesUrl?.isNotEmpty ?? false) ||
              hasSetlist;
          final bool isRecurringGig = gig.isRecurring || gig.isFromRecurring;

          return Card(
            elevation: isPast ? 0.5 : (isJam ? 1.5 : 2),
            color: isPast
                ? Colors.grey.shade300
                : (isJam
                ? Theme.of(context)
                .colorScheme
                .secondaryContainer
                .withOpacity(0.7)
                : Theme.of(context).cardColor),
            margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: isJam
                    ? Theme.of(context).colorScheme.tertiary
                    : (isPast
                    ? Colors.grey.shade400
                    : Theme.of(context).colorScheme.primary),
                foregroundColor: isJam
                    ? Theme.of(context).colorScheme.onTertiary
                    : Colors.white,
                child: isJam
                    ? const Icon(Icons.music_note, size: 20)
                    : Text(DateFormat('d').format(gig.dateTime)),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      gig.venueName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isPast
                            ? Colors.grey.shade700
                            : (isJam
                            ? Theme.of(context).colorScheme.onSecondaryContainer
                            : Theme.of(context).textTheme.titleLarge?.color),
                      ),
                    ),
                  ),
                  if (isRecurringGig && !isJam)
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: Icon(
                        Icons.event_repeat,
                        size: 16,
                        color: isPast
                            ? Colors.grey.shade600
                            : Theme.of(context).colorScheme.secondary,
                        semanticLabel: "Recurring Gig",
                      ),
                    ),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${DateFormat.yMMMEd().format(gig.dateTime)} at ${DateFormat.jm().format(gig.dateTime)}',
                    style: TextStyle(
                        color: isPast
                            ? Colors.grey.shade600
                            : (isJam
                            ? Theme.of(context)
                            .colorScheme
                            .onSecondaryContainer
                            .withOpacity(0.8)
                            : Theme.of(context).textTheme.bodyMedium?.color)),
                  ),
                  if (!isJam)
                    Text(
                      'Pay: \$${gig.pay.toStringAsFixed(0)} - ${gig.gigLengthHours.toStringAsFixed(1)} hrs',
                      style: TextStyle(
                          color: isPast
                              ? Colors.grey.shade600
                              : Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.color
                              ?.withOpacity(0.9)),
                    )
                  else
                    const Text(
                      "Open Mic / Jam Session",
                      style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
                    ),
                ],
              ),
              trailing: isJam
                  ? null
                  : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Show "Review" badge for past unreviewed gigs
                  if (isPast && !(gig.retrospectiveCompleted ?? false))
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Review',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ),
                  IconButton(
                    icon: Icon(
                      hasNotes
                          ? Icons.speaker_notes
                          : Icons.speaker_notes_off_outlined,
                      color: hasNotes
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey,
                    ),
                    onPressed: () => _launchNotesPageForGig(gig),
                    tooltip: 'View/Edit Notes',
                  ),
                ],
              ),
              onTap: () => _launchBookingDialogForGig(gig),
            ),
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
    return Column(children: [
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
                color: Theme.of(context).colorScheme.primaryContainer.withAlpha(128),
                shape: BoxShape.circle),
            todayTextStyle: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer),
            selectedDecoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle),
            selectedTextStyle: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
            markerDecoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondary,
              shape: BoxShape.circle,
            ),
          ),
          daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold),
              weekendStyle: TextStyle(color: Colors.red.shade600, fontWeight: FontWeight.bold)),
          headerStyle: HeaderStyle(
            titleTextStyle: const TextStyle(
                color: Colors.black87, fontSize: 17.0, fontWeight: FontWeight.bold),
            formatButtonVisible: true,
            titleCentered: true,
            formatButtonShowsNext: false,
            formatButtonTextStyle: TextStyle(color: Theme.of(context).colorScheme.primary),
            formatButtonDecoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.primary),
                borderRadius: BorderRadius.circular(12.0)),
            leftChevronIcon: Icon(Icons.chevron_left, color: Colors.black54),
            rightChevronIcon: Icon(Icons.chevron_right, color: Colors.black54),
          ),
          onDaySelected: _onDaySelected,
          onFormatChanged: (format) {
            if (_calendarFormat != format) {
              if (!mounted) return;
              setState(() { _calendarFormat = format; });
            }
          },
          onPageChanged: (focusedDay) {
            if (!mounted) return;
            setState(() { _focusedDay = focusedDay; });
            _onDaySelected(focusedDay, focusedDay);
          },
          calendarBuilders: CalendarBuilders<Gig>(
            markerBuilder: (context, date, events) {
              if (events.isEmpty) return null;

              final List<Gig> gigEvents = events.cast<Gig>();
              bool hasActualGig = gigEvents.any((gig) => !gig.isJamOpenMic && !gig.isRecurring); // One-off gig
              bool hasRecurringGig = gigEvents.any((gig) => !gig.isJamOpenMic && gig.isRecurring); // Recurring gig instance
              bool hasJam = gigEvents.any((gig) => gig.isJamOpenMic);
              List<Widget> markers = [];
              if (hasActualGig) {
                markers.add(_buildEventsMarker(Theme.of(context).colorScheme.secondary));
              }
              if (hasRecurringGig) {
                if (markers.isNotEmpty) markers.add(const SizedBox(width: 2));
                markers.add(_buildEventsMarker(Colors.blue)); // Dot for recurring gigs
              }
              if (hasJam) {
                if (markers.isNotEmpty) markers.add(const SizedBox(width: 2));
                markers.add(_buildEventsMarker(Theme.of(context).colorScheme.tertiary)); // Dot for jam sessions
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
            bool isPast;
            DateTime gigEndTime = gig.dateTime.add(Duration(minutes: (gig.gigLengthHours * 60).toInt()));
            isPast = gigEndTime.isBefore(DateTime.now());
            bool isJam = gig.isJamOpenMic;

            // --- ADDED: Check for notes and retrospective status ---
            final bool hasSetlist = gig.setlistId?.isNotEmpty ?? false;
            final bool hasNotes = (gig.notes?.isNotEmpty ?? false) ||
                (gig.notesUrl?.isNotEmpty ?? false) ||
                hasSetlist;
            final bool needsReview = isPast &&
                !isJam &&
                !(gig.retrospectiveCompleted ?? false);
            // --- END ADDED ---

            return Card(
              elevation: isPast ? 0.5 : (isJam ? 1.0 : 1.5),
              color: isPast
                  ? Colors.grey.shade300
                  : (isJam
                  ? Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.6)
                  : Colors.white),
              margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
              child: ListTile(
                leading: isJam
                    ? Icon(Icons.music_note, color: isPast ? Colors.grey.shade500 : Theme.of(context).colorScheme.tertiary)
                    : Icon(Icons.event, color: isPast ? Colors.grey.shade500 : Theme.of(context).colorScheme.primary),
                title: Text(
                  gig.venueName,
                  style: TextStyle(fontWeight: FontWeight.bold, color: isPast ? Colors.grey.shade600 : Colors.black87),
                ),
                subtitle: Text(
                  isJam ? '${DateFormat.jm().format(gig.dateTime)} - Jam/Open Mic' : '${DateFormat.jm().format(gig.dateTime)} - \$${gig.pay.toStringAsFixed(0)}',
                  style: TextStyle(color: isPast ? Colors.grey.shade500 : Colors.black54),
                ),
                // --- ADDED: Trailing with notes icon and review badge ---
                trailing: isJam ? null : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Show "Review" badge for past unreviewed gigs
                    if (needsReview)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Review',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade800,
                          ),
                        ),
                      ),
                    IconButton(
                      icon: Icon(
                        hasNotes ? Icons.speaker_notes : Icons.speaker_notes_off_outlined,
                        color: hasNotes
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                      ),
                      onPressed: () => _launchNotesPageForGig(gig),
                      tooltip: 'View/Edit Notes',
                    ),
                  ],
                ),
                // --- END ADDED ---
                onTap: () => _launchBookingDialogForGig(gig),
              ),
            );
          },
        )
            : Center(
          child: Text(
            _selectedDay != null ? 'No events for ${DateFormat.yMMMEd().format(_selectedDay!)}.' : 'Select a day to see events.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    ]);
  }

  Widget _buildEventsMarker(Color markerColor) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: markerColor,
      ),
      width: 7.0,
      height: 7.0,
      margin: const EdgeInsets.symmetric(horizontal: 0.5),
    );
  }

}