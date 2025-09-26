import 'dart:convert'; // For jsonDecode
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Required for PlatformException
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http; // Import for API calls
import 'package:the_money_gigs/global_refresh_notifier.dart';
import 'gig_model.dart'; // Your Gig class
import 'venue_model.dart'; // Ensure StoredLocation has 'isArchived' and 'copyWith'
import 'package:add_2_calendar_new/add_2_calendar_new.dart';

// Enum to indicate the result of the dialog when editing
enum GigEditResultAction { updated, deleted, noChange }

class GigEditResult {
  final GigEditResultAction action;
  final Gig? gig; // The updated gig, or the gig to be deleted

  GigEditResult({required this.action, this.gig});
}

class BookingDialog extends StatefulWidget {
  final String? calculatedHourlyRate;
  final double? totalPay;
  final double? gigLengthHours;
  final double? driveSetupTimeHours;
  final double? rehearsalTimeHours;
  final StoredLocation? preselectedVenue;
  final Future<void> Function()? onNewVenuePotentiallyAdded;
  final String googleApiKey;
  final List<Gig> existingGigs;
  final Gig? editingGig;

  const BookingDialog({
    super.key,
    this.calculatedHourlyRate,
    this.totalPay,
    this.gigLengthHours,
    this.driveSetupTimeHours,
    this.rehearsalTimeHours,
    this.preselectedVenue,
    this.onNewVenuePotentiallyAdded,
    required this.googleApiKey,
    required this.existingGigs,
    this.editingGig,
  }) : assert(
  editingGig != null ||
      preselectedVenue != null ||
      (calculatedHourlyRate != null &&
          totalPay != null &&
          gigLengthHours != null &&
          driveSetupTimeHours != null &&
          rehearsalTimeHours != null),
  'If not editing, either a preselectedVenue (map mode) or all financial details (calculator mode) must be provided.');

  @override
  State<BookingDialog> createState() => _BookingDialogState();
}

