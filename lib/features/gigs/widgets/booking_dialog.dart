// lib/features/gigs/widgets/booking_dialog.dart
import 'dart:async';
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
import 'package:the_money_gigs/core/services/analytics_service.dart';
import 'package:the_money_gigs/core/services/notification_service.dart';
import 'package:the_money_gigs/features/gigs/widgets/recurring_gig_dialog.dart';
import 'package:the_money_gigs/core/utils/logger.dart';

// Band/Project Expansion v3.0.0 — Sprint Task 7
import 'package:the_money_gigs/core/services/auth_service.dart';
import 'package:the_money_gigs/features/bands/models/band_model.dart';
import 'package:the_money_gigs/features/bands/repositories/band_repository.dart';
import 'package:the_money_gigs/features/bands/views/create_band_page.dart';

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

  List<StoredLocation> _selectableVenuesForDropdown = [];
  StoredLocation? _selectedVenue;
  bool _isAddNewVenue = false;

  // ── Band/Project Expansion v3.0.0 — Sprint Task 7 ─────────────────────────
  // Real bands (led OR member-of — see BandRepository.getBandsForUser)
  // replace the old free-text/SharedPreferences band list.
  final BandRepository _bandRepository = BandRepository();
  List<BandProject> _realBands = [];
  String? _selectedBandId; // null = Solo, unless _legacyBandName is set
  String? _selectedBandName;
  // A free-text bandName from before this feature existed, with no matching
  // bandId — spec section 5: "render as-is in the list. No migration."
  // Cleared the moment the leader picks anything else from the dropdown.
  String? _legacyBandName;
  static const String _soloValue = '__solo__';
  static const String _addNewBandValue = '__add_new_band__';
  static const String _legacyBandValue = '__legacy_band__';
  bool _isNotifyingBand = false; // Sprint Task 8

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
          if (context.mounted) {
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
    if (!context.mounted) return;

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
    log("--- Initializing Dialog State ---");
    await _loadProfileAddress();
    await _loadAllKnownVenuesInternal();
    await _loadAllKnownBands();
    if (!context.mounted) return;
    if (_isEditingMode) {
      log("Editing Mode: Gig has bandName = '${widget.editingGig?.bandName}'");

      _editableGig = widget.editingGig!.copyWith(
        id: widget.editingGig!.id,
        bandName: () => widget.editingGig!.bandName, // <-- CRITICAL: This was missing
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
    if (context.mounted) {
      setState(() {
        _resolveInitialBandSelection();
        _isInitialized = true;
      });
      log("Setting UI state: _selectedBandId = '$_selectedBandId', "
          "_selectedBandName = '$_selectedBandName', "
          "_legacyBandName = '$_legacyBandName'");
    }
  }

  /// Figures out what the band dropdown should show on open. Three cases:
  /// a real bandId that still resolves to a band in _realBands, an old
  /// free-text-only bandName with no bandId (legacy — spec section 5, "no
  /// migration"), or a bandId that no longer resolves (band deleted/access
  /// lost) — falls back to showing the last-known name as legacy rather
  /// than silently dropping it. New/non-editing gigs default to Solo.
  void _resolveInitialBandSelection() {
    final gig = _editableGig;
    if (gig?.bandId != null) {
      final match = _realBands.where((b) => b.bandId == gig!.bandId);
      if (match.isNotEmpty) {
        _selectedBandId = gig!.bandId;
        _selectedBandName = match.first.name;
        _legacyBandName = null;
        return;
      }
      // bandId set but doesn't resolve anymore — don't lose the name.
      _legacyBandName = gig!.bandName;
      _selectedBandId = null;
      _selectedBandName = null;
      return;
    }
    if (gig?.bandName != null && gig!.bandName!.isNotEmpty) {
      _legacyBandName = gig.bandName;
      _selectedBandId = null;
      _selectedBandName = null;
      return;
    }
    // Solo.
    _selectedBandId = null;
    _selectedBandName = null;
    _legacyBandName = null;
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
      if (context.mounted) {
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
      if (context.mounted) {
        setState(() {
          _manualDriveDurationString = resultVenue?.driveDuration;
          _manualDriveDistance = resultVenue?.driveDistance;
        });
      }
    }
    if (context.mounted) {
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
    if (demoProvider.isDemoModeActive &&
        widget.currentDemoStep == DemoStep.bookingFormAction) {
      demoProvider.nextStep();
      Navigator.of(context)
          .pop(GigEditResult(action: GigEditResultAction.noChange));
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null || _selectedTime == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select a date and time.')));
      }
      return;
    }
    if (context.mounted) setState(() => _isProcessing = true);

    final DateTime selectedFullDateTime = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _selectedTime!.hour,
        _selectedTime!.minute);

    final double finalPay = double.tryParse(_payController.text) ?? 0;
    final double finalOtherExpenses =
        double.tryParse(_otherExpensesController.text) ?? 0;
    final double finalGigLengthHours =
        double.tryParse(_gigLengthController.text) ?? 0;
    final double finalDriveSetupHours =
        double.tryParse(_driveSetupController.text) ?? 0;
    final double finalRehearsalHours =
        double.tryParse(_rehearsalController.text) ?? 0;

    StoredLocation finalVenueDetails;
    if (_isAddNewVenue) {
      String newVenueName = _newVenueNameController.text.trim();
      String newVenueAddress = _newVenueAddressController.text.trim();
      if (newVenueName.isEmpty || newVenueAddress.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:
              Text('New venue name and address are required.')));
          setState(() => _isProcessing = false);
        }
        return;
      }
      LatLng? coords = await _geocodeAddress(newVenueAddress);
      if (coords == null) {
        if (context.mounted) setState(() => _isProcessing = false);
        return;
      }
      finalVenueDetails = StoredLocation(
          placeId: 'manual_${DateTime.now().millisecondsSinceEpoch}',
          name: newVenueName,
          address: newVenueAddress,
          coordinates: coords,
          isArchived: false,
          isPrivate: _isPrivateVenue);
      await _saveNewVenueToPrefs(finalVenueDetails);
    } else {
      if (_selectedVenue!.isPrivate != _isPrivateVenue) {
        finalVenueDetails = _selectedVenue!.copyWith(isPrivate: _isPrivateVenue);
        await _saveNewVenueToPrefs(finalVenueDetails);
      } else {
        finalVenueDetails = _selectedVenue!;
      }
    }

    if (!context.mounted) {
      setState(() => _isProcessing = false);
      return;
    }

    // _legacyBandName and _selectedBandName are mutually exclusive by
    // construction (see _onBandDropdownChanged / _resolveInitialBandSelection)
    // — a legacy free-text name never coexists with a real bandId.
    final String? finalBandName = _legacyBandName ?? _selectedBandName;
    final String? finalBandId = _legacyBandName != null ? null : _selectedBandId;

    log("--- Confirming Action ---");
    log("Returning gig with bandName: '$finalBandName', bandId: '$finalBandId'");

    // ✅ FIX: New bookings always start with retrospectiveCompleted = false.
    // Edit mode preserves the existing review state.
    // This prevents recurring occurrences from inheriting a completed
    // review from the parent template record.
    final bool? resolvedRetrospectiveCompleted =
    _isEditingMode ? _editableGig!.retrospectiveCompleted : false;

    final Gig newOrUpdatedGigData = _editableGig!.copyWith(
        venueName: finalVenueDetails.name,
        bandName: () => finalBandName,
        bandId: () => finalBandId,
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
        recurrenceDay: _editableGig!.recurrenceDay,
        recurrenceNthValue: _editableGig!.recurrenceNthValue,
        recurrenceEndDate: _editableGig!.recurrenceEndDate,
        retrospectiveCompleted: resolvedRetrospectiveCompleted);

    log("🧹 retrospectiveCompleted set to: $resolvedRetrospectiveCompleted (editingMode: $_isEditingMode)");

    List<Gig> otherGigsToCheck =
    List.from(widget.existingGigs.where((g) => !g.isJamOpenMic));
    if (_isEditingMode) {
      otherGigsToCheck
          .removeWhere((g) => g.id == widget.editingGig!.id);
    }
    final conflictingGig = _checkForConflict(newOrUpdatedGigData.dateTime,
        newOrUpdatedGigData.gigLengthHours, otherGigsToCheck);
    if (conflictingGig != null) {
      final bool? bookAnyway = await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
              title: const Text('Scheduling Conflict'),
              content: Text(
                  'This gig conflicts with "${conflictingGig.venueName}" on ${DateFormat.yMMMEd().format(conflictingGig.dateTime)}. ${_isEditingMode ? "Update" : "Book"} anyway?'),
              actions: <Widget>[
                TextButton(
                    child: const Text('CANCEL'),
                    onPressed: () =>
                        Navigator.of(dialogContext).pop(false)),
                TextButton(
                    child: Text(
                        '${_isEditingMode ? "UPDATE" : "BOOK"} ANYWAY'),
                    onPressed: () =>
                        Navigator.of(dialogContext).pop(true))
              ]));
      if (bookAnyway != true) {
        if (context.mounted) setState(() => _isProcessing = false);
        return;
      }
    }

    await _audioPlayer.play(AssetSource('sounds/thetone.wav'));
    await Future.delayed(const Duration(milliseconds: 2500));

    try {
      final notificationService = NotificationService();
      await notificationService.init();
      await notificationService.updateAllGigNotifications();
      log("🔔 Notifications rescheduled after gig save.");
    } catch (e) {
      log("⚠️ Error rescheduling notifications, but continuing. Error: $e");
    }

    // Fired on the BOOK button specifically — new gigs only, not edits —
    // regardless of which of the three entry points it came from (map,
    // calculator, or the "+" button/Add Gig flow). Per Cliff (8/9).
    if (!_isEditingMode) {
      final String entryPoint = _isCalculatorMode
          ? 'calculator'
          : (_isMapModeNewGig ? 'map' : 'add_button');
      unawaited(AnalyticsService.logGigBooked(
        entryPoint: entryPoint,
        hasBand: finalBandName != null,
        isRecurring: newOrUpdatedGigData.isRecurring,
      ));
    }

    if (context.mounted) setState(() => _isProcessing = false);
    if (context.mounted && Navigator.canPop(context)) {
      Navigator.of(context).pop(
          GigEditResult(action: GigEditResultAction.updated, gig: newOrUpdatedGigData));
    }
  }

  Future<void> _loadAllKnownVenuesInternal() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? locationsJson = prefs.getStringList('saved_locations');
    if (locationsJson != null) {
      _allKnownVenuesInternal = locationsJson.map((jsonString) {
        try { return StoredLocation.fromJson(jsonDecode(jsonString)); }
        catch (e) { log("Error decoding one stored location in BookingDialog: $e"); return null; }
      }).whereType<StoredLocation>().toList();
    }
  }

  /// Loads bands the current user leads OR belongs to as an active member
  /// (BandRepository.getBandsForUser — same query My Bands uses), so a
  /// member who isn't the leader can still represent the band on their own
  /// gigs, not just leaders.
  Future<void> _loadAllKnownBands() async {
    final authService = AuthService();
    if (!authService.isSignedIn) {
      // Standalone/signed-out — no backend connection, so no real bands.
      // Any existing bandName on the gig still renders via the legacy path.
      return;
    }
    try {
      final bands = await _bandRepository.getBandsForUser(authService.currentUserId);
      if (!mounted) return;
      setState(() {
        _realBands = bands..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      });
    } catch (e) {
      log("❌ Error loading bands for booking dialog: $e");
    }
  }

  /// Handles every possible band-dropdown selection: Solo, the legacy
  /// free-text placeholder (re-selecting it is a no-op — nothing to change),
  /// "+ New Band" (pushes CreateBandPage and auto-selects the result), or a
  /// real band's bandId.
  Future<void> _onBandDropdownChanged(String? val) async {
    if (val == null || val == _soloValue) {
      setState(() {
        _selectedBandId = null;
        _selectedBandName = null;
        _legacyBandName = null;
      });
      return;
    }

    if (val == _legacyBandValue) {
      return; // re-affirming the existing legacy value — nothing to do
    }

    if (val == _addNewBandValue) {
      final authService = AuthService();

      // Standalone / signed-out users have no backend connection, so a real
      // Firestore band can't exist for them regardless of price tier or
      // intent — but per Cliff (7/20), the plain text-caption way of
      // labeling a band is a permanent standalone feature, not something to
      // gate behind sign-in. Give them a lightweight prompt instead of the
      // full Create Band flow.
      if (!authService.isSignedIn) {
        final caption = await _promptForSimpleBandCaption();
        if (!mounted || caption == null || caption.trim().isEmpty) return;
        setState(() {
          _legacyBandName = caption.trim();
          _selectedBandId = null;
          _selectedBandName = null;
        });
        return;
      }

      final newBand = await Navigator.of(context).push<BandProject>(
        MaterialPageRoute(
          builder: (_) => CreateBandPage(leaderId: authService.currentUserId),
        ),
      );
      if (!mounted || newBand == null) return;
      setState(() {
        _realBands = [..._realBands, newBand]
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        _selectedBandId = newBand.bandId;
        _selectedBandName = newBand.name;
        _legacyBandName = null;
      });
      return;
    }

    // Otherwise val is a real band's bandId.
    final matchOnChange = _realBands.where((b) => b.bandId == val);
    if (matchOnChange.isEmpty) return;
    setState(() {
      _selectedBandId = matchOnChange.first.bandId;
      _selectedBandName = matchOnChange.first.name;
      _legacyBandName = null;
    });
  }

  /// Lightweight text-entry prompt for standalone/signed-out users who want
  /// to label a gig with a band name without any Firestore-backed Band
  /// entity. Deliberately just a caption — no members, no invites, nothing
  /// synced. This mirrors the pre-Task-7 free-text behavior and is the same
  /// mechanism that renders old/legacy band names (_legacyBandName), so a
  /// standalone-created caption is indistinguishable from historical data
  /// and needs no separate code path elsewhere in this file.
  Future<String?> _promptForSimpleBandCaption() async {
    final controller = TextEditingController(text: _legacyBandName ?? '');
    // Deliberately not disposing `controller` here — it's a one-off, local
    // controller with no other listeners, same as the equivalent rename
    // dialog in band_detail_page.dart. Disposing it right after showDialog
    // returns fires before the dialog's exit transition finishes (the
    // Future resolves the instant Navigator.pop runs, not after the
    // animation), which throws "TextEditingController used after being
    // disposed" on the still-animating-out TextField. Not worth chasing a
    // frame-timing fix for a single short-lived object GC handles fine.
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Band / Project Name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: "e.g. 'JC Band'",
            border: OutlineInputBorder(),
          ),
          onSubmitted: (val) => Navigator.of(dialogContext).pop(val),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return result;
  }

  /// Only the band's leader gets a Notify Band button — sidemen shouldn't
  /// be triggering notifications to their own bandmates.
  bool get _canNotifyBand {
    if (_selectedBandId == null) return false;
    final match = _realBands.where((b) => b.bandId == _selectedBandId);
    if (match.isEmpty) return false;
    return match.first.leaderId == AuthService().currentUserId;
  }

  /// Writes the gig-notification document (spec 7.1). Only reachable in
  /// edit mode, on an already-saved gig — a brand-new booking's id is still
  /// a temporary placeholder until _confirmAction persists it, so there's
  /// nothing real to notify about until the gig has been reopened once.
  /// This is Task 8's write only; no email actually goes out yet — that's
  /// the Cloud Function in Task 9, triggered server-side off this write.
  Future<void> _notifyBand() async {
    if (_selectedBandId == null || _editableGig == null) return;
    setState(() => _isNotifyingBand = true);

    final success = await _bandRepository.notifyBandOfGig(
      bandId: _selectedBandId!,
      gigId: _editableGig!.id,
      venueName: _editableGig!.venueName,
      dateTime: _editableGig!.dateTime,
      pay: _editableGig!.pay,
      address: _editableGig!.address,
    );

    if (!mounted) return;
    setState(() => _isNotifyingBand = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success
            ? 'Notification recorded for ${_selectedBandName ?? "the band"}.'
            : 'Could not record the notification. Try again.'),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }

  void _calculateDynamicRate() {
    if (!context.mounted || _isCalculatorMode) return;
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
    if (context.mounted) setState(() { _dynamicRateString = newRateString; _dynamicRateResultColor = newColor; });
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
      log("Error filtering/setting up venues for dropdown: $e");
      if (context.mounted) {
        setState(() {
          _selectableVenuesForDropdown = [_addNewVenuePlaceholder];
          _selectedVenue = _addNewVenuePlaceholder;
          _isAddNewVenue = true;
        });
      }
    } finally {
      if (context.mounted) setState(() { _isLoadingVenues = false; });
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
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Geocoding failed: API Key not configured.'), backgroundColor: Colors.red));
      return null;
    }
    final String encodedAddress = Uri.encodeComponent(address);
    final String url = 'https://maps.googleapis.com/maps/api/geocode/json?address=$encodedAddress&key=${widget.googleApiKey}';
    if(mounted) setState(() => _isGeocoding = true);
    try {
      final response = await http.get(Uri.parse(url));
      if (!context.mounted) return null;
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['results'] != null && (data['results'] as List).isNotEmpty) {
          final location = data['results'][0]['geometry']['location'];
          return LatLng(location['lat'], location['lng']);
        } else {
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not find coordinates: ${data['status']} ${data['error_message'] ?? ''}')));
          return null;
        }
      } else {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error contacting Geocoding service: ${response.statusCode}')));
        return null;
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('An error occurred while finding coordinates: $e')));
      return null;
    } finally {
      if (context.mounted) setState(() => _isGeocoding = false);
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

      if (context.mounted) setState(() => _isProcessing = true);

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

                      // --- START: BAND SELECTION FIELD (v3.0.0 real bands) ---
                      const Divider(height: 32),
                      Text("Band / Project:", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _legacyBandName != null
                            ? _legacyBandValue
                            : (_selectedBandId ?? _soloValue),
                        decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: [
                          const DropdownMenuItem<String>(value: _soloValue, child: Text("None / Solo")),
                          if (_legacyBandName != null)
                            DropdownMenuItem<String>(
                              value: _legacyBandValue,
                              child: Text(
                                '$_legacyBandName (unlinked)',
                                style: const TextStyle(fontStyle: FontStyle.italic),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ..._realBands.map((band) => DropdownMenuItem<String>(
                            value: band.bandId,
                            child: Text(band.name, overflow: TextOverflow.ellipsis),
                          )),
                          const DropdownMenuItem<String>(
                              value: _addNewBandValue,
                              child: Text('+ New Band', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))
                          ),
                        ],
                        onChanged: _onBandDropdownChanged,
                      ),
                      // --- END: BAND SELECTION FIELD ---
                      if (_isEditingMode && _canNotifyBand)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Center(
                            child: OutlinedButton.icon(
                              icon: _isNotifyingBand
                                  ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                                  : const Icon(Icons.notifications_active_outlined),
                              label: const Text('Notify Band'),
                              onPressed: _isNotifyingBand ? null : _notifyBand,
                            ),
                          ),
                        ),

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
                  Positioned.fill(child: Container(color: Colors.black.withValues(alpha: 0.3), child: const Center(child: CircularProgressIndicator()))),
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