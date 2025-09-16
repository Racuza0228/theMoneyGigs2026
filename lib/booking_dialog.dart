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
  TimeOfDay? _selectedTime;

  bool _isLoadingVenues = false; // True only when loading dropdown for calculator mode
  bool _isGeocoding = false;
  bool _isProcessing = false; // Generic flag for confirm/cancel operations

  // --- Determine dialog mode ---
  bool get _isEditingMode => widget.editingGig != null;
  bool get _isCalculatorMode => widget.calculatedHourlyRate != null && !_isEditingMode && widget.preselectedVenue == null;
  bool get _isMapModeNewGig => widget.preselectedVenue != null && !_isEditingMode;


  @override
  void initState() {
    super.initState();
    _loadAllKnownVenuesInternal(); // Load all venues once for potential reference

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
      _isLoadingVenues = false; // Venue is fixed

      _payController.addListener(_calculateDynamicRate);
      _gigLengthController.addListener(_calculateDynamicRate);
      _driveSetupController.addListener(_calculateDynamicRate);
      _rehearsalController.addListener(_calculateDynamicRate);
      _calculateDynamicRate();
    } else if (_isMapModeNewGig) {
      _payController = TextEditingController(text: widget.totalPay?.toStringAsFixed(0) ?? '');
      _gigLengthController = TextEditingController(text: widget.gigLengthHours?.toStringAsFixed(1) ?? '');
      _driveSetupController = TextEditingController(text: widget.driveSetupTimeHours?.toStringAsFixed(1) ?? '');
      _rehearsalController = TextEditingController(text: widget.rehearsalTimeHours?.toStringAsFixed(1) ?? '');
      _selectedVenue = widget.preselectedVenue;
      _isAddNewVenue = false;
      _isLoadingVenues = false; // Venue is fixed

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
      // Rate is pre-calculated for this mode, no dynamic calculation needed on text change.
      _loadSelectableVenuesForDropdown(); // Load venues for dropdown
    }

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

  Future<void> _loadAllKnownVenuesInternal() async {
    // Load all venues once for _findArchivedStatusForGigVenue
    // This doesn't trigger setState unless specifically for the dropdown loading
    final prefs = await SharedPreferences.getInstance();
    final List<String>? locationsJson = prefs.getStringList('saved_locations');
    if (locationsJson != null) {
      _allKnownVenuesInternal = locationsJson
          .map((jsonString) => StoredLocation.fromJson(jsonDecode(jsonString)))
          .toList();
    }
  }

  bool _findArchivedStatusForGigVenue(Gig gig) {
    if (_allKnownVenuesInternal.isEmpty) { // Ensure venues are loaded
      print("Warning: _allKnownVenuesInternal not loaded when trying to find archive status.");
      return false; // Default if lookup fails
    }
    StoredLocation? foundVenue;
    if (gig.placeId != null && gig.placeId!.isNotEmpty) {
      foundVenue = _allKnownVenuesInternal.firstWhere(
            (v) => v.placeId == gig.placeId,
        orElse: () => StoredLocation(name: '', address: '', coordinates: LatLng(0,0), placeId: 'not_found_${DateTime.now().millisecondsSinceEpoch}', isArchived: false),
      );
    }
    if (foundVenue == null || foundVenue.placeId.isEmpty) { // Fallback to name/address if no placeId match
      foundVenue = _allKnownVenuesInternal.firstWhere(
            (v) => v.name.toLowerCase() == gig.venueName.toLowerCase() && v.address == gig.address,
        orElse: () => StoredLocation(name: '', address: '', coordinates: LatLng(0,0), placeId: 'not_found_name_addr_${DateTime.now().millisecondsSinceEpoch}', isArchived: false),
      );
    }
    return foundVenue.isArchived;
  }


  void _calculateDynamicRate() {
    if (!mounted || _isCalculatorMode) return; // Only for map (new) or edit mode
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
    setState(() {
      _dynamicRateString = newRateString;
      _dynamicRateResultColor = newColor;
    });
  }

  Future<void> _loadSelectableVenuesForDropdown() async {
    // Only called in Calculator mode for new gigs
    if (!_isCalculatorMode) {
      setState(() => _isLoadingVenues = false );
      return;
    }
    setState(() { _isLoadingVenues = true; });
    // _allKnownVenuesInternal should be populated by now from initState call
    // If not, it means _loadAllKnownVenuesInternal hasn't completed, which is an order of ops issue.
    // For simplicity here, we assume it's populated.
    try {
      List<StoredLocation> activeVenues = _allKnownVenuesInternal.where((v) => !v.isArchived).toList();
      _selectableVenuesForDropdown = [];
      _selectableVenuesForDropdown.addAll(activeVenues);
      _selectableVenuesForDropdown.removeWhere((v) => v.placeId == StoredLocation.addNewVenuePlaceholder.placeId);
      _selectableVenuesForDropdown.add(StoredLocation.addNewVenuePlaceholder);

      if (_selectableVenuesForDropdown.isEmpty) { // Should at least have placeholder
        _selectableVenuesForDropdown.add(StoredLocation.addNewVenuePlaceholder);
      }

      if (_selectableVenuesForDropdown.length == 1 &&
          _selectableVenuesForDropdown.first.placeId == StoredLocation.addNewVenuePlaceholder.placeId) {
        _selectedVenue = _selectableVenuesForDropdown.first;
        _isAddNewVenue = true;
      } else if (_selectableVenuesForDropdown.isNotEmpty) {
        _selectedVenue = _selectableVenuesForDropdown.firstWhere(
                (v) => v.placeId != StoredLocation.addNewVenuePlaceholder.placeId && !v.isArchived,
            orElse: () => _selectableVenuesForDropdown.firstWhere(
                    (v)=> v.placeId == StoredLocation.addNewVenuePlaceholder.placeId,
                orElse: () => _selectableVenuesForDropdown.first
            )
        );
        _isAddNewVenue = (_selectedVenue?.placeId == StoredLocation.addNewVenuePlaceholder.placeId);
      }
      setState(() { _isLoadingVenues = false; });

    } catch (e) {
      print("Error filtering/setting up venues for dropdown in BookingDialog: $e");
      if (mounted) {
        setState(() {
          _isLoadingVenues = false;
          _selectableVenuesForDropdown = [StoredLocation.addNewVenuePlaceholder];
          _selectedVenue = StoredLocation.addNewVenuePlaceholder;
          _isAddNewVenue = true;
        });
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
      firstDate: DateTime(DateTime.now().year - 2), // Allow past dates for editing
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() { _selectedDate = picked; });
    }
  }

  Future<void> _pickTime(BuildContext context) async {
    final TimeOfDay initialPickerTime = _selectedTime ?? TimeOfDay.now();
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialPickerTime,
    );
    if (picked != null && picked != _selectedTime) {
      setState(() { _selectedTime = picked; });
    }
  }

  Future<LatLng?> _geocodeAddress(String address) async {
    if (widget.googleApiKey.isEmpty || widget.googleApiKey == "YOUR_GOOGLE_PLACES_API_KEY_HERE") {
      print("Geocoding failed: API key is missing or invalid.");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Geocoding failed: API Key not configured.'), backgroundColor: Colors.red),
        );
      }
      return null;
    }
    final String encodedAddress = Uri.encodeComponent(address);
    final String url = 'https://maps.googleapis.com/maps/api/geocode/json?address=$encodedAddress&key=${widget.googleApiKey}';
    setState(() => _isGeocoding = true);
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
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not find coordinates: ${data['status']}')));
          return null;
        }
      } else {
        print('Geocoding HTTP error: ${response.statusCode}');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error contacting Geocoding service: ${response.statusCode}')));
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
    // Ensure isArchived is false for genuinely new manual venues.
    // For venues from Places API (via map preselection), their existing status would be respected if known,
    // or they'd be new and non-archived.
    final StoredLocation venueWithCorrectArchiveStatus = venueToSave.copyWith(
        isArchived: venueToSave.placeId.startsWith('manual_') // New manual venues are not archived
            ? false
            : venueToSave.isArchived // Otherwise, respect the passed status (e.g. from preselectedVenue)
    );

    final prefs = await SharedPreferences.getInstance();
    // Use _allKnownVenuesInternal as the source of truth for existing venues
    // to avoid re-reading from prefs unnecessarily within this method if called multiple times.
    List<StoredLocation> currentSavedVenues = List.from(_allKnownVenuesInternal);

    int existingIndex = currentSavedVenues.indexWhere((v) => v.placeId == venueWithCorrectArchiveStatus.placeId && v.placeId != StoredLocation.addNewVenuePlaceholder.placeId);
    bool wasActuallyAddedOrUpdated = false;

    if (existingIndex != -1) {
      if (currentSavedVenues[existingIndex] != venueWithCorrectArchiveStatus) {
        currentSavedVenues[existingIndex] = venueWithCorrectArchiveStatus;
        print("BookingDialog: Updated existing venue '${venueWithCorrectArchiveStatus.name}'.");
        wasActuallyAddedOrUpdated = true;
      }
    } else if (!currentSavedVenues.any((v) =>
    (v.placeId != null && venueWithCorrectArchiveStatus.placeId != null && v.placeId!.isNotEmpty && venueWithCorrectArchiveStatus.placeId!.isNotEmpty && v.placeId == venueWithCorrectArchiveStatus.placeId && v.placeId != StoredLocation.addNewVenuePlaceholder.placeId) ||
        (v.name.toLowerCase() == venueWithCorrectArchiveStatus.name.toLowerCase() && v.placeId != StoredLocation.addNewVenuePlaceholder.placeId)
    )) {
      currentSavedVenues.add(venueWithCorrectArchiveStatus);
      _allKnownVenuesInternal.add(venueWithCorrectArchiveStatus); // Update the internal cache
      print("BookingDialog: Added new venue '${venueWithCorrectArchiveStatus.name}'.");
      wasActuallyAddedOrUpdated = true;
    } else {
      print("BookingDialog: Venue '${venueWithCorrectArchiveStatus.name}' (Place ID: ${venueWithCorrectArchiveStatus.placeId}) already exists. Not re-saving as new.");
      if (widget.onNewVenuePotentiallyAdded != null) await widget.onNewVenuePotentiallyAdded!();
      return;
    }

    if (wasActuallyAddedOrUpdated) {
      final List<String> updatedLocationsJson = currentSavedVenues.map((loc) => jsonEncode(loc.toJson())).toList();
      bool success = await prefs.setStringList('saved_locations', updatedLocationsJson);
      if (success) {
        globalRefreshNotifier.notify(); // Notify other parts of the app
        print("BookingDialog: Global refresh notified after saving/updating venue.");
        // If a new venue was added, refresh the local dropdown for this dialog instance
        if (!_isEditingMode && !_isMapModeNewGig) { // Only if in calculator mode
          _loadSelectableVenuesForDropdown();
        }
      } else {
        print("BookingDialog: FAILED to save/update venue '${venueWithCorrectArchiveStatus.name}'.");
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: Could not save ${venueWithCorrectArchiveStatus.name}.'), backgroundColor: Colors.red));
      }
    }
    if (widget.onNewVenuePotentiallyAdded != null) await widget.onNewVenuePotentiallyAdded!();
  }

  Gig? _checkForConflict(DateTime newGigStart, double newGigDurationHours, List<Gig> otherGigsToCheck) {
    // Note: The `otherGigsToCheck` list should already have the current gig (if editing) excluded by the caller.
    final newGigEnd = newGigStart.add(Duration(milliseconds: (newGigDurationHours * 3600000).toInt()));
    for (var existingGig in otherGigsToCheck) {
      // The ID check is redundant if otherGigsToCheck is correctly filtered by the caller
      // if (gigIdToIgnore != null && existingGig.id == gigIdToIgnore) {
      //   continue;
      // }
      final existingGigStart = existingGig.dateTime;
      final existingGigEnd = existingGigStart.add(Duration(milliseconds: (existingGig.gigLengthHours * 3600000).toInt()));
      if (newGigStart.isBefore(existingGigEnd) && newGigEnd.isAfter(existingGigStart)) {
        bool startsDuring = newGigStart.isAtSameMomentAs(existingGigStart) || (newGigStart.isAfter(existingGigStart) && newGigStart.isBefore(existingGigEnd));
        bool endsDuring = newGigEnd.isAfter(existingGigStart) && (newGigEnd.isBefore(existingGigEnd) || newGigEnd.isAtSameMomentAs(existingGigEnd));
        bool envelops = newGigStart.isBefore(existingGigStart) && newGigEnd.isAfter(existingGigEnd);
        bool isEnvelopedBy = existingGigStart.isBefore(newGigStart) && existingGigEnd.isAfter(newGigEnd); // Corrected logic

        if (startsDuring || endsDuring || envelops || isEnvelopedBy || newGigStart.isAtSameMomentAs(existingGigStart)) {
          return existingGig;
        }
      }
    }
    return null;
  }

  Future<void> _handleGigCancellation() async {
    if (!_isEditingMode || widget.editingGig == null) return;
    setState(() => _isProcessing = true);
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
    setState(() => _isProcessing = false);
    if (confirmCancel) {
      if (mounted) Navigator.of(context).pop(GigEditResult(action: GigEditResultAction.deleted, gig: widget.editingGig));
    }
  }

  void _confirmAction() async { // Renamed from _confirmBooking / _confirmSaveOrUpdate
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a date and time.')));
      return;
    }
    setState(() => _isProcessing = true);

    double finalPay = double.tryParse(_payController.text) ?? 0;
    double finalGigLengthHours = double.tryParse(_gigLengthController.text) ?? 0;
    double finalDriveSetupHours = double.tryParse(_driveSetupController.text) ?? 0;
    double finalRehearsalHours = double.tryParse(_rehearsalController.text) ?? 0;

    if (_isCalculatorMode) { // Use widget values if from calculator
      finalPay = widget.totalPay!;
      finalGigLengthHours = widget.gigLengthHours!;
      finalDriveSetupHours = widget.driveSetupTimeHours!;
      finalRehearsalHours = widget.rehearsalTimeHours!;
    } else { // For Map mode new gig or Editing mode, values from controllers
      if (finalPay <= 0 || finalGigLengthHours <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Valid Pay & Gig Length required.')));
        setState(() => _isProcessing = false);
        return;
      }
    }


    StoredLocation finalVenueDetails;

    if (_isEditingMode) {
      finalVenueDetails = _selectedVenue!; // Venue is fixed
      if (finalVenueDetails.isArchived) { // Should not happen if UI prevents, but double check
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${finalVenueDetails.name} is archived. Gig cannot be updated to an archived venue.'), backgroundColor: Colors.orange));
        setState(() => _isProcessing = false);
        return;
      }
    } else if (_isMapModeNewGig) {
      finalVenueDetails = widget.preselectedVenue!;
      if (finalVenueDetails.isArchived) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${finalVenueDetails.name} is archived and cannot be booked.'), backgroundColor: Colors.orange));
        setState(() => _isProcessing = false);
        return;
      }
      // Ensure preselected venue from map is saved if it's new to the user's list
      final prefs = await SharedPreferences.getInstance();
      final List<String>? locationsJson = prefs.getStringList('saved_locations');
      bool isKnown = locationsJson?.any((json) => StoredLocation.fromJson(jsonDecode(json)).placeId == finalVenueDetails.placeId) ?? false;
      if (!isKnown) {
        await _saveNewVenueToPrefs(finalVenueDetails.copyWith(isArchived: false));
      }
    } else { // Calculator Mode (New Gig)
      if (_isAddNewVenue) {
        String newVenueName = _newVenueNameController.text.trim();
        String newVenueAddress = _newVenueAddressController.text.trim();
        LatLng? newVenueCoordinates = await _geocodeAddress(newVenueAddress); // This sets _isGeocoding
        if (newVenueCoordinates == null) {
          setState(() => _isProcessing = false); return;
        }
        finalVenueDetails = StoredLocation(
            placeId: 'manual_${DateTime.now().millisecondsSinceEpoch}', name: newVenueName, address: newVenueAddress,
            coordinates: newVenueCoordinates, isArchived: false
        );
        await _saveNewVenueToPrefs(finalVenueDetails);
      } else { // Existing venue selected from dropdown
        if (_selectedVenue == null || _selectedVenue!.placeId == StoredLocation.addNewVenuePlaceholder.placeId) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select or add a venue.')));
          setState(() => _isProcessing = false); return;
        }
        finalVenueDetails = _selectedVenue!;
        // Selected venue from dropdown should already be !isArchived due to dropdown filtering
      }
    }

    final DateTime newGigDateTime = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day, _selectedTime!.hour, _selectedTime!.minute);
    final String gigId = _isEditingMode ? widget.editingGig!.id : 'gig_${DateTime.now().millisecondsSinceEpoch}';

    final Gig newOrUpdatedGigData = Gig(
      id: gigId,
      venueName: finalVenueDetails.name, latitude: finalVenueDetails.coordinates.latitude,
      longitude: finalVenueDetails.coordinates.longitude, address: finalVenueDetails.address, placeId: finalVenueDetails.placeId,
      dateTime: newGigDateTime, pay: finalPay, gigLengthHours: finalGigLengthHours,
      driveSetupTimeHours: finalDriveSetupHours, rehearsalLengthHours: finalRehearsalHours,
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
      if (bookAnyway != true) {
        setState(() => _isProcessing = false);
        return; // User cancelled due to conflict
      }
    }
    setState(() => _isProcessing = false); // Processing ends before pop
    if (_isEditingMode) {
      Navigator.of(context).pop(GigEditResult(action: GigEditResultAction.updated, gig: newOrUpdatedGigData));
    } else { // New gig
      Navigator.of(context).pop(newOrUpdatedGigData); // GigsPage will handle this as a new Gig
    }
  }


  Widget _buildVenueDropdown() {
    if (_isEditingMode || _isMapModeNewGig) {
      // Venue is fixed, just display it.
      StoredLocation? venueToShow = _isEditingMode ? _selectedVenue : widget.preselectedVenue;
      if (venueToShow == null) return const Text("Venue information missing.", style: TextStyle(color: Colors.red, fontStyle: FontStyle.italic));

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_isEditingMode ? "Venue (Cannot Change):" : "Venue:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          Text(venueToShow.name, style: Theme.of(context).textTheme.titleMedium),
          Text(venueToShow.address, style: Theme.of(context).textTheme.bodySmall),
          if (venueToShow.isArchived)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text("(This venue is archived)", style: TextStyle(color: Colors.orange.shade700, fontStyle: FontStyle.italic, fontSize: 12)),
            ),
          const SizedBox(height: 8),
        ],
      );
    }

    // --- Calculator Mode: Venue Dropdown ---
    if (_isLoadingVenues) return const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()));

    if (_selectableVenuesForDropdown.isEmpty || (_selectableVenuesForDropdown.length == 1 && _selectableVenuesForDropdown.first.placeId == StoredLocation.addNewVenuePlaceholder.placeId && !_isAddNewVenue)) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: const Text('No active venues saved. Add one below or from the "Gigs" page venue list.', textAlign: TextAlign.center, style: TextStyle(fontStyle: FontStyle.italic)),
          ),
          DropdownButtonFormField<StoredLocation>(
            decoration: const InputDecoration(labelText: 'Select Venue', border: OutlineInputBorder()),
            value: _selectedVenue, // Should be the placeholder if this branch is hit
            isExpanded: true,
            hint: const Text('Add new venue'),
            items: [StoredLocation.addNewVenuePlaceholder].map<DropdownMenuItem<StoredLocation>>((StoredLocation venue) {
              return DropdownMenuItem<StoredLocation>(
                value: venue,
                child: Text(venue.name, overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: (StoredLocation? newValue) {
              setState(() {
                _selectedVenue = newValue;
                _isAddNewVenue = (newValue?.placeId == StoredLocation.addNewVenuePlaceholder.placeId);
              });
            },
            validator: (value) {
              if (value == null) return 'Please select an option.';
              return null;
            },
          ),
        ],
      );
    }

    return DropdownButtonFormField<StoredLocation>(
      decoration: const InputDecoration(labelText: 'Select Venue', border: OutlineInputBorder()),
      value: _selectedVenue,
      isExpanded: true,
      hint: const Text('Choose or add new venue'),
      items: _selectableVenuesForDropdown.map<DropdownMenuItem<StoredLocation>>((StoredLocation venue) {
        return DropdownMenuItem<StoredLocation>(
          value: venue,
          enabled: !venue.isArchived || venue.placeId == StoredLocation.addNewVenuePlaceholder.placeId,
          child: Text(
            venue.name + (venue.isArchived && venue.placeId != StoredLocation.addNewVenuePlaceholder.placeId ? " (Archived)" : ""),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: venue.isArchived && venue.placeId != StoredLocation.addNewVenuePlaceholder.placeId ? Colors.grey.shade500 : null,
            ),
          ),
        );
      }).toList(),
      onChanged: (StoredLocation? newValue) {
        if (newValue != null && newValue.isArchived && newValue.placeId != StoredLocation.addNewVenuePlaceholder.placeId) {
          // This should ideally not be reachable if `enabled` property is working.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("${newValue.name} is archived and cannot be selected."), backgroundColor: Colors.orange),
          );
          return;
        }
        setState(() {
          _selectedVenue = newValue;
          _isAddNewVenue = (newValue?.placeId == StoredLocation.addNewVenuePlaceholder.placeId);
        });
      },
      validator: (value) {
        if (value == null) return 'Please select a venue option.';
        if (value.isArchived && value.placeId != StoredLocation.addNewVenuePlaceholder.placeId) {
          return 'Archived venue cannot be booked.';
        }
        return null;
      },
    );
  }

  Widget _buildFinancialInputs() {
    // This is shown for "new from map" and "editing existing"
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _payController,
          decoration: const InputDecoration(labelText: 'Total Pay (\$)*', border: OutlineInputBorder(), prefixText: '\$'),
          keyboardType: const TextInputType.numberWithOptions(decimal: false), // No decimals for pay
          validator: (value) {
            if (value == null || value.isEmpty) return 'Pay is required';
            if (double.tryParse(value) == null) return 'Invalid number for pay';
            if (double.parse(value) <= 0) return 'Pay must be positive';
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
            if (double.tryParse(value) == null) return 'Invalid number for length';
            if (double.parse(value) <= 0) return 'Length must be positive';
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _driveSetupController,
          decoration: const InputDecoration(labelText: 'Drive/Setup (hours)', border: OutlineInputBorder(), suffixText: 'hrs'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (value) {
            if (value != null && value.isNotEmpty && double.tryParse(value) == null) return 'Invalid number for drive/setup';
            if (value != null && value.isNotEmpty && double.parse(value) < 0) return 'Drive/Setup cannot be negative';
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _rehearsalController,
          decoration: const InputDecoration(labelText: 'Rehearsal (hours)', border: OutlineInputBorder(), suffixText: 'hrs'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (value) {
            if (value != null && value.isNotEmpty && double.tryParse(value) == null) return 'Invalid number for rehearsal';
            if (value != null && value.isNotEmpty && double.parse(value) < 0) return 'Rehearsal cannot be negative';
            return null;
          },
        ),
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
    bool isDialogProcessing = _isProcessing || _isGeocoding || (_isLoadingVenues && _isCalculatorMode);


    String dialogTitle = "Book New Gig"; // Default for Calculator mode
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
                  // Section 1: Display pre-calculated details (Calculator Mode Only)
                  // OR Financial Input Fields (Map Mode New Gig / Editing Mode)
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
                  ] else ...[ // This covers _isMapModeNewGig OR _isEditingMode
                    _buildFinancialInputs(),
                    const Divider(height: 24, thickness: 1),
                  ],

                  // Section 2: Venue & Schedule (Common to all modes, but display varies)
                  Text(
                      _isEditingMode ? "Venue (Cannot Change):" : (_isMapModeNewGig ? "Confirm Venue & Schedule:" : "Venue & Schedule:"),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)
                  ),
                  const SizedBox(height: 12),
                  _buildVenueDropdown(), // Handles display/dropdown based on mode
                  const SizedBox(height: 12),

                  // "Add New Venue" fields (only in Calculator mode if "_isAddNewVenue" is true)
                  if (_isCalculatorMode && _isAddNewVenue) ...[
                    TextFormField(
                      controller: _newVenueNameController,
                      decoration: const InputDecoration(labelText: 'New Venue Name*', border: OutlineInputBorder()),
                      validator: (value) {
                        if (_isCalculatorMode && _isAddNewVenue && (value == null || value.isEmpty)) return 'Venue name is required';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _newVenueAddressController,
                      decoration: const InputDecoration(labelText: 'New Venue Address*', hintText: 'e.g., 1600 Amphitheatre Pkwy, Mountain View, CA', border: OutlineInputBorder()),
                      validator: (value) {
                        if (_isCalculatorMode && _isAddNewVenue && (value == null || value.isEmpty)) return 'Venue address is required';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Section 3: Date and Time Pickers (Common to all modes)
                  Row(
                    children: [
                      Expanded(child: Text(_selectedDate == null ? 'No date selected*' : 'Date: ${DateFormat.yMMMEd().format(_selectedDate!)}')),
                      TextButton(onPressed: isDialogProcessing ? null : () => _pickDate(context), child: const Text('SELECT DATE')),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: Text(_selectedTime == null ? 'No time selected*' : 'Time: ${_selectedTime!.format(context)}')),
                      TextButton(onPressed: isDialogProcessing ? null : () => _pickTime(context), child: const Text('SELECT TIME')),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Loading Overlay
          if (isDialogProcessing)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.3),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      actions: <Widget>[
        if (_isEditingMode)
          TextButton(
            child: const Text('CLOSE'), // New "CLOSE" button for edit mode
            onPressed: isDialogProcessing ? null : () => Navigator.of(context).pop(GigEditResult(action: GigEditResultAction.noChange)),
          )
        else // Standard "CANCEL" for new gig modes (was "CLOSE" before, "CANCEL" is more standard for aborting a new entry)
          TextButton(
            child: const Text('CANCEL'),
            onPressed: isDialogProcessing ? null : () => Navigator.of(context).pop(GigEditResult(action: GigEditResultAction.noChange)),
          ),

        // Group the destructive/confirm actions on the right if in edit mode
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isEditingMode) ...[
              TextButton(
                child: Text('CANCEL GIG', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                onPressed: isDialogProcessing ? null : _handleGigCancellation,
              ),
              const SizedBox(width: 8), // Spacer between buttons
            ],
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Theme.of(context).colorScheme.onPrimary),
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
