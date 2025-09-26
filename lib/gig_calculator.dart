import 'package:flutter/material.dart';
import 'dart:convert'; // For jsonEncode, jsonDecode
import 'package:shared_preferences/shared_preferences.dart';

import 'booking_dialog.dart'; // Import the BookingDialog
import 'gig_model.dart';      // Import your Gig model
import 'package:the_money_gigs/global_refresh_notifier.dart'; // Import the notifier

class GigCalculator extends StatefulWidget {
  const GigCalculator({super.key});

  @override
  State<GigCalculator> createState() => _GigCalculatorState();
}

class _GigCalculatorState extends State<GigCalculator> {
  static const String _googleApiKey = String.fromEnvironment('GOOGLE_API_KEY');

  final _payController = TextEditingController();
  final _gigTimeController = TextEditingController();
  final _driveSetupTimeController = TextEditingController();
  final _rehearsalTimeController = TextEditingController();
  String _hourlyRateResult = "";
  final _formKey = GlobalKey<FormState>();

  bool _showTakeGigButton = false;
  double _currentPay = 0.0;
  double _currentGigLengthHours = 0.0;
  double _currentDriveSetupHours = 0.0;
  double _currentRehearsalHours = 0.0;
  String _currentHourlyRateString = "";

  double? _userMinHourlyRate;
  Color _rateResultColor = Colors.greenAccent.shade400;

  static const String _keyMinHourlyRate = 'profile_min_hourly_rate';
  static const String _keyGigsList = 'gigs_list';

  // FocusNodes for managing focus and keyboard
  final _payFocusNode = FocusNode();
  final _gigTimeFocusNode = FocusNode();
  final _driveSetupTimeFocusNode = FocusNode();
  final _rehearsalTimeFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadUserMinHourlyRate();

