// lib/booking_dialog.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:the_money_gigs/global_refresh_notifier.dart';
import 'package:the_money_gigs/gig_model.dart';
import 'package:the_money_gigs/venue_model.dart';
import 'package:the_money_gigs/notes_page.dart';
import 'package:url_launcher/url_launcher.dart';

enum GigEditResultAction { updated, deleted, noChange }

class GigEditResult {
  final GigEditResultAction action;
  final Gig? gig;
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
  // <<< FIXED: Define a local constant for the placeholder >>>
  // This removes the dependency on the static getter from venue_model.dart
  // and resolves the 'addNewVenuePlaceholder isn't defined' error.
  static final StoredLocation _addNewVenuePlaceholder = StoredLocation(
    placeId: 'add_new_venue_placeholder',
    name: '--- Add New Venue ---',
    address: '',
    coordinates: const LatLng(0, 0),
  );

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

  String? _gigNotes;
  String? _gigNotesUrl;

  bool get _isEditingMode => widget.editingGig != null;
  bool get _isCalculatorMode => widget.calculatedHourlyRate != null && !_isEditingMode && widget.preselectedVenue == null;
  bool get _isMapModeNewGig => widget.preselectedVenue != null && !_isEditingMode;

  final TimeOfDay _defaultGigTime = const TimeOfDay(hour: 20, minute: 0);

  @override
  void initState() {
    super.initState();
    _initializeDialogState();
    globalRefreshNotifier.addListener(_onGlobalRefresh);
  }

  @override
  void dispose() {
    globalRefreshNotifier.removeListener(_onGlobalRefresh);
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

  void _onGlobalRefresh() {
    if (widget.editingGig != null && mounted) {
      _initializeDialogState();
    }
  }

  Future<void> _initializeDialogState() async {
    final prefs = await SharedPreferences.getInstance();
    final allGigsJson = prefs.getString('gigs_list') ?? '[]';
    final allGigs = Gig.decode(allGigsJson);

    await _loadAllKnownVenuesInternal();
    if (!mounted) return;

    if (_isEditingMode) {
      final currentGig = allGigs.firstWhere(
            (g) => g.id == widget.editingGig!.id,
        orElse: () => widget.editingGig!,
      );

      _payController = TextEditingController(text: currentGig.pay.toStringAsFixed(0));
      _gigLengthController = TextEditingController(text: currentGig.gigLengthHours.toStringAsFixed(1));
      _driveSetupController = TextEditingController(text: currentGig.driveSetupTimeHours.toStringAsFixed(1));
      _rehearsalController = TextEditingController(text: currentGig.rehearsalLengthHours.toStringAsFixed(1));
      _selectedDate = currentGig.dateTime;
      _selectedTime = TimeOfDay.fromDateTime(currentGig.dateTime);
      _gigNotes = currentGig.notes;
      _gigNotesUrl = currentGig.notesUrl;

      _selectedVenue = _allKnownVenuesInternal.firstWhere(
            (v) => (currentGig.placeId != null && v.placeId == currentGig.placeId) || (v.name == currentGig.venueName && v.address == currentGig.address),
        orElse: () => StoredLocation(
            placeId: currentGig.placeId ?? 'edited_${currentGig.id}',
            name: currentGig.venueName,
            address: currentGig.address,
            coordinates: LatLng(currentGig.latitude, currentGig.longitude),
            isArchived: true,
            hasJamOpenMic: false,
            jamStyle: null
        ),
      );
      _isAddNewVenue = false;
      _isLoadingVenues = false;

      if (!_payController.hasListeners) {
        _payController.addListener(_calculateDynamicRate);
        _gigLengthController.addListener(_calculateDynamicRate);
        _driveSetupController.addListener(_calculateDynamicRate);
        _rehearsalController.addListener(_calculateDynamicRate);
      }
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

  void _showNotesPage() {
    if (widget.editingGig == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NotesPage(editingGigId: widget.editingGig!.id),
      ),
    );
  }

  void _confirmAction() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null || _selectedTime == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a date and time.')));
      }
      return;
    }
    if (mounted) setState(() => _isProcessing = true);

