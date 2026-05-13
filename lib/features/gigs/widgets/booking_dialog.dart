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
import 'package:the_money_gigs/features/app_demo/widgets/booking_demo_overlay.dart';
import 'package:the_money_gigs/features/gigs/widgets/booking_dialog_widgets/calculator_summary_view.dart';
import 'package:the_money_gigs/features/gigs/widgets/booking_dialog_widgets/financial_inputs_view.dart';
import 'package:the_money_gigs/features/gigs/widgets/booking_dialog_widgets/venue_selection_view.dart';
import 'package:the_money_gigs/core/services/notification_service.dart';
import 'package:the_money_gigs/features/gigs/widgets/recurring_gig_dialog.dart';

// These enums and classes remain the same
enum GigEditResultAction { updated, deleted, noChange }
enum RecurringCancelChoice { thisInstanceOnly, allFutureInstances, doNothing }

class GigEditResult {
  final GigEditResultAction action;
  final Gig? gig;
  final RecurringCancelChoice? cancelChoice;

  GigEditResult({required this.action, this.gig, this.cancelChoice});
}

class BookingDialog extends StatefulWidget {
  final String? calculatedHourlyRate;
  final double? totalPay;
  final double? otherExpenses;
  final double? gigLengthHours;
  final double? driveSetupTimeHours;
  final double? rehearsalTimeHours;
  final StoredLocation? preselectedVenue;
  final Future<void> Function()? onNewVenuePotentiallyAdded;
  final String googleApiKey;
  final List<Gig> existingGigs;
  final Gig? editingGig;
  final DemoStep? currentDemoStep;

  const BookingDialog({
    super.key,
    this.calculatedHourlyRate,
    this.totalPay,
    this.otherExpenses,
    this.gigLengthHours,
    this.driveSetupTimeHours,
    this.rehearsalTimeHours,
    this.preselectedVenue,
    this.onNewVenuePotentiallyAdded,
    required this.googleApiKey,
    required this.existingGigs,
    this.editingGig,
    this.currentDemoStep,
  });

  @override
  State<BookingDialog> createState() => _BookingDialogState();
}

class _BookingDialogState extends State<BookingDialog> {
  // All state variables and controllers remain the same
  static final StoredLocation _addNewVenuePlaceholder = StoredLocation(
    placeId: 'add_new_venue_placeholder',
    name: '--- Add New Venue ---',
    address: '',
    coordinates: const LatLng(0, 0),
  );
  final AudioPlayer _audioPlayer = AudioPlayer();
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _payController;
  late TextEditingController _otherExpensesController;
  late TextEditingController _gigLengthController;
  late TextEditingController _driveSetupController;
  late TextEditingController _rehearsalController;
  String _dynamicRateString = "";
  Color _dynamicRateResultColor = Colors.grey;
  List<StoredLocation> _allKnownVenuesInternal = [];
  List<String> _allKnownBands = [];

  List<StoredLocation> _selectableVenuesForDropdown = [];
  StoredLocation? _selectedVenue;
  bool _isAddNewVenue = false;

  String? _selectedBand;
  bool _isAddNewBand = false;
  static const String _keyGigsList = 'gigs_list';
  static const String _addNewBandPlaceholder = "--- Add New Band ---";

  final TextEditingController _newVenueNameController = TextEditingController();
  final TextEditingController _newVenueAddressController = TextEditingController();
  final TextEditingController _newBandNameController = TextEditingController();

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

  // --- START: ADDED FOR DEMO ---
  final FocusNode _payFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  // --- END: ADDED FOR DEMO ---

  // --- DEMO KEYS & SCRIPT ---
  final GlobalKey _payKey = GlobalKey();
  final GlobalKey _gigLengthKey = GlobalKey();
  final GlobalKey _driveSetupKey = GlobalKey();
  final GlobalKey _rehearsalKey = GlobalKey();
  final GlobalKey _otherExpensesKey = GlobalKey();
  final GlobalKey _rateDisplayKey = GlobalKey();
  final GlobalKey _dateButtonKey = GlobalKey();
  final GlobalKey _confirmBtnKey = GlobalKey();
  bool _showDemoOverlay = false;

  bool get _isEditingMode => widget.editingGig != null;
  bool get _isCalculatorMode => widget.calculatedHourlyRate != null && !_isEditingMode && widget.preselectedVenue == null;
  bool get _isMapModeNewGig => widget.preselectedVenue != null && !_isEditingMode;
  bool get _isAddGigMode => !_isEditingMode && !_isCalculatorMode && !_isMapModeNewGig;
  bool _isInitialized = false;
  final TimeOfDay _defaultGigTime = const TimeOfDay(hour: 20, minute: 0);

