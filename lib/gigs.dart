// lib/gigs.dart
import 'dart:collection'; // For LinkedHashMap (used by TableCalendar for events)
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart'; // Import TableCalendar
import 'package:the_money_gigs/global_refresh_notifier.dart'; // Import the notifier
import 'package:url_launcher/url_launcher.dart';

// Import your models
import 'gig_model.dart';    // For Gigs (ensure isJamOpenMic exists)
import 'venue_model.dart'; // For StoredLocation and DayOfWeek enum
import 'booking_dialog.dart'; // Make sure this is imported
import 'jam_open_mic_dialog.dart'; // <<<--- ADD THIS IMPORT

// Enum for Gigs view type
enum GigsViewType { list, calendar }

class GigsPage extends StatefulWidget {
  const GigsPage({super.key});

  @override
  State<GigsPage> createState() => _GigsPageState();
}

class _GigsPageState extends State<GigsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Gig> _loadedGigs = [];
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _selectedDay = _focusedDay;
    _tabController.addListener(_handleTabSelection);
    _loadAllDataForGigsPage(); // This will call _loadVenues first, then _loadGigs
    globalRefreshNotifier.addListener(_handleGlobalRefresh);
  }

  void _handleGlobalRefresh() {
    if (mounted) {
      _loadAllDataForGigsPage();
    }
  }

  Future<void> _loadAllDataForGigsPage() async {
    // It's important to load venues first, as _loadGigs might depend on _allKnownVenues for jam nights
    await _loadVenues(); // Wait for venues to be loaded
    await _loadGigs();   // Then load gigs
  }


  void _handleTabSelection() {
    if (_tabController.indexIsChanging ||
        (_tabController.animation != null && _tabController.animation!.value != _tabController.index.toDouble())) {
      return;
    }
    if (mounted) {
      if (_tabController.index == 0) {
        // Gigs tab selected - _loadGigs would have been called by _loadAllData or refresh
      } else if (_tabController.index == 1) {
        // Venues tab selected - _loadVenues would have been called by _loadAllData or refresh
        // No specific action needed here if data is already loaded and up-to-date
      }
    }
  }

  @override
  void dispose() {
    globalRefreshNotifier.removeListener(_handleGlobalRefresh);
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadGigs() async {
    if (!mounted) return;
    setState(() { _isLoadingGigs = true; });
    final prefs = await SharedPreferences.getInstance();
    final String? gigsJsonString = prefs.getString(_keyGigsList);
    List<Gig> actualGigs = [];
    if (gigsJsonString != null && gigsJsonString.isNotEmpty) {
      try {
        actualGigs = Gig.decode(gigsJsonString);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading actual gigs: $e')));
      }
    }

    List<Gig> jamOpenMicGigs = _generateJamOpenMicGigs();
    List<Gig> allDisplayGigs = [...actualGigs, ...jamOpenMicGigs];
    allDisplayGigs.sort((a, b) => a.dateTime.compareTo(b.dateTime));

    if (mounted) {
      setState(() {
        _loadedGigs = allDisplayGigs;
        _isLoadingGigs = false;
      });
      _prepareCalendarEvents();
      _onDaySelected(_selectedDay ?? _focusedDay, _focusedDay);
    }
  }

  List<Gig> _generateJamOpenMicGigs() {
    List<Gig> jamGigs = [];
    DateTime today = DateTime.now();
    DateTime calculationStartDate = DateTime(today.year, today.month, today.day); // Start from the beginning of today
    DateTime rangeEndDate = DateTime(today.year, today.month + 6, today.day); // Generate for next 6 months

    for (var venue in _allKnownVenues) {
      if (!venue.hasJamOpenMic || !venue.addJamToGigs || venue.jamOpenMicDay == null || venue.jamOpenMicTime == null || venue.isArchived) {
        continue;
      }

      int targetWeekday = venue.jamOpenMicDay!.index + 1; // 1=Monday, ..., 7=Sunday

      // Use a local variable for currentDate within each frequency block if necessary
      // to avoid interference if one logic path modifies it in an unexpected way for another.

      if (venue.jamFrequencyType == JamFrequencyType.weekly) {
        DateTime currentDate = calculationStartDate;
        while (currentDate.isBefore(rangeEndDate) || isSameDay(currentDate, rangeEndDate)) {
          if (currentDate.weekday == targetWeekday) {
            _addJamGigIfApplicable(jamGigs, venue, currentDate);
          }
          currentDate = currentDate.add(const Duration(days: 1));
        }
      } else if (venue.jamFrequencyType == JamFrequencyType.biWeekly) {
        DateTime firstPossibleOccurrence = _findNextDayOfWeek(calculationStartDate, targetWeekday);
        // For bi-weekly, we need an anchor. A simple way is to find the *very first* occurrence
        // of this weekday, even if it was in the past, to establish a consistent cycle.
        // This is a common approach for "every other".
        // Let's find the first valid day based on an arbitrary past date to get the cycle right.
        // A more robust system could store an explicit anchor date.
        DateTime cycleAnchorDate = _findNextDayOfWeek(DateTime(2020,1,1), targetWeekday); // Arbitrary old date

        DateTime currentTestDate = firstPossibleOccurrence;
        while (currentTestDate.isBefore(rangeEndDate) || isSameDay(currentTestDate, rangeEndDate)) {
          if (currentTestDate.weekday == targetWeekday) {
            int weeksDifference = currentTestDate.difference(cycleAnchorDate).inDays ~/ 7;
            if (weeksDifference % 2 == 0) { // Every other week relative to the anchor
              _addJamGigIfApplicable(jamGigs, venue, currentTestDate);
            }
          }
          // Increment by a week if it was a match, or by a day to find the next match
          if (currentTestDate.weekday == targetWeekday) {
            currentTestDate = currentTestDate.add(const Duration(days: 7));
          } else {
            currentTestDate = currentTestDate.add(const Duration(days: 1));
            currentTestDate = _findNextDayOfWeek(currentTestDate, targetWeekday); // Jump to next target weekday
          }
        }
      } else if (venue.jamFrequencyType == JamFrequencyType.customNthDay && venue.customNthValue != null && venue.customNthValue! > 0) {
        int nth = venue.customNthValue!;
        DateTime firstPossibleOccurrence = _findNextDayOfWeek(calculationStartDate, targetWeekday);
        DateTime cycleAnchorDate = _findNextDayOfWeek(DateTime(2020,1,1), targetWeekday); // Arbitrary old date for cycle anchor

        DateTime currentTestDate = firstPossibleOccurrence;
        while (currentTestDate.isBefore(rangeEndDate) || isSameDay(currentTestDate, rangeEndDate)) {
          if (currentTestDate.weekday == targetWeekday) {
            int weeksDifference = currentTestDate.difference(cycleAnchorDate).inDays ~/ 7;
            if (weeksDifference % nth == 0) { // Every Nth week
              _addJamGigIfApplicable(jamGigs, venue, currentTestDate);
            }
          }
          if (currentTestDate.weekday == targetWeekday) {
            currentTestDate = currentTestDate.add(const Duration(days: 7));
          } else {
            currentTestDate = currentTestDate.add(const Duration(days: 1));
            currentTestDate = _findNextDayOfWeek(currentTestDate, targetWeekday);
          }
        }
      } else if (venue.jamFrequencyType == JamFrequencyType.monthlySameDay && venue.customNthValue != null && venue.customNthValue! > 0) {
        int nthOccurrence = venue.customNthValue!;
        // Iterate through each month in the range
        DateTime monthIterator = DateTime(calculationStartDate.year, calculationStartDate.month, 1);
        while(monthIterator.isBefore(rangeEndDate) || (monthIterator.year == rangeEndDate.year && monthIterator.month == rangeEndDate.month)) {
          DateTime? nthDayInMonth = _findNthSpecificWeekdayOfMonth(monthIterator.year, monthIterator.month, targetWeekday, nthOccurrence);
          if (nthDayInMonth != null) {
            // Ensure it's not before our overall calculation start date (e.g. if today is 15th, don't add 1st Tues of this month)
            if (!nthDayInMonth.isBefore(calculationStartDate)) {
              _addJamGigIfApplicable(jamGigs, venue, nthDayInMonth);
            }
          }
          // Move to the next month
          monthIterator = DateTime(monthIterator.year, monthIterator.month + 1, 1);
        }
      }
      // Note: JamFrequencyType.monthlySameDate is still omitted for brevity
      // as it's less common for day-of-week specific jams.
    }
    return jamGigs;
  }

// Helper to add the gig if it's not in the past relative to 'today' (considering time)
  void _addJamGigIfApplicable(List<Gig> jamGigs, StoredLocation venue, DateTime dateOfJam) {
    DateTime jamDateTime = DateTime(
      dateOfJam.year,
      dateOfJam.month,
      dateOfJam.day,
      venue.jamOpenMicTime!.hour,
      venue.jamOpenMicTime!.minute,
    );

    DateTime now = DateTime.now();
    // Only add if the jam session's specific date and time is in the future,
    // or if it's today and the time hasn't passed yet.
    if (jamDateTime.isAfter(now)) {
      // Check for duplicates before adding (important if logic generates same date multiple times)
      bool alreadyExists = jamGigs.any((g) => g.placeId == venue.placeId && isSameDay(g.dateTime, jamDateTime) && g.dateTime.hour == jamDateTime.hour && g.dateTime.minute == jamDateTime.minute);
      if (!alreadyExists) {
        jamGigs.add(
          Gig(
            id: 'jam_${venue.placeId}_${DateFormat('yyyyMMddHHmm').format(jamDateTime)}_${venue.jamFrequencyType.toString().split('.').last}',
            venueName: "[JAM] ${venue.name}",
            latitude: venue.coordinates.latitude,
            longitude: venue.coordinates.longitude,
            address: venue.address,
            placeId: venue.placeId,
            dateTime: jamDateTime,
            pay: 0,
            gigLengthHours: 2,
            driveSetupTimeHours: 0,
            rehearsalLengthHours: 0,
            isJamOpenMic: true,
          ),
        );
      }
    }
  }

// Helper: Finds the next specific weekday (e.g., next Tuesday) on or after a given date
  DateTime _findNextDayOfWeek(DateTime startDate, int targetWeekday) {
    DateTime date = DateTime(startDate.year, startDate.month, startDate.day); // Normalize to start of day
    while (date.weekday != targetWeekday) {
      date = date.add(const Duration(days: 1));
    }
    return date;
  }

// Helper: Finds the Nth specific weekday of a given month and year
  DateTime? _findNthSpecificWeekdayOfMonth(int year, int month, int targetWeekday, int nth) {
    if (nth < 1 || nth > 5) return null;

    DateTime firstDayOfMonth = DateTime(year, month, 1);
    int occurrences = 0;

    for (int day = 1; day <= DateTime(year, month + 1, 0).day; day++) {
      DateTime currentDate = DateTime(year, month, day);
      if (currentDate.weekday == targetWeekday) {
        occurrences++;
        if (occurrences == nth) {
          return currentDate;
        }
      }
    }
    return null; // Nth occurrence not found
  }


  void _prepareCalendarEvents() {
    final events = LinkedHashMap<DateTime, List<Gig>>(equals: isSameDay, hashCode: getHashCode);
    for (var gig in _loadedGigs) {
      final date = DateTime.utc(gig.dateTime.year, gig.dateTime.month, gig.dateTime.day);
      events.putIfAbsent(date, () => []).add(gig);
    }
    if (mounted) setState(() { _calendarEvents = events; });
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
        _focusedDay = focusedDay; // Keep focusedDay in sync if selecting from calendar
        _selectedDayGigs = _getEventsForDay(selectedDay);
      });
    } else {
      // If the same day is clicked again, ensure the list is still correct (e.g., if underlying data changed)
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
            return null; // Skip problematic venue
          }
        }).whereType<StoredLocation>().toList(); // Filter out nulls
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

  Future<void> _deleteGig(Gig gigToDelete) async {
    // Prevent deleting auto-generated Jam/Open Mic gigs this way
    if (gigToDelete.isJamOpenMic) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Jam/Open Mic nights are managed via Venue Settings.'), backgroundColor: Colors.blueAccent),
      );
      return;
    }

    if (!mounted) return;

    final List<Gig> updatedGigs = List.from(_loadedGigs)..removeWhere((gig) => gig.id == gigToDelete.id && !gig.isJamOpenMic);

    final prefs = await SharedPreferences.getInstance();
    // Encode only actual gigs, not the dynamically generated jam gigs
    await prefs.setString(_keyGigsList, Gig.encode(updatedGigs.where((g) => !g.isJamOpenMic).toList()));


    if (mounted) {
      setState(() {
        _loadedGigs = updatedGigs; // This list will be rebuilt with jams in the next _loadGigs or UI update
        _prepareCalendarEvents();
        _onDaySelected(_selectedDay ?? _focusedDay, _focusedDay);
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gig "${gigToDelete.venueName}" cancelled.'), backgroundColor: Colors.orange));
      _loadGigs(); // To correctly rebuild the list including Jams
    }
  }

  Future<void> _launchBookingDialogForGig(Gig gigToEdit) async {
    if (gigToEdit.isJamOpenMic) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Jam/Open Mic details are viewed via Venue Settings.'), backgroundColor: Colors.blueAccent),
      );
      // Optionally, you could find the venue and open _showVenueDetailsDialog(venue)
      final venue = _allKnownVenues.firstWhere((v) => v.placeId == gigToEdit.placeId, orElse: () => StoredLocation(placeId: '', name: '', address: '', coordinates: const LatLng(0,0)));
      if (venue.placeId.isNotEmpty) {
        _showVenueDetailsDialog(venue);
      }
      return;
    }
    if (!mounted) return;

    const String googleApiKey = String.fromEnvironment('GOOGLE_API_KEY');

    final result = await showDialog<dynamic>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        // Find the original venue from _allKnownVenues to get its most up-to-date 'isArchived' status
        StoredLocation? completeVenueDetails;
        try {
          completeVenueDetails = _allKnownVenues.firstWhere(
                (v) => (gigToEdit.placeId != null && v.placeId == gigToEdit.placeId) || (v.name == gigToEdit.venueName && v.address == gigToEdit.address),
          );
        } catch (e) {
          // Fallback if not found in _allKnownVenues (e.g. venue was deleted externally but gig still exists)
          completeVenueDetails = StoredLocation(
            name: gigToEdit.venueName,
            address: gigToEdit.address,
            coordinates: LatLng(gigToEdit.latitude, gigToEdit.longitude),
            placeId: gigToEdit.placeId ?? 'edited_${gigToEdit.id}',
            isArchived: true, // Assume archived if not found, to be safe
            // Ensure all fields from your StoredLocation are here if needed by BookingDialog's preselectedVenue
            hasJamOpenMic: false, // Default
            addJamToGigs: false,  // Default
          );
        }


        return BookingDialog(
          editingGig: gigToEdit,
          preselectedVenue: completeVenueDetails, // Pass the full StoredLocation object
          googleApiKey: googleApiKey,
          existingGigs: _loadedGigs.where((g) => !g.isJamOpenMic && g.id != gigToEdit.id).toList(), // Exclude jam gigs & self
        );
      },
    );

    bool needsUIRefresh = false;

    if (result is GigEditResult) {
      if (result.action == GigEditResultAction.updated && result.gig != null) {
        final updatedGig = result.gig!;
        // Update _loadedGigs (which contains actual gigs and jam gigs)
        // We only want to update the 'actual' gig part.
        final List<Gig> currentActualGigs = _loadedGigs.where((g) => !g.isJamOpenMic).toList();
        final int gigIndex = currentActualGigs.indexWhere((g) => g.id == updatedGig.id);

        if (gigIndex != -1) {
          currentActualGigs[gigIndex] = updatedGig;

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_keyGigsList, Gig.encode(currentActualGigs)); // Save only actual gigs

          if (mounted) {
            // Reload all gigs to reconstruct the list with updated actual gigs and existing jam gigs
            await _loadGigs(); // This will re-sort and call prepareCalendarEvents etc.
            needsUIRefresh = true; // For global notifier
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Gig "${updatedGig.venueName}" updated.'), backgroundColor: Colors.green),
            );
          }
        }
      } else if (result.action == GigEditResultAction.deleted && result.gig != null) {
        await _deleteGig(result.gig!); // _deleteGig already handles SharedPreferences and setState for _loadedGigs
        needsUIRefresh = true;
      }
    } else if (result is Gig) { // New gig created
      List<Gig> currentActualGigs = _loadedGigs.where((g) => !g.isJamOpenMic).toList();
      currentActualGigs.add(result);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyGigsList, Gig.encode(currentActualGigs));

      if (mounted) {
        await _loadGigs(); // Reload all gigs
        needsUIRefresh = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('New gig "${result.venueName}" booked.'), backgroundColor: Colors.green),
        );
      }
    }

    if (needsUIRefresh && mounted) {
      globalRefreshNotifier.notify();
    }
  }


  Future<void> _archiveVenue(StoredLocation venueToArchive) async {
    if (!mounted) return;

    // Filter out jam session placeholder gigs before counting
    List<Gig> upcomingActualGigsAtVenue = _getGigsForVenue(venueToArchive, futureOnly: true)
        .where((gig) => !gig.isJamOpenMic)
        .toList();
    String dialogMessage = 'Are you sure you want to archive "${venueToArchive.name}"?';
    if (upcomingActualGigsAtVenue.isNotEmpty) {
      dialogMessage += '\n\nThis will also DELETE ${upcomingActualGigsAtVenue.length} upcoming actual gig(s) scheduled here.';
    } else {
      dialogMessage += '\nIt will be hidden from lists but not permanently deleted. Jam night settings will be preserved but not shown for archived venues.';
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
                child: Text('ARCHIVE & DELETE GIGS', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                onPressed: () => Navigator.of(dialogContext).pop(true)),
          ],
        );
      },
    ) ?? false;

    if (confirmArchive) {
      setState(() { _isLoadingVenues = true; _isLoadingGigs = true; });
      final prefs = await SharedPreferences.getInstance();

      // 1. Delete associated actual upcoming gigs
      if (upcomingActualGigsAtVenue.isNotEmpty) {
        List<String> gigIdsToDelete = upcomingActualGigsAtVenue.map((gig) => gig.id).toList();
        List<Gig> currentAllActualGigs = _loadedGigs.where((g) => !g.isJamOpenMic).toList();
        currentAllActualGigs.removeWhere((gig) => gigIdsToDelete.contains(gig.id));
        await prefs.setString(_keyGigsList, Gig.encode(currentAllActualGigs));
      }

      // 2. Archive the venue
      int index = _allKnownVenues.indexWhere((v) => v.placeId == venueToArchive.placeId);
      if (index != -1) {
        List<StoredLocation> updatedAllVenues = List.from(_allKnownVenues);
        // Preserve jam night settings, just mark as archived
        updatedAllVenues[index] = updatedAllVenues[index].copyWith(isArchived: true);
        final List<String> updatedVenuesJson = updatedAllVenues.map((v) => jsonEncode(v.toJson())).toList();
        await prefs.setStringList(_keySavedLocations, updatedVenuesJson);
      }

      // 3. Notify and update UI (will trigger full data reload)
      globalRefreshNotifier.notify();

      if (mounted) {
        String snackbarMessage = 'Venue "${venueToArchive.name}" archived.';
        if (upcomingActualGigsAtVenue.isNotEmpty) {
          snackbarMessage += ' ${upcomingActualGigsAtVenue.length} upcoming actual gig(s) deleted.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(snackbarMessage), backgroundColor: Colors.orange),
        );
        // No need for individual setState for loading flags, globalRefresh will handle it via _loadAllData
      }
    }
  }

  // Helper method to update Jam Night settings and save the venue
  Future<void> _updateVenueJamNightSettings(StoredLocation updatedVenue) async {
    final prefs = await SharedPreferences.getInstance();
    int index = _allKnownVenues.indexWhere((v) => v.placeId == updatedVenue.placeId);

    if (index != -1) {
      List<StoredLocation> updatedAllVenuesList = List.from(_allKnownVenues);
      updatedAllVenuesList[index] = updatedVenue;

      final List<String> updatedVenuesJson = updatedAllVenuesList
          .map((v) => jsonEncode(v.toJson()))
          .toList();
      bool success = await prefs.setStringList(_keySavedLocations, updatedVenuesJson);

      if (success) {
        if (mounted) {
          // Update local state immediately for responsiveness
          setState(() {
            _allKnownVenues = updatedAllVenuesList;
            _displayableVenues = _allKnownVenues.where((venue) => !venue.isArchived).toList();
          });
          // Reload gigs as jam night settings might affect the displayed gig list
          await _loadGigs();
          globalRefreshNotifier.notify(); // Notify other parts of the app if necessary

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Jam/Open Mic settings updated for ${updatedVenue.name}.'), backgroundColor: Colors.green),
          );
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save Jam Night settings for ${updatedVenue.name}.'), backgroundColor: Colors.red));
      }
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: Could not find venue to update jam settings.'), backgroundColor: Colors.red));
    }
  }


  List<Gig> _getGigsForVenue(StoredLocation venue, {bool futureOnly = false}) {
    DateTime comparisonDate = DateTime.now();
    return _loadedGigs.where((gig) {
      // Match by placeId if available, otherwise by name (more robust to have placeId)
      bool venueMatch = (gig.placeId != null && gig.placeId!.isNotEmpty && gig.placeId == venue.placeId) ||
          (gig.placeId == null && gig.venueName.toLowerCase() == venue.name.toLowerCase());

      bool dateMatch = true;
      if (futureOnly) {
        // For futureOnly, compare the start of the gig day with the start of today
        DateTime gigDayStart = DateTime(gig.dateTime.year, gig.dateTime.month, gig.dateTime.day);
        DateTime todayStart = DateTime(comparisonDate.year, comparisonDate.month, comparisonDate.day);
        dateMatch = gigDayStart.isAfter(todayStart) || gigDayStart.isAtSameMomentAs(todayStart);
      }
      return venueMatch && dateMatch;
    }).toList();
  }


  Future<void> _showVenueDetailsDialog(StoredLocation venue) async {
    if (!mounted) return;

    List<Gig> upcomingGigsAtVenue = _getGigsForVenue(venue, futureOnly: true)
        .where((g) => !g.isJamOpenMic) // Exclude placeholder jams
        .toList();
    upcomingGigsAtVenue.sort((a,b) => a.dateTime.compareTo(b.dateTime));
    Gig? nextUpcomingGig = upcomingGigsAtVenue.isNotEmpty ? upcomingGigsAtVenue.first : null;

    String jamDisplay = "Not set up";
    if (venue.hasJamOpenMic && venue.jamOpenMicDay != null && venue.jamOpenMicTime != null) {
      // Use the model's helper if available and pass context
      // For simplicity here, directly formatting. Ensure `intl` is imported.
      jamDisplay = "${toBeginningOfSentenceCase(venue.jamOpenMicDay.toString().split('.').last)} at ${venue.jamOpenMicTime!.format(context)}";
      if (venue.addJamToGigs) {
        jamDisplay += " (shown in gigs)";
      }
    }

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(venue.name),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text("Address: ${venue.address.isNotEmpty ? venue.address : 'Not specified'}"),
                const SizedBox(height: 8),
                if (venue.rating > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Row(children: [
                      const Text("Rating: "),
                      Icon(Icons.star, color: Colors.amber, size: 20),
                      const SizedBox(width: 4),
                      Text('${venue.rating.toStringAsFixed(1)} / 5.0'),
                    ]),
                  ),
                if (venue.comment != null && venue.comment!.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 4.0), child: Text("Comment: ${venue.comment!}")),
                const Divider(height: 20, thickness: 1),

                // --- JAM/OPEN MIC SECTION ---
                const Text('Jam/Open Mic:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(jamDisplay),
                Padding(
                  padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
                  child: TextButton(
                    child: const Text('Edit Jam/Open Mic Settings'),
                    onPressed: () async {
                      Navigator.of(dialogContext).pop(); // Close details dialog first
                      final result = await showDialog<JamOpenMicDialogResult>(
                        context: context, // Use the page's context for the new dialog
                        builder: (_) => JamOpenMicDialog(venue: venue),
                      );
                      if (result != null && result.settingsChanged && result.updatedVenue != null) {
                        await _updateVenueJamNightSettings(result.updatedVenue!);
                      }
                    },
                  ),
                ),
                const Divider(height: 20, thickness: 1),
                // --- END JAM/OPEN MIC SECTION ---

                if (nextUpcomingGig != null) ...[
                  const Text('Next Actual Gig Here:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4.0),
                  Text(
                    '${DateFormat.MMMEd().format(nextUpcomingGig.dateTime)} at ${DateFormat.jm().format(nextUpcomingGig.dateTime)}',
                    style: Theme.of(dialogContext).textTheme.bodyMedium,
                  ),
                ] else ...[
                  const Text("No upcoming actual gigs scheduled here.", style: TextStyle(fontStyle: FontStyle.italic)),
                ],
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Open in Maps'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(dialogContext).colorScheme.secondary,
                    foregroundColor: Theme.of(dialogContext).colorScheme.onSecondary,
                  ),
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    await _openVenueInMap(venue);
                  },
                ),
              ],
            ),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: <Widget>[
            TextButton(
              child: Text('ARCHIVE', style: TextStyle(color: Theme.of(dialogContext).colorScheme.error)),
              onPressed: () { Navigator.of(dialogContext).pop(); _archiveVenue(venue); },
            ),
            TextButton(child: const Text('Close'), onPressed: () => Navigator.of(dialogContext).pop()),
          ],
        );
      },
    );
  }

  Future<void> _openVenueInMap(StoredLocation venue) async {
    // ... (no changes here)
    final lat = venue.coordinates.latitude;
    final lng = venue.coordinates.longitude;
    final String query = Uri.encodeComponent(venue.address.isNotEmpty ? venue.address : venue.name);
    Uri mapUri = Uri.parse('https://maps.google.com/maps?q=$query&ll=$lat,$lng');

    if (await canLaunchUrl(mapUri)) {
      await launchUrl(mapUri, mode: LaunchMode.externalApplication);
    } else {
      Uri fallbackMapUri = Uri.parse('https://maps.google.com/maps?q=$lat,$lng');
      if (await canLaunchUrl(fallbackMapUri)) {
        await launchUrl(fallbackMapUri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open map application.')),
          );
        }
        print('Could not launch $mapUri or $fallbackMapUri');
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    // ... (no changes to overall structure)
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
              _buildVenuesList(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGigsTabContent() {
    // ... (no significant changes, but _loadedGigs now contains jam gigs)
    if (_isLoadingGigs && _loadedGigs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    // ... (rest of the method)
    if (!_isLoadingGigs && _loadedGigs.isEmpty) {
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
            spacing: 8.0, runSpacing: 8.0, alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center,
            children: [ _buildGigsViewToggle(), ],
          ),
        ),
        if (_isLoadingGigs && _loadedGigs.isNotEmpty)
          const Padding(padding: EdgeInsets.all(8.0), child: Center(child: SizedBox(width:24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)))),
        Expanded(child: _gigsViewType == GigsViewType.list ? _buildGigsListView() : _buildGigsCalendarView()),
      ],
    );
  }

  Widget _buildGigsViewToggle() {
    // ... (no changes here)
    return SegmentedButton<GigsViewType>(
      segments: const <ButtonSegment<GigsViewType>>[
        ButtonSegment<GigsViewType>(value: GigsViewType.list, label: Text('List'), icon: Icon(Icons.list)),
        ButtonSegment<GigsViewType>(value: GigsViewType.calendar, label: Text('Calendar'), icon: Icon(Icons.calendar_today)),
      ],
      selected: <GigsViewType>{_gigsViewType},
      onSelectionChanged: (Set<GigsViewType> newSelection) { if (!mounted) return; setState(() { _gigsViewType = newSelection.first; }); },
    );
  }

  Widget _buildGigsListView() {
    if (_loadedGigs.isEmpty) return const Center(child: Text('No gigs or jam nights to display.', textAlign: TextAlign.center));
    return ListView.builder(
      itemCount: _loadedGigs.length,
      itemBuilder: (context, index) {
        final gig = _loadedGigs[index];
        bool isPast = gig.dateTime.isBefore(DateTime.now().subtract(const Duration(hours:1))); // Check if gig END time is past
        if (!gig.isJamOpenMic) { // For actual gigs, check if end time is past
          DateTime gigEndTime = gig.dateTime.add(Duration(minutes: (gig.gigLengthHours * 60).toInt()));
          isPast = gigEndTime.isBefore(DateTime.now());
        } else { // For Jams, just check if the start time is past (as they might not have a defined end for this check)
          isPast = gig.dateTime.isBefore(DateTime.now());
        }

        bool isJam = gig.isJamOpenMic;

        return Card(
          elevation: isPast ? 0.5 : (isJam ? 1.5 : 2),
          color: isPast ? Colors.grey.shade300 : (isJam ? Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.7) : Theme.of(context).cardColor),
          margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isJam ? Theme.of(context).colorScheme.tertiary : (isPast ? Colors.grey.shade400 : Theme.of(context).colorScheme.primary),
              foregroundColor: isJam? Theme.of(context).colorScheme.onTertiary : Colors.white,
              child: isJam ? const Icon(Icons.music_note, size: 20) : Text(DateFormat('d').format(gig.dateTime)),
            ),
            title: Text(
              gig.venueName, // Already prefixed with [JAM] if it's a jam gig
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isPast ? Colors.grey.shade700 : (isJam ? Theme.of(context).colorScheme.onSecondaryContainer : Theme.of(context).textTheme.titleLarge?.color),
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${DateFormat.yMMMEd().format(gig.dateTime)} at ${DateFormat.jm().format(gig.dateTime)}',
                  style: TextStyle(color: isPast ? Colors.grey.shade600 : (isJam ? Theme.of(context).colorScheme.onSecondaryContainer.withOpacity(0.8) : Theme.of(context).textTheme.bodyMedium?.color)),
                ),
                if (!isJam)
                  Text(
                    'Pay: \$${gig.pay.toStringAsFixed(0)} - ${gig.gigLengthHours.toStringAsFixed(1)} hrs',
                    style: TextStyle(color: isPast ? Colors.grey.shade600 : Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.9)),
                  )
                else
                  Text(
                    "Open Mic / Jam Session",
                    style: TextStyle(fontStyle: FontStyle.italic, color: isPast ? Colors.grey.shade600 : Theme.of(context).colorScheme.onSecondaryContainer.withOpacity(0.8)),
                  ),
                if (gig.address.isNotEmpty)
                  Text(
                    gig.address,
                    style: TextStyle(fontSize: 12, color: isPast ? Colors.grey.shade500 : (isJam ? Theme.of(context).colorScheme.onSecondaryContainer.withOpacity(0.7) : Colors.grey.shade600)),
                  ),
              ],
            ),
            isThreeLine: true,
            onTap: () => _launchBookingDialogForGig(gig), // Will show venue details for jam nights
          ),
        );
      },
    );
  }