class _BookingDialogState extends State<BookingDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _payController;
  late TextEditingController _gigLengthController;
  late TextEditingController _driveSetupController;
  late TextEditingController _rehearsalController;

  String _dynamicRateString = "";
  Color _dynamicRateResultColor = Colors.grey;

  List<StoredLocation> _allKnownVenuesInternal = [];
  List<StoredLocation> _selectableVenuesForDropdown = [];

  StoredLocation? _selectedVenue;
  bool _isAddNewVenue = false;

  final TextEditingController _newVenueNameController = TextEditingController();
  final TextEditingController _newVenueAddressController = TextEditingController();

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  bool _isLoadingVenues = false;
  bool _isGeocoding = false;
  bool _isProcessing = false;

  bool get _isEditingMode => widget.editingGig != null;
  bool get _isCalculatorMode => widget.calculatedHourlyRate != null && !_isEditingMode && widget.preselectedVenue == null;
  bool get _isMapModeNewGig => widget.preselectedVenue != null && !_isEditingMode;

  final TimeOfDay _defaultGigTime = const TimeOfDay(hour: 20, minute: 0);
  bool _addGigToCalendar = false;

  @override
  void initState() {
    super.initState();
    _initializeDialogState();

    if (widget.googleApiKey.isEmpty || widget.googleApiKey == "YOUR_GOOGLE_PLACES_API_KEY_HERE") {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Warning: Google API Key is missing. Geocoding may fail.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        }
      });
    }
  }

  Future<void> _initializeDialogState() async {
    await _loadAllKnownVenuesInternal();
    if (!mounted) return;

    if (_isEditingMode) {
      final Gig gig = widget.editingGig!;
      _payController = TextEditingController(text: gig.pay.toStringAsFixed(0));
      _gigLengthController = TextEditingController(text: gig.gigLengthHours.toStringAsFixed(1));
      _driveSetupController = TextEditingController(text: gig.driveSetupTimeHours.toStringAsFixed(1));
      _rehearsalController = TextEditingController(text: gig.rehearsalLengthHours.toStringAsFixed(1));
      _selectedDate = gig.dateTime;
      _selectedTime = TimeOfDay.fromDateTime(gig.dateTime);
      _selectedVenue = _allKnownVenuesInternal.firstWhere(
            (v) => (gig.placeId != null && v.placeId == gig.placeId) || (v.name == gig.venueName && v.address == gig.address),
        orElse: () => StoredLocation( // Fallback if venue not found in internal list (e.g. deleted)
            placeId: gig.placeId ?? 'edited_${gig.id}',
            name: gig.venueName,
            address: gig.address,
            coordinates: LatLng(gig.latitude, gig.longitude),
            isArchived: true // Assume archived if not found to prevent booking
        ),
      );
      _isAddNewVenue = false;
      _isLoadingVenues = false;
      _addGigToCalendar = false;

      _payController.addListener(_calculateDynamicRate);
      _gigLengthController.addListener(_calculateDynamicRate);
      _driveSetupController.addListener(_calculateDynamicRate);
      _rehearsalController.addListener(_calculateDynamicRate);
      _calculateDynamicRate();
    } else {
      _selectedTime = _defaultGigTime;
      _addGigToCalendar = true;

      if (_isMapModeNewGig) {
        _payController = TextEditingController(text: widget.totalPay?.toStringAsFixed(0) ?? '');
        _gigLengthController = TextEditingController(text: widget.gigLengthHours?.toStringAsFixed(1) ?? '');
        _driveSetupController = TextEditingController(text: widget.driveSetupTimeHours?.toStringAsFixed(1) ?? '');
        _rehearsalController = TextEditingController(text: widget.rehearsalTimeHours?.toStringAsFixed(1) ?? '');
        _selectedVenue = widget.preselectedVenue;
        _isAddNewVenue = false;
        _isLoadingVenues = false;

        _payController.addListener(_calculateDynamicRate);
        _gigLengthController.addListener(_calculateDynamicRate);
        _driveSetupController.addListener(_calculateDynamicRate);
        _rehearsalController.addListener(_calculateDynamicRate);
        _calculateDynamicRate();
      } else { // Calculator Mode
        _payController = TextEditingController(text: widget.totalPay?.toStringAsFixed(0) ?? '');
        _gigLengthController = TextEditingController(text: widget.gigLengthHours?.toStringAsFixed(1) ?? '');
        _driveSetupController = TextEditingController(text: widget.driveSetupTimeHours?.toStringAsFixed(1) ?? '');
        _rehearsalController = TextEditingController(text: widget.rehearsalTimeHours?.toStringAsFixed(1) ?? '');
        await _loadSelectableVenuesForDropdown();
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadAllKnownVenuesInternal() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? locationsJson = prefs.getStringList('saved_locations');
    if (locationsJson != null) {
      _allKnownVenuesInternal = locationsJson
          .map((jsonString) {
        try {
          return StoredLocation.fromJson(jsonDecode(jsonString));
        } catch(e) {
          print("Error decoding one stored location in BookingDialog: $e");
          return null;
        }
      })
          .whereType<StoredLocation>()
          .toList();
    }
  }

  // Not used in current logic, _selectedVenue is directly assigned in initState or through dropdown.
  // bool _findArchivedStatusForGigVenue(Gig gig) { ... }

  void _calculateDynamicRate() {
    if (!mounted || _isCalculatorMode) return;
    final double pay = double.tryParse(_payController.text) ?? 0;
    final double gigTime = double.tryParse(_gigLengthController.text) ?? 0;
    final double driveSetupTime = double.tryParse(_driveSetupController.text) ?? 0;
    final double rehearsalTime = double.tryParse(_rehearsalController.text) ?? 0;
    final double totalHoursForRateCalc = gigTime + driveSetupTime + rehearsalTime;
    String newRateString = "";
    Color newColor = Colors.grey;

    if (totalHoursForRateCalc > 0 && pay > 0) {
      final double calculatedRate = pay / totalHoursForRateCalc;
      newRateString = '\$${calculatedRate.toStringAsFixed(2)} / hr';
      newColor = Colors.green;
    } else if (pay > 0 && totalHoursForRateCalc <= 0) {
      newRateString = "Enter hours";
      newColor = Colors.orangeAccent;
    } else if (pay <= 0 && totalHoursForRateCalc > 0) {
      newRateString = "Enter pay";
      newColor = Colors.orangeAccent;
    } else {
      newRateString = "Rate: N/A";
      newColor = Colors.grey;
    }
    if (mounted) {
      setState(() {
        _dynamicRateString = newRateString;
        _dynamicRateResultColor = newColor;
      });
    }
  }

  Future<void> _loadSelectableVenuesForDropdown() async {
    if (!_isCalculatorMode) {
      if(mounted) setState(() => _isLoadingVenues = false );
      return;
    }
    if(mounted) setState(() { _isLoadingVenues = true; });

    try {
      List<StoredLocation> activeVenues = _allKnownVenuesInternal.where((v) => !v.isArchived).toList();
      _selectableVenuesForDropdown = [];
      _selectableVenuesForDropdown.addAll(activeVenues);
      _selectableVenuesForDropdown.removeWhere((v) => v.placeId == StoredLocation.addNewVenuePlaceholder.placeId);
      _selectableVenuesForDropdown.sort((a,b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _selectableVenuesForDropdown.insert(0, StoredLocation.addNewVenuePlaceholder);

      if (_selectableVenuesForDropdown.length == 1 &&
          _selectableVenuesForDropdown.first.placeId == StoredLocation.addNewVenuePlaceholder.placeId) {
        _selectedVenue = _selectableVenuesForDropdown.first;
        _isAddNewVenue = true;
      } else if (_selectableVenuesForDropdown.length > 1) {
        _selectedVenue = _selectableVenuesForDropdown.firstWhere(
                (v) => v.placeId != StoredLocation.addNewVenuePlaceholder.placeId && !v.isArchived,
            orElse: () => _selectableVenuesForDropdown.first
        );
        _isAddNewVenue = (_selectedVenue?.placeId == StoredLocation.addNewVenuePlaceholder.placeId);
      } else {
        _selectableVenuesForDropdown = [StoredLocation.addNewVenuePlaceholder];
        _selectedVenue = _selectableVenuesForDropdown.first;
        _isAddNewVenue = true;
      }
    } catch (e) {
      print("Error filtering/setting up venues for dropdown: $e");
      _selectableVenuesForDropdown = [StoredLocation.addNewVenuePlaceholder];
      _selectedVenue = StoredLocation.addNewVenuePlaceholder;
      _isAddNewVenue = true;
    } finally {
      if (mounted) {
        setState(() { _isLoadingVenues = false; });
      }
    }
  }

  @override
  void dispose() {
    _newVenueNameController.dispose();
    _newVenueAddressController.dispose();
    _payController.dispose();
    _gigLengthController.dispose();
    _driveSetupController.dispose();
    _rehearsalController.dispose();

    if (_isMapModeNewGig || _isEditingMode) {
      _payController.removeListener(_calculateDynamicRate);
      _gigLengthController.removeListener(_calculateDynamicRate);
      _driveSetupController.removeListener(_calculateDynamicRate);
      _rehearsalController.removeListener(_calculateDynamicRate);
    }
    super.dispose();
  }

  Future<void> _pickDate(BuildContext context) async {
    final DateTime initialDatePickerDate = _selectedDate ?? DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDatePickerDate,
      firstDate: DateTime(DateTime.now().year - 5), // Allow past dates for editing historical gigs
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked != null && picked != _selectedDate) {
      if(mounted) setState(() { _selectedDate = picked; });
    }
  }

  Future<void> _pickTime(BuildContext context) async {
    final TimeOfDay initialPickerTime = _selectedTime ?? _defaultGigTime;
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialPickerTime,
    );
    if (picked != null && picked != _selectedTime) {
      if(mounted) setState(() { _selectedTime = picked; });
    }
  }

  Future<LatLng?> _geocodeAddress(String address) async {
    if (widget.googleApiKey.isEmpty || widget.googleApiKey == "YOUR_GOOGLE_PLACES_API_KEY_HERE") {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Geocoding failed: API Key not configured.'), backgroundColor: Colors.red),
        );
      }
      return null;
    }
    final String encodedAddress = Uri.encodeComponent(address);
    final String url = 'https://maps.googleapis.com/maps/api/geocode/json?address=$encodedAddress&key=${widget.googleApiKey}';
    if(mounted) setState(() => _isGeocoding = true);
    try {
      final response = await http.get(Uri.parse(url));
      if (!mounted) return null;
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['results'] != null && (data['results'] as List).isNotEmpty) {
          final location = data['results'][0]['geometry']['location'];
          return LatLng(location['lat'], location['lng']);
        } else {
          print('Geocoding error: ${data['status']} - ${data['error_message']}');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not find coordinates: ${data['status']} ${data['error_message'] ?? ''}')));
          }
          return null;
        }
      } else {
        print('Geocoding HTTP error: ${response.statusCode}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error contacting Geocoding service: ${response.statusCode}')));
        }
        return null;
      }
    } catch (e) {
      print('Exception during geocoding: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('An error occurred while finding coordinates: $e')));
      return null;
    } finally {
      if (mounted) setState(() => _isGeocoding = false);
    }
  }

  Future<void> _saveNewVenueToPrefs(StoredLocation venueToSave) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final StoredLocation venueWithCorrectArchiveStatus = venueToSave.copyWith(
        isArchived: venueToSave.placeId != null && venueToSave.placeId!.startsWith('manual_')
            ? false // Manually added venues are active by default
            : venueToSave.isArchived // Otherwise, respect its current status (e.g., from map preselection)
    );

    List<StoredLocation> currentSavedVenues = List.from(_allKnownVenuesInternal);
    int existingIndex = -1;
    if(venueWithCorrectArchiveStatus.placeId != null && venueWithCorrectArchiveStatus.placeId != StoredLocation.addNewVenuePlaceholder.placeId && venueWithCorrectArchiveStatus.placeId!.isNotEmpty) {
      existingIndex = currentSavedVenues.indexWhere((v) => v.placeId == venueWithCorrectArchiveStatus.placeId);
    }

    bool wasActuallyAddedOrUpdated = false;

    if (existingIndex != -1) {
      // Potentially update if different (e.g. name/address was edited for an existing placeId)
      // For now, if placeId exists, we assume it's the same venue, but this could be enhanced.
      // Let's assume if it has a placeId and it exists, we don't need to re-save unless other properties have changed.
      // The current logic might re-save if an instance from map (with placeId) is "newly" added by this dialog.
      if (currentSavedVenues[existingIndex] != venueWithCorrectArchiveStatus) { // Basic check
        currentSavedVenues[existingIndex] = venueWithCorrectArchiveStatus;
        wasActuallyAddedOrUpdated = true;
        print("BookingDialog: Updated existing venue via placeId '${venueWithCorrectArchiveStatus.name}'.");
      }
    } else if (
    venueWithCorrectArchiveStatus.placeId != StoredLocation.addNewVenuePlaceholder.placeId &&
        !currentSavedVenues.any((v) =>
        (v.placeId != null && venueWithCorrectArchiveStatus.placeId != null && v.placeId!.isNotEmpty && venueWithCorrectArchiveStatus.placeId!.isNotEmpty && v.placeId == venueWithCorrectArchiveStatus.placeId) || // Check by Place ID
            (v.name.toLowerCase() == venueWithCorrectArchiveStatus.name.toLowerCase() && v.address.toLowerCase() == venueWithCorrectArchiveStatus.address.toLowerCase()) // Fallback to name/address
        )
    ){
      currentSavedVenues.add(venueWithCorrectArchiveStatus);
      wasActuallyAddedOrUpdated = true;
      print("BookingDialog: Added new venue '${venueWithCorrectArchiveStatus.name}'.");
    } else {
      print("BookingDialog: Venue '${venueWithCorrectArchiveStatus.name}' (Place ID: ${venueWithCorrectArchiveStatus.placeId}) likely already exists or is placeholder. Not re-saving as new.");
    }

    if (wasActuallyAddedOrUpdated) {
      _allKnownVenuesInternal = List.from(currentSavedVenues);
      final List<String> updatedLocationsJson = _allKnownVenuesInternal
          .where((loc) => loc.placeId != StoredLocation.addNewVenuePlaceholder.placeId)
          .map((loc) => jsonEncode(loc.toJson())).toList();
      bool success = await prefs.setStringList('saved_locations', updatedLocationsJson);

      if (success) {
        globalRefreshNotifier.notify();
        print("BookingDialog: Global refresh notified after saving/updating venue.");
        if (_isCalculatorMode && mounted) {
          await _loadSelectableVenuesForDropdown();
          final newVenueInList = _allKnownVenuesInternal.firstWhere(
                  (v) => v.placeId == venueToSave.placeId,
              orElse: () => _selectedVenue ?? StoredLocation.addNewVenuePlaceholder);
          if(mounted) {
            setState(() {
              _selectedVenue = newVenueInList;
              _isAddNewVenue = false;
            });
          }
        }
      } else {
        print("BookingDialog: FAILED to save/update venue '${venueWithCorrectArchiveStatus.name}'.");
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: Could not save ${venueWithCorrectArchiveStatus.name}.'), backgroundColor: Colors.red));
      }
    }
    if (widget.onNewVenuePotentiallyAdded != null) await widget.onNewVenuePotentiallyAdded!();
  }

  Gig? _checkForConflict(DateTime newGigStart, double newGigDurationHours, List<Gig> otherGigsToCheck) {
    final newGigEnd = newGigStart.add(Duration(milliseconds: (newGigDurationHours * 3600000).toInt()));
    for (var existingGig in otherGigsToCheck) {
      if (existingGig.isJamOpenMic) continue; // Don't conflict with placeholder jams
      final existingGigStart = existingGig.dateTime;
      final existingGigEnd = existingGigStart.add(Duration(milliseconds: (existingGig.gigLengthHours * 3600000).toInt()));
      if (newGigStart.isBefore(existingGigEnd) && newGigEnd.isAfter(existingGigStart)) {
        return existingGig;
      }
    }
    return null;
  }

  Future<void> _handleGigCancellation() async {
    if (!_isEditingMode || widget.editingGig == null) return;
    if(mounted) setState(() => _isProcessing = true);
    final bool confirmCancel = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Gig Cancellation'),
          content: Text('Are you sure you want to cancel the gig at "${widget.editingGig!.venueName}" on ${DateFormat.yMMMEd().format(widget.editingGig!.dateTime)}? This cannot be undone.'),
          actions: <Widget>[
            TextButton(child: const Text('NO, KEEP GIG'), onPressed: () => Navigator.of(dialogContext).pop(false)),
            TextButton(child: Text('YES, CANCEL GIG', style: TextStyle(color: Theme.of(context).colorScheme.error)), onPressed: () => Navigator.of(dialogContext).pop(true)),
          ],
        );
      },
    ) ?? false;

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (confirmCancel) {
      Navigator.of(context).pop(GigEditResult(action: GigEditResultAction.deleted, gig: widget.editingGig));
    }
  }

  void _confirmAction() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null || _selectedTime == null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Please select a date and time.')));
      }
      return;
    }
    if (mounted) setState(() => _isProcessing = true);

    // --- PAST DATE/TIME WARNING LOGIC ---
    final DateTime now = DateTime.now();
    final DateTime selectedFullDateTime = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );

    if (!_isEditingMode && selectedFullDateTime.isBefore(now)) { // Only show for new gigs, allow editing past gigs
      if (!mounted) {
        if (mounted) setState(() => _isProcessing = false);
        return;
      }
      final bool? confirmPastBooking = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Confirm Past Date'),
            content: Text(
                'The selected date and time (${DateFormat.yMMMEd().add_jm().format(selectedFullDateTime)}) is in the past. Do you want to book this gig anyway?'),
            actions: <Widget>[
              TextButton(
                child: const Text('CANCEL'),
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              TextButton(
                child: const Text('BOOK ANYWAY'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          );
        },
      );

      if (confirmPastBooking != true) {
        if (mounted) setState(() => _isProcessing = false);
        return;
      }
    } else if (_isEditingMode && selectedFullDateTime.isBefore(now) && selectedFullDateTime != widget.editingGig!.dateTime) {
      // If editing, and the new date is in the past AND it's different from the original past date, also warn.
      // This prevents accidentally making a past gig even further in the past without confirmation.
      // If they are just re-saving a past gig without changing its date, no need to warn again.
      if (!mounted) {
        if (mounted) setState(() => _isProcessing = false);
        return;
      }
      final bool? confirmPastUpdate = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Confirm Past Date Update'),
            content: Text(
                'The updated date and time (${DateFormat.yMMMEd().add_jm().format(selectedFullDateTime)}) is in the past. Do you want to update this gig anyway?'),
            actions: <Widget>[
              TextButton(
                child: const Text('CANCEL UPDATE'),
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              TextButton(
                child: const Text('UPDATE ANYWAY'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          );
        },
      );
      if (confirmPastUpdate != true) {
        if (mounted) setState(() => _isProcessing = false);
        return;
      }
    }
    // --- END PAST DATE/TIME WARNING LOGIC ---

    double finalPay;
    double finalGigLengthHours;
    double finalDriveSetupHours;
    double finalRehearsalHours;

    if (_isCalculatorMode) {
      finalPay = widget.totalPay!;
      finalGigLengthHours = widget.gigLengthHours!;
      finalDriveSetupHours = widget.driveSetupTimeHours!;
      finalRehearsalHours = widget.rehearsalTimeHours!;
    } else {
      finalPay = double.tryParse(_payController.text) ?? 0;
      finalGigLengthHours = double.tryParse(_gigLengthController.text) ?? 0;
      finalDriveSetupHours = double.tryParse(_driveSetupController.text) ?? 0;
      finalRehearsalHours = double.tryParse(_rehearsalController.text) ?? 0;
      if (finalPay <= 0 || finalGigLengthHours <= 0) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Valid Pay & Gig Length required.')));
          setState(() => _isProcessing = false);
        }
        return;
      }
    }

    StoredLocation finalVenueDetails;

    if (_isEditingMode) {
      finalVenueDetails = _selectedVenue!;
      if (finalVenueDetails.isArchived && finalVenueDetails.placeId != widget.editingGig?.placeId) { // Allow editing if it's the *same* archived venue
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('${finalVenueDetails.name} is archived. Gig cannot be moved to a different archived venue.'),
              backgroundColor: Colors.orange));
          setState(() => _isProcessing = false);
        }
        return;
      }
    } else if (_isMapModeNewGig) {
      finalVenueDetails = widget.preselectedVenue!;
      if (finalVenueDetails.isArchived) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('${finalVenueDetails.name} is archived and cannot be booked.'),
              backgroundColor: Colors.orange));
          setState(() => _isProcessing = false);
        }
        return;
      }
      bool isKnown = _allKnownVenuesInternal.any((v) => v.placeId == finalVenueDetails.placeId && v.placeId != null && v.placeId!.isNotEmpty);
      if (!isKnown) {
        await _saveNewVenueToPrefs(finalVenueDetails.copyWith(isArchived: false));
        if (!mounted) {
          if (mounted) setState(() => _isProcessing = false);
          return;
        }
      }
    } else { // Calculator Mode (New Gig)
      if (_isAddNewVenue) {
        String newVenueName = _newVenueNameController.text.trim();
        String newVenueAddress = _newVenueAddressController.text.trim();
        if (newVenueName.isEmpty || newVenueAddress.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('New venue name and address are required.')));
            setState(() => _isProcessing = false);
          }
          return;
        }
        LatLng? newVenueCoordinates = await _geocodeAddress(newVenueAddress);
        if (!mounted) {
          if (mounted) setState(() => _isProcessing = false);
          return;
        }
        if (newVenueCoordinates == null) {
          if (mounted) setState(() => _isProcessing = false);
          return;
        }
        finalVenueDetails = StoredLocation(
            placeId: 'manual_${DateTime.now().millisecondsSinceEpoch}',
            name: newVenueName,
            address: newVenueAddress,
            coordinates: newVenueCoordinates,
            isArchived: false);
        await _saveNewVenueToPrefs(finalVenueDetails);
        if (!mounted) {
          if (mounted) setState(() => _isProcessing = false);
          return;
        }
        _selectedVenue = finalVenueDetails; // Update _selectedVenue after adding
      } else {
        if (_selectedVenue == null || _selectedVenue!.placeId == StoredLocation.addNewVenuePlaceholder.placeId) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Please select or add a venue.')));
            setState(() => _isProcessing = false);
          }
          return;
        }
        finalVenueDetails = _selectedVenue!;
        if (finalVenueDetails.isArchived) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('${finalVenueDetails.name} is archived and cannot be booked.'),
                backgroundColor: Colors.orange));
            setState(() => _isProcessing = false);
          }
          return;
        }
      }
    }
    if (!mounted) {
      if (mounted) setState(() => _isProcessing = false);
      return;
    }

    final String gigId = _isEditingMode ? widget.editingGig!.id : 'gig_${DateTime.now().millisecondsSinceEpoch}';

    final Gig newOrUpdatedGigData = Gig(
      id: gigId,
      venueName: finalVenueDetails.name,
      latitude: finalVenueDetails.coordinates.latitude,
      longitude: finalVenueDetails.coordinates.longitude,
      address: finalVenueDetails.address,
      placeId: finalVenueDetails.placeId,
      dateTime: selectedFullDateTime, // Use the combined and potentially past-confirmed date
      pay: finalPay,
      gigLengthHours: finalGigLengthHours,
      driveSetupTimeHours: finalDriveSetupHours,
      rehearsalLengthHours: finalRehearsalHours,
    );

    List<Gig> otherGigsToCheck = List.from(widget.existingGigs.where((g) => !g.isJamOpenMic)); // Exclude jam gigs
    if (_isEditingMode) {
      otherGigsToCheck.removeWhere((g) => g.id == widget.editingGig!.id);
    }

    final conflictingGig = _checkForConflict(newOrUpdatedGigData.dateTime, newOrUpdatedGigData.gigLengthHours, otherGigsToCheck);

    if (conflictingGig != null) {
      if (!mounted) {
        if (mounted) setState(() => _isProcessing = false);
        return;
      }
      final bool? bookAnyway = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('Scheduling Conflict'),
          content: Text(
              'This gig conflicts with "${conflictingGig.venueName}" on ${DateFormat.yMMMEd().format(conflictingGig.dateTime)} at ${DateFormat.jm().format(conflictingGig.dateTime)}. ${_isEditingMode ? "Update" : "Book"} anyway?'),
          actions: <Widget>[
            TextButton(
                child: const Text('CANCEL ACTION'),
                onPressed: () => Navigator.of(dialogContext).pop(false)),
            TextButton(
                child: Text('${_isEditingMode ? "UPDATE" : "BOOK"} ANYWAY'),
                onPressed: () => Navigator.of(dialogContext).pop(true)),
          ],
        ),
      );
      if (bookAnyway != true) {
        if (mounted) setState(() => _isProcessing = false);
        return;
      }
    }

    if (!mounted) {
      if (mounted) setState(() => _isProcessing = false);
      return;
    }

    bool calendarAddAttempted = false;
    bool calendarAddSuccess = false;
    if (_addGigToCalendar) {
      calendarAddAttempted = true;
      final Event event = Event(
        title: 'MoneyGig: ${newOrUpdatedGigData.venueName}',
        description:
        'Pay: \$${newOrUpdatedGigData.pay.toStringAsFixed(0)}\nGig Length: ${newOrUpdatedGigData.gigLengthHours} hrs\nRehearsal: ${newOrUpdatedGigData.rehearsalLengthHours} hrs',
        location: newOrUpdatedGigData.address.isNotEmpty
            ? newOrUpdatedGigData.address
            : newOrUpdatedGigData.venueName,
        startDate: newOrUpdatedGigData.dateTime,
        endDate: newOrUpdatedGigData.dateTime
            .add(Duration(minutes: (newOrUpdatedGigData.gigLengthHours * 60).toInt())),
        allDay: false,
      );
      try {
        final bool didPluginSucceed = await Add2Calendar.addEvent2Cal(event);
        calendarAddSuccess = didPluginSucceed;
        print("Add2Calendar.addEvent2Cal for '${newOrUpdatedGigData.venueName}' returned: $didPluginSucceed");
      } on PlatformException catch (e, s) {
        print("PLATFORM EXCEPTION adding gig to calendar: ${e.message}, Stack: $s");
        calendarAddSuccess = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Error adding to calendar: ${e.message}'),
              backgroundColor: Colors.orange));
        }
      } catch (e, s) {
        print("Error adding gig to calendar: $e, Stack: $s");
        calendarAddSuccess = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Could not add to calendar: $e'),
              backgroundColor: Colors.orange));
        }
      }
    }

    if (mounted) setState(() => _isProcessing = false);

    if (_isEditingMode) {
      Navigator.of(context).pop(GigEditResult(action: GigEditResultAction.updated, gig: newOrUpdatedGigData));
    } else {
      Navigator.of(context).pop(newOrUpdatedGigData);
    }

    if (calendarAddAttempted && mounted) {
      // Use a GlobalKey for ScaffoldMessenger if showing SnackBar after dialog pop
      // Or ensure the context used is still valid. For simplicity, we assume context is page context.
      // However, it's safer to get it from a global key or pass the page's ScaffoldMessenger key.
      // For now, will try with current context, but be aware this can sometimes fail if context is from dialog.
      BuildContext snackbarContext = GlobalKey<ScaffoldMessengerState>().currentContext ?? context;
      if (mounted && ScaffoldMessenger.maybeOf(snackbarContext) != null) { // Check if ScaffoldMessenger is available
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            ScaffoldMessenger.of(snackbarContext).showSnackBar(
              SnackBar(
                content: Text(calendarAddSuccess
                    ? 'Gig sent to your calendar app.'
                    : 'Could not add gig to calendar. Check app permissions?'),
                backgroundColor: calendarAddSuccess ? Colors.green : Colors.orange,
              ),
            );
          }
        });
      } else {
        print("Could not show calendar SnackBar: No ScaffoldMessenger found with the context.");
      }
    }
  }

  Widget _buildVenueDropdown() {
    if (_isEditingMode) {
      StoredLocation? venueToShow = _selectedVenue;
      if (venueToShow == null) return const Text("Venue information missing.", style: TextStyle(color: Colors.red, fontStyle: FontStyle.italic));
      return Column( crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(venueToShow.name, style: Theme.of(context).textTheme.titleMedium),
        Text(venueToShow.address, style: Theme.of(context).textTheme.bodySmall ?? const TextStyle()),
        if (venueToShow.isArchived) Padding( padding: const EdgeInsets.only(top: 4.0), child: Text("(This venue is archived)", style: TextStyle(color: Colors.orange.shade700, fontStyle: FontStyle.italic, fontSize: 12)),),
        const SizedBox(height: 8),
      ]);
    }
    if (_isMapModeNewGig) {
      StoredLocation? venueToShow = widget.preselectedVenue;
      if (venueToShow == null) return const Text("Preselected venue missing.", style: TextStyle(color: Colors.red, fontStyle: FontStyle.italic));
      return Column( crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(venueToShow.name, style: Theme.of(context).textTheme.titleMedium),
        Text(venueToShow.address, style: Theme.of(context).textTheme.bodySmall ?? const TextStyle()),
        if (venueToShow.isArchived) Padding( padding: const EdgeInsets.only(top: 4.0), child: Text("(This venue is archived)", style: TextStyle(color: Colors.orange.shade700, fontStyle: FontStyle.italic, fontSize: 12)),),
        const SizedBox(height: 8),
      ]);
    }

    if (_isLoadingVenues) {
      return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()));
    }
    if (_selectableVenuesForDropdown.isEmpty && !_isAddNewVenue) {
      // If empty and not already in "add new" mode, switch to it
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(() {
        _isAddNewVenue = true;
        _selectableVenuesForDropdown = [StoredLocation.addNewVenuePlaceholder];
        _selectedVenue = StoredLocation.addNewVenuePlaceholder;
      }); });
    } else if (_selectableVenuesForDropdown.isEmpty && _isAddNewVenue) {
      // Already in add new mode, ensure placeholder is there
      _selectableVenuesForDropdown = [StoredLocation.addNewVenuePlaceholder];
      _selectedVenue ??= StoredLocation.addNewVenuePlaceholder;
    }


    return DropdownButtonFormField<StoredLocation>(
      decoration: const InputDecoration(labelText: 'Select or Add Venue', border: OutlineInputBorder()),
      value: _selectedVenue,
      isExpanded: true,
      items: _selectableVenuesForDropdown.map<DropdownMenuItem<StoredLocation>>((StoredLocation venue) {
        bool isEnabled = !venue.isArchived || venue.placeId == StoredLocation.addNewVenuePlaceholder.placeId;
        return DropdownMenuItem<StoredLocation>(
          value: venue,
          enabled: isEnabled,
          child: Text( venue.name + (venue.isArchived && venue.placeId != StoredLocation.addNewVenuePlaceholder.placeId ? " (Archived)" : ""), overflow: TextOverflow.ellipsis, style: TextStyle( color: isEnabled ? null : Colors.grey.shade500, ),),
        );
      }).toList(),
      onChanged: (StoredLocation? newValue) {
        if (newValue == null) return;
        if (newValue.isArchived && newValue.placeId != StoredLocation.addNewVenuePlaceholder.placeId) {
          if(mounted) { ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text("${newValue.name} is archived and cannot be selected."), backgroundColor: Colors.orange), ); }
          return;
        }
        if(mounted) { setState(() { _selectedVenue = newValue; _isAddNewVenue = (newValue.placeId == StoredLocation.addNewVenuePlaceholder.placeId); });}
      },
      validator: (value) {
        if (value == null) return 'Please select a venue option.';
        if (value.isArchived && value.placeId != StoredLocation.addNewVenuePlaceholder.placeId) { return 'Archived venues cannot be booked.'; }
        if (_isCalculatorMode && _isAddNewVenue) { /* Validation handled by specific text fields */ }
        else if (_selectedVenue == null || _selectedVenue!.placeId == StoredLocation.addNewVenuePlaceholder.placeId && !_isAddNewVenue) {
          return 'Please select a venue.';
        }
        return null;
      },
    );
  }

  Widget _buildFinancialInputs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField( controller: _payController, decoration: const InputDecoration(labelText: 'Total Pay (\$)*', border: OutlineInputBorder(), prefixText: '\$'), keyboardType: const TextInputType.numberWithOptions(decimal: false),
          validator: (value) { if (value == null || value.isEmpty) return 'Pay is required'; final pay = double.tryParse(value); if (pay == null) return 'Invalid number for pay'; if (pay <= 0) return 'Pay must be positive'; return null; },
        ),
        const SizedBox(height: 12),
        TextFormField( controller: _gigLengthController, decoration: const InputDecoration(labelText: 'Gig Length (hours)*', border: OutlineInputBorder(), suffixText: 'hrs'), keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (value) { if (value == null || value.isEmpty) return 'Gig length is required'; final length = double.tryParse(value); if (length == null) return 'Invalid number for length'; if (length <= 0) return 'Length must be positive'; return null; },
        ),
        const SizedBox(height: 12),
        TextFormField( controller: _driveSetupController, decoration: const InputDecoration(labelText: 'Drive/Setup (hours)', border: OutlineInputBorder(), suffixText: 'hrs'), keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (value) { if (value != null && value.isNotEmpty) { final driveTime = double.tryParse(value); if (driveTime == null) return 'Invalid number for drive/setup'; if (driveTime < 0) return 'Drive/Setup cannot be negative'; } return null; },
        ),
        const SizedBox(height: 12),
        TextFormField( controller: _rehearsalController, decoration: const InputDecoration(labelText: 'Rehearsal (hours)', border: OutlineInputBorder(), suffixText: 'hrs'), keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (value) { if (value != null && value.isNotEmpty) { final rehearsalTime = double.tryParse(value); if (rehearsalTime == null) return 'Invalid number for rehearsal'; if (rehearsalTime < 0) return 'Rehearsal cannot be negative'; } return null; },
        ),
        if ((_isMapModeNewGig || _isEditingMode) && _dynamicRateString.isNotEmpty) ...[
          const SizedBox(height: 16),
          Align( alignment: Alignment.centerRight, child: Text( _dynamicRateString, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _dynamicRateResultColor),),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    TextStyle detailLabelStyle = const TextStyle(fontWeight: FontWeight.bold);
    TextStyle detailValueStyle = TextStyle(color: Colors.grey.shade700, fontSize: 14);
    TextStyle rateValueStyle = const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16);
    bool isDialogProcessing = _isProcessing || _isGeocoding || (_isLoadingVenues && _isCalculatorMode && !_isAddNewVenue); // Adjust loading state

    String dialogTitle = "Book New Gig";
    String confirmButtonText = "CONFIRM & BOOK";
    if (_isEditingMode) {
      dialogTitle = "Edit Gig Details";
      confirmButtonText = "UPDATE GIG";
    } else if (_isMapModeNewGig) {
      dialogTitle = "Book Gig at Selected Venue";
    }

    return AlertDialog(
      title: Text(dialogTitle),
      contentPadding: const EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 0.0),
      content: Stack(
        children: [
          Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: ListBody(
                children: <Widget>[
                  if (_isCalculatorMode) ...[
                    const Text("Review Calculated Details:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const Divider(height: 20, thickness: 1),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Total Pay:', style: detailLabelStyle), Text('\$${widget.totalPay?.toStringAsFixed(0) ?? 'N/A'}', style: detailValueStyle)]),
                    const SizedBox(height: 4),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Gig Length:', style: detailLabelStyle), Text('${widget.gigLengthHours?.toStringAsFixed(1) ?? 'N/A'} hrs', style: detailValueStyle)]),
                    const SizedBox(height: 4),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Drive/Setup:', style: detailLabelStyle), Text('${widget.driveSetupTimeHours?.toStringAsFixed(1) ?? 'N/A'} hrs', style: detailValueStyle)]),
                    const SizedBox(height: 4),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Rehearsal:', style: detailLabelStyle), Text('${widget.rehearsalTimeHours?.toStringAsFixed(1) ?? 'N/A'} hrs', style: detailValueStyle)]),
                    const SizedBox(height: 8),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Hourly Rate:', style: detailLabelStyle), Text(widget.calculatedHourlyRate ?? 'N/A', style: rateValueStyle)]),
                    const Divider(height: 24, thickness: 1),
                  ] else ...[
                    _buildFinancialInputs(),
                    const Divider(height: 24, thickness: 1),
                  ],

                  Text( _isEditingMode ? "Venue & Schedule:" : (_isMapModeNewGig ? "Confirm Venue & Schedule:" : "Venue & Schedule:"), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _buildVenueDropdown(),
                  const SizedBox(height: 12),

                  if ((_isCalculatorMode || _isMapModeNewGig) && _isAddNewVenue) ...[ // Also allow for MapMode if somehow venue becomes add new
                    TextFormField( controller: _newVenueNameController, decoration: const InputDecoration(labelText: 'New Venue Name*', border: OutlineInputBorder()),
                      validator: (value) { if (_isAddNewVenue && (value == null || value.trim().isEmpty)) { return 'Venue name is required'; } return null; },
                    ),
                    const SizedBox(height: 12),
                    TextFormField( controller: _newVenueAddressController, decoration: const InputDecoration(labelText: 'New Venue Address*', hintText: 'e.g., 1600 Amphitheatre Pkwy, MV, CA', border: OutlineInputBorder()),
                      validator: (value) { if (_isAddNewVenue && (value == null || value.trim().isEmpty)) { return 'Venue address is required'; } return null; },
                    ),
                    const SizedBox(height: 12),
                  ],

                  Row( children: [ Expanded(child: Text(_selectedDate == null ? 'No date selected*' : 'Date: ${DateFormat.yMMMEd().format(_selectedDate!)}')), TextButton(onPressed: isDialogProcessing ? null : () => _pickDate(context), child: const Text('SELECT DATE')), ], ),
                  Row( children: [ Expanded(child: Text(_selectedTime == null ? 'No time selected*' : 'Time: ${_selectedTime!.format(context)}')), TextButton(onPressed: isDialogProcessing ? null : () => _pickTime(context), child: const Text('SELECT TIME')), ], ),

                  Padding(
                    padding: const EdgeInsets.only(top: 8.0, bottom: 0.0),
                    child: CheckboxListTile(
                      title: const Text("Add to device calendar"),
                      value: _addGigToCalendar,
                      onChanged: isDialogProcessing ? null : (bool? value) {
                        if (mounted && value != null) {
                          setState(() {
                            _addGigToCalendar = value;
                          });
                        }
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
          if (isDialogProcessing) Positioned.fill( child: Container( color: Colors.black.withOpacity(0.3), child: const Center(child: CircularProgressIndicator()), ), ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      actions: <Widget>[
        if (_isEditingMode) TextButton( child: const Text('CLOSE'), onPressed: isDialogProcessing ? null : () => Navigator.of(context).pop(GigEditResult(action: GigEditResultAction.noChange)), )
        else TextButton( child: const Text('CANCEL'), onPressed: isDialogProcessing ? null : () => Navigator.of(context).pop(), ),
        Row( mainAxisSize: MainAxisSize.min, children: [
          if (_isEditingMode) ...[
            TextButton( child: Text('CANCEL GIG', style: TextStyle(color: Theme.of(context).colorScheme.error)), onPressed: isDialogProcessing ? null : _handleGigCancellation, ),
            const SizedBox(width: 8),
          ],
          ElevatedButton(
            style: ElevatedButton.styleFrom( backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Theme.of(context).colorScheme.onPrimary ),
            onPressed: isDialogProcessing ? null : _confirmAction,
            child: isDialogProcessing ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white))) : Text(confirmButtonText),
          ),
        ],
        ),
      ],
    );
  }
}