    final DateTime selectedFullDateTime = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day, _selectedTime!.hour, _selectedTime!.minute);
    double finalPay, finalGigLengthHours, finalDriveSetupHours, finalRehearsalHours;

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
    }

    StoredLocation finalVenueDetails;
    if (_isAddNewVenue) {
      String newVenueName = _newVenueNameController.text.trim();
      String newVenueAddress = _newVenueAddressController.text.trim();
      if (newVenueName.isEmpty || newVenueAddress.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('New venue name and address are required.')));
          setState(() => _isProcessing = false);
        }
        return;
      }
      LatLng? coords = await _geocodeAddress(newVenueAddress);
      if (coords == null) {
        if (mounted) setState(() => _isProcessing = false);
        return;
      }
      finalVenueDetails = StoredLocation(
        placeId: 'manual_${DateTime.now().millisecondsSinceEpoch}',
        name: newVenueName,
        address: newVenueAddress,
        coordinates: coords,
        isArchived: false,
        hasJamOpenMic: false,
        jamStyle: null,
      );
      await _saveNewVenueToPrefs(finalVenueDetails);
    } else {
      finalVenueDetails = _selectedVenue!;
    }
    if (!mounted) {
      setState(() => _isProcessing = false);
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
      dateTime: selectedFullDateTime,
      pay: finalPay,
      gigLengthHours: finalGigLengthHours,
      driveSetupTimeHours: finalDriveSetupHours,
      rehearsalLengthHours: finalRehearsalHours,
      notes: _gigNotes,
      notesUrl: _gigNotesUrl,
    );

    List<Gig> otherGigsToCheck = List.from(widget.existingGigs.where((g) => !g.isJamOpenMic));
    if (_isEditingMode) {
      otherGigsToCheck.removeWhere((g) => g.id == widget.editingGig!.id);
    }
    final conflictingGig = _checkForConflict(newOrUpdatedGigData.dateTime, newOrUpdatedGigData.gigLengthHours, otherGigsToCheck);
    if (conflictingGig != null) {
      final bool? bookAnyway = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('Scheduling Conflict'),
          content: Text('This gig conflicts with "${conflictingGig.venueName}" on ${DateFormat.yMMMEd().format(conflictingGig.dateTime)}. ${_isEditingMode ? "Update" : "Book"} anyway?'),
          actions: <Widget>[
            TextButton(child: const Text('CANCEL'), onPressed: () => Navigator.of(dialogContext).pop(false)),
            TextButton(child: Text('${_isEditingMode ? "UPDATE" : "BOOK"} ANYWAY'), onPressed: () => Navigator.of(dialogContext).pop(true)),
          ],
        ),
      );
      if (bookAnyway != true) {
        if (mounted) setState(() => _isProcessing = false);
        return;
      }
    }

    if (mounted) setState(() => _isProcessing = false);

    if (_isEditingMode) {
      Navigator.of(context).pop(GigEditResult(action: GigEditResultAction.updated, gig: newOrUpdatedGigData));
    } else {
      Navigator.of(context).pop(newOrUpdatedGigData);
    }
  }

  Future<void> _loadAllKnownVenuesInternal() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? locationsJson = prefs.getStringList('saved_locations');
    if (locationsJson != null) {
      _allKnownVenuesInternal = locationsJson.map((jsonString) {
        try { return StoredLocation.fromJson(jsonDecode(jsonString)); }
        catch (e) { print("Error decoding one stored location in BookingDialog: $e"); return null; }
      }).whereType<StoredLocation>().toList();
    }
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
      newRateString = "Enter hours"; newColor = Colors.orangeAccent;
    } else if (pay <= 0 && totalHoursForRateCalc > 0) {
      newRateString = "Enter pay"; newColor = Colors.orangeAccent;
    } else {
      newRateString = "Rate: N/A"; newColor = Colors.grey;
    }
    if (mounted) setState(() { _dynamicRateString = newRateString; _dynamicRateResultColor = newColor; });
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
      _selectableVenuesForDropdown.removeWhere((v) => v.placeId == _addNewVenuePlaceholder.placeId); // FIXED
      _selectableVenuesForDropdown.sort((a,b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _selectableVenuesForDropdown.insert(0, _addNewVenuePlaceholder); // FIXED

      if (_selectableVenuesForDropdown.length == 1 && _selectableVenuesForDropdown.first.placeId == _addNewVenuePlaceholder.placeId) { // FIXED
        _selectedVenue = _selectableVenuesForDropdown.first;
        _isAddNewVenue = true;
      } else if (_selectableVenuesForDropdown.length > 1) {
        _selectedVenue = _selectableVenuesForDropdown.firstWhere((v) => v.placeId != _addNewVenuePlaceholder.placeId && !v.isArchived, orElse: () => _selectableVenuesForDropdown.first); // FIXED
        _isAddNewVenue = (_selectedVenue?.placeId == _addNewVenuePlaceholder.placeId); // FIXED
      } else {
        _selectableVenuesForDropdown = [_addNewVenuePlaceholder]; // FIXED
        _selectedVenue = _selectableVenuesForDropdown.first;
        _isAddNewVenue = true;
      }
    } catch (e) {
      print("Error filtering/setting up venues for dropdown: $e");
      _selectableVenuesForDropdown = [_addNewVenuePlaceholder]; // FIXED
      _selectedVenue = _addNewVenuePlaceholder; // FIXED
      _isAddNewVenue = true;
    } finally {
      if (mounted) setState(() { _isLoadingVenues = false; });
    }
  }

  Future<void> _pickDate(BuildContext context) async {
    final DateTime initialDatePickerDate = _selectedDate ?? DateTime.now();
    final DateTime? picked = await showDatePicker(context: context, initialDate: initialDatePickerDate, firstDate: DateTime(DateTime.now().year - 5), lastDate: DateTime(DateTime.now().year + 5));
    if (picked != null && picked != _selectedDate) {
      if(mounted) setState(() { _selectedDate = picked; });
    }
  }

  Future<void> _pickTime(BuildContext context) async {
    final TimeOfDay initialPickerTime = _selectedTime ?? _defaultGigTime;
    final TimeOfDay? picked = await showTimePicker(context: context, initialTime: initialPickerTime);
    if (picked != null && picked != _selectedTime) {
      if(mounted) setState(() { _selectedTime = picked; });
    }
  }

  Future<LatLng?> _geocodeAddress(String address) async {
    if (widget.googleApiKey.isEmpty || widget.googleApiKey == "YOUR_GOOGLE_PLACES_API_KEY_HERE") {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Geocoding failed: API Key not configured.'), backgroundColor: Colors.red));
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
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not find coordinates: ${data['status']} ${data['error_message'] ?? ''}')));
          return null;
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error contacting Geocoding service: ${response.statusCode}')));
        return null;
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('An error occurred while finding coordinates: $e')));
      return null;
    } finally {
      if (mounted) setState(() => _isGeocoding = false);
    }
  }

  Future<void> _saveNewVenueToPrefs(StoredLocation venueToSave) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final StoredLocation venueWithCorrectArchiveStatus = venueToSave.copyWith(isArchived: venueToSave.placeId.startsWith('manual_') ? false : venueToSave.isArchived);
    List<StoredLocation> currentSavedVenues = List.from(_allKnownVenuesInternal);
    int existingIndex = -1;
    if(venueWithCorrectArchiveStatus.placeId != _addNewVenuePlaceholder.placeId && venueWithCorrectArchiveStatus.placeId.isNotEmpty) { // FIXED
      existingIndex = currentSavedVenues.indexWhere((v) => v.placeId == venueWithCorrectArchiveStatus.placeId);
    }
    bool wasActuallyAddedOrUpdated = false;
    if (existingIndex != -1) {
      if (currentSavedVenues[existingIndex] != venueWithCorrectArchiveStatus) {
        currentSavedVenues[existingIndex] = venueWithCorrectArchiveStatus;
        wasActuallyAddedOrUpdated = true;
      }
    } else if (venueWithCorrectArchiveStatus.placeId != _addNewVenuePlaceholder.placeId && !currentSavedVenues.any((v) =>(v.placeId.isNotEmpty && venueWithCorrectArchiveStatus.placeId.isNotEmpty && v.placeId == venueWithCorrectArchiveStatus.placeId) ||(v.name.toLowerCase() == venueWithCorrectArchiveStatus.name.toLowerCase() && v.address.toLowerCase() == venueWithCorrectArchiveStatus.address.toLowerCase()))) { // FIXED
      currentSavedVenues.add(venueWithCorrectArchiveStatus);
      wasActuallyAddedOrUpdated = true;
    }
    if (wasActuallyAddedOrUpdated) {
      _allKnownVenuesInternal = List.from(currentSavedVenues);
      final List<String> updatedLocationsJson = _allKnownVenuesInternal.where((loc) => loc.placeId != _addNewVenuePlaceholder.placeId).map((loc) => jsonEncode(loc.toJson())).toList(); // FIXED
      await prefs.setStringList('saved_locations', updatedLocationsJson);
      globalRefreshNotifier.notify();
      if (_isCalculatorMode && mounted) {
        await _loadSelectableVenuesForDropdown();
        final newVenueInList = _allKnownVenuesInternal.firstWhere((v) => v.placeId == venueToSave.placeId, orElse: () => _selectedVenue ?? _addNewVenuePlaceholder); // FIXED
        if(mounted) {
          setState(() {
            _selectedVenue = newVenueInList;
            _isAddNewVenue = false;
          });
        }
      }
    }
    if (widget.onNewVenuePotentiallyAdded != null) await widget.onNewVenuePotentiallyAdded!();
  }

  Gig? _checkForConflict(DateTime newGigStart, double newGigDurationHours, List<Gig> otherGigsToCheck) {
    final newGigEnd = newGigStart.add(Duration(milliseconds: (newGigDurationHours * 3600000).toInt()));
    for (var existingGig in otherGigsToCheck) {
      if (existingGig.isJamOpenMic) continue;
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

  Widget _buildVenueDropdown() {
    // ... This method is unchanged ...
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
    return DropdownButtonFormField<StoredLocation>(
      decoration: const InputDecoration(labelText: 'Select or Add Venue', border: OutlineInputBorder()),
      value: _selectedVenue,
      isExpanded: true,
      items: _selectableVenuesForDropdown.map<DropdownMenuItem<StoredLocation>>((StoredLocation venue) {
        bool isEnabled = !venue.isArchived || venue.placeId == _addNewVenuePlaceholder.placeId; // FIXED
        return DropdownMenuItem<StoredLocation>(
          value: venue,
          enabled: isEnabled,
          child: Text( venue.name + (venue.isArchived && venue.placeId != _addNewVenuePlaceholder.placeId ? " (Archived)" : ""), overflow: TextOverflow.ellipsis, style: TextStyle( color: isEnabled ? null : Colors.grey.shade500, ),), // FIXED
        );
      }).toList(),
      onChanged: (StoredLocation? newValue) {
        if (newValue == null) return;
        if (newValue.isArchived && newValue.placeId != _addNewVenuePlaceholder.placeId) { // FIXED
          if(mounted) { ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text("${newValue.name} is archived and cannot be selected."), backgroundColor: Colors.orange), ); }
          return;
        }
        if(mounted) { setState(() { _selectedVenue = newValue; _isAddNewVenue = (newValue.placeId == _addNewVenuePlaceholder.placeId); });} // FIXED
      },
      validator: (value) {
        if (value == null) return 'Please select a venue option.';
        if (value.isArchived && value.placeId != _addNewVenuePlaceholder.placeId) { return 'Archived venues cannot be booked.'; } // FIXED
        return null;
      },
    );
  }

  // ... The rest of the file (_buildFinancialInputs, build method) is unchanged...
  // ... but for completeness, it is included below ...
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
    bool isDialogProcessing = _isProcessing || _isGeocoding || (_isLoadingVenues && _isCalculatorMode && !_isAddNewVenue);

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

                  if ((_isCalculatorMode || _isMapModeNewGig) && _isAddNewVenue) ...[
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

                  if (_isEditingMode) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: OutlinedButton.icon(
                        icon: Icon((_gigNotes?.isNotEmpty ?? false) || (_gigNotesUrl?.isNotEmpty ?? false) ? Icons.speaker_notes : Icons.speaker_notes_off_outlined),
                        label: const Text('GIG NOTES & LINK'),
                        onPressed: isDialogProcessing ? null : _showNotesPage,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: (_gigNotes?.isNotEmpty ?? false) || (_gigNotesUrl?.isNotEmpty ?? false) ? Theme.of(context).colorScheme.primary : Colors.grey,
                          side: BorderSide(color: (_gigNotes?.isNotEmpty ?? false) || (_gigNotesUrl?.isNotEmpty ?? false) ? Theme.of(context).colorScheme.primary : Colors.grey),
                        ),
                      ),
                    ),
                  ],
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
        if (_isEditingMode)
          TextButton(
            child: Text('CANCEL GIG', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onPressed: isDialogProcessing ? null : _handleGigCancellation,
          )
        else
          TextButton(
            child: const Text('CANCEL'),
            onPressed: isDialogProcessing ? null : () => Navigator.of(context).pop(),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isEditingMode)
              TextButton(
                child: const Text('CLOSE'),
                onPressed: isDialogProcessing ? null : () => Navigator.of(context).pop(GigEditResult(action: GigEditResultAction.noChange)),
              ),
            const SizedBox(width: 8),
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
