// lib/features/gigs/views/gig_calculator_page.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/core/utils/logger.dart';
import 'package:the_money_gigs/features/gigs/widgets/booking_dialog.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';
import 'package:the_money_gigs/global_refresh_notifier.dart';

class GigCalculator extends StatefulWidget {
  const GigCalculator({super.key});

  @override
  State<GigCalculator> createState() => _GigCalculatorState();
}

class _GigCalculatorState extends State<GigCalculator>
    with WidgetsBindingObserver {
  static const String _googleApiKey = String.fromEnvironment('GOOGLE_API_KEY');

  final _payController = TextEditingController();
  final _gigTimeController = TextEditingController();
  final _driveSetupTimeController = TextEditingController();
  final _rehearsalTimeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String _hourlyRateResult = '';
  bool _showTakeGigButton = false;
  bool _isDoorGig = false;
  double _currentPay = 0.0;
  double _currentGigLengthHours = 0.0;
  double _currentDriveSetupHours = 0.0;
  double _currentRehearsalHours = 0.0;
  String _currentHourlyRateString = '';
  bool _showStageRateNotice = false;
  double _stageRate = 0.0;

  double? _userMinHourlyRate;
  Color _rateResultColor = Colors.greenAccent.shade400;

  bool _showSuggestedPayNotice = false;
  double _suggestedPay = 0.0;

  static const String _keyMinHourlyRate = 'profile_min_hourly_rate';
  static const String _keyGigsList = 'gigs_list';

  final _payFocusNode = FocusNode();
  final _gigTimeFocusNode = FocusNode();
  final _driveSetupTimeFocusNode = FocusNode();
  final _rehearsalTimeFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserMinHourlyRate();

    _gigTimeController.addListener(_calculateSuggestedPay);
    _driveSetupTimeController.addListener(_calculateSuggestedPay);
    _rehearsalTimeController.addListener(_calculateSuggestedPay);

    if (_googleApiKey.isEmpty) {
      log('WARNING (GigCalculator): GOOGLE_API_KEY not defined.');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _gigTimeController.removeListener(_calculateSuggestedPay);
    _driveSetupTimeController.removeListener(_calculateSuggestedPay);
    _rehearsalTimeController.removeListener(_calculateSuggestedPay);

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _loadUserMinHourlyRate();
    }
  }

  Future<void> _loadUserMinHourlyRate() async {
    final prefs = await SharedPreferences.getInstance();
    if (!context.mounted) return;
    setState(() {
      _userMinHourlyRate = prefs.getInt(_keyMinHourlyRate)?.toDouble();
      _calculateSuggestedPay();
    });
  }

  void _calculateSuggestedPay() {
    final pay = double.tryParse(_payController.text) ?? 0;
    final gigTime = double.tryParse(_gigTimeController.text) ?? 0;
    final driveTime = double.tryParse(_driveSetupTimeController.text) ?? 0;
    final rehearsalTime = double.tryParse(_rehearsalTimeController.text) ?? 0;

    setState(() {
      if (pay > 0 && gigTime > 0) {
        _stageRate = pay / gigTime;
        _showStageRateNotice = true;
      } else {
        _showStageRateNotice = false;
      }

      if (_userMinHourlyRate != null && _userMinHourlyRate! > 0) {
        final bool shouldShow =
            gigTime > 0 && (driveTime > 0 || rehearsalTime > 0);
        if (shouldShow) {
          final totalHours = gigTime + driveTime + rehearsalTime;
          _suggestedPay = totalHours * _userMinHourlyRate!;
          _showSuggestedPayNotice = true;
        } else {
          _showSuggestedPayNotice = false;
        }
      } else {
        _showSuggestedPayNotice = false;
      }
    });
  }

  void _clearAllInputFields() {
    FocusScope.of(context).unfocus();
    _payController.clear();
    _gigTimeController.clear();
    _driveSetupTimeController.clear();
    _rehearsalTimeController.clear();
    if (context.mounted) {
      setState(() {
        _isDoorGig = false;
        _hourlyRateResult = '';
        _showTakeGigButton = false;
        _showSuggestedPayNotice = false;
        _showStageRateNotice = false;
      });
    }
  }

  Future<void> _performCalculation() async {
    FocusScope.of(context).unfocus();
    await _loadUserMinHourlyRate();
    if (!context.mounted) return;

    String newHourlyRateResult = '';
    String newCurrentHourlyRateString = '';
    Color newRateResultColor = Colors.greenAccent.shade400;
    bool newShowTakeGigButton = false;
    double newCurrentPay = 0.0;
    double newCurrentGigLengthHours = 0.0;
    double newCurrentDriveSetupHours = 0.0;
    double newCurrentRehearsalHours = 0.0;

    if (_formKey.currentState!.validate()) {
      final double pay = double.tryParse(_payController.text) ?? 0;
      final double gigTime = double.tryParse(_gigTimeController.text) ?? 0;
      final double driveSetupTime =
          double.tryParse(_driveSetupTimeController.text) ?? 0;
      final double rehearsalTime =
          double.tryParse(_rehearsalTimeController.text) ?? 0;
      final double totalHours = gigTime + driveSetupTime + rehearsalTime;

      if (totalHours > 0) {
        if (pay > 0) {
          final double calculatedRate = pay / totalHours;
          final String rateString =
              '\$${calculatedRate.toStringAsFixed(2)} per hour';
          newHourlyRateResult = rateString;
          newCurrentHourlyRateString = rateString;
          newRateResultColor =
          (_userMinHourlyRate != null && calculatedRate < _userMinHourlyRate!)
              ? Colors.redAccent.shade200
              : Colors.greenAccent.shade400;
          newShowTakeGigButton = true;
          newCurrentPay = pay;
        } else if (_isDoorGig) {
          newHourlyRateResult = 'Door Gig - Pay TBD';
          newCurrentHourlyRateString = 'Door Gig';
          newRateResultColor = Colors.orangeAccent;
          newShowTakeGigButton = true;
          newCurrentPay = 0.0;
        } else {
          newHourlyRateResult = 'Please provide the Pay for the Gig.';
          newRateResultColor = Colors.lightBlue.shade200;
        }
        newCurrentGigLengthHours = gigTime;
        newCurrentDriveSetupHours = driveSetupTime;
        newCurrentRehearsalHours = rehearsalTime;
      } else {
        newHourlyRateResult = 'Enter the time(s) for the rate calculation.';
        newRateResultColor = Colors.lightBlue.shade200;
      }
    } else {
      newHourlyRateResult = 'Please check the fields above.';
      newRateResultColor = Colors.lightBlue.shade200;
    }

    setState(() {
      _hourlyRateResult = newHourlyRateResult;
      _currentHourlyRateString = newCurrentHourlyRateString;
      _rateResultColor = newRateResultColor;
      _showTakeGigButton = newShowTakeGigButton;
      _currentPay = newCurrentPay;
      _currentGigLengthHours = newCurrentGigLengthHours;
      _currentDriveSetupHours = newCurrentDriveSetupHours;
      _currentRehearsalHours = newCurrentRehearsalHours;
    });
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
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error loading existing gigs: $e'),
            backgroundColor: Colors.orange));
      }
      return [];
    }
  }

  Future<void> _saveBookedGigToList(Gig gigToSave) async {
    final prefs = await SharedPreferences.getInstance();
    List<Gig> existingGigs = await _loadAllGigsFromPreferences();
    final index = existingGigs.indexWhere((g) => g.id == gigToSave.id);
    if (index != -1) {
      existingGigs[index] = gigToSave;
    } else {
      existingGigs.add(gigToSave);
    }
    existingGigs.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    await prefs.setString(_keyGigsList, Gig.encode(existingGigs));
    globalRefreshNotifier.notify();
  }

  Future<void> _showBookingDialog() async {
    if (!_showTakeGigButton ||
        _currentHourlyRateString.isEmpty ||
        (!_isDoorGig && _currentPay <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please calculate valid gig details first.')));
      return;
    }

    if (_googleApiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('API Key Missing. Booking new venues may fail.'),
          backgroundColor: Colors.redAccent));
    }

    final List<Gig> allExistingGigs = await _loadAllGigsFromPreferences();
    if (!context.mounted) return;

    final GigEditResult? result = await showDialog<GigEditResult>(
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
          existingGigs:
          allExistingGigs.where((g) => !g.isJamOpenMic).toList(),
          onNewVenuePotentiallyAdded: () async {},
        );
      },
    );

    if (!context.mounted) return;

    if (result != null &&
        result.action == GigEditResultAction.updated &&
        result.gig != null) {
      final bookedGig = result.gig!;
      await _saveBookedGigToList(bookedGig);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${bookedGig.venueName} gig booked!'),
            backgroundColor: Colors.green),
      );
      _clearAllInputFields();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking cancelled.')),
      );
    }
  }

  String? _validatePay(String? value) {
    if (_isDoorGig) return null;
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

  // ── Build ─────────────────────────────────────────────────────────────────
  // No Consumer/Stack wrapper — direct return fixes the ripple effect.

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
          borderSide:
          BorderSide(color: focusedInputBorderColor, width: 2.0),
          borderRadius: BorderRadius.circular(8.0),
        ),
        errorBorder: OutlineInputBorder(
          borderSide:
          BorderSide(color: Colors.redAccent.shade200, width: 1.5),
          borderRadius: BorderRadius.circular(8.0),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderSide:
          BorderSide(color: Colors.redAccent.shade200, width: 2.0),
          borderRadius: BorderRadius.circular(8.0),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        FocusScopeNode currentFocus = FocusScope.of(context);
        if (!currentFocus.hasPrimaryFocus &&
            currentFocus.focusedChild != null) {
          FocusManager.instance.primaryFocus?.unfocus();
        }
      },
      child: SingleChildScrollView(
        padding:
        const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
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
                const Padding(
                  padding: EdgeInsets.fromLTRB(8.0, 0.0, 8.0, 24.0),
                  child: Text(
                    'Your pay data is stored on your device only and never shared.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                        fontStyle: FontStyle.italic),
                  ),
                ),

                // Pay field
                TextFormField(
                  controller: _payController,
                  focusNode: _payFocusNode,
                  style: TextStyle(color: formTextColor, fontSize: 16),
                  decoration: formInputDecoration(
                    labelText: _isDoorGig ? 'Estimated Pay' : 'Total Pay',
                    hintText: "Ask: What's your budget?",
                    icon: Icons.attach_money,
                  ),
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  validator: _validatePay,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) =>
                      FocusScope.of(context).requestFocus(_gigTimeFocusNode),
                ),

                // Door gig toggle
                Padding(
                  padding: const EdgeInsets.only(left: 4.0),
                  child: Row(
                    children: [
                      const Text('Door Gig',
                          style: TextStyle(color: Colors.white70)),
                      Switch(
                        value: _isDoorGig,
                        activeThumbColor: Colors.orangeAccent,
                        onChanged: (bool value) {
                          setState(() {
                            _isDoorGig = value;
                            _formKey.currentState?.validate();
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16.0),

                // Suggested pay notice
                AnimatedOpacity(
                  opacity: _showSuggestedPayNotice ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 400),
                  child: _showSuggestedPayNotice
                      ? Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 16.0),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12.0, vertical: 8.0),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade800,
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    child: Text(
                      "You'd like at least ${NumberFormat.currency(locale: 'en_US', symbol: '\$').format(_suggestedPay)} for this gig.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.lightBlue.shade200,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                      : const SizedBox.shrink(),
                ),

                // Gig time field
                TextFormField(
                  controller: _gigTimeController,
                  focusNode: _gigTimeFocusNode,
                  style: TextStyle(color: formTextColor, fontSize: 16),
                  decoration: formInputDecoration(
                    labelText: 'Gig Time (hours)',
                    hintText: 'e.g., 3.5',
                    icon: Icons.timer_outlined,
                  ),
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) => _validateTime(value, 'Gig Time'),
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => FocusScope.of(context)
                      .requestFocus(_driveSetupTimeFocusNode),
                ),

                // Stage rate notice
                AnimatedOpacity(
                  opacity: _showStageRateNotice ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 400),
                  child: _showStageRateNotice
                      ? Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12.0, vertical: 8.0),
                    decoration: BoxDecoration(
                      color:
                      Colors.blueGrey.shade900.withAlpha(150),
                      borderRadius: BorderRadius.circular(8.0),
                      border:
                      Border.all(color: Colors.blueGrey.shade700),
                    ),
                    child: Text(
                      'Stage Rate: ${NumberFormat.currency(locale: 'en_US', symbol: '\$').format(_stageRate)} / hr',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.orangeAccent.shade100,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: 16.0),

                // Drive & setup field
                TextFormField(
                  controller: _driveSetupTimeController,
                  focusNode: _driveSetupTimeFocusNode,
                  style: TextStyle(color: formTextColor, fontSize: 16),
                  decoration: formInputDecoration(
                    labelText: 'Drive & Setup (hours)',
                    hintText: 'e.g., 1',
                    icon: Icons.directions_car_outlined,
                  ),
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) =>
                      _validateTime(value, 'Drive & Setup Time'),
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => FocusScope.of(context)
                      .requestFocus(_rehearsalTimeFocusNode),
                ),
                const SizedBox(height: 16.0),

                // Rehearsal time + Calculate button
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
                          icon: Icons.music_note_outlined,
                        ),
                        keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
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
                          backgroundColor:
                          Theme.of(context).colorScheme.primary,
                          foregroundColor:
                          Theme.of(context).colorScheme.onPrimary,
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

                // Result display
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

                // Take Gig / Clear buttons
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
                              padding: const EdgeInsets.symmetric(
                                  vertical: 16.0),
                              textStyle: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12.0)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12.0),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _clearAllInputFields,
                            icon: Icon(Icons.clear_all_outlined,
                                color: Colors.grey.shade300),
                            label: Text(
                              'Clear All',
                              style:
                              TextStyle(color: Colors.grey.shade300),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.grey.shade600),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 16.0),
                              textStyle: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12.0)),
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
      ),
    );
  }
}