// lib/features/gigs/views/gig_calculator_page.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // <<< ADDED for currency formatting
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:the_money_gigs/features/gigs/widgets/booking_dialog.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';
import 'package:the_money_gigs/global_refresh_notifier.dart';

// Demo-related imports
import 'package:the_money_gigs/features/app_demo/providers/demo_provider.dart';
import 'package:the_money_gigs/features/app_demo/widgets/tutorial_overlay.dart';

// Helper class for the demo script
class _DemoStep {
  final GlobalKey key;
  final String text;
  final Alignment alignment;
  final VoidCallback? onBefore;
  final bool hideNextButton;

  _DemoStep({
    required this.key,
    required this.text,
    required this.alignment,
    this.onBefore,
    this.hideNextButton = false,
  });
}

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

  // <<< ADDED >>> State for the new suggested pay notice
  bool _showSuggestedPayNotice = false;
  double _suggestedPay = 0.0;

  static const String _keyMinHourlyRate = 'profile_min_hourly_rate';
  static const String _keyGigsList = 'gigs_list';

  final _payFocusNode = FocusNode();
  final _gigTimeFocusNode = FocusNode();
  final _driveSetupTimeFocusNode = FocusNode();
  final _rehearsalTimeFocusNode = FocusNode();

  // GlobalKeys for each demo step target
  final GlobalKey _payKey = GlobalKey();
  final GlobalKey _gigTimeKey = GlobalKey();
  final GlobalKey _driveTimeKey = GlobalKey();
  final GlobalKey _rehearsalTimeKey = GlobalKey();
  final GlobalKey _calculateBtnKey = GlobalKey();
  final GlobalKey _rateResultKey = GlobalKey();
  final GlobalKey _takeGigBtnKey =
  GlobalKey(); // <<< 1. ADD KEY FOR "TAKE GIG" BUTTON

  late final List<_DemoStep> _demoScript;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _loadUserMinHourlyRate();

    // <<< ADDED >>> Listen to time fields to calculate suggested pay automatically
    _gigTimeController.addListener(_calculateSuggestedPay);
    _driveSetupTimeController.addListener(_calculateSuggestedPay);
    _rehearsalTimeController.addListener(_calculateSuggestedPay);

    _demoScript = [
      // Steps 1-5 are unchanged
      _DemoStep(
        key: _payKey,
        text:
        'Hey there! Welcome!\n Let\'s cover some basics. First, we enter the total pay for the gig. For this demo, we\'ll use \$250.',
        alignment: Alignment.center,
        onBefore: () {
          _payController.text = '250';
          _gigTimeController.text = '3';
          _driveSetupTimeController.text = '2.5';
          _rehearsalTimeController.text = '2';
        },
      ),
      _DemoStep(
        key: _gigTimeKey,
        text:
        'Next, input the actual length of the performance in hours. Let\'s say it\'s a 3-hour gig.',
        alignment: Alignment.bottomCenter,
      ),
      _DemoStep(
        key: _driveTimeKey,
        text:
        'This is for all the unpaid time spent driving, loading in, setting up, and sound check. We\'ll estimate 2.5 hours.',
        alignment: Alignment.bottomCenter,
      ),
      _DemoStep(
        key: _rehearsalTimeKey,
        text:
        'Finally, add any unpaid rehearsal time for this specific gig. Let\'s add 2 hours.',
        alignment: Alignment.bottomCenter,
      ),
      _DemoStep(
        key: _calculateBtnKey,
        text: 'Now, click that Calculate button.',
        alignment: Alignment.topCenter,
        hideNextButton: true,
      ),
      _DemoStep(
        key: _rateResultKey,
        text:
        'There it is! Your rate isn\'t what you get for playing; it\'s what you earn for all the work involved. Your time is valuable! You can use this to negotiate.',
        alignment: Alignment.topCenter,
      ),
      // <<< 2. ADD STEP 7 FOR "TAKE THIS GIG" BUTTON >>>
      _DemoStep(
        key: _takeGigBtnKey,
        text: 'Now, let\'s book this gig! Tap here to open the booking dialog.',
        alignment: Alignment.center,
        hideNextButton: true, // User must click the real button
      ),
    ];

    if (_googleApiKey.isEmpty) {
      print(
          "CRITICAL WARNING (GigCalculator): GOOGLE_API_KEY is not defined. Geocoding will fail.");
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _payController.dispose();
    _gigTimeController.dispose();
    _driveSetupTimeController.dispose();
    _rehearsalTimeController.dispose();

    // <<< MODIFIED >>> Also remove the new listeners
    _gigTimeController.removeListener(_calculateSuggestedPay);
    _driveSetupTimeController.removeListener(_calculateSuggestedPay);
    _rehearsalTimeController.removeListener(_calculateSuggestedPay);

    _payFocusNode.dispose();
    _gigTimeFocusNode.dispose();
    _driveSetupTimeFocusNode.dispose();
    _rehearsalTimeFocusNode.dispose();
    super.dispose();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // When the user returns to the app (or this page), reload the rate.
    if (state == AppLifecycleState.resumed) {
      _loadUserMinHourlyRate();
    }
  }

  Future<void> _loadUserMinHourlyRate() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _userMinHourlyRate = prefs.getInt(_keyMinHourlyRate)?.toDouble();
      // Recalculate the suggested pay with the potentially new rate
      _calculateSuggestedPay();
    });
  }

  // <<< ADDED >>> New function to calculate suggested pay and show/hide the notice
  void _calculateSuggestedPay() {
    // We must have a minimum rate from the user's profile
    if (_userMinHourlyRate == null || _userMinHourlyRate! <= 0) {
      if (_showSuggestedPayNotice) {
        setState(() => _showSuggestedPayNotice = false);
      }
      return;
    }

    final gigTime = double.tryParse(_gigTimeController.text) ?? 0;
    final driveTime = double.tryParse(_driveSetupTimeController.text) ?? 0;
    final rehearsalTime = double.tryParse(_rehearsalTimeController.text) ?? 0;

    // Condition: Gig Time > 0 AND (Drive Time > 0 OR Rehearsal Time > 0)
    final bool shouldShow = gigTime > 0 && (driveTime > 0 || rehearsalTime > 0);

    if (shouldShow) {
      final totalHours = gigTime + driveTime + rehearsalTime;
      final newSuggestedPay = totalHours * _userMinHourlyRate!;
      setState(() {
        _suggestedPay = newSuggestedPay;
        _showSuggestedPayNotice = true;
      });
    } else {
      // If conditions are not met, ensure the notice is hidden
      if (_showSuggestedPayNotice) {
        setState(() => _showSuggestedPayNotice = false);
      }
    }
  }

  void _clearAllInputFields() {
    FocusScope.of(context).unfocus();
    _payController.clear();
    _gigTimeController.clear();
    _driveSetupTimeController.clear();
    _rehearsalTimeController.clear();
    if (mounted) {
      setState(() {
        _hourlyRateResult = "";
        _showTakeGigButton = false;
        _showSuggestedPayNotice = false; // <<< MODIFIED >>> Hide notice on clear
      });
    }
  }

  Future<void> _performCalculation() async {
    FocusScope.of(context).unfocus();
    await _loadUserMinHourlyRate();

    if (!mounted) return;

    String newHourlyRateResult = "";
    String newCurrentHourlyRateString = "";
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
      final double totalHoursForRateCalc =
          gigTime + driveSetupTime + rehearsalTime;

      if (totalHoursForRateCalc > 0 && pay > 0) {
        final double calculatedRate = pay / totalHoursForRateCalc;
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
        newCurrentGigLengthHours = gigTime;
        newCurrentDriveSetupHours = driveSetupTime;
        newCurrentRehearsalHours = rehearsalTime;
      } else {
        String errorMessage = "";
        if (pay <= 0 && totalHoursForRateCalc > 0) {
          errorMessage = 'Please provide the Pay for the Gig.';
        } else if (pay > 0 && totalHoursForRateCalc <= 0) {
          errorMessage =
          'We need some hours to divide the pay to get your rate.';
        } else {
          errorMessage = 'Enter the pay and time(s) for the rate calculation.';
        }
        newHourlyRateResult = errorMessage;
        newRateResultColor = Colors.lightBlue.shade200;
        newShowTakeGigButton = false;
      }
    } else {
      newHourlyRateResult = 'Please provide the Pay for the Gig.';
      newRateResultColor = Colors.lightBlue.shade200;
      newShowTakeGigButton = false;
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

    final demoProvider = Provider.of<DemoProvider>(context, listen: false);
    if (demoProvider.isDemoModeActive && demoProvider.currentStep == 5) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        demoProvider.nextStep();
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
      if (mounted) {
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

  // <<< 3. MODIFY _showBookingDialog TO BE DEMO-AWARE >>>
  Future<void> _showBookingDialog() async {
    final demoProvider = Provider.of<DemoProvider>(context, listen: false);

    // If in demo mode and on the correct step, advance the demo.
    if (demoProvider.isDemoModeActive && demoProvider.currentStep == 7) {
      demoProvider.nextStep(); // Advance to step 8, which the dialog will handle
    }

    if (!_showTakeGigButton ||
        _currentHourlyRateString.isEmpty ||
        _currentPay <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please calculate valid gig details first.')));
      return;
    }
    if (_googleApiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('API Key Missing. Booking new venues may fail.'),
          backgroundColor: Colors.redAccent));
    }

    List<Gig> allExistingGigs = await _loadAllGigsFromPreferences();
    if (!mounted) return;

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
          existingGigs: allExistingGigs.where((g) => !g.isJamOpenMic).toList(),
          onNewVenuePotentiallyAdded: () async {},
        );
      },
    );

    if (!mounted) return;

    // Handle the result - works for both normal gigs and demo gigs
    if (result != null && result.action == GigEditResultAction.updated && result.gig != null) {
      final bookedGig = result.gig!;
      await _saveBookedGigToList(bookedGig);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${bookedGig.venueName} gig booked!'),
            backgroundColor: Colors.green),
      );
      _clearAllInputFields();

      // CRITICAL: Do NOT end demo here!
      // The demo needs to continue to steps 12 (Venues tab), 13 (My Gigs tab), and 14 (final message)
      // The demo will end naturally at step 14 when the user clicks FINISH in main.dart

    } else {
      // User cancelled the dialog
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking cancelled.')),
      );

      // Only end the demo if the user explicitly cancels
      if (demoProvider.isDemoModeActive) {
        print('🎬 Calculator: User cancelled during demo, ending demo');
        demoProvider.endDemo();
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

  Widget _buildDemoOverlay(DemoProvider demoProvider) {
    int currentStepIndex = demoProvider.currentStep - 1;

    // This page only handles steps 1-7.
    if (currentStepIndex < 0 || currentStepIndex >= 7) {
      return const SizedBox.shrink();
    }

    final step = _demoScript[currentStepIndex];

    if (step.onBefore != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        step.onBefore!();
      });
    }

    return TutorialOverlay(
      key: ValueKey('demo_step_$currentStepIndex'),
      highlightKey: step.key,
      instructionalText: step.text,
      textAlignment: step.alignment,
      hideNextButton: step.hideNextButton,
      onNext: () {
        if (currentStepIndex == _demoScript.length - 1) {
          demoProvider.endDemo();
        } else {
          demoProvider.nextStep();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DemoProvider>(
      builder: (context, demoProvider, child) {
        return Stack(
          children: [
            _buildCalculatorUI(context),
            if (demoProvider.isDemoModeActive) _buildDemoOverlay(demoProvider),
          ],
        );
      },
    );
  }

  Widget _buildCalculatorUI(BuildContext context) {
    //_loadUserMinHourlyRate();

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
        if (!currentFocus.hasPrimaryFocus &&
            currentFocus.focusedChild != null) {
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
                const Padding(
                  padding: EdgeInsets.fromLTRB(8.0, 0.0, 8.0, 24.0),
                  child: Text(
                    "Your pay data is stored on your device only and never shared.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                        fontStyle: FontStyle.italic),
                  ),
                ),
                Container(
                  key: _payKey,
                  child: TextFormField(
                    controller: _payController,
                    focusNode: _payFocusNode,
                    style: TextStyle(color: formTextColor, fontSize: 16),
                    decoration: formInputDecoration(
                        labelText: 'Pay',
                        hintText: 'Ask: What\'s your budget?',
                        icon: Icons.attach_money),
                    keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                    validator: _validatePay,
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) =>
                        FocusScope.of(context).requestFocus(_gigTimeFocusNode),
                  ),
                ),
                const SizedBox(height: 16.0),

                // <<< ADDED >>> The Suggested Pay Notice Widget
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

                Container(
                  key: _gigTimeKey,
                  child: TextFormField(
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
                ),
                const SizedBox(height: 16.0),
                Container(
                  key: _driveTimeKey,
                  child: TextFormField(
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
                ),
                const SizedBox(height: 16.0),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Container(
                        key: _rehearsalTimeKey,
                        child: TextFormField(
                          controller: _rehearsalTimeController,
                          focusNode: _rehearsalTimeFocusNode,
                          style: TextStyle(color: formTextColor, fontSize: 16),
                          decoration: formInputDecoration(
                              labelText: 'Rehearsal Time (hours)',
                              hintText: 'e.g., 2',
                              icon: Icons.music_note_outlined),
                          keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                          validator: (value) =>
                              _validateTime(value, 'Rehearsal Time'),
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _performCalculation(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12.0),
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: ElevatedButton(
                        key: _calculateBtnKey,
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
                if (_hourlyRateResult.isNotEmpty)
                  Padding(
                    key: _rateResultKey,
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
                        // <<< 4. ASSIGN THE KEY TO THE "TAKE THIS GIG" BUTTON'S PARENT >>>
                        Expanded(
                          key: _takeGigBtnKey,
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
                            onPressed: _clearAllInputFields,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}