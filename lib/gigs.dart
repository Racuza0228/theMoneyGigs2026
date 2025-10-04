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
import 'gig_model.dart';
import 'venue_model.dart';
import 'booking_dialog.dart';
import 'jam_open_mic_dialog.dart';
import 'notes_page.dart';
import 'venue_contact.dart';
import 'venue_contact_dialog.dart';

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
    _loadAllDataForGigsPage();
    globalRefreshNotifier.addListener(_handleGlobalRefresh);
  }

  @override
  void dispose() {
    globalRefreshNotifier.removeListener(_handleGlobalRefresh);
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    super.dispose();
  }

  void _handleGlobalRefresh() {
    if (mounted) {
      _loadAllDataForGigsPage();
    }
  }

  Future<void> _loadAllDataForGigsPage() async {
    await _loadVenues();
    await _loadGigs();
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
    DateTime calculationStartDate = DateTime(today.year, today.month, today.day);
    DateTime rangeEndDate = DateTime(today.year, today.month + 6, today.day);

    for (var venue in _allKnownVenues) {
      if (!venue.hasJamOpenMic || !venue.addJamToGigs || venue.jamOpenMicDay == null || venue.jamOpenMicTime == null || venue.isArchived) {
        continue;
      }
      int targetWeekday = venue.jamOpenMicDay!.index + 1;
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
        DateTime cycleAnchorDate = _findNextDayOfWeek(DateTime(2020, 1, 1), targetWeekday);
        DateTime currentTestDate = firstPossibleOccurrence;
        while (currentTestDate.isBefore(rangeEndDate) || isSameDay(currentTestDate, rangeEndDate)) {
          if (currentTestDate.weekday == targetWeekday) {
            int weeksDifference = currentTestDate.difference(cycleAnchorDate).inDays ~/ 7;
            if (weeksDifference % 2 == 0) {
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
      } else if (venue.jamFrequencyType == JamFrequencyType.customNthDay && venue.customNthValue != null && venue.customNthValue! > 0) {
        int nth = venue.customNthValue!;
        DateTime firstPossibleOccurrence = _findNextDayOfWeek(calculationStartDate, targetWeekday);
        DateTime cycleAnchorDate = _findNextDayOfWeek(DateTime(2020, 1, 1), targetWeekday);
        DateTime currentTestDate = firstPossibleOccurrence;
        while (currentTestDate.isBefore(rangeEndDate) || isSameDay(currentTestDate, rangeEndDate)) {
          if (currentTestDate.weekday == targetWeekday) {
            int weeksDifference = currentTestDate.difference(cycleAnchorDate).inDays ~/ 7;
            if (weeksDifference % nth == 0) {
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
        DateTime monthIterator = DateTime(calculationStartDate.year, calculationStartDate.month, 1);
        while (monthIterator.isBefore(rangeEndDate) || (monthIterator.year == rangeEndDate.year && monthIterator.month == rangeEndDate.month)) {
          DateTime? nthDayInMonth = _findNthSpecificWeekdayOfMonth(monthIterator.year, monthIterator.month, targetWeekday, nthOccurrence);
          if (nthDayInMonth != null) {
            if (!nthDayInMonth.isBefore(calculationStartDate)) {
              _addJamGigIfApplicable(jamGigs, venue, nthDayInMonth);
            }
          }
          monthIterator = DateTime(monthIterator.year, monthIterator.month + 1, 1);
        }
      }
    }
    return jamGigs;
  }

  void _addJamGigIfApplicable(List<Gig> jamGigs, StoredLocation venue, DateTime dateOfJam) {
    DateTime jamDateTime = DateTime(
      dateOfJam.year,
      dateOfJam.month,
      dateOfJam.day,
      venue.jamOpenMicTime!.hour,
      venue.jamOpenMicTime!.minute,
    );
    DateTime now = DateTime.now();
    if (jamDateTime.isAfter(now)) {
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

  DateTime _findNextDayOfWeek(DateTime startDate, int targetWeekday) {
    DateTime date = DateTime(startDate.year, startDate.month, startDate.day);
    while (date.weekday != targetWeekday) {
      date = date.add(const Duration(days: 1));
    }
    return date;
  }

  DateTime? _findNthSpecificWeekdayOfMonth(int year, int month, int targetWeekday, int nth) {
    if (nth < 1 || nth > 5) return null;
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
    return null;
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

  void _launchNotesPageForGig(Gig gig) {
    if (gig.isJamOpenMic) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NotesPage(editingGigId: gig.id),
      ),
    );
  }

  Future<void> _launchBookingDialogForGig(Gig gigToEdit) async {
    if (gigToEdit.isJamOpenMic) {
      final sourceVenue = _allKnownVenues.firstWhere(
            (v) => v.placeId == gigToEdit.placeId,
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
                child: Text('REMOVE FROM MY GIGS', style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  await _setVenueMutedState(sourceVenue, true);
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
          editingGig: gigToEdit,
          googleApiKey: googleApiKey,
          existingGigs: _loadedGigs.where((g) => !g.isJamOpenMic).toList(),
        );
      },
    );
    if (result is GigEditResult && result.action != GigEditResultAction.noChange) {
      if (result.action == GigEditResultAction.updated && result.gig != null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gig "${result.gig!.venueName}" updated.'), backgroundColor: Colors.green));
      } else if (result.action == GigEditResultAction.deleted && result.gig != null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gig "${result.gig!.venueName}" cancelled.'), backgroundColor: Colors.orange));
      }
    } else if (result is Gig) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('New gig "${result.venueName}" booked.'), backgroundColor: Colors.green));
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

  Future<void> _deleteGig(Gig gigToDelete) async {
    if (gigToDelete.isJamOpenMic) return;
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final String? gigsJsonString = prefs.getString(_keyGigsList);
    List<Gig> currentActualGigs = (gigsJsonString != null) ? Gig.decode(gigsJsonString) : [];
    currentActualGigs.removeWhere((gig) => gig.id == gigToDelete.id);
    await prefs.setString(_keyGigsList, Gig.encode(currentActualGigs));
    globalRefreshNotifier.notify();
  }

  /// ****** CORRECTED METHOD ******
  Future<void> _archiveVenue(StoredLocation venueToArchive) async {
    if (!mounted) return;
    // CORRECTED: Only check for REAL, non-jam gigs.
    List<Gig> upcomingActualGigsAtVenue = _getGigsForVenue(venueToArchive, futureOnly: true)
        .where((gig) => !gig.isJamOpenMic)
        .toList();

    String dialogMessage = 'Are you sure you want to archive "${venueToArchive.name}"?';
    if (upcomingActualGigsAtVenue.isNotEmpty) {
      dialogMessage += '\n\nThis will also DELETE ${upcomingActualGigsAtVenue.length} upcoming actual gig(s) scheduled here.';
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
      if (upcomingActualGigsAtVenue.isNotEmpty) {
        List<String> gigIdsToDelete = upcomingActualGigsAtVenue.map((gig) => gig.id).toList();
        final String? gigsJsonString = prefs.getString(_keyGigsList);
        List<Gig> currentAllActualGigs = (gigsJsonString != null) ? Gig.decode(gigsJsonString) : [];
        currentAllActualGigs.removeWhere((gig) => gigIdsToDelete.contains(gig.id));
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
          snackbarMessage += ' ${upcomingActualGigsAtVenue.length} upcoming actual gig(s) deleted.';
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
      final List<String> updatedVenuesJson = updatedAllVenuesList.map((v) => jsonEncode(v.toJson())).toList();
      await prefs.setStringList(_keySavedLocations, updatedVenuesJson);
      if (mounted) {
        globalRefreshNotifier.notify();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Jam/Open Mic settings updated for ${updatedVenue.name}.'), backgroundColor: Colors.green),
        );
      }
    }
  }

  List<Gig> _getGigsForVenue(StoredLocation venue, {bool futureOnly = false}) {
    DateTime comparisonDate = DateTime.now();
    return _loadedGigs.where((gig) {
      bool venueMatch = (gig.placeId != null && gig.placeId!.isNotEmpty && gig.placeId == venue.placeId) ||
          (gig.placeId == null && gig.venueName.toLowerCase() == venue.name.toLowerCase());
      bool dateMatch = true;
      if (futureOnly) {
        DateTime gigDayStart = DateTime(gig.dateTime.year, gig.dateTime.month, gig.dateTime.day);
        DateTime todayStart = DateTime(comparisonDate.year, comparisonDate.month, comparisonDate.day);
        dateMatch = !gigDayStart.isBefore(todayStart);
      }
      return venueMatch && dateMatch;
    }).toList();
  }

  Future<void> _showVenueDetailsDialog(StoredLocation venue) async {
    if (!mounted) return;
    List<Gig> upcomingGigsAtVenue = _getGigsForVenue(venue, futureOnly: true)
        .where((g) => !g.isJamOpenMic)
        .toList();
    upcomingGigsAtVenue.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    Gig? nextUpcomingGig = upcomingGigsAtVenue.isNotEmpty ? upcomingGigsAtVenue.first : null;

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(venue.name),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Contact:', style: TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      iconSize: 20.0,
                      color: Theme.of(context).colorScheme.primary,
                      tooltip: 'Edit Contact Info',
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        _editVenueContact(venue);
                      },
                    )
                  ],
                ),
                if (venue.contact != null && venue.contact!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (venue.contact!.name.isNotEmpty) Text(venue.contact!.name),
                        if (venue.contact!.phone.isNotEmpty)
                          InkWell(
                            child: Text(venue.contact!.phone, style: TextStyle(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline)),
                            onTap: () => launchUrl(Uri.parse('tel:${venue.contact!.phone}')),
                          ),
                        if (venue.contact!.email.isNotEmpty)
                          InkWell(
                            child: Text(venue.contact!.email, style: TextStyle(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline)),
                            onTap: () => launchUrl(Uri.parse('mailto:${venue.contact!.email}')),
                          ),
                      ],
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(left: 8.0, bottom: 8.0),
                    child: Text('No contact saved.', style: TextStyle(fontStyle: FontStyle.italic)),
                  ),
                const Divider(height: 20, thickness: 1),
                const Text('Jam/Open Mic:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(venue.jamOpenMicDisplayString(context)),
                Padding(
                  padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
                  child: TextButton(
                    child: const Text('Edit Jam/Open Mic Settings'),
                    onPressed: () async {
                      Navigator.of(dialogContext).pop();
                      final result = await showDialog<JamOpenMicDialogResult>(
                        context: context,
                        builder: (_) => JamOpenMicDialog(venue: venue),
                      );
                      if (result != null && result.settingsChanged && result.updatedVenue != null) {
                        await _updateVenueJamNightSettings(result.updatedVenue!);
                      }
                    },
                  ),
                ),
                const Divider(height: 20, thickness: 1),
                Text("Address: ${venue.address.isNotEmpty ? venue.address : 'Not specified'}"),
                const SizedBox(height: 8),
                if (nextUpcomingGig != null) ...[
                  const SizedBox(height: 16),
                  const Text('Next Gig Here:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('${DateFormat.yMMMEd().format(nextUpcomingGig.dateTime)} at ${DateFormat.jm().format(nextUpcomingGig.dateTime)}'),
                ],
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Open in Maps'),
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
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _archiveVenue(venue);
              },
            ),
            TextButton(child: const Text('Close'), onPressed: () => Navigator.of(dialogContext).pop()),
          ],
        );
      },
    );
  }

  Future<void> _openVenueInMap(StoredLocation venue) async {
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
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open map application.')));
      }
    }
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
              _buildVenuesList(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGigsTabContent() {
    if (_isLoadingGigs && _loadedGigs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
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
          const Padding(padding: EdgeInsets.all(8.0), child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)))),
        Expanded(child: _gigsViewType == GigsViewType.list ? _buildGigsListView() : _buildGigsCalendarView()),
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

  Widget _buildGigsListView() {
    if (_loadedGigs.isEmpty) return const Center(child: Text('No gigs or jam nights to display.', textAlign: TextAlign.center));
    return ListView.builder(
      itemCount: _loadedGigs.length,
      itemBuilder: (context, index) {
        final gig = _loadedGigs[index];
        bool isPast;
        if (!gig.isJamOpenMic) {
          DateTime gigEndTime = gig.dateTime.add(Duration(minutes: (gig.gigLengthHours * 60).toInt()));
          isPast = gigEndTime.isBefore(DateTime.now());
        } else {
          isPast = gig.dateTime.isBefore(DateTime.now());
        }
        bool isJam = gig.isJamOpenMic;
        bool hasNotes = (gig.notes?.isNotEmpty ?? false) || (gig.notesUrl?.isNotEmpty ?? false);

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
              gig.venueName,
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
                  const Text(
                    "Open Mic / Jam Session",
                    style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
                  ),
              ],
            ),
            trailing: isJam
                ? null
                : IconButton(
              icon: Icon(
                hasNotes ? Icons.speaker_notes : Icons.speaker_notes_off_outlined,
                color: hasNotes ? Theme.of(context).colorScheme.primary : Colors.grey,
              ),
              onPressed: () => _launchNotesPageForGig(gig),
              tooltip: 'View/Edit Notes',
            ),
            onTap: () => _launchBookingDialogForGig(gig),
          ),
        );
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
              bool hasActualGig = gigEvents.any((gig) => !gig.isJamOpenMic);
              bool hasJam = gigEvents.any((gig) => gig.isJamOpenMic);
              List<Widget> markers = [];
              if (hasActualGig) {
                markers.add(_buildEventsMarker(Theme.of(context).colorScheme.secondary));
              }
              if (hasJam) {
                if (markers.isNotEmpty) markers.add(SizedBox(width: markers.length * 1.5));
                markers.add(_buildEventsMarker(Theme.of(context).colorScheme.tertiary));
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
                leading: isJam ? Icon(Icons.music_note, color: isPast ? Colors.grey.shade500 : Theme.of(context).colorScheme.tertiary) : Icon(Icons.event, color: isPast ? Colors.grey.shade500 : Theme.of(context).colorScheme.primary),
                title: Text(
                  gig.venueName,
                  style: TextStyle(fontWeight: FontWeight.bold, color: isPast ? Colors.grey.shade600 : Colors.black87),
                ),
                subtitle: Text(
                  isJam ? '${DateFormat.jm().format(gig.dateTime)} - Jam/Open Mic' : '${DateFormat.jm().format(gig.dateTime)} - \$${gig.pay.toStringAsFixed(0)}',
                  style: TextStyle(color: isPast ? Colors.grey.shade500 : Colors.black54),
                ),
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

  /// ****** CORRECTED METHOD ******
  Widget _buildVenuesList() {
    if (_isLoadingVenues && _displayableVenues.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_displayableVenues.isEmpty) {
      return const Center( child: Text("No venues saved yet. Add a new venue when booking a gig!", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey)) );
    }
    List<StoredLocation> sortedDisplayableVenues = List.from(_displayableVenues)..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return ListView.builder(
      itemCount: sortedDisplayableVenues.length,
      itemBuilder: (context, index) {
        final venue = sortedDisplayableVenues[index];
        final int futureGigsCount = _getGigsForVenue(venue, futureOnly: true).where((g) => !g.isJamOpenMic).toList().length;
        final bool hasVenueNotes = (venue.venueNotes?.isNotEmpty ?? false) || (venue.venueNotesUrl?.isNotEmpty ?? false);
        final venueContact = venue.contact;

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
                Text(venue.address.isNotEmpty ? venue.address : 'Address not specified', style: TextStyle(color: Colors.grey.shade600)),
                if (venueContact != null && venueContact.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${venueContact.name} ${venueContact.phone}'.trim(),
                    style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                  if (venueContact.email.isNotEmpty)
                    Text(
                      venueContact.email,
                      style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                    ),
                ]
              ],
            ),
            trailing: IconButton(
              icon: Icon(
                hasVenueNotes ? Icons.speaker_notes : Icons.speaker_notes_off_outlined,
                color: hasVenueNotes ? Theme.of(context).colorScheme.primary : Colors.grey,
              ),
              tooltip: 'View/Edit Venue Notes',
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => NotesPage(editingVenueId: venue.placeId),
                ));
              },
            ),
            onTap: () => _showVenueDetailsDialog(venue),
          ),
        );
      },
    );
  }
}
