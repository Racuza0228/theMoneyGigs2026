// lib/booking_dialog.dart
import 'dart:convert'; // For jsonDecode
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http; // Import for API calls
import 'package:the_money_gigs/global_refresh_notifier.dart';
import 'gig_model.dart'; // Your Gig class
import 'venue_model.dart'; // Ensure StoredLocation has 'isArchived' and 'copyWith'

// Enum to indicate the result of the dialog when editing
enum GigEditResultAction { updated, deleted, noChange }

class GigEditResult {
  final GigEditResultAction action;
  final Gig? gig; // The updated gig, or the gig to be deleted

  GigEditResult({required this.action, this.gig});
}


class BookingDialog extends StatefulWidget {
  // Existing properties
  final String? calculatedHourlyRate;
  final double? totalPay;
  final double? gigLengthHours;
  final double? driveSetupTimeHours;
  final double? rehearsalTimeHours;
  final StoredLocation? preselectedVenue; // For new gigs from calculator or map
  final Future<void> Function()? onNewVenuePotentiallyAdded;
  final String googleApiKey;
  final List<Gig> existingGigs; // All other gigs for conflict checking

  // --- NEW PROPERTY FOR EDITING ---
  final Gig? editingGig;

  const BookingDialog({
    super.key,
    // For new gigs from calculator
    this.calculatedHourlyRate,
    this.totalPay,
    this.gigLengthHours,
    this.driveSetupTimeHours,
    this.rehearsalTimeHours,
    // For new gigs from map, or when editing an existing gig (venue is then fixed)
    this.preselectedVenue,
    this.onNewVenuePotentiallyAdded,
    required this.googleApiKey,
    required this.existingGigs,
    this.editingGig, // <<< NEW
  }) : assert(
  editingGig != null || // If editing, other params can be null initially
      preselectedVenue != null || // If new from map, venue is present
      (calculatedHourlyRate != null && // If new from calculator
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

  String _dynamicRateString = ""; // Used for map mode new gig and editing existing gig
  Color _dynamicRateResultColor = Colors.grey;

  List<StoredLocation> _allKnownVenuesInternal = []; // Loaded once if needed
  List<StoredLocation> _selectableVenuesForDropdown = []; // For calculator mode's dropdown

  StoredLocation? _selectedVenue; // Holds the venue for the gig being booked/edited
  bool _isAddNewVenue = false; // Only relevant if not editing and not map mode new gig

  final TextEditingController _newVenueNameController = TextEditingController();
  final TextEditingController _newVenueAddressController = TextEditingController();

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime; // Will be initialized to default if not editing

  bool _isLoadingVenues = false; // True only when loading dropdown for calculator mode
  bool _isGeocoding = false;
  bool _isProcessing = false; // Generic flag for confirm/cancel operations

  // --- Determine dialog mode ---
  bool get _isEditingMode => widget.editingGig != null;
  bool get _isCalculatorMode => widget.calculatedHourlyRate != null && !_isEditingMode && widget.preselectedVenue == null;
  bool get _isMapModeNewGig => widget.preselectedVenue != null && !_isEditingMode;

  // Define the default time
  final TimeOfDay _defaultGigTime = const TimeOfDay(hour: 20, minute: 0); // 8:00 PM


  @override
  void initState() {
    super.initState();
    // Chain the loading operations
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

  // New async method to handle initialization order
  Future<void> _initializeDialogState() async {
    await _loadAllKnownVenuesInternal(); // Wait for venues to load

    if (!mounted) return; // Check if the widget is still in the tree

    if (_isEditingMode) {
      final Gig gig = widget.editingGig!;
      _payController = TextEditingController(text: gig.pay.toStringAsFixed(0));
      _gigLengthController = TextEditingController(text: gig.gigLengthHours.toStringAsFixed(1));
      _driveSetupController = TextEditingController(text: gig.driveSetupTimeHours.toStringAsFixed(1));
      _rehearsalController = TextEditingController(text: gig.rehearsalLengthHours.toStringAsFixed(1));
      _selectedDate = gig.dateTime;
      _selectedTime = TimeOfDay.fromDateTime(gig.dateTime);
      _selectedVenue = StoredLocation(
          placeId: gig.placeId ?? 'edited_${gig.id}',
          name: gig.venueName,
          address: gig.address,
          coordinates: LatLng(gig.latitude, gig.longitude),
          isArchived: _findArchivedStatusForGigVenue(gig)
      );
      _isAddNewVenue = false;
      _isLoadingVenues = false;

      _payController.addListener(_calculateDynamicRate);
      _gigLengthController.addListener(_calculateDynamicRate);
      _driveSetupController.addListener(_calculateDynamicRate);
      _rehearsalController.addListener(_calculateDynamicRate);
      _calculateDynamicRate();
    } else {
      _selectedTime = _defaultGigTime;

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
      } else { // Calculator Mode (New Gig)
        _payController = TextEditingController(text: widget.totalPay?.toStringAsFixed(0) ?? '');
        _gigLengthController = TextEditingController(text: widget.gigLengthHours?.toStringAsFixed(1) ?? '');
        _driveSetupController = TextEditingController(text: widget.driveSetupTimeHours?.toStringAsFixed(1) ?? '');
        _rehearsalController = TextEditingController(text: widget.rehearsalTimeHours?.toStringAsFixed(1) ?? '');
        // Now call this after _allKnownVenuesInternal is likely populated
        await _loadSelectableVenuesForDropdown();
      }
    }
    // If the widget was disposed during async operations, do not call setState.
    if (mounted) {
      setState(() {}); // Ensure UI updates after async operations
    }
  }


  Future<void> _loadAllKnownVenuesInternal() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? locationsJson = prefs.getStringList('saved_locations');
    if (locationsJson != null) {
      _allKnownVenuesInternal = locationsJson
          .map((jsonString) => StoredLocation.fromJson(jsonDecode(jsonString)))
          .toList();
    }
    // No setState here as it's for internal data.
    // UI update will be triggered by _loadSelectableVenuesForDropdown or other parts of initState
  }

  bool _findArchivedStatusForGigVenue(Gig gig) {
    if (_allKnownVenuesInternal.isEmpty) {
      return false;
    }
    StoredLocation? foundVenue;
    if (gig.placeId != null && gig.placeId!.isNotEmpty) {
      try {
        foundVenue = _allKnownVenuesInternal.firstWhere(
              (v) => v.placeId == gig.placeId,
        );
      } catch (e) {
        foundVenue = null; // Not found by placeId
      }
    }

    if (foundVenue == null) { // Fallback to name/address
      try {
        foundVenue = _allKnownVenuesInternal.firstWhere(
              (v) => v.name.toLowerCase() == gig.venueName.toLowerCase() && v.address == gig.address,
        );
      } catch (e) {
        // If still not found, create a temporary one that is not archived
        return false;
      }
    }
    return foundVenue.isArchived;
  }


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
      // _allKnownVenuesInternal should be populated by now due to await in _initializeDialogState
      List<StoredLocation> activeVenues = _allKnownVenuesInternal.where((v) => !v.isArchived).toList();
      _selectableVenuesForDropdown = []; // Clear previous
      _selectableVenuesForDropdown.addAll(activeVenues);
      _selectableVenuesForDropdown.removeWhere((v) => v.placeId == StoredLocation.addNewVenuePlaceholder.placeId); // Ensure placeholder isn't duplicated
      _selectableVenuesForDropdown.sort((a,b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())); // Sort alphabetically
      _selectableVenuesForDropdown.insert(0, StoredLocation.addNewVenuePlaceholder); // Add "Add New" at the top


      if (_selectableVenuesForDropdown.length == 1 && // Only "Add New"
          _selectableVenuesForDropdown.first.placeId == StoredLocation.addNewVenuePlaceholder.placeId) {
        _selectedVenue = _selectableVenuesForDropdown.first;
        _isAddNewVenue = true;
      } else if (_selectableVenuesForDropdown.length > 1) { // Has "Add New" and at least one other venue
        // Try to select the first non-archived, non-placeholder venue
        _selectedVenue = _selectableVenuesForDropdown.firstWhere(
                (v) => v.placeId != StoredLocation.addNewVenuePlaceholder.placeId && !v.isArchived,
            orElse: () => _selectableVenuesForDropdown.first // Default to "Add New" if no other suitable venue
        );
        _isAddNewVenue = (_selectedVenue?.placeId == StoredLocation.addNewVenuePlaceholder.placeId);
      } else { // Should not happen if "Add New" is always added, but as a fallback:
        _selectableVenuesForDropdown = [StoredLocation.addNewVenuePlaceholder];
        _selectedVenue = _selectableVenuesForDropdown.first;
        _isAddNewVenue = true;
      }

    } catch (e) {
      print("Error filtering/setting up venues for dropdown in BookingDialog: $e");
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
      firstDate: DateTime(DateTime.now().year - 5),
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
    final StoredLocation venueWithCorrectArchiveStatus = venueToSave.copyWith(
        isArchived: venueToSave.placeId != null && venueToSave.placeId!.startsWith('manual_')
            ? false
            : venueToSave.isArchived
    );

    final prefs = await SharedPreferences.getInstance();
    // Use a copy of _allKnownVenuesInternal to modify, then update the state variable
    List<StoredLocation> currentSavedVenues = List.from(_allKnownVenuesInternal);

    int existingIndex = -1;
    if(venueWithCorrectArchiveStatus.placeId != null && venueWithCorrectArchiveStatus.placeId != StoredLocation.addNewVenuePlaceholder.placeId) {
      existingIndex = currentSavedVenues.indexWhere((v) => v.placeId == venueWithCorrectArchiveStatus.placeId);
    }

    bool wasActuallyAddedOrUpdated = false;

    if (existingIndex != -1) {
      // Check if the venue data actually changed to avoid unnecessary saves/refreshes
      if (currentSavedVenues[existingIndex] != venueWithCorrectArchiveStatus) {
        currentSavedVenues[existingIndex] = venueWithCorrectArchiveStatus;
        wasActuallyAddedOrUpdated = true;
        print("BookingDialog: Updated existing venue '${venueWithCorrectArchiveStatus.name}'.");
      }
    } else if (
    venueWithCorrectArchiveStatus.placeId != StoredLocation.addNewVenuePlaceholder.placeId &&
        !currentSavedVenues.any((v) =>
        (v.placeId != null && venueWithCorrectArchiveStatus.placeId != null && v.placeId!.isNotEmpty && venueWithCorrectArchiveStatus.placeId!.isNotEmpty && v.placeId == venueWithCorrectArchiveStatus.placeId) ||
            (v.name.toLowerCase() == venueWithCorrectArchiveStatus.name.toLowerCase() && v.address.toLowerCase() == venueWithCorrectArchiveStatus.address.toLowerCase())
        )) {
      currentSavedVenues.add(venueWithCorrectArchiveStatus);
      wasActuallyAddedOrUpdated = true;
      print("BookingDialog: Added new venue '${venueWithCorrectArchiveStatus.name}'.");
    } else {
      print("BookingDialog: Venue '${venueWithCorrectArchiveStatus.name}' (Place ID: ${venueWithCorrectArchiveStatus.placeId}) already exists or is placeholder. Not re-saving as new.");
      // No actual change, but call the callback if it exists
      if (widget.onNewVenuePotentiallyAdded != null) await widget.onNewVenuePotentiallyAdded!();
      return;
    }

    if (wasActuallyAddedOrUpdated) {
      _allKnownVenuesInternal = List.from(currentSavedVenues); // Update the internal state list

      final List<String> updatedLocationsJson = _allKnownVenuesInternal // Use the updated internal list
          .where((loc) => loc.placeId != StoredLocation.addNewVenuePlaceholder.placeId) // Exclude placeholder
          .map((loc) => jsonEncode(loc.toJson())).toList();
      bool success = await prefs.setStringList('saved_locations', updatedLocationsJson);

      if (success) {
        globalRefreshNotifier.notify();
        print("BookingDialog: Global refresh notified after saving/updating venue.");
        // If in calculator mode (where dropdown is visible and might need updating)
        // and a new venue was added (not just an update from map mode)
        if (_isCalculatorMode && mounted) {
          await _loadSelectableVenuesForDropdown(); // Reload dropdown to reflect changes
          // Ensure the newly added venue (if it was 'finalVenueDetails') is selected
          // This logic might need adjustment if _saveNewVenueToPrefs is called in other contexts
          // where _selectedVenue should not be changed.
          if (_selectedVenue?.placeId == 'manual_${DateTime.now().millisecondsSinceEpoch}' || // A bit fragile way to check if it was the one just added
              _allKnownVenuesInternal.any((v) => v.placeId == venueToSave.placeId && v.name == venueToSave.name )
          ) {
            final newVenueInList = _allKnownVenuesInternal.firstWhere(
                    (v) => v.placeId == venueToSave.placeId,
                orElse: () => _selectedVenue ?? StoredLocation.addNewVenuePlaceholder); // Fallback
            if(mounted) {
              setState(() {
                _selectedVenue = newVenueInList;
                _isAddNewVenue = false; // It's now a selected venue
              });
            }
          }
        }
      } else {
        print("BookingDialog: FAILED to save/update venue '${venueWithCorrectArchiveStatus.name}'.");
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: Could not save ${venueWithCorrectArchiveStatus.name}.'), backgroundColor: Colors.red));
      }
    }
    // Call this regardless of whether a new venue was *persisted*,
    // as the intention might have been to add one even if it was a duplicate.
    if (widget.onNewVenuePotentiallyAdded != null) await widget.onNewVenuePotentiallyAdded!();
  }

