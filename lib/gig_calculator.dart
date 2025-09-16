// lib/gig_calculator.dart

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
  // No need for _keySavedLocations here, BookingDialog handles saving new venues.

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
    super.dispose();
  }

  void _resetGigDetailsAndForm() {
    FocusScope.of(context).unfocus();
    setState(() {
      _showTakeGigButton = false;
      _currentPay = 0.0;
      _currentGigLengthHours = 0.0;
      _currentDriveSetupHours = 0.0;
      _currentRehearsalHours = 0.0;
      _currentHourlyRateString = "";
      _hourlyRateResult = "";
      _rateResultColor = Colors.greenAccent.shade400;
      _payController.clear();
      _gigTimeController.clear();
      _driveSetupTimeController.clear();
      _rehearsalTimeController.clear();
    });
  }

  Future<void> _calculateHourlyRate() async {
    await _loadUserMinHourlyRate();
    setState(() {
      _showTakeGigButton = false;
      _currentHourlyRateString = "";
      _hourlyRateResult = "";
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
      } else {
        String errorMessage = "";
        if (pay <= 0 && totalHoursForRateCalc > 0) {
          errorMessage = 'Please enter a valid pay amount.';
        } else if (pay > 0 && totalHoursForRateCalc <= 0) {
          errorMessage = 'Total hours must be greater than zero.';
        } else {
          errorMessage = 'Please enter valid pay and time(s) for the gig calculation.';
        }
        setState(() {
          _hourlyRateResult = errorMessage;
          _rateResultColor = Colors.redAccent.shade200;
          _showTakeGigButton = false;
        });
      }
    } else {
      setState(() {
        _hourlyRateResult = 'Please correct the errors above.';
        _rateResultColor = Colors.redAccent.shade200;
        _showTakeGigButton = false;
      });
    }
  }

  Future<List<Gig>> _loadAllGigsFromPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? gigsJsonString = prefs.getString(_keyGigsList);
      if (gigsJsonString != null && gigsJsonString.isNotEmpty) {
        return Gig.decode(gigsJsonString);
      }
      return [];
    } catch (e) {
      print("Error loading all gigs from SharedPreferences: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading existing gigs: $e'), backgroundColor: Colors.orange));
      return [];
    }
  }

  Future<void> _saveBookedGigToList(Gig gigToSave) async {
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
    existingGigs.sort((a,b) => a.dateTime.compareTo(b.dateTime));
    await prefs.setString(_keyGigsList, Gig.encode(existingGigs));
    globalRefreshNotifier.notify();
    print("GigCalculator: Global refresh notified after saving gig.");
  }

  Future<void> _showBookingDialog() async {
    if (!_showTakeGigButton || _currentHourlyRateString.isEmpty || _currentPay <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please calculate valid gig details first.')));
      return;
    }
    if (_googleApiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('API Key Missing. Booking new venues may fail.'), backgroundColor: Colors.redAccent));
      // Optionally allow proceeding if user acknowledges, or return
    }

    List<Gig> allExistingGigs = await _loadAllGigsFromPreferences();
    if (!mounted) return;

    final Gig? bookedGig = await showDialog<Gig>(
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
          existingGigs: allExistingGigs,
          onNewVenuePotentiallyAdded: () async {
            print("GigCalculator: BookingDialog's onNewVenuePotentiallyAdded callback received.");
          },
        );
      },
    );

    if (bookedGig != null) {
      await _saveBookedGigToList(bookedGig);
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${bookedGig.venueName} gig booked!'), backgroundColor: Colors.green),
        );
      }
      _resetGigDetailsAndForm();
    } else {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Booking cancelled.')),
        );
      }
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

  // --- BUILD METHOD RESTORED ---
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

    return SingleChildScrollView(
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
                style: TextStyle(color: formTextColor, fontSize: 16),
                decoration: formInputDecoration(labelText: 'Pay', hintText: 'e.g., 150', icon: Icons.attach_money),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: _validatePay,
              ),
              const SizedBox(height: 16.0),
              TextFormField(
                controller: _gigTimeController,
                style: TextStyle(color: formTextColor, fontSize: 16),
                decoration: formInputDecoration(labelText: 'Gig Time (hours)', hintText: 'e.g., 3.5', icon: Icons.timer_outlined),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) => _validateTime(value, 'Gig Time'),
              ),
              const SizedBox(height: 16.0),
              TextFormField(
                controller: _driveSetupTimeController,
                style: TextStyle(color: formTextColor, fontSize: 16),
                decoration: formInputDecoration(labelText: 'Drive & Setup (hours)', hintText: 'e.g., 1', icon: Icons.directions_car_outlined),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) => _validateTime(value, 'Drive & Setup Time'),
              ),
              const SizedBox(height: 16.0),
              TextFormField(
                controller: _rehearsalTimeController,
                style: TextStyle(color: formTextColor, fontSize: 16),
                decoration: formInputDecoration(labelText: 'Rehearsal Time (hours)', hintText: 'e.g., 2', icon: Icons.music_note_outlined),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) => _validateTime(value, 'Rehearsal Time'),
              ),
              const SizedBox(height: 24.0),
              ElevatedButton(
                onPressed: _calculateHourlyRate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                ),
                child: const Text('Calculate Hourly Rate'),
              ),
              const SizedBox(height: 16.0),
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
                            backgroundColor: _rateResultColor == Colors.redAccent.shade200
                                ? Colors.orange.shade700
                                : Colors.green.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16.0),
                            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12.0),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _resetGigDetailsAndForm,
                          icon: Icon(Icons.cancel_outlined, color: Colors.grey.shade300),
                          label: Text(
                            'Clear',
                            style: TextStyle(color: Colors.grey.shade300),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.grey.shade600),
                            padding: const EdgeInsets.symmetric(vertical: 16.0),
                            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
// --- END OF BUILD METHOD ---
}