    if (_googleApiKey.isEmpty) {
      print("CRITICAL WARNING (GigCalculator): GOOGLE_API_KEY is not defined. Geocoding will fail.");
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('API Key Missing: Booking new venues may fail.'),
              backgroundColor: Colors.redAccent,
              duration: Duration(seconds: 7),
            ),
          );
        }
      });
    }
  }

  Future<void> _loadUserMinHourlyRate() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _userMinHourlyRate = prefs.getInt(_keyMinHourlyRate)?.toDouble();
    });
  }

  @override
  void dispose() {
    _payController.dispose();
    _gigTimeController.dispose();
    _driveSetupTimeController.dispose();
    _rehearsalTimeController.dispose();

    _payFocusNode.dispose();
    _gigTimeFocusNode.dispose();
    _driveSetupTimeFocusNode.dispose();
    _rehearsalTimeFocusNode.dispose();
    super.dispose();
  }

  // This method is designed to reset results and form validation BUT keep input text
  // It is NOT currently used by the "Clear All" button in your provided build method
  void _resetGigDetailsAndForm() {
    FocusScope.of(context).unfocus(); // Dismiss keyboard
    if (mounted) {
      setState(() {
        _showTakeGigButton = false;
        _currentPay = 0.0;
        _currentGigLengthHours = 0.0;
        _currentDriveSetupHours = 0.0;
        _currentRehearsalHours = 0.0;
        _currentHourlyRateString = "";
        _hourlyRateResult = "";
        _rateResultColor = Colors.greenAccent.shade400;
        _formKey.currentState?.reset(); // Resets validation state
      });
    }
  }

  // This method is called by the "Clear All" button.
  // It clears TextFormFields and resets calculated results and form state.
  void _clearAllInputFields() {
    print("DEBUG: _clearAllInputFields CALLED");
    FocusScope.of(context).unfocus();

    print("DEBUG: _payController.text BEFORE clear(): '${_payController.text}'");
    _payController.clear();
    print("DEBUG: _payController.text AFTER clear(): '${_payController.text}'");

    _gigTimeController.clear();
    _driveSetupTimeController.clear();
    _rehearsalTimeController.clear();

    if (mounted) {
      // TEMPORARY: Minimal setState to force a rebuild and see if the controller's empty state is picked up
      setState(() {
        // Just change one simple boolean to ensure setState itself is working
        // _showTakeGigButton = !_showTakeGigButton; // Or some other trivial change
        // OR even just an empty setState can sometimes be enough for controllers if their internal state changed
        print("DEBUG: Minimal setState in _clearAllInputFields EXECUTED");
      });

      // Optional: Call the full setState AFTER a short delay to see if it's a timing issue
      // Future.delayed(const Duration(milliseconds: 100), () {
      //   if (mounted) {
      //     setState(() {
      //       _showTakeGigButton = false;
      //       _currentPay = 0.0;
      //       _currentGigLengthHours = 0.0;
      //       _currentDriveSetupHours = 0.0;
      //       _currentRehearsalHours = 0.0;
      //       _currentHourlyRateString = "";//       _hourlyRateResult = "";
      //       _rateResultColor = Colors.greenAccent.shade400;
      //       _formKey.currentState?.reset();
      //       print("DEBUG: FULL setState in _clearAllInputFields EXECUTED after delay");
      //     });
      //   }
      // });

    } else {
      print("DEBUG: _clearAllInputFields - NOT MOUNTED when setState was to be called");
    }
  }

  Future<void> _performCalculation() async {
    FocusScope.of(context).unfocus();
    await _loadUserMinHourlyRate();

    if (!mounted) return;
    setState(() {
      _showTakeGigButton = false;
      _currentHourlyRateString = "";
      _hourlyRateResult = ""; // Clear previous results before validating
      _rateResultColor = Colors.greenAccent.shade400;
    });

    if (_formKey.currentState!.validate()) {
      final double pay = double.tryParse(_payController.text) ?? 0;
      final double gigTime = double.tryParse(_gigTimeController.text) ?? 0;
      final double driveSetupTime = double.tryParse(_driveSetupTimeController.text) ?? 0;
      final double rehearsalTime = double.tryParse(_rehearsalTimeController.text) ?? 0;
      final double totalHoursForRateCalc = gigTime + driveSetupTime + rehearsalTime;

      if (totalHoursForRateCalc > 0 && pay > 0) {
        final double calculatedRate = pay / totalHoursForRateCalc;
        final String rateString = '\$${calculatedRate.toStringAsFixed(2)} per hour';
        Color newResultColor = Colors.greenAccent.shade400;
        if (_userMinHourlyRate != null && calculatedRate < _userMinHourlyRate!) {
          newResultColor = Colors.redAccent.shade200;
        }
        if (mounted) {
          setState(() {
            _hourlyRateResult = rateString;
            _currentHourlyRateString = rateString;
            _rateResultColor = newResultColor;
            _showTakeGigButton = true;
            _currentPay = pay;
            _currentGigLengthHours = gigTime;
            _currentDriveSetupHours = driveSetupTime;
            _currentRehearsalHours = rehearsalTime;
          });
        }
      } else {
        String errorMessage = "";
        if (pay <= 0 && totalHoursForRateCalc > 0) {
          errorMessage = 'Please enter a valid pay amount.';
        } else if (pay > 0 && totalHoursForRateCalc <= 0) {
          errorMessage = 'Total hours must be greater than zero.';
        } else {
          errorMessage = 'Please enter valid pay and time(s) for the gig calculation.';
        }
        if (mounted) {
          setState(() {
            _hourlyRateResult = errorMessage;
            _rateResultColor = Colors.redAccent.shade200;
            _showTakeGigButton = false;
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _hourlyRateResult = 'Please correct the errors above.';
          _rateResultColor = Colors.redAccent.shade200;
          _showTakeGigButton = false;
        });
      }
    }
  }

  Future<List<Gig>> _loadAllGigsFromPreferences() async {
    // ... (no changes needed here for "Clear All" button)
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? gigsJsonString = prefs.getString(_keyGigsList);
      if (gigsJsonString != null && gigsJsonString.isNotEmpty) {
        return Gig.decode(gigsJsonString);
      }
      return [];
    } catch (e) {
      print("Error loading all gigs from SharedPreferences: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error loading existing gigs: $e'),
            backgroundColor: Colors.orange));
      }
      return [];
    }
  }

  Future<void> _saveBookedGigToList(Gig gigToSave) async {
    // ... (no changes needed here for "Clear All" button)
    final prefs = await SharedPreferences.getInstance();
    List<Gig> existingGigs = await _loadAllGigsFromPreferences();
    final index = existingGigs.indexWhere((g) => g.id == gigToSave.id);
    if (index != -1) {
      existingGigs[index] = gigToSave;
      print("GigCalculator: Gig updated: ${gigToSave.venueName}");
    } else {
      existingGigs.add(gigToSave);
      print("GigCalculator: Gig saved: ${gigToSave.venueName}");
    }
    existingGigs.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    await prefs.setString(_keyGigsList, Gig.encode(existingGigs));
    globalRefreshNotifier.notify();
    print("GigCalculator: Global refresh notified after saving gig.");
  }

  Future<void> _showBookingDialog() async {
    // ... (no changes needed here for "Clear All" button, but it calls _clearAllInputFields on success)
    if (!_showTakeGigButton ||
        _currentHourlyRateString.isEmpty ||
        _currentPay <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please calculate valid gig details first.')));
      return;
    }
    if (_googleApiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('API Key Missing. Booking new venues may fail.'),
          backgroundColor: Colors.redAccent));
    }

    List<Gig> allExistingGigs = await _loadAllGigsFromPreferences();
    if (!mounted) return;

    final dynamic result = await showDialog<dynamic>( // Changed to dynamic to handle Gig or GigEditResult
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return BookingDialog(
          calculatedHourlyRate: _currentHourlyRateString,
          totalPay: _currentPay,
          gigLengthHours: _currentGigLengthHours,
          driveSetupTimeHours: _currentDriveSetupHours,
          rehearsalTimeHours: _currentRehearsalHours,
          googleApiKey: _googleApiKey,
          existingGigs: allExistingGigs.where((g) => !g.isJamOpenMic).toList(), // Pass only actual gigs
          onNewVenuePotentiallyAdded: () async {
            print("GigCalculator: BookingDialog's onNewVenuePotentiallyAdded callback received.");
          },
        );
      },
    );

    if (!mounted) return;

    if (result is Gig) { // New gig was booked
      final bookedGig = result;
      await _saveBookedGigToList(bookedGig);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${bookedGig.venueName} gig booked!'),
            backgroundColor: Colors.green),
      );
      _clearAllInputFields(); // Clear fields after successful booking
    } else if (result is GigEditResult) {
      // This case should ideally not happen if launching BookingDialog for a new gig
      // but handling it defensively.
      if (result.action == GigEditResultAction.updated && result.gig != null) {
        // This implies an existing gig was somehow passed and updated, which is not the flow here
        print("GigCalculator: Unexpected GigEditResult.updated from new gig booking flow.");
      } else if (result.action == GigEditResultAction.deleted) {
        print("GigCalculator: Unexpected GigEditResult.deleted from new gig booking flow.");
      }
      // If GigEditResultAction.noChange or other, treat as cancellation for new gig flow
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking process not completed.')),
      );
    } else { // Dialog was dismissed or returned null (treat as cancellation)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking cancelled.')),
      );
    }
  }

  String? _validatePay(String? value) {
    if (value == null || value.isEmpty) return 'Please enter pay amount';
    final number = double.tryParse(value);
    if (number == null) return 'Please enter a valid number';
    if (number <= 0) return 'Pay must be > 0';
    return null;
  }

  String? _validateTime(String? value, String fieldName) {
    if (value == null || value.isEmpty) return null;
    final number = double.tryParse(value);
    if (number == null) return 'Enter a valid number for $fieldName';
    if (number < 0) return '$fieldName cannot be negative';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final formBackgroundColor = Colors.black.withAlpha(128);
    final formTextColor = Colors.white;
    final formHintColor = Colors.white70;
    final formLabelColor = Colors.orangeAccent.shade100;
    final inputBorderColor = Colors.grey.shade600;
    final focusedInputBorderColor = Theme.of(context).colorScheme.primary;

    InputDecoration formInputDecoration({
      required String labelText,
      required String hintText,
      required IconData icon,
    }) {
      return InputDecoration(
        labelText: labelText,
        labelStyle: TextStyle(color: formLabelColor),
        hintText: hintText,
        hintStyle: TextStyle(color: formHintColor),
        prefixIcon: Icon(icon, color: formLabelColor),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: inputBorderColor),
          borderRadius: BorderRadius.circular(8.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: focusedInputBorderColor, width: 2.0),
          borderRadius: BorderRadius.circular(8.0),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.redAccent.shade200, width: 1.5),
          borderRadius: BorderRadius.circular(8.0),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.redAccent.shade200, width: 2.0),
          borderRadius: BorderRadius.circular(8.0),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        FocusScopeNode currentFocus = FocusScope.of(context);
        if (!currentFocus.hasPrimaryFocus && currentFocus.focusedChild != null) {
          FocusManager.instance.primaryFocus?.unfocus();
        }
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
        child: Container(
          padding: const EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            color: formBackgroundColor,
            borderRadius: BorderRadius.circular(16.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(128),
                spreadRadius: 2,
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextFormField(
                  controller: _payController,
                  focusNode: _payFocusNode,
                  style: TextStyle(color: formTextColor, fontSize: 16),
                  decoration: formInputDecoration(
                      labelText: 'Pay',
                      hintText: 'e.g., 150',
                      icon: Icons.attach_money),
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  validator: _validatePay,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) =>
                      FocusScope.of(context).requestFocus(_gigTimeFocusNode),
                ),
                const SizedBox(height: 16.0),
                TextFormField(
                  controller: _gigTimeController,
                  focusNode: _gigTimeFocusNode,
                  style: TextStyle(color: formTextColor, fontSize: 16),
                  decoration: formInputDecoration(
                      labelText: 'Gig Time (hours)',
                      hintText: 'e.g., 3.5',
                      icon: Icons.timer_outlined),
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) => _validateTime(value, 'Gig Time'),
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => FocusScope.of(context)
                      .requestFocus(_driveSetupTimeFocusNode),
                ),
                const SizedBox(height: 16.0),
                TextFormField(
                  controller: _driveSetupTimeController,
                  focusNode: _driveSetupTimeFocusNode,
                  style: TextStyle(color: formTextColor, fontSize: 16),
                  decoration: formInputDecoration(
                      labelText: 'Drive & Setup (hours)',
                      hintText: 'e.g., 1',
                      icon: Icons.directions_car_outlined),
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) =>
                      _validateTime(value, 'Drive & Setup Time'),
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => FocusScope.of(context)
                      .requestFocus(_rehearsalTimeFocusNode),
                ),
                const SizedBox(height: 16.0),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _rehearsalTimeController,
                        focusNode: _rehearsalTimeFocusNode,
                        style: TextStyle(color: formTextColor, fontSize: 16),
                        decoration: formInputDecoration(
                            labelText: 'Rehearsal Time (hours)',
                            hintText: 'e.g., 2',
                            icon: Icons.music_note_outlined),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        validator: (value) =>
                            _validateTime(value, 'Rehearsal Time'),
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _performCalculation(),
                      ),
                    ),
                    const SizedBox(width: 12.0),
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: ElevatedButton(
                        onPressed: _performCalculation,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Theme.of(context).colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18.0, vertical: 15.0),
                          textStyle: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8.0)),
                        ),
                        child: const Text('Calculate'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24.0),
                if (_hourlyRateResult.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Center(
                      child: Text(
                        _hourlyRateResult,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _rateResultColor,
                          shadows: [
                            Shadow(
                              offset: const Offset(1.0, 1.0),
                              blurRadius: 2.0,
                              color: Colors.black.withAlpha(128),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                // "Take This Gig" and "Clear All" buttons are shown together if _showTakeGigButton is true
                if (_showTakeGigButton)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _showBookingDialog,
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Take This Gig!'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                              _rateResultColor == Colors.redAccent.shade200
                                  ? Colors.orange.shade700
                                  : Colors.green.shade600,
                              foregroundColor: Colors.white,
                              padding:
                              const EdgeInsets.symmetric(vertical: 16.0),
                              textStyle: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12.0)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12.0),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _clearAllInputFields, // This is the correct method
                            icon: Icon(Icons.clear_all_outlined,
                                color: Colors.grey.shade300),
                            label: Text(
                              'Clear All',
                              style: TextStyle(color: Colors.grey.shade300),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.grey.shade600),
                              padding:
                              const EdgeInsets.symmetric(vertical: 16.0),
                              textStyle: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12.0)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                // If you want the "Clear All" button to be visible even when "Take This Gig" isn't,
                // you would move it outside the `if (_showTakeGigButton)` block
                // or have a separate condition for it.
                // For example, to always show a clear button if there's any text or result:
                /*
                else if (_payController.text.isNotEmpty ||
                           _gigTimeController.text.isNotEmpty ||
                           _driveSetupTimeController.text.isNotEmpty ||
                           _rehearsalTimeController.text.isNotEmpty ||
                           _hourlyRateResult.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                    child: Center( // Or use a Row if you prefer alignment
                      child: OutlinedButton.icon(
                        onPressed: _clearAllInputFields,
                        icon: Icon(Icons.clear_all_outlined, color: Colors.grey.shade300),
                        label: Text('Clear All', style: TextStyle(color: Colors.grey.shade300)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey.shade600),
                          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 24.0),
                          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                        ),
                      ),
                    ),
                  ),
                */
              ],
            ),
          ),
        ),
      ),
    );
  }
}