  Gig? _checkForConflict(DateTime newGigStart, double newGigDurationHours, List<Gig> otherGigsToCheck) {
    final newGigEnd = newGigStart.add(Duration(milliseconds: (newGigDurationHours * 3600000).toInt()));
    for (var existingGig in otherGigsToCheck) {
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

    if (!mounted) return; // Check mount status after dialog
    setState(() => _isProcessing = false);

    if (confirmCancel) {
      Navigator.of(context).pop(GigEditResult(action: GigEditResultAction.deleted, gig: widget.editingGig));
    }
  }

  void _confirmAction() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null || _selectedTime == null) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a date and time.')));
      return;
    }
    if(mounted) setState(() => _isProcessing = true);

    double finalPay = double.tryParse(_payController.text) ?? 0;
    double finalGigLengthHours = double.tryParse(_gigLengthController.text) ?? 0;
    double finalDriveSetupHours = double.tryParse(_driveSetupController.text) ?? 0;
    double finalRehearsalHours = double.tryParse(_rehearsalController.text) ?? 0;

    if (_isCalculatorMode) {
      finalPay = widget.totalPay!;
      finalGigLengthHours = widget.gigLengthHours!;
      finalDriveSetupHours = widget.driveSetupTimeHours!;
      finalRehearsalHours = widget.rehearsalTimeHours!;
    } else {
      if (finalPay <= 0 || finalGigLengthHours <= 0) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Valid Pay & Gig Length required.')));
        if(mounted) setState(() => _isProcessing = false);
        return;
      }
    }


    StoredLocation finalVenueDetails;

    if (_isEditingMode) {
      finalVenueDetails = _selectedVenue!; // Should be set in initState for editing
      if (finalVenueDetails.isArchived) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${finalVenueDetails.name} is archived. Gig cannot be updated to an archived venue.'), backgroundColor: Colors.orange));
        if(mounted) setState(() => _isProcessing = false);
        return;
      }
    } else if (_isMapModeNewGig) {
      finalVenueDetails = widget.preselectedVenue!; // Set from widget property
      if (finalVenueDetails.isArchived) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${finalVenueDetails.name} is archived and cannot be booked.'), backgroundColor: Colors.orange));
        if(mounted) setState(() => _isProcessing = false);
        return;
      }
      // Save if it's a new venue from map that isn't known yet
      bool isKnown = _allKnownVenuesInternal.any((v) => v.placeId == finalVenueDetails.placeId && v.placeId != null && v.placeId!.isNotEmpty);
      if (!isKnown) {
        await _saveNewVenueToPrefs(finalVenueDetails.copyWith(isArchived: false)); // Ensure it's not archived when saved
        if(!mounted) { setState(() => _isProcessing = false); return; }
      }
    } else { // Calculator Mode (New Gig)
      if (_isAddNewVenue) {
        String newVenueName = _newVenueNameController.text.trim();
        String newVenueAddress = _newVenueAddressController.text.trim();
        if(newVenueName.isEmpty || newVenueAddress.isEmpty){
          if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('New venue name and address are required.')));
          if(mounted) setState(() => _isProcessing = false); return;
        }
        LatLng? newVenueCoordinates = await _geocodeAddress(newVenueAddress);
        if (!mounted) { setState(() => _isProcessing = false); return; }
        if (newVenueCoordinates == null) { // Geocoding failed or returned null
          // The geocodeAddress method already shows a SnackBar
          setState(() => _isProcessing = false); return;
        }
        finalVenueDetails = StoredLocation(
            placeId: 'manual_${DateTime.now().millisecondsSinceEpoch}', // Unique ID for manually added
            name: newVenueName,
            address: newVenueAddress,
            coordinates: newVenueCoordinates,
            isArchived: false // New venues are not archived
        );
        await _saveNewVenueToPrefs(finalVenueDetails);
        if (!mounted) { setState(() => _isProcessing = false); return; }
        // After saving, _selectedVenue should be updated by _saveNewVenueToPrefs (if it reloads dropdown)
        // or we need to ensure finalVenueDetails is what we proceed with.
        // For clarity, we use finalVenueDetails which is definitely the new one.
        _selectedVenue = finalVenueDetails; // Update the state's selected venue to the one just created


      } else { // Using an existing venue from dropdown
        if (_selectedVenue == null || _selectedVenue!.placeId == StoredLocation.addNewVenuePlaceholder.placeId) {
          if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select or add a venue.')));
          if(mounted) setState(() => _isProcessing = false); return;
        }
        finalVenueDetails = _selectedVenue!;
        if (finalVenueDetails.isArchived) {
          if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${finalVenueDetails.name} is archived and cannot be booked.'), backgroundColor: Colors.orange));
          if(mounted) setState(() => _isProcessing = false); return;
        }
      }
    }
    if (!mounted) { setState(() => _isProcessing = false); return; }


    final DateTime newGigDateTime = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day, _selectedTime!.hour, _selectedTime!.minute);
    final String gigId = _isEditingMode ? widget.editingGig!.id : 'gig_${DateTime.now().millisecondsSinceEpoch}';

    final Gig newOrUpdatedGigData = Gig(
      id: gigId,
      venueName: finalVenueDetails.name, // Use the determined finalVenueDetails
      latitude: finalVenueDetails.coordinates.latitude,
      longitude: finalVenueDetails.coordinates.longitude,
      address: finalVenueDetails.address,
      placeId: finalVenueDetails.placeId,
      dateTime: newGigDateTime,
      pay: finalPay,
      gigLengthHours: finalGigLengthHours,
      driveSetupTimeHours: finalDriveSetupHours,
      rehearsalLengthHours: finalRehearsalHours,
    );

    List<Gig> otherGigsToCheck = List.from(widget.existingGigs);
    if (_isEditingMode) {
      otherGigsToCheck.removeWhere((g) => g.id == widget.editingGig!.id);
    }

    final conflictingGig = _checkForConflict(newOrUpdatedGigData.dateTime, newOrUpdatedGigData.gigLengthHours, otherGigsToCheck);

    if (conflictingGig != null) {
      if (!mounted) { setState(() => _isProcessing = false); return; }
      final bool? bookAnyway = await showDialog<bool>(
        context: context, builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Scheduling Conflict'),
        content: Text('This gig conflicts with "${conflictingGig.venueName}" on ${DateFormat.yMMMEd().format(conflictingGig.dateTime)} at ${DateFormat.jm().format(conflictingGig.dateTime)}. ${_isEditingMode ? "Update" : "Book"} anyway?'),
        actions: <Widget>[
          TextButton(child: const Text('CANCEL ACTION'), onPressed: () => Navigator.of(dialogContext).pop(false)),
          TextButton(child: Text('${_isEditingMode ? "UPDATE" : "BOOK"} ANYWAY'), onPressed: () => Navigator.of(dialogContext).pop(true)),
        ],
      ),
      );
      if (bookAnyway != true) { // User chose not to book/update
        setState(() => _isProcessing = false);
        return;
      }
    }

    // If we reach here, either no conflict or user chose to proceed despite conflict
    if (!mounted) return; // Final check before pop
    setState(() => _isProcessing = false);


    if (_isEditingMode) {
      Navigator.of(context).pop(GigEditResult(action: GigEditResultAction.updated, gig: newOrUpdatedGigData));
    } else {
      Navigator.of(context).pop(newOrUpdatedGigData); // For new gigs
    }
  }


  Widget _buildVenueDropdown() {
    // Mode 1: Editing existing gig - Venue is fixed and displayed as text.
    if (_isEditingMode) {
      // _selectedVenue is initialized in initState for editing mode.
      StoredLocation? venueToShow = _selectedVenue;
      if (venueToShow == null) return const Text("Venue information missing.", style: TextStyle(color: Colors.red, fontStyle: FontStyle.italic));

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(venueToShow.name, style: Theme.of(context).textTheme.titleMedium),
          Text(venueToShow.address, style: Theme.of(context).textTheme.bodySmall ?? const TextStyle()),
          if (venueToShow.isArchived)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text("(This venue is archived)", style: TextStyle(color: Colors.orange.shade700, fontStyle: FontStyle.italic, fontSize: 12)),
            ),
          const SizedBox(height: 8), // Spacing after venue details
        ],
      );
    }

    // Mode 2: New gig from map - Venue is preselected and displayed as text.
    if (_isMapModeNewGig) {
      StoredLocation? venueToShow = widget.preselectedVenue; // Venue comes from widget property.
      if (venueToShow == null) return const Text("Preselected venue missing.", style: TextStyle(color: Colors.red, fontStyle: FontStyle.italic));

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(venueToShow.name, style: Theme.of(context).textTheme.titleMedium),
          Text(venueToShow.address, style: Theme.of(context).textTheme.bodySmall ?? const TextStyle()),
          if (venueToShow.isArchived) // Should ideally not happen if checks are in place before showing dialog
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text("(This venue is archived)", style: TextStyle(color: Colors.orange.shade700, fontStyle: FontStyle.italic, fontSize: 12)),
            ),
          const SizedBox(height: 8),
        ],
      );
    }

    // Mode 3: Calculator mode (new gig) - Dropdown for venue selection.
    // This is the only mode that should show the actual DropdownButtonFormField.
    if (_isLoadingVenues) {
      return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()));
    }

    // Fallback if _selectableVenuesForDropdown is somehow null or unexpectedly empty
    // though _loadSelectableVenuesForDropdown should always add at least the placeholder.
    if (_selectableVenuesForDropdown.isEmpty) {
      // This case should ideally be prevented by _loadSelectableVenuesForDropdown
      // always initializing _selectableVenuesForDropdown, at least with the placeholder.
      // For safety, ensure _isAddNewVenue is true if only placeholder exists.
      if (!_isAddNewVenue) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _isAddNewVenue = true);
        });
      }
      _selectableVenuesForDropdown = [StoredLocation.addNewVenuePlaceholder];
      if (_selectedVenue == null || _selectedVenue?.placeId != StoredLocation.addNewVenuePlaceholder.placeId) {
        _selectedVenue = StoredLocation.addNewVenuePlaceholder;
      }
    }


    return DropdownButtonFormField<StoredLocation>(
      decoration: const InputDecoration(labelText: 'Select or Add Venue', border: OutlineInputBorder()),
      value: _selectedVenue, // Ensures the dropdown shows the current selection
      isExpanded: true,
      items: _selectableVenuesForDropdown.map<DropdownMenuItem<StoredLocation>>((StoredLocation venue) {
        bool isEnabled = !venue.isArchived || venue.placeId == StoredLocation.addNewVenuePlaceholder.placeId;
        return DropdownMenuItem<StoredLocation>(
          value: venue,
          enabled: isEnabled,
          child: Text(
            venue.name + (venue.isArchived && venue.placeId != StoredLocation.addNewVenuePlaceholder.placeId ? " (Archived)" : ""),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isEnabled ? null : Colors.grey.shade500, // Dim text for disabled archived venues
            ),
          ),
        );
      }).toList(),
      onChanged: (StoredLocation? newValue) {
        if (newValue == null) return; // Should not happen if validator is in place

        // Prevent selection of an archived venue (unless it's the "Add New" placeholder)
        if (newValue.isArchived && newValue.placeId != StoredLocation.addNewVenuePlaceholder.placeId) {
          if(mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("${newValue.name} is archived and cannot be selected."), backgroundColor: Colors.orange),
            );
          }
          // Do not update _selectedVenue to an invalid choice, keep the previous valid one.
          // Or, reset to placeholder if no previous valid one. This depends on desired UX.
          // For now, we simply don't change the state.
          return;
        }

        if(mounted) {
          setState(() {
            _selectedVenue = newValue;
            _isAddNewVenue = (newValue.placeId == StoredLocation.addNewVenuePlaceholder.placeId);
          });
        }
      },
      validator: (value) {
        if (value == null) return 'Please select a venue option.';
        // This validation is a bit redundant if onChanged already prevents selection,
        // but good for form validation integrity.
        if (value.isArchived && value.placeId != StoredLocation.addNewVenuePlaceholder.placeId) {
          return 'Archived venues cannot be booked.';
        }
        return null;
      },
    );
  }

  Widget _buildFinancialInputs() {
    // These inputs are NOT shown in _isCalculatorMode, as details are pre-filled.
    // They ARE shown for _isMapModeNewGig and _isEditingMode.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _payController,
          decoration: const InputDecoration(labelText: 'Total Pay (\$)*', border: OutlineInputBorder(), prefixText: '\$'),
          keyboardType: const TextInputType.numberWithOptions(decimal: false), // No decimals for pay
          validator: (value) {
            if (value == null || value.isEmpty) return 'Pay is required';
            final pay = double.tryParse(value);
            if (pay == null) return 'Invalid number for pay';
            if (pay <= 0) return 'Pay must be positive';
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _gigLengthController,
          decoration: const InputDecoration(labelText: 'Gig Length (hours)*', border: OutlineInputBorder(), suffixText: 'hrs'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (value) {
            if (value == null || value.isEmpty) return 'Gig length is required';
            final length = double.tryParse(value);
            if (length == null) return 'Invalid number for length';
            if (length <= 0) return 'Length must be positive';
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _driveSetupController,
          decoration: const InputDecoration(labelText: 'Drive/Setup (hours)', border: OutlineInputBorder(), suffixText: 'hrs'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (value) {
            if (value != null && value.isNotEmpty) {
              final driveTime = double.tryParse(value);
              if (driveTime == null) return 'Invalid number for drive/setup';
              if (driveTime < 0) return 'Drive/Setup cannot be negative';
            }
            return null; // Optional field
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _rehearsalController,
          decoration: const InputDecoration(labelText: 'Rehearsal (hours)', border: OutlineInputBorder(), suffixText: 'hrs'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (value) {
            if (value != null && value.isNotEmpty) {
              final rehearsalTime = double.tryParse(value);
              if (rehearsalTime == null) return 'Invalid number for rehearsal';
              if (rehearsalTime < 0) return 'Rehearsal cannot be negative';
            }
            return null; // Optional field
          },
        ),
        // Dynamic rate display only for map new gig or editing mode
        if ((_isMapModeNewGig || _isEditingMode) && _dynamicRateString.isNotEmpty) ...[
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: Text( _dynamicRateString, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _dynamicRateResultColor),),
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
    // Determine if any background processing is happening
    bool isDialogProcessing = _isProcessing || _isGeocoding || (_isLoadingVenues && _isCalculatorMode);


    String dialogTitle = "Book New Gig"; // Default for calculator mode
    String confirmButtonText = "CONFIRM & BOOK";
    if (_isEditingMode) {
      dialogTitle = "Edit Gig Details";
      confirmButtonText = "UPDATE GIG";
    } else if (_isMapModeNewGig) {
      dialogTitle = "Book Gig at Selected Venue";
      // Confirm button text remains "CONFIRM & BOOK" or could be specialized
    }


    return AlertDialog(
      title: Text(dialogTitle),
      contentPadding: const EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 0.0), // Adjusted padding
      content: Stack( // Stack for overlaying progress indicator
        children: [
          Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: ListBody(
                children: <Widget>[
                  // Section 1: Financials (either display from calculator or input fields)
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
                    // For Map Mode New Gig & Editing Mode: show financial input fields
                    _buildFinancialInputs(),
                    const Divider(height: 24, thickness: 1),
                  ],

                  // Section 2: Venue and Schedule
                  Text(
                      _isEditingMode ? "Venue & Schedule:" : (_isMapModeNewGig ? "Confirm Venue & Schedule:" : "Venue & Schedule:"),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)
                  ),
                  const SizedBox(height: 12),

                  _buildVenueDropdown(), // Handles all venue display/selection logic
                  const SizedBox(height: 12),

                  // Section 2.1: New Venue Input Fields (only for calculator mode if "Add New Venue" is selected)
                  if (_isCalculatorMode && _isAddNewVenue) ...[
                    TextFormField(
                      controller: _newVenueNameController,
                      decoration: const InputDecoration(labelText: 'New Venue Name*', border: OutlineInputBorder()),
                      validator: (value) {
                        // Only validate if in calculator mode and adding new venue
                        if (_isCalculatorMode && _isAddNewVenue && (value == null || value.trim().isEmpty)) {
                          return 'Venue name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _newVenueAddressController,
                      decoration: const InputDecoration(labelText: 'New Venue Address*', hintText: 'e.g., 1600 Amphitheatre Pkwy, MV, CA', border: OutlineInputBorder()),
                      validator: (value) {
                        // Only validate if in calculator mode and adding new venue
                        if (_isCalculatorMode && _isAddNewVenue && (value == null || value.trim().isEmpty)) {
                          return 'Venue address is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Section 2.2: Date and Time Pickers
                  Row(
                    children: [
                      Expanded(child: Text(_selectedDate == null ? 'No date selected*' : 'Date: ${DateFormat.yMMMEd().format(_selectedDate!)}')),
                      TextButton(onPressed: isDialogProcessing ? null : () => _pickDate(context), child: const Text('SELECT DATE')),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: Text(_selectedTime == null ? 'No time selected*' : 'Time: ${_selectedTime!.format(context)}')), // _selectedTime should always have a value
                      TextButton(onPressed: isDialogProcessing ? null : () => _pickTime(context), child: const Text('SELECT TIME')),
                    ],
                  ),
                  const SizedBox(height: 16), // Padding at the bottom of scroll view
                ],
              ),
            ),
          ),
          // Loading Overlay
          if (isDialogProcessing)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.3), // Semi-transparent overlay
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      actions: <Widget>[
        // Left Action: Close or Cancel
        if (_isEditingMode)
          TextButton(
            child: const Text('CLOSE'), // "No Change" for editing
            onPressed: isDialogProcessing ? null : () => Navigator.of(context).pop(GigEditResult(action: GigEditResultAction.noChange)),
          )
        else // For new gigs (calculator or map)
          TextButton(
            child: const Text('CANCEL'),
            onPressed: isDialogProcessing ? null : () => Navigator.of(context).pop(), // Pop without a result
          ),

        // Right Actions: Cancel Gig (edit mode only) & Confirm/Book/Update
        Row(
          mainAxisSize: MainAxisSize.min, // Keep buttons grouped
          children: [
            if (_isEditingMode) ...[
              TextButton(
                child: Text('CANCEL GIG', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                onPressed: isDialogProcessing ? null : _handleGigCancellation,
              ),
              const SizedBox(width: 8), // Spacer between cancel gig and update
            ],
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary
              ),
              onPressed: isDialogProcessing ? null : _confirmAction,
              child: isDialogProcessing
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                  : Text(confirmButtonText),
            ),
          ],
        ),
      ],
    );
  }
}