  @override
  void initState() {
    super.initState();
    _initializeDialogState();

    _scrollController.addListener(() {
      if (_showDemoOverlay) {
        setState(() {}); // Triggers a rebuild of the Stack, forcing painter to update
      }
    });

    _newVenueAddressFocusNode.addListener(_onAddressFocusChange);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final demoProvider = Provider.of<DemoProvider>(context, listen: false);
      demoProvider.addListener(_onDemoStatusChanged); // Register listener

      final isBookingDemo = widget.currentDemoStep == DemoStep.bookingFormValue ||
          widget.currentDemoStep == DemoStep.bookingFormAction;

      if (isBookingDemo && mounted) {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) {
            setState(() {
              _showDemoOverlay = true;
            });
            _handleDemoStepChange(demoProvider.currentStep);
          }
        });
      }
    });
  }

  void _onDemoStatusChanged() {
    //🎯 CRITICAL: Check mounted BEFORE accessing context or calling setState
    if (!mounted) return;

    final demoProvider = Provider.of<DemoProvider>(context, listen: false);

    if (!demoProvider.isDemoModeActive) {
      setState(() {
        _showDemoOverlay = false;
      });
    }
  }

  void _handleDemoStepChange(DemoStep? demoStep) {
    FocusScope.of(context).unfocus();

    if (demoStep == DemoStep.bookingFormAction) {
      // 🎯 Scroll to the absolute bottom of the dialog
      // This ensures the Confirm & Book button is fully visible
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
          );
        }
      });
    } else if (demoStep == DemoStep.bookingFormValue) {
      _payFocusNode.requestFocus();
    }
  }

  @override
  void dispose() {

    try {
      Provider.of<DemoProvider>(context, listen: false).removeListener(_onDemoStatusChanged);
    } catch (_) {}


    _scrollController.dispose();
    _payFocusNode.dispose();
    _audioPlayer.dispose();
    _newVenueNameController.dispose();
    _newVenueAddressController.dispose();
    _newVenueAddressFocusNode.removeListener(_onAddressFocusChange);
    _newVenueAddressFocusNode.dispose();
    _payController.dispose();
    _otherExpensesController.dispose();
    _gigLengthController.dispose();
    _driveSetupController.dispose();
    _rehearsalController.dispose();
    if (_isMapModeNewGig || _isEditingMode || _isAddGigMode) {
      _payController.removeListener(_calculateDynamicRate);
      _otherExpensesController.removeListener(_calculateDynamicRate);
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

  Future<void> _scheduleGigNotifications(Gig gig) async {
    final prefs = await SharedPreferences.getInstance();

    // Singleton: NotificationService() always returns the same instance.
    // init() is a no-op if already initialized, so calling it here is safe.
    final notificationService = NotificationService();
    await notificationService.init();

    final int base = gig.id.hashCode;
    final now = DateTime.now();
    final gigTime = DateFormat.jm().format(gig.dateTime);

    // ── Day-of (9am on gig day) ──────────────────────────────────────────────
    final bool notifyOnDayOfGig = prefs.getBool('notify_on_day_of_gig') ?? false;
    final DateTime dayOfTime = DateTime(
        gig.dateTime.year, gig.dateTime.month, gig.dateTime.day, 9, 0);

    if (notifyOnDayOfGig && dayOfTime.isAfter(now)) {
      await notificationService.scheduleNotification(
        id: base,
        title: 'You have a gig today!',
        body: 'You have a gig today at ${gig.venueName} at $gigTime!',
        scheduledDate: dayOfTime,
        payload: 'day_of:${gig.id}',
      );
    } else {
      await notificationService.cancelNotification(base);
    }

    // ── Days-before (9am N days before gig) ─────────────────────────────────
    final int? daysBefore = prefs.getInt('notify_days_before');
    if (daysBefore != null && daysBefore > 0) {
      final DateTime beforeDate =
      gig.dateTime.subtract(Duration(days: daysBefore));
      final DateTime beforeTime = DateTime(
          beforeDate.year, beforeDate.month, beforeDate.day, 9, 0);
      if (beforeTime.isAfter(now)) {
        await notificationService.scheduleNotification(
          id: base + 1,
          title: 'Upcoming gig reminder',
          body: 'Your gig at ${gig.venueName} is in '
              '$daysBefore day${daysBefore > 1 ? "s" : ""} '
              'on ${DateFormat.yMMMEd().format(gig.dateTime)} at $gigTime.',
          scheduledDate: beforeTime,
          payload: 'days_before:${gig.id}',
        );
      } else {
        await notificationService.cancelNotification(base + 1);
      }
    } else {
      await notificationService.cancelNotification(base + 1);
    }

    // ── Day-after retrospective (9am the morning after the gig) ─────────────
    final bool notifyAfterGig = prefs.getBool('notify_after_gig') ?? true;
    final DateTime afterGigDate = gig.dateTime.add(const Duration(days: 1));
    final DateTime afterTime = DateTime(
        afterGigDate.year, afterGigDate.month, afterGigDate.day, 9, 0);
    if (notifyAfterGig && afterTime.isAfter(now)) {
      await notificationService.scheduleNotification(
        id: base + 2,
        title: 'How was the gig?',
        body: 'How did the gig at ${gig.venueName} go?',
        scheduledDate: afterTime,
        payload: 'retrospective:${gig.id}',
      );
    } else {
      await notificationService.cancelNotification(base + 2);
    }

    await notificationService.debugPendingNotifications();
  }

  Future<void> _cancelGigNotifications(Gig gig) async {
    // Bug fix: previously created a fresh uninitialized NotificationService
    // instance and called cancel() on it without calling init() first.
    // The singleton + init() call ensures the plugin is always ready.
    final notificationService = NotificationService();
    await notificationService.init();

    final int base = gig.id.hashCode;
    await notificationService.cancelNotification(base);      // day-of
    await notificationService.cancelNotification(base + 1);  // days-before
    await notificationService.cancelNotification(base + 2);  // day-after
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
    print("--- Initializing Dialog State ---");
    await _loadProfileAddress();
    await _loadAllKnownVenuesInternal();
    await _loadAllKnownBands();
    if (!mounted) return;
    if (_isEditingMode) {
      print("Editing Mode: Gig has bandName = '${widget.editingGig?.bandName}'");

      _editableGig = widget.editingGig!.copyWith(
        id: widget.editingGig!.id,
        bandName: widget.editingGig!.bandName, // <-- CRITICAL: This was missing
        venueName: widget.editingGig!.venueName,
        latitude: widget.editingGig!.latitude,
        longitude: widget.editingGig!.longitude,
        address: widget.editingGig!.address,
        placeId: widget.editingGig!.placeId,
        dateTime: widget.editingGig!.dateTime,
        pay: widget.editingGig!.pay,
        otherExpenses: widget.editingGig!.otherExpenses,
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
      _otherExpensesController = TextEditingController(text: (_editableGig!.otherExpenses ?? 0.0).toStringAsFixed(2));
      _gigLengthController = TextEditingController(text: _editableGig!.gigLengthHours.toStringAsFixed(1));
      _driveSetupController = TextEditingController(text: _editableGig!.driveSetupTimeHours.toStringAsFixed(1));
      _rehearsalController = TextEditingController(text: _editableGig!.rehearsalLengthHours.toStringAsFixed(1));
      _selectedDate = _editableGig!.dateTime;
      _selectedTime = TimeOfDay.fromDateTime(_editableGig!.dateTime);
      _selectedVenue = _allKnownVenuesInternal.firstWhere((v) => (_editableGig!.placeId != null && v.placeId == _editableGig!.placeId) || (v.name == _editableGig!.venueName && v.address == _editableGig!.address), orElse: () => StoredLocation( placeId: _editableGig!.placeId ?? 'edited_${_editableGig!.id}', name: _editableGig!.venueName, address: _editableGig!.address, coordinates: LatLng(_editableGig!.latitude, _editableGig!.longitude), isArchived: true));
      _isAddNewVenue = false;
      _isLoadingVenues = false;
      await _handleVenueSelection(_selectedVenue);
      _payController.addListener(_calculateDynamicRate);
      _otherExpensesController.addListener(_calculateDynamicRate);
      _gigLengthController.addListener(_calculateDynamicRate);
      _driveSetupController.addListener(_calculateDynamicRate);
      _rehearsalController.addListener(_calculateDynamicRate);
      _calculateDynamicRate();
    } else {
      _payController = TextEditingController(text: widget.totalPay?.toStringAsFixed(0) ?? '');
      _otherExpensesController = TextEditingController(text: widget.otherExpenses?.toStringAsFixed(2) ?? '');
      _gigLengthController = TextEditingController(text: widget.gigLengthHours?.toStringAsFixed(1) ?? '');
      _driveSetupController = TextEditingController(text: widget.driveSetupTimeHours?.toStringAsFixed(1) ?? '');
      _rehearsalController = TextEditingController(text: widget.rehearsalTimeHours?.toStringAsFixed(1) ?? '');
      _editableGig = Gig(id: 'new_${DateTime.now().millisecondsSinceEpoch}', venueName: widget.preselectedVenue?.name ?? '', address: widget.preselectedVenue?.address ?? '', latitude: widget.preselectedVenue?.coordinates.latitude ?? 0, longitude: widget.preselectedVenue?.coordinates.longitude ?? 0, dateTime: DateTime.now(), pay: widget.totalPay ?? 0, otherExpenses: widget.otherExpenses ?? 0.0, gigLengthHours: widget.gigLengthHours ?? 0, driveSetupTimeHours: widget.driveSetupTimeHours ?? 0, rehearsalLengthHours: widget.rehearsalTimeHours ?? 0);
      _selectedTime = _defaultGigTime;
      if (_isMapModeNewGig) {
        _selectedVenue = widget.preselectedVenue;
        _isPrivateVenue = _selectedVenue?.isPrivate ?? false;
        _isAddNewVenue = false;
        _isLoadingVenues = false;
        await _handleVenueSelection(_selectedVenue);
        _payController.addListener(_calculateDynamicRate);
        _otherExpensesController.addListener(_calculateDynamicRate);
        _gigLengthController.addListener(_calculateDynamicRate);
        _driveSetupController.addListener(_calculateDynamicRate);
        _rehearsalController.addListener(_calculateDynamicRate);
        _calculateDynamicRate();
      } else {
        await _loadSelectableVenuesForDropdown(defaultToAddVenue: true);
        if (_isAddGigMode) {
          _payController.addListener(_calculateDynamicRate);
          _gigLengthController.addListener(_calculateDynamicRate);
          _driveSetupController.addListener(_calculateDynamicRate);
          _rehearsalController.addListener(_calculateDynamicRate);
          _calculateDynamicRate();
        }
      }
    }
    if (mounted) {
      setState(() {
        // This is where the dropdown UI gets its value
        _selectedBand = _editableGig?.bandName;
        _isInitialized = true;
      });
      print("Setting UI state: _selectedBand = '$_selectedBand'");
    }
  }

  DriveTimeService _createDriveTimeService() {
    return DriveTimeService(googleApiKey: widget.googleApiKey, allKnownVenues: _allKnownVenuesInternal, address1: _profileAddress1, city: _profileCity, state: _profileState, zipCode: _profileZipCode);
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
      final tempVenue = StoredLocation(name: 'temp', address: address, coordinates: coords, placeId: 'temp_manual_place_id_${DateTime.now().millisecondsSinceEpoch}', instrumentTags: [], genreTags: []);
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
      gigForDialog = _editableGig!.copyWith(isRecurring: true, recurrenceFrequency: JamFrequencyType.weekly, recurrenceDay: DayOfWeek.values[_editableGig!.dateTime.weekday - 1]);
    }
    final updatedGig = await showDialog<Gig>(context: context, builder: (context) => RecurringGigDialog(gig: gigForDialog));
    if (updatedGig != null && mounted) {
      setState(() {
        _editableGig = updatedGig;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_editableGig!.isRecurring ? 'Recurrence settings applied.' : 'Recurrence settings removed.'), duration: const Duration(seconds: 2), backgroundColor: Theme.of(context).colorScheme.primary));
    }
  }

  void _confirmAction() async {
    final demoProvider = Provider.of<DemoProvider>(context, listen: false);
    if (demoProvider.isDemoModeActive && widget.currentDemoStep == DemoStep.bookingFormAction) {
      demoProvider.nextStep();
      Navigator.of(context).pop(GigEditResult(action: GigEditResultAction.noChange));
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
    final double finalOtherExpenses = double.tryParse(_otherExpensesController.text) ?? 0;
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
      finalVenueDetails = StoredLocation(placeId: 'manual_${DateTime.now().millisecondsSinceEpoch}', name: newVenueName, address: newVenueAddress, coordinates: coords, isArchived: false, isPrivate: _isPrivateVenue);
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

    String? finalBandName;
    if (_isAddNewBand) {
      finalBandName = _newBandNameController.text.trim();
      if (finalBandName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a band name.')));
        return;
      }
      // Save to global list if new
      if (!_allKnownBands.contains(finalBandName)) {
        _allKnownBands.add(finalBandName);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('saved_band_names', _allKnownBands);
      }
    } else {
      finalBandName = _selectedBand;
    }

    print("--- Confirming Action ---");
    print("Returning gig with bandName: '$finalBandName'");

    final Gig newOrUpdatedGigData = _editableGig!.copyWith(
        venueName: finalVenueDetails.name,
        bandName: finalBandName,
        latitude: finalVenueDetails.coordinates.latitude,
        longitude: finalVenueDetails.coordinates.longitude,
        address: finalVenueDetails.address,
        placeId: finalVenueDetails.placeId,
        dateTime: selectedFullDateTime,
        pay: finalPay,
        otherExpenses: finalOtherExpenses,
        gigLengthHours: finalGigLengthHours,
        driveSetupTimeHours: finalDriveSetupHours,
        rehearsalLengthHours: finalRehearsalHours,
        notes: _editableGig!.notes,
        notesUrl: _editableGig!.notesUrl,
        isRecurring: _editableGig!.isRecurring,
        recurrenceFrequency: _editableGig!.recurrenceFrequency,
        recurrenceDay: _editableGig!.recurrenceDay, recurrenceNthValue: _editableGig!.recurrenceNthValue, recurrenceEndDate: _editableGig!.recurrenceEndDate);

    List<Gig> otherGigsToCheck = List.from(widget.existingGigs.where((g) => !g.isJamOpenMic));
    if (_isEditingMode) {
      otherGigsToCheck.removeWhere((g) => g.id == widget.editingGig!.id);
    }
    final conflictingGig = _checkForConflict(newOrUpdatedGigData.dateTime, newOrUpdatedGigData.gigLengthHours, otherGigsToCheck);
    if (conflictingGig != null) {
      final bool? bookAnyway = await showDialog<bool>(context: context, builder: (BuildContext dialogContext) => AlertDialog(title: const Text('Scheduling Conflict'), content: Text('This gig conflicts with "${conflictingGig.venueName}" on ${DateFormat.yMMMEd().format(conflictingGig.dateTime)}. ${_isEditingMode ? "Update" : "Book"} anyway?'), actions: <Widget>[TextButton(child: const Text('CANCEL'), onPressed: () => Navigator.of(dialogContext).pop(false)), TextButton(child: Text('${_isEditingMode ? "UPDATE" : "BOOK"} ANYWAY'), onPressed: () => Navigator.of(dialogContext).pop(true))]));
      if (bookAnyway != true) {
        if (mounted) setState(() => _isProcessing = false);
        return;
      }
    }
    await _audioPlayer.play(AssetSource('sounds/thetone.wav'));
    await Future.delayed(const Duration(milliseconds: 2500));
    if (await _areNotificationsEnabled()) {
      try {
        await _scheduleGigNotifications(newOrUpdatedGigData);
      } catch (e) {
        print("⚠️ Error scheduling notifications, but continuing with booking. Error: $e");
      }
    } else {
      print("🔕 Notifications are disabled by the user. Skipping scheduling.");
    }
    if (mounted) setState(() => _isProcessing = false);
    if (mounted && Navigator.canPop(context)) {
      Navigator.of(context).pop(GigEditResult(action: GigEditResultAction.updated, gig: newOrUpdatedGigData));
    }
  }

  Future<bool> _areNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final bool notifyOnDayOfGig = prefs.getBool('notify_on_day_of_gig') ?? false;
    final bool notifyAfterGig   = prefs.getBool('notify_after_gig') ?? true;
    final int? daysBefore = prefs.getInt('notify_days_before');
    return notifyOnDayOfGig || notifyAfterGig || (daysBefore != null && daysBefore > 0);
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

  Future<void> _loadAllKnownBands() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Load the manual list of "Saved Bands"
    final List<String> savedBands = prefs.getStringList('saved_band_names') ?? [];

    // 2. Load the actual Gigs list from disk using our shared key to extract any bands used
    final String? gigsJson = prefs.getString(_keyGigsList); // <--- USING THE KEY HERE
    Set<String> bandsFromDisk = {};
    if (gigsJson != null) {
      final List<Gig> decodedGigs = Gig.decode(gigsJson);
      bandsFromDisk = decodedGigs.map((g) => g.bandName).whereType<String>().toSet();
    }

    // 3. Combine with the list passed from the widget (existingGigs)
    final Set<String> bandsFromWidget = widget.existingGigs
        .map((g) => g.bandName)
        .whereType<String>()
        .toSet();

    setState(() {
      // Merge all sources to ensure the dropdown is exhaustive
      _allKnownBands = {...savedBands, ...bandsFromDisk, ...bandsFromWidget}.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    });
  }

  void _calculateDynamicRate() {
    if (!mounted || _isCalculatorMode) return;
    final double pay = double.tryParse(_payController.text) ?? 0;
    final double otherExpenses = double.tryParse(_otherExpensesController.text) ?? 0;
    final double gigTime = double.tryParse(_gigLengthController.text) ?? 0;
    final double driveSetupTime = double.tryParse(_driveSetupController.text) ?? 0;
    final double rehearsalTime = double.tryParse(_rehearsalController.text) ?? 0;
    final double effectivePay = pay - otherExpenses;
    final double totalHoursForRateCalc = gigTime + driveSetupTime + rehearsalTime;
    String newRateString = "";
    Color newColor = Colors.grey;
    if (totalHoursForRateCalc > 0 && pay > 0) {
      final double calculatedRate = effectivePay / totalHoursForRateCalc;
      newRateString = '\$${calculatedRate.toStringAsFixed(2)} / hr';
      newColor = calculatedRate >= 0 ? Colors.green : Colors.red;
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
    if (mounted) setState(() { _dynamicRateString = newRateString; _dynamicRateResultColor = newColor; });
  }

  Future<void> _loadSelectableVenuesForDropdown({bool defaultToAddVenue = false}) async {
    if (!_isCalculatorMode && !_isAddGigMode) {
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

    // 1. Handle Recurring Gigs
    if (gigToCancel.isRecurring || gigToCancel.isFromRecurring) {
      final RecurringCancelChoice? choice = await showDialog<RecurringCancelChoice>(
          context: context,
          builder: (BuildContext dialogContext) {
            return AlertDialog(
                title: const Text('Cancel Recurring Gig'),
                content: Text('This is part of a recurring series. What would you like to do?'),
                actions: <Widget>[
                  TextButton(
                      child: const Text('CANCEL THIS EVENT ONLY'),
                      onPressed: () => Navigator.of(dialogContext).pop(RecurringCancelChoice.thisInstanceOnly)
                  ),
                  TextButton(
                      child: Text('CANCEL ALL FUTURE EVENTS', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      onPressed: () => Navigator.of(dialogContext).pop(RecurringCancelChoice.allFutureInstances)
                  ),
                  TextButton(
                      child: const Text('NEVERMIND'),
                      onPressed: () => Navigator.of(dialogContext).pop(RecurringCancelChoice.doNothing)
                  )
                ]
            );
          }
      );

      if (choice == null || choice == RecurringCancelChoice.doNothing) return;

      if (mounted) setState(() => _isProcessing = true);

      // 🎯 CRITICAL: Pop the choice back to GigsPage
      Navigator.of(context).pop(GigEditResult(
          action: GigEditResultAction.deleted,
          gig: gigToCancel,
          cancelChoice: choice
      ));
      return;
    }

    // 2. Handle Single Gigs
    final bool confirmCancel = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
              title: const Text('Confirm Gig Cancellation'),
              content: const Text('Are you sure you want to cancel this gig?'),
              actions: <Widget>[
                TextButton(child: const Text('NO'), onPressed: () => Navigator.of(dialogContext).pop(false)),
                TextButton(
                    child: const Text('YES, CANCEL GIG'),
                    onPressed: () => Navigator.of(dialogContext).pop(true)
                ),
              ]
          );
        }
    ) ?? false;

    if (confirmCancel && mounted) {
      // 🎯 CRITICAL: Pop the deletion result back to GigsPage
      Navigator.of(context).pop(GigEditResult(
          action: GigEditResultAction.deleted,
          gig: gigToCancel
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const AlertDialog(
        title: Text("Loading..."),
        content: Center(heightFactor: 2, child: CircularProgressIndicator()),);
    }

    return Consumer<DemoProvider>(
      builder: (context, demoProvider, child) {
        final bool isFirstBookingDemoStep = demoProvider.currentStep == DemoStep.bookingFormValue;

        bool isDialogProcessing = _isProcessing || _isGeocoding || (_isLoadingVenues && _isCalculatorMode) || _isFetchingDriveTime;

        String dialogTitle = "Book New Gig";
        String confirmButtonText = "CONFIRM & BOOK";
        if (_isEditingMode) {
          dialogTitle = "Edit Gig Details";
          confirmButtonText = "UPDATE GIG";
        } else if (_isMapModeNewGig) {
          dialogTitle = "Book Gig at Selected Venue";
        }

        final dialogUI = AlertDialog(
          title: Text(dialogTitle),
          contentPadding: const EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 0.0),
          content: SingleChildScrollView(
            controller: _scrollController,
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Stack(
              children: [
                Form(
                  key: _formKey,
                  child: ListBody(
                    children: <Widget>[
                      if (_showDemoOverlay && widget.currentDemoStep == DemoStep.bookingFormValue)
                        const SizedBox(height: 80), // Creates a hole for the top banner
                      if (_isCalculatorMode)
                        CalculatorSummaryView(
                            totalPay: widget.totalPay,
                            gigLengthHours: widget.gigLengthHours,
                            driveSetupTimeHours: widget.driveSetupTimeHours,
                            rehearsalTimeHours: widget.rehearsalTimeHours,
                            calculatedHourlyRate: widget.calculatedHourlyRate)
                      else
                        FinancialInputsView(
                          payFocusNode: _payFocusNode,
                          payKey: _payKey,
                          gigLengthKey: _gigLengthKey,
                          driveSetupKey: _driveSetupKey,
                          rehearsalKey: _rehearsalKey,
                          otherExpensesKey: _otherExpensesKey,
                          rateDisplayKey: _rateDisplayKey,
                          payController: _payController,
                          otherExpensesController: _otherExpensesController,
                          gigLengthController: _gigLengthController,
                          driveSetupController: _driveSetupController,
                          rehearsalController: _rehearsalController,
                          showDynamicRate: _isMapModeNewGig || _isEditingMode || _isAddGigMode,
                          dynamicRateString: _dynamicRateString,
                          dynamicRateResultColor: _dynamicRateResultColor,
                        ),
                      const Divider(height: 24, thickness: 1),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text( _isEditingMode ? "Venue & Schedule:" : (_isMapModeNewGig ? "Confirm Venue & Schedule:" : "Venue & Schedule:"), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          VenueSelectionView(isStaticDisplay: _isEditingMode || _isMapModeNewGig, isLoading: _isLoadingVenues, selectedVenue: _selectedVenue, selectableVenues: _selectableVenuesForDropdown, addNewVenuePlaceholder: _addNewVenuePlaceholder, onVenueSelected: (venue) {
                            _handleVenueSelection(venue);
                          },
                          ),
                          if (_isAddNewVenue) ...[
                            const SizedBox(height: 8),
                            TextFormField(controller: _newVenueNameController, decoration: const InputDecoration(labelText: 'New Venue Name*', border: OutlineInputBorder()), validator: (value) { if (_isAddNewVenue && (value == null || value.trim().isEmpty)) { return 'Venue name is required'; } return null; }),
                            const SizedBox(height: 12),
                            TextFormField(controller: _newVenueAddressController, focusNode: _newVenueAddressFocusNode, decoration: const InputDecoration(labelText: 'New Venue Address*', hintText: 'e.g., 1600 Amphitheatre Pkwy, MV, CA', border: OutlineInputBorder()), onFieldSubmitted: (_) => _fetchDriveTimeForManualAddress(), validator: (value) { if (_isAddNewVenue && (value == null || value.trim().isEmpty)) { return 'Venue address is required'; } return null; }),
                            const SizedBox(height: 8),
                            SwitchListTile(title: const Text('Private Venue'), subtitle: const Text('Never shared'), value: _isPrivateVenue, onChanged: (bool value) => setState(() => _isPrivateVenue = value), dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 4))
                          ],
                          DriveTimeDisplay(isFetching: _isFetchingDriveTime, duration: _isAddNewVenue ? _manualDriveDurationString : _selectedVenue?.driveDuration, distance: _isAddNewVenue ? _manualDriveDistance : _selectedVenue?.driveDistance, userProfileAddress: _userProfileAddressForDisplay),
                        ],
                      ),

                      // --- START: NEW BAND SELECTION FIELD ---
                      const Divider(height: 32),
                      Text("Band / Project:", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _isAddNewBand ? _addNewBandPlaceholder : _selectedBand,
                        decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            hintText: "Select Band (Optional)"
                        ),
                        items: [
                          const DropdownMenuItem<String>(value: null, child: Text("None / Solo")),
                          ..._allKnownBands.map((band) => DropdownMenuItem(value: band, child: Text(band))),
                          const DropdownMenuItem<String>(
                              value: _addNewBandPlaceholder,
                              child: Text(_addNewBandPlaceholder, style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))
                          ),
                        ],
                        onChanged: (val) {
                          setState(() {
                            if (val == _addNewBandPlaceholder) {
                              _isAddNewBand = true;
                              _selectedBand = null;
                            } else {
                              _isAddNewBand = false;
                              _selectedBand = val;
                            }
                          });
                        },
                      ),
                      if (_isAddNewBand) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _newBandNameController,
                          decoration: const InputDecoration(labelText: 'New Band Name*', border: OutlineInputBorder()),
                          validator: (value) => (_isAddNewBand && (value == null || value.trim().isEmpty)) ? 'Band name required' : null,
                        ),
                      ],
                      // --- END: NEW BAND SELECTION FIELD ---

                      const SizedBox(height: 16),
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
                                side: BorderSide(color: _editableGig?.isRecurring ?? false ? Theme.of(context).colorScheme.primary : Colors.grey),
                              ),
                            ),
                          ),
                        ),
                      Row(
                        key: _dateButtonKey,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: ElevatedButton.icon(
                                  onPressed: isDialogProcessing ? null : () => _pickDate(context),
                                  icon: const Icon(Icons.calendar_today, size: 18),
                                  label: Text(_selectedDate == null ? 'Select Date' : DateFormat('M/d/yy').format(_selectedDate!),
                                      softWrap: false,
                                      style: const TextStyle(fontSize: 15)),
                                  style: ElevatedButton.styleFrom(backgroundColor: _selectedDate == null ? Colors.orange.shade700 : Colors.green.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: ElevatedButton.icon(onPressed: isDialogProcessing ? null : () => _pickTime(context), icon: const Icon(Icons.access_time, size: 18), label: Text(_selectedTime == null ? 'Select Time' : _selectedTime!.format(context), style: const TextStyle(fontSize: 15)), style: ElevatedButton.styleFrom(backgroundColor: _selectedTime == null ? Colors.orange.shade700 : Colors.green.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
                if (isDialogProcessing)
                  Positioned.fill(child: Container(color: Colors.black.withOpacity(0.3), child: const Center(child: CircularProgressIndicator()))),
              ],
            ),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          actions: isFirstBookingDemoStep ? <Widget>[] : <Widget>[
            if (_isEditingMode)
              TextButton(onPressed: isDialogProcessing ? null : _handleGigCancellation, child: Text('CANCEL GIG', style: TextStyle(color: Theme.of(context).colorScheme.error)))
            else
              TextButton(onPressed: isDialogProcessing ? null : () { if (Navigator.canPop(context)) { Navigator.of(context).pop(); } }, child: const Text('CANCEL')),
            Row(
              key: _confirmBtnKey,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isEditingMode)
                  TextButton(onPressed: isDialogProcessing ? null : () { if (Navigator.canPop(context)) { Navigator.of(context).pop(GigEditResult(action: GigEditResultAction.noChange)); } }, child: const Text('CLOSE')),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Theme.of(context).colorScheme.onPrimary),
                  onPressed: isDialogProcessing ? null : _confirmAction,
                  child: isDialogProcessing ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white))) : Text(confirmButtonText),
                ),
              ],
            ),
          ],
        );

        if (!_showDemoOverlay || demoProvider.currentStep == DemoStep.none) {
          return dialogUI;
        }

        // The Stack now correctly passes the reactive demoProvider.currentStep
        return Stack(
          children: [
            dialogUI,
            BookingDemoOverlay(
              demoStep: demoProvider.currentStep,
              onStepChange: _handleDemoStepChange,
              isAddNewVenueMode: _isAddNewVenue,
              driveSetupKey: _driveSetupKey,
              rehearsalKey: _rehearsalKey,
              payKey: _payKey,
              lengthKey: _gigLengthKey,
              otherExpensesKey: _otherExpensesKey,
              rateDisplayKey: _rateDisplayKey,
              dateKey: _dateButtonKey,
              confirmKey: _confirmBtnKey,
            ),
          ],
        );
      },
    );
  }
}