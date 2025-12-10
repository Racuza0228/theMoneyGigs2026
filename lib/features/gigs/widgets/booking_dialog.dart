// lib/features/gigs/widgets/booking_dialog.dart
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:the_money_gigs/core/services/drive_time_service.dart';
import 'package:the_money_gigs/core/widgets/drive_time_display.dart';
import 'package:the_money_gigs/global_refresh_notifier.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';
import 'package:the_money_gigs/core/models/enums.dart';
import 'package:the_money_gigs/features/app_demo/providers/demo_provider.dart';
import 'package:the_money_gigs/features/app_demo/widgets/tutorial_overlay.dart';
import 'package:the_money_gigs/features/gigs/widgets/booking_dialog_widgets/calculator_summary_view.dart';
import 'package:the_money_gigs/features/gigs/widgets/booking_dialog_widgets/financial_inputs_view.dart';
import 'package:the_money_gigs/features/gigs/widgets/booking_dialog_widgets/venue_selection_view.dart';
import 'package:the_money_gigs/core/services/notification_service.dart'; // <-- ADD THIS
import 'package:the_money_gigs/features/gigs/widgets/recurring_gig_dialog.dart';

class _DialogDemoStep {
  final GlobalKey key;
  final String text;
  final Alignment alignment;
  final VoidCallback? onBefore;
  final bool hideNextButton;

  _DialogDemoStep({
    required this.key,
    required this.text,
    required this.alignment,
    this.onBefore,
    this.hideNextButton = false,
  });
}

enum GigEditResultAction { updated, deleted, noChange }
enum RecurringCancelChoice { thisInstanceOnly, allFutureInstances, doNothing }

class GigEditResult {
  final GigEditResultAction action;
  final Gig? gig;
  final RecurringCancelChoice? cancelChoice; // Pass the choice

  GigEditResult({required this.action, this.gig, this.cancelChoice});
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
  static final StoredLocation _addNewVenuePlaceholder = StoredLocation(
    placeId: 'add_new_venue_placeholder',
    name: '--- Add New Venue ---',
    address: '',
    coordinates: const LatLng(0, 0),
  );

  final AudioPlayer _audioPlayer = AudioPlayer();

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
  final FocusNode _newVenueAddressFocusNode = FocusNode();

  String? _manualDriveDurationString;
  String? _manualDriveDistance;

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  bool _isLoadingVenues = false;
  bool _isGeocoding = false;
  bool _isProcessing = false;

  Gig? _editableGig;

  bool _isFetchingDriveTime = false;
  bool _isPrivateVenue = false;

  String? _profileAddress1;
  String? _profileCity;
  String? _profileState;
  String? _profileZipCode;
  String? _userProfileAddressForDisplay;

  // --- DEMO KEYS & SCRIPT ---
  final GlobalKey _summaryKey = GlobalKey();
  final GlobalKey _venueSectionKey = GlobalKey();
  final GlobalKey _dateSectionKey = GlobalKey();
  final GlobalKey _confirmBtnKey = GlobalKey();
  late final List<_DialogDemoStep> _demoScript;

  bool get _isEditingMode => widget.editingGig != null;
  bool get _isCalculatorMode => widget.calculatedHourlyRate != null && !_isEditingMode && widget.preselectedVenue == null;
  bool get _isMapModeNewGig => widget.preselectedVenue != null && !_isEditingMode;
  bool _isInitialized = false;

  final TimeOfDay _defaultGigTime = const TimeOfDay(hour: 20, minute: 0);

  @override
  void initState() {
    super.initState();
    _initializeDialogState();
    _newVenueAddressFocusNode.addListener(_onAddressFocusChange);

    _demoScript = [
      _DialogDemoStep(
        key: _summaryKey,
        text: 'Notice the pay and time details have been transferred.',
        alignment: Alignment.center,
      ),
      _DialogDemoStep(
        key: _venueSectionKey,
        text: 'Next, provide the venue info. We\'ll use a favorite place of mine to play, Oakley Kroger. Stop in, catch a performance, and say Hello to Jay sometime!',
        alignment: Alignment.bottomCenter,
        onBefore: () {
          _newVenueNameController.text = "Kroger Marketplace";
          _newVenueAddressController.text = "4613 Marburg Ave, Cincinnati, OH 45209";
        },
      ),
      _DialogDemoStep(
        key: _dateSectionKey,
        text: 'Now we pick the date and time for the gig. We can use today at 8.',
        alignment: Alignment.topCenter,
        onBefore: () {
          if (mounted) {
            setState(() {
              _selectedDate = DateTime.now();
            });
          }
        },
      ),
      _DialogDemoStep(
        key: _confirmBtnKey,
        text: 'Finally, Confirm & Book! Click that button!',
        alignment: Alignment.center,
        hideNextButton: true,
      ),
    ];
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _newVenueNameController.dispose();
    _newVenueAddressController.dispose();
    _newVenueAddressFocusNode.removeListener(_onAddressFocusChange);
    _newVenueAddressFocusNode.dispose();
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

  void _onAddressFocusChange() {
    if (!_newVenueAddressFocusNode.hasFocus &&
        _isAddNewVenue &&
        _newVenueAddressController.text.trim().isNotEmpty) {
      _fetchDriveTimeForManualAddress();
    }
  }

  // Inside _BookingDialogState class in booking_dialog.dart

  Future<void> _scheduleGigNotifications(Gig gig) async {
    final prefs = await SharedPreferences.getInstance();
    final notificationService = NotificationService();
    final int baseNotificationId = gig.id.hashCode;

    // --- Schedule notification for the day of the gig ---
    final bool notifyOnDayOfGig = prefs.getBool('notify_on_day_of_gig') ?? false;
    final int dayOfGigNotificationId = baseNotificationId;

    if (notifyOnDayOfGig) {
      // THIS IS THE TEST CODE WE NEED. IT SETS THE NOTIFICATION FOR 1 MINUTE FROM NOW.
      final DateTime scheduledDate = DateTime.now().add(const Duration(minutes: 1));

      if (scheduledDate.isAfter(DateTime.now())) {
        // We will use the detailed scheduleNotification method from notification_service.dart
        // which has the try/catch block for debugging.
        await notificationService.scheduleNotification(
          id: dayOfGigNotificationId,
          title: '[TEST] Gig Reminder',
          body: 'Your gig "${gig.venueName}" is scheduled for ${DateFormat.jm().format(gig.dateTime)}.',
          scheduledDate: scheduledDate,
        );
      }
    } else {
      await notificationService.cancelNotification(dayOfGigNotificationId);
    }

    // --- Schedule notification for 'days before' the gig ---
    final int? daysBefore = prefs.getInt('notify_days_before');
    final int daysBeforeNotificationId = baseNotificationId + 1;

    if (daysBefore != null && daysBefore > 0) {
      final DateTime notificationDate = gig.dateTime.subtract(Duration(days: daysBefore));
      final DateTime scheduledDate = DateTime(notificationDate.year, notificationDate.month, notificationDate.day, 9, 0);

      if (scheduledDate.isAfter(DateTime.now())) {
        await notificationService.scheduleNotification(
          id: daysBeforeNotificationId,
          title: 'Upcoming Gig Reminder',
          body: 'Your gig "${gig.venueName}" is in $daysBefore day(s).',
          scheduledDate: scheduledDate,
        );
      }
    } else {
      await notificationService.cancelNotification(daysBeforeNotificationId);
    }
  }

  Future<void> _cancelGigNotifications(Gig gig) async {
    final notificationService = NotificationService();
    final int baseNotificationId = gig.id.hashCode;

    // Cancel both potential notifications
    await notificationService.cancelNotification(baseNotificationId);      // Day-of notification
    await notificationService.cancelNotification(baseNotificationId + 1);  // Days-before notification
  }

  Future<void> _loadProfileAddress() async {
    final prefs = await SharedPreferences.getInstance();
    _profileAddress1 = prefs.getString('profile_address1');
    _profileCity = prefs.getString('profile_city');
    _profileState = prefs.getString('profile_state');
    _profileZipCode = prefs.getString('profile_zip_code');

    if ((_profileCity != null && _profileCity!.isNotEmpty) || (_profileZipCode != null && _profileZipCode!.isNotEmpty)) {
      _userProfileAddressForDisplay = '${_profileCity ?? ''}, ${_profileState ?? ''} ${_profileZipCode ?? ''}'.trim();
    } else {
      _userProfileAddressForDisplay = null;
    }
  }

  Future<void> _initializeDialogState() async {
    await _loadProfileAddress();
    await _loadAllKnownVenuesInternal();
    if (!mounted) return;

    if (_isEditingMode) {
      // --- (a) DEBUG PRINT: Print the incoming gig data ---
      print("--- LOADING GIG INTO DIALOG ---");
      print("Gig ID: ${widget.editingGig!.id}");
      print("isRecurring: ${widget.editingGig!.isRecurring}");
      print("Frequency: ${widget.editingGig!.recurrenceFrequency}");
      print("Day: ${widget.editingGig!.recurrenceDay}");
      print("Nth Value: ${widget.editingGig!.recurrenceNthValue}");
      print("End Date: ${widget.editingGig!.recurrenceEndDate}");
      print("---------------------------------");

      _editableGig = widget.editingGig!.copyWith(
        // Explicitly copy all fields to ensure a complete state object
        id: widget.editingGig!.id,
        venueName: widget.editingGig!.venueName,
        latitude: widget.editingGig!.latitude,
        longitude: widget.editingGig!.longitude,
        address: widget.editingGig!.address,
        placeId: widget.editingGig!.placeId,
        dateTime: widget.editingGig!.dateTime,
        pay: widget.editingGig!.pay,
        gigLengthHours: widget.editingGig!.gigLengthHours,
        driveSetupTimeHours: widget.editingGig!.driveSetupTimeHours,
        rehearsalLengthHours: widget.editingGig!.rehearsalLengthHours,
        isJamOpenMic: widget.editingGig!.isJamOpenMic,
        notes: widget.editingGig!.notes,
        notesUrl: widget.editingGig!.notesUrl,
        isRecurring: widget.editingGig!.isRecurring,
        recurrenceFrequency: widget.editingGig!.recurrenceFrequency,
        recurrenceDay: widget.editingGig!.recurrenceDay,
        recurrenceNthValue: widget.editingGig!.recurrenceNthValue,
        recurrenceEndDate: widget.editingGig!.recurrenceEndDate,
      );

      _payController = TextEditingController(text: _editableGig!.pay.toStringAsFixed(0));
      _gigLengthController = TextEditingController(text: _editableGig!.gigLengthHours.toStringAsFixed(1));
      _driveSetupController = TextEditingController(text: _editableGig!.driveSetupTimeHours.toStringAsFixed(1));
      _rehearsalController = TextEditingController(text: _editableGig!.rehearsalLengthHours.toStringAsFixed(1));

      _selectedDate = _editableGig!.dateTime;
      _selectedTime = TimeOfDay.fromDateTime(_editableGig!.dateTime);

      _selectedVenue = _allKnownVenuesInternal.firstWhere(
            (v) => (_editableGig!.placeId != null && v.placeId == _editableGig!.placeId) || (v.name == _editableGig!.venueName && v.address == _editableGig!.address),
        orElse: () => StoredLocation( placeId: _editableGig!.placeId ?? 'edited_${_editableGig!.id}', name: _editableGig!.venueName, address: _editableGig!.address, coordinates: LatLng(_editableGig!.latitude, _editableGig!.longitude), isArchived: true),
      );
      _isAddNewVenue = false;
      _isLoadingVenues = false;

      await _handleVenueSelection(_selectedVenue);

      _payController.addListener(_calculateDynamicRate);
      _gigLengthController.addListener(_calculateDynamicRate);
      _driveSetupController.addListener(_calculateDynamicRate);
      _rehearsalController.addListener(_calculateDynamicRate);
      _calculateDynamicRate();

    } else {

      _payController = TextEditingController(text: widget.totalPay?.toStringAsFixed(0) ?? '');
      _gigLengthController = TextEditingController(text: widget.gigLengthHours?.toStringAsFixed(1) ?? '');
      _driveSetupController = TextEditingController(text: widget.driveSetupTimeHours?.toStringAsFixed(1) ?? '');
      _rehearsalController = TextEditingController(text: widget.rehearsalTimeHours?.toStringAsFixed(1) ?? '');

      _editableGig = Gig(
        id: 'new_${DateTime.now().millisecondsSinceEpoch}',
        venueName: widget.preselectedVenue?.name ?? '',
        address: widget.preselectedVenue?.address ?? '',
        latitude: widget.preselectedVenue?.coordinates.latitude ?? 0,
        longitude: widget.preselectedVenue?.coordinates.longitude ?? 0,
        dateTime: DateTime.now(), // Default, will be updated by picker
        pay: widget.totalPay ?? 0,
        gigLengthHours: widget.gigLengthHours ?? 0,
        driveSetupTimeHours: widget.driveSetupTimeHours ?? 0,
        rehearsalLengthHours: widget.rehearsalTimeHours ?? 0,
      );

      _selectedTime = _defaultGigTime;

      if (_isMapModeNewGig) {
        _selectedVenue = widget.preselectedVenue;
        _isPrivateVenue = _selectedVenue?.isPrivate ?? false;
        _isAddNewVenue = false;
        _isLoadingVenues = false;
        await _handleVenueSelection(_selectedVenue);

        _payController.addListener(_calculateDynamicRate);
        _gigLengthController.addListener(_calculateDynamicRate);
        _driveSetupController.addListener(_calculateDynamicRate);
        _rehearsalController.addListener(_calculateDynamicRate);
        _calculateDynamicRate();
      } else {
        await _loadSelectableVenuesForDropdown(defaultToAddVenue: true);
      }
    }
    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  DriveTimeService _createDriveTimeService() {
    return DriveTimeService(
      googleApiKey: widget.googleApiKey,
      allKnownVenues: _allKnownVenuesInternal,
      address1: _profileAddress1,
      city: _profileCity,
      state: _profileState,
      zipCode: _profileZipCode,
    );
  }

  Future<void> _handleVenueSelection(StoredLocation? venue) async {
    setState(() {
      _manualDriveDistance = null;
      _manualDriveDurationString = null;
    });

    if (venue == null || venue.placeId == _addNewVenuePlaceholder.placeId) {
      setState(() {
        _selectedVenue = venue;
        _isAddNewVenue = (venue?.placeId == _addNewVenuePlaceholder.placeId);
        if (!_isAddNewVenue) {
          _isPrivateVenue = venue?.isPrivate ?? false;
        } else {
          _isPrivateVenue = false;
        }
      });
      return;
    }

    setState(() {
      _selectedVenue = venue;
      _isAddNewVenue = false;
    });

    if (venue.driveDuration == null) {
      setState(() => _isFetchingDriveTime = true);
      final driveTimeService = _createDriveTimeService();
      final updatedVenue = await driveTimeService.fetchAndCacheDriveTime(venue);

      if (mounted) {
        setState(() {
          if (updatedVenue != null) {
            final index = _allKnownVenuesInternal.indexWhere((v) => v.placeId == updatedVenue.placeId);
            if(index != -1) _allKnownVenuesInternal[index] = updatedVenue;
            _selectedVenue = updatedVenue;
          }
          _isFetchingDriveTime = false;
        });
      }
    }
  }

  Future<void> _fetchDriveTimeForManualAddress() async {
    final address = _newVenueAddressController.text.trim();
    if (address.isEmpty) return;
    setState(() => _isFetchingDriveTime = true);
    LatLng? coords = await _geocodeAddress(address);
    if (coords != null && mounted) {
      final tempVenue = StoredLocation(
        name: 'temp',
        address: address,
        coordinates: coords,
        placeId: 'temp_manual_place_id_${DateTime.now().millisecondsSinceEpoch}',
      );
      final driveTimeService = _createDriveTimeService();
      final resultVenue = await driveTimeService.fetchAndCacheDriveTime(tempVenue);
      if (mounted) {
        setState(() {
          _manualDriveDurationString = resultVenue?.driveDuration;
          _manualDriveDistance = resultVenue?.driveDistance;
        });
      }
    }
    if (mounted) {
      setState(() => _isFetchingDriveTime = false);
    }
  }

  Future<void> _openRecurringGigSettings() async {
    if (_editableGig == null) return;

    Gig gigForDialog = _editableGig!;
    if (!_editableGig!.isRecurring) {
      gigForDialog = _editableGig!.copyWith(
        isRecurring: true, // Check the box by default
        recurrenceFrequency: JamFrequencyType.weekly, // Default to weekly
        recurrenceDay: DayOfWeek.values[_editableGig!.dateTime.weekday - 1],
      );
    }

    final updatedGig = await showDialog<Gig>(
      context: context,
      builder: (context) => RecurringGigDialog(gig: gigForDialog),
    );

    if (updatedGig != null && mounted) {
      setState(() {
        _editableGig = updatedGig; // Update the state with changes from the dialog
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_editableGig!.isRecurring ? 'Recurrence settings applied.' : 'Recurrence settings removed.'),
          duration: const Duration(seconds: 2),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    }
  }

  void _confirmAction() async {
    final demoProvider = Provider.of<DemoProvider>(context, listen: false);
    // When on the final demo step, clicking this button just finishes the demo.
    if (demoProvider.isDemoModeActive && demoProvider.currentStep == 11) {
      // ... demo logic remains the same
      if (mounted) setState(() => _isProcessing = true);

      // 1. Create the demo venue and gig objects using the static IDs from DemoProvider
      const LatLng demoCoords = LatLng(39.1602761, -84.429593);
      final demoVenue = StoredLocation(
        placeId: DemoProvider.demoVenuePlaceId,
        name: 'Kroger Marketplace',
        address: '4613 Marburg Ave, Cincinnati, OH 45209',
        coordinates: demoCoords,
      );

      final demoGig = Gig(
        id: DemoProvider.demoGigId,
        venueName: demoVenue.name,
        address: demoVenue.address,
        placeId: demoVenue.placeId,
        latitude: demoCoords.latitude,
        longitude: demoCoords.longitude,
        dateTime: DateTime.now().add(const Duration(days: 7)),
        pay: 250,
        gigLengthHours: 3,
        driveSetupTimeHours: 2.5,
        rehearsalLengthHours: 2,
      );

      // 2. Save them to SharedPreferences
      final prefs = await SharedPreferences.getInstance();

      // Save Venue
      _allKnownVenuesInternal.removeWhere((v) => v.placeId == DemoProvider.demoVenuePlaceId);
      _allKnownVenuesInternal.add(demoVenue);
      final List<String> updatedLocationsJson = _allKnownVenuesInternal.map((loc) => jsonEncode(loc.toJson())).toList();
      await prefs.setStringList('saved_locations', updatedLocationsJson);

      // Save Gig
      final String? gigsJsonString = prefs.getString('gigs_list');
      List<Gig> allGigs = (gigsJsonString != null) ? Gig.decode(gigsJsonString) : [];
      allGigs.removeWhere((g) => g.id == DemoProvider.demoGigId);
      allGigs.add(demoGig);
      await prefs.setString('gigs_list', Gig.encode(allGigs));

      // 3. Notify the app that data has changed, so the map updates itself
      if (mounted) context.read<GlobalRefreshNotifier>().notify();

      if (mounted) setState(() => _isProcessing = false);

      // 4. Proceed with the rest of the demo flow
      await _audioPlayer.play(AssetSource('sounds/thetone.wav'));
      await Future.delayed(const Duration(milliseconds: 2500));
      demoProvider.nextStep(); // Advance to step 12
      if (mounted) Navigator.of(context).pop("demo_completed");
      return;
    }


    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null || _selectedTime == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a date and time.')));
      }
      return;
    }
    if (mounted) setState(() => _isProcessing = true);

    final DateTime selectedFullDateTime = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day, _selectedTime!.hour, _selectedTime!.minute);

    final double finalPay = double.tryParse(_payController.text) ?? 0;
    final double finalGigLengthHours = double.tryParse(_gigLengthController.text) ?? 0;
    final double finalDriveSetupHours = double.tryParse(_driveSetupController.text) ?? 0;
    final double finalRehearsalHours = double.tryParse(_rehearsalController.text) ?? 0;

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
        isPrivate: _isPrivateVenue,
      );
      await _saveNewVenueToPrefs(finalVenueDetails);
    } else {
      if (_selectedVenue!.isPrivate != _isPrivateVenue) {
        finalVenueDetails = _selectedVenue!.copyWith(isPrivate: _isPrivateVenue);
        await _saveNewVenueToPrefs(finalVenueDetails);
      } else {
        finalVenueDetails = _selectedVenue!;
      }
    }
    if (!mounted) {
      setState(() => _isProcessing = false);
      return;
    }

    final Gig newOrUpdatedGigData = _editableGig!.copyWith(
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
      notes: _editableGig!.notes,
      notesUrl: _editableGig!.notesUrl,
      // EXPLICITLY CARRY OVER THE RECURRENCE SETTINGS
      isRecurring: _editableGig!.isRecurring,
      recurrenceFrequency: _editableGig!.recurrenceFrequency,
      recurrenceDay: _editableGig!.recurrenceDay,
      recurrenceNthValue: _editableGig!.recurrenceNthValue,
      recurrenceEndDate: _editableGig!.recurrenceEndDate,
    );
    // --- (a) DEBUG PRINT: Print the outgoing gig data before saving ---
    print("--- SAVING GIG FROM DIALOG ---");
    print("Gig ID: ${newOrUpdatedGigData.id}");
    print("isRecurring: ${newOrUpdatedGigData.isRecurring}");
    print("Frequency: ${newOrUpdatedGigData.recurrenceFrequency}");
    print("Day: ${newOrUpdatedGigData.recurrenceDay}");
    print("Nth Value: ${newOrUpdatedGigData.recurrenceNthValue}");
    print("End Date: ${newOrUpdatedGigData.recurrenceEndDate}");
    print("--------------------------------");

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

    await _audioPlayer.play(AssetSource('sounds/thetone.wav'));
    await Future.delayed(const Duration(milliseconds: 2500));


    await _scheduleGigNotifications(newOrUpdatedGigData);
    print("scheduled gig notifications ${newOrUpdatedGigData.id}");

    if (mounted) setState(() => _isProcessing = false);

    if (_isEditingMode) {
      Navigator.of(context).pop(GigEditResult(action: GigEditResultAction.updated, gig: newOrUpdatedGigData));
    } else {
      Navigator.of(context).pop(newOrUpdatedGigData);
    }
  }

  // ... (All other helper methods like _loadAllKnownVenuesInternal, _calculateDynamicRate, etc., remain the same)
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

  Future<void> _loadSelectableVenuesForDropdown({bool defaultToAddVenue = false}) async {
    if (!_isCalculatorMode) {
      if(mounted) setState(() => _isLoadingVenues = false );
      return;
    }
    if(mounted) setState(() { _isLoadingVenues = true; });

    try {
      List<StoredLocation> activeVenues = _allKnownVenuesInternal.where((v) => !v.isArchived).toList();
      _selectableVenuesForDropdown = [];
      _selectableVenuesForDropdown.addAll(activeVenues);
      _selectableVenuesForDropdown.removeWhere((v) => v.placeId == _addNewVenuePlaceholder.placeId);
      _selectableVenuesForDropdown.sort((a,b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _selectableVenuesForDropdown.insert(0, _addNewVenuePlaceholder);

      StoredLocation? initialSelection;
      if (defaultToAddVenue) {
        initialSelection = _addNewVenuePlaceholder;
      } else if (_selectableVenuesForDropdown.length > 1) {
        initialSelection = _selectableVenuesForDropdown.firstWhere((v) => v.placeId != _addNewVenuePlaceholder.placeId && !v.isArchived, orElse: () => _selectableVenuesForDropdown.first);
      } else {
        _selectableVenuesForDropdown = [_addNewVenuePlaceholder];
        initialSelection = _selectableVenuesForDropdown.first;
      }

      await _handleVenueSelection(initialSelection);
      if(mounted) {
        setState(() {
          _isAddNewVenue = (initialSelection?.placeId == _addNewVenuePlaceholder.placeId);
        });
      }
    } catch (e) {
      print("Error filtering/setting up venues for dropdown: $e");
      if (mounted) {
        setState(() {
          _selectableVenuesForDropdown = [_addNewVenuePlaceholder];
          _selectedVenue = _addNewVenuePlaceholder;
          _isAddNewVenue = true;
        });
      }
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
    if(venueWithCorrectArchiveStatus.placeId != _addNewVenuePlaceholder.placeId && venueWithCorrectArchiveStatus.placeId.isNotEmpty) {
      existingIndex = currentSavedVenues.indexWhere((v) => v.placeId == venueWithCorrectArchiveStatus.placeId);
    }
    bool wasActuallyAddedOrUpdated = false;
    if (existingIndex != -1) {
      if (currentSavedVenues[existingIndex] != venueWithCorrectArchiveStatus) {
        currentSavedVenues[existingIndex] = venueWithCorrectArchiveStatus;
        wasActuallyAddedOrUpdated = true;
      }
    } else if (venueWithCorrectArchiveStatus.placeId != _addNewVenuePlaceholder.placeId && !currentSavedVenues.any((v) =>(v.placeId.isNotEmpty && venueWithCorrectArchiveStatus.placeId.isNotEmpty && v.placeId == venueWithCorrectArchiveStatus.placeId) ||(v.name.toLowerCase() == venueWithCorrectArchiveStatus.name.toLowerCase() && v.address.toLowerCase() == venueWithCorrectArchiveStatus.address.toLowerCase()))) {
      currentSavedVenues.add(venueWithCorrectArchiveStatus);
      wasActuallyAddedOrUpdated = true;
    }
    if (wasActuallyAddedOrUpdated) {
      _allKnownVenuesInternal = List.from(currentSavedVenues);
      final List<String> updatedLocationsJson = _allKnownVenuesInternal.where((loc) => loc.placeId != _addNewVenuePlaceholder.placeId).map((loc) => jsonEncode(loc.toJson())).toList();
      await prefs.setStringList('saved_locations', updatedLocationsJson);
      globalRefreshNotifier.notify();
      if (_isCalculatorMode && mounted) {
        await _loadSelectableVenuesForDropdown();
        final newVenueInList = _allKnownVenuesInternal.firstWhere((v) => v.placeId == venueToSave.placeId, orElse: () => _selectedVenue ?? _addNewVenuePlaceholder);
        if(mounted) {
          await _handleVenueSelection(newVenueInList);
          setState(() {
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

    Gig gigToCancel = widget.editingGig!;
    bool isRecurringTemplate = gigToCancel.isRecurring;
    bool isFromRecurringSeries = gigToCancel.isFromRecurring;

    // Show a special dialog for recurring gigs
    if (isRecurringTemplate || isFromRecurringSeries) {
      final RecurringCancelChoice? choice = await showDialog<RecurringCancelChoice>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Cancel Recurring Gig'),
            content: Text('This is part of a recurring series. What would you like to do with the gig at "${gigToCancel.venueName}" on ${DateFormat.yMMMEd().format(gigToCancel.dateTime)}?'),
            actions: <Widget>[
              TextButton(
                child: const Text('CANCEL THIS EVENT ONLY'),
                onPressed: () => Navigator.of(dialogContext).pop(RecurringCancelChoice.thisInstanceOnly),
              ),
              TextButton(
                child: Text('CANCEL ALL FUTURE EVENTS', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                onPressed: () => Navigator.of(dialogContext).pop(RecurringCancelChoice.allFutureInstances),
              ),
              const SizedBox(height: 10),
              TextButton(
                child: const Text('NEVERMIND'),
                onPressed: () => Navigator.of(dialogContext).pop(RecurringCancelChoice.doNothing),
              ),
            ],
          );
        },
      );

      if (choice == null || choice == RecurringCancelChoice.doNothing) {
        return; // User cancelled the action
      }

      if (choice == RecurringCancelChoice.thisInstanceOnly) {
        await _cancelGigNotifications(gigToCancel);
      }
      if (mounted) setState(() => _isProcessing = true);
      // Pass the choice and the gig to the parent page to handle the logic
      Navigator.of(context).pop(GigEditResult(action: GigEditResultAction.deleted, gig: gigToCancel, cancelChoice: choice));
      return; // Stop execution here
    }


    // --- This is the original logic for non-recurring gigs ---
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
      await _cancelGigNotifications(widget.editingGig!);
      Navigator.of(context).pop(GigEditResult(action: GigEditResultAction.deleted, gig: widget.editingGig));
    }
  }

  Widget _buildDemoOverlay(DemoProvider demoProvider) {
    // This dialog handles steps 8, 9, 10, 11.
    // The demo provider's step is 1-based, our script list is 0-based.
    // We subtract 8 to map the global step to the local script index.
    int currentStepIndex = demoProvider.currentStep - 8;

    if (currentStepIndex < 0 || currentStepIndex >= _demoScript.length) {
      return const SizedBox.shrink();
    }

    final step = _demoScript[currentStepIndex];

    if (step.onBefore != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Ensure state changes from onBefore happen after the build.
        step.onBefore!();
      });
    }

    return TutorialOverlay(
      key: ValueKey('dialog_demo_step_${demoProvider.currentStep}'),
      highlightKey: step.key,
      instructionalText: step.text,
      textAlignment: step.alignment,
      hideNextButton: step.hideNextButton,
      onNext: () {
        if (demoProvider.currentStep == 11) { // Final step for this dialog
          demoProvider.endDemo();
        } else {
          demoProvider.nextStep();
        }
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      // If initialization is not complete, show a loading indicator
      // inside a correctly-sized AlertDialog shell.
      return const AlertDialog(
        title: Text("Loading..."),
        content: Center(
          heightFactor: 2,
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Consumer<DemoProvider>(
      builder: (context, demoProvider, child) {
        bool isDialogProcessing = _isProcessing || _isGeocoding || (_isLoadingVenues && _isCalculatorMode) || _isFetchingDriveTime;

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
                      if (_isCalculatorMode)
                        Container(
                          key: _summaryKey,
                          child: CalculatorSummaryView(
                            totalPay: widget.totalPay,
                            gigLengthHours: widget.gigLengthHours,
                            driveSetupTimeHours: widget.driveSetupTimeHours,
                            rehearsalTimeHours: widget.rehearsalTimeHours,
                            calculatedHourlyRate: widget.calculatedHourlyRate,
                          ),
                        )
                      else ...[
                        FinancialInputsView(
                          payController: _payController,
                          gigLengthController: _gigLengthController,
                          driveSetupController: _driveSetupController,
                          rehearsalController: _rehearsalController,
                          showDynamicRate: _isMapModeNewGig || _isEditingMode,
                          dynamicRateString: _dynamicRateString,
                          dynamicRateResultColor: _dynamicRateResultColor,
                        ),
                        const Divider(height: 24, thickness: 1),
                      ],
                      Container(
                        key: _venueSectionKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text( _isEditingMode ? "Venue & Schedule:" : (_isMapModeNewGig ? "Confirm Venue & Schedule:" : "Venue & Schedule:"), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            VenueSelectionView(
                              isStaticDisplay: _isEditingMode || _isMapModeNewGig,
                              isLoading: _isLoadingVenues,
                              selectedVenue: _selectedVenue,
                              selectableVenues: _selectableVenuesForDropdown,
                              addNewVenuePlaceholder: _addNewVenuePlaceholder,
                              onVenueSelected: (venue) {
                                _handleVenueSelection(venue);
                              },
                            ),
                            if (_isAddNewVenue) ...[
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _newVenueNameController,
                                decoration: const InputDecoration(labelText: 'New Venue Name*', border: OutlineInputBorder()),
                                validator: (value) { if (_isAddNewVenue && (value == null || value.trim().isEmpty)) { return 'Venue name is required'; } return null; },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _newVenueAddressController,
                                focusNode: _newVenueAddressFocusNode,
                                decoration: const InputDecoration(labelText: 'New Venue Address*', hintText: 'e.g., 1600 Amphitheatre Pkwy, MV, CA', border: OutlineInputBorder()),
                                onFieldSubmitted: (_) => _fetchDriveTimeForManualAddress(),
                                validator: (value) { if (_isAddNewVenue && (value == null || value.trim().isEmpty)) { return 'Venue address is required'; } return null; },
                              ),
                              const SizedBox(height: 8),
                              SwitchListTile(
                                title: const Text('Private Venue'),
                                subtitle: const Text('Never shared'),
                                value: _isPrivateVenue,
                                onChanged: (bool value) {
                                  setState((){ _isPrivateVenue = value;
                                  });
                                },
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                              )
                            ],
                            DriveTimeDisplay(
                              isFetching: _isFetchingDriveTime,
                              duration: _isAddNewVenue ? _manualDriveDurationString : _selectedVenue?.driveDuration,
                              distance: _isAddNewVenue ? _manualDriveDistance : _selectedVenue?.driveDistance,
                              userProfileAddress: _userProfileAddressForDisplay,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),

                      // --- 4. ADD THE BUTTON TO THE UI ---
                      if (_isEditingMode)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Center(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.repeat),
                              label: Text(_editableGig?.isRecurring ?? false ? 'Edit Recurring Settings' : 'Set Up Recurrence'),
                              onPressed: _openRecurringGigSettings,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _editableGig?.isRecurring ?? false ? Theme.of(context).colorScheme.primary : null,
                                side: BorderSide(
                                  color: _editableGig?.isRecurring ?? false ? Theme.of(context).colorScheme.primary : Colors.grey,
                                ),
                              ),
                            ),
                          ),
                        ),

                      Container(
                        key: _dateSectionKey,
                        child: Column(
                          children: [
                            Row( children: [ Expanded(child: Text(_selectedDate == null ? 'No date selected*' : 'Date: ${DateFormat.yMMMEd().format(_selectedDate!)}')), TextButton(onPressed: isDialogProcessing ? null : () => _pickDate(context), child: const Text('SELECT DATE')), ], ),
                            Row( children: [ Expanded(child: Text(_selectedTime == null ? 'No time selected*' : 'Time: ${_selectedTime!.format(context)}')), TextButton(onPressed: isDialogProcessing ? null : () => _pickTime(context), child: const Text('SELECT TIME')), ], ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
              if (isDialogProcessing) Positioned.fill( child: Container( color: Colors.black.withOpacity(0.3), child: const Center(child: CircularProgressIndicator()), ), ),
              if (demoProvider.isDemoModeActive)
                _buildDemoOverlay(demoProvider),
            ],
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          actions: <Widget>[
            if (_isEditingMode)
              TextButton(
                onPressed: isDialogProcessing ? null : _handleGigCancellation,
                child: Text('CANCEL GIG', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              )
            else
              TextButton(
                onPressed: isDialogProcessing ? null : () => Navigator.of(context).pop(),
                child: const Text('CANCEL'),
              ),
            Row(
              key: _confirmBtnKey,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isEditingMode)
                  TextButton(
                    onPressed: isDialogProcessing ? null : () => Navigator.of(context).pop(GigEditResult(action: GigEditResultAction.noChange)),
                    child: const Text('CLOSE'),
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
      },
    );
  }
}