// In gigs.dart, inside _GigsPageState

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
          // Remove markerBuilder from here
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
            // Default marker decoration (can be overridden by calendarBuilders)
            markerDecoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondary, // Fallback color
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
            _onDaySelected(focusedDay, focusedDay); // Also update selected day gigs on page change
          },
          // --- ADD calendarBuilders HERE ---
          calendarBuilders: CalendarBuilders<Gig>(
            markerBuilder: (context, date, events) {
              if (events.isEmpty) return null;

              final List<Gig> gigEvents = events.cast<Gig>();
              bool hasActualGig = gigEvents.any((gig) => !gig.isJamOpenMic);
              bool hasJam = gigEvents.any((gig) => gig.isJamOpenMic);

              List<Widget> markers = [];

              if (hasActualGig) {
                markers.add(
                  _buildEventsMarker( // Your existing helper for creating the marker widget
                    Theme.of(context).colorScheme.secondary, // Color for actual gigs
                  ),
                );
              }
              if (hasJam) {
                // Add some spacing if both types of markers are present
                if (markers.isNotEmpty) markers.add(SizedBox(width: markers.length * 1.5));
                markers.add(
                  _buildEventsMarker(
                    Theme.of(context).colorScheme.tertiary, // Different color for jams
                  ),
                );
              }

              if (markers.isEmpty) return null;

              // Use a Row to display multiple markers side-by-side
              return Positioned(
                bottom: 1, // Adjust as needed
                // Center the row of markers if you prefer
                // left: 0,
                // right: 0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: markers,
                ),
              );
            },
            // You might also need/want to customize other builders like:
            // singleMarkerBuilder, multiMarkerBuilder, defaultMarkerBuilder
            // depending on your table_calendar version and desired behavior.
            // The 'markerBuilder' is often a good general-purpose one.
          ),
        ),
      ),
      Expanded(
        child: _selectedDayGigs.isNotEmpty
            ? ListView.builder(
          itemCount: _selectedDayGigs.length,
          itemBuilder: (context, index) {
            final gig = _selectedDayGigs[index];
            // bool isPast = gig.dateTime.isBefore(DateTime.now().subtract(const Duration(days:1)));
            bool isPast;
            if (!gig.isJamOpenMic) {
              DateTime gigEndTime = gig.dateTime.add(Duration(minutes: (gig.gigLengthHours * 60).toInt()));
              isPast = gigEndTime.isBefore(DateTime.now());
            } else {
              isPast = gig.dateTime.isBefore(DateTime.now());
            }
            bool isJam = gig.isJamOpenMic;

            return Card(
              elevation: isPast ? 0.5 : (isJam ? 1.0 : 1.5),
              color: isPast
                  ? Colors.grey.shade200.withOpacity(0.7)
                  : (isJam
                  ? Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.6)
                  : Colors.white),
              margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
              child: ListTile(
                leading: isJam
                    ? Icon(Icons.music_note, color: isPast ? Colors.grey.shade500 : Theme.of(context).colorScheme.tertiary)
                    : Icon(Icons.event, color: isPast ? Colors.grey.shade500 : Theme.of(context).colorScheme.primary),
                title: Text(
                  gig.venueName, // Already prefixed with [JAM]
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isPast ? Colors.grey.shade600 : Colors.black87),
                ),
                subtitle: Text(
                  isJam
                      ? '${DateFormat.jm().format(gig.dateTime)} - Jam/Open Mic'
                      : '${DateFormat.jm().format(gig.dateTime)} - \$${gig.pay.toStringAsFixed(0)}',
                  style: TextStyle(
                      color: isPast ? Colors.grey.shade500 : Colors.black54),
                ),
                onTap: () => _launchBookingDialogForGig(gig),
              ),
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
                        : Colors.black87))),
      ),
    ]);
  }

// Helper for calendar event markers (adjust this if you removed parameters)
  Widget _buildEventsMarker(Color markerColor) { // Simplified this based on usage
    return Container( // AnimatedContainer might be overkill if not changing dynamically here
      // duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: markerColor,
      ),
      width: 7.0,
      height: 7.0,
      margin: const EdgeInsets.symmetric(horizontal: 0.5), // Add a little space between markers in a row
    );
  }

  Widget _buildVenuesList() {
    if (_isLoadingVenues && _displayableVenues.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_displayableVenues.isEmpty) {
      return const Center( /* ... existing empty message ... */ );
    }

    List<StoredLocation> sortedDisplayableVenues = List.from(_displayableVenues)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return ListView.builder(
      itemCount: sortedDisplayableVenues.length,
      itemBuilder: (context, index) {
        final venue = sortedDisplayableVenues[index];
        // Get count of *actual* future gigs for this venue
        final List<Gig> futureActualGigsForVenue = _getGigsForVenue(venue, futureOnly: true)
            .where((g) => !g.isJamOpenMic)
            .toList();
        final int futureGigsCount = futureActualGigsForVenue.length;

        String jamInfo = "";
        if (venue.hasJamOpenMic && venue.jamOpenMicDay != null && venue.jamOpenMicTime != null) {
          jamInfo = "Jam: ${toBeginningOfSentenceCase(venue.jamOpenMicDay.toString().split('.').last)} at ${venue.jamOpenMicTime!.format(context)}";
          if (venue.addJamToGigs) {
            jamInfo += " (in gigs)";
          }
        }

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: ListTile(
            leading: Icon(Icons.business, color: Theme.of(context).colorScheme.secondary),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(venue.name, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                if (futureGigsCount > 0)
                  Text(
                    ' ($futureGigsCount upcoming)',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, fontStyle: FontStyle.italic),
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(venue.address.isNotEmpty ? venue.address : 'Address not specified'),
                if (venue.rating > 0)
                  Row(children: [ /* ... rating display ... */
                    Icon(Icons.star, color: Colors.amber, size: 16), const SizedBox(width: 4), Text('${venue.rating.toStringAsFixed(1)} ★ ${venue.comment != null && venue.comment!.isNotEmpty ? "(${venue.comment})" : ""}', style: const TextStyle(fontSize: 12))
                  ])
                else if (venue.comment != null && venue.comment!.isNotEmpty)
                  Text("Comment: ${venue.comment}", style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic))
                else
                  const Text("Not yet rated or commented", style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),

                if (jamInfo.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(jamInfo, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.tertiary, fontStyle: FontStyle.italic)),
                  ),
              ],
            ),
            onTap: () => _showVenueDetailsDialog(venue),
          ),
        );
      },
    );
  }
}
