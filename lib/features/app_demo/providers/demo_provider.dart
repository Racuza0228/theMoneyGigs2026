// lib/features/app_demo/providers/demo_provider.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DemoProvider with ChangeNotifier {
  static const String _demoCompletionFlag = 'hasCompletedFirstLaunchDemo';

  bool _isDemoModeActive = false;
  int _currentStep = 0;

  bool get isDemoModeActive => _isDemoModeActive;
  int get currentStep => _currentStep;

  DemoProvider() {
    _checkFirstLaunch();
  }

  // This checks if the demo should start when the app opens.
  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final bool hasCompletedDemo = prefs.getBool(_demoCompletionFlag) ?? false;

    if (!hasCompletedDemo) {
      // A small delay allows the initial UI to build before starting the demo.
      await Future.delayed(const Duration(seconds: 2));
      startDemo();
    }
  }

  void startDemo() {
    if (_isDemoModeActive) return; // Don't restart if already active
    _isDemoModeActive = true;
    _currentStep = 1;
    print("DEMO STARTED: Step 1");
    notifyListeners();
  }

  void nextStep() {
    if (!_isDemoModeActive) return;
    _currentStep++;
    print("DEMO PROGRESSED: Now on step $_currentStep");
    notifyListeners();
  }

  Future<void> endDemo() async {
    if (!_isDemoModeActive) return;
    _isDemoModeActive = false;
    _currentStep = 0;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_demoCompletionFlag, true);

    print("DEMO ENDED and flag set to true.");
    notifyListeners();
  }

  // Utility to reset the demo for testing purposes
  Future<void> resetDemoFlagForTesting() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_demoCompletionFlag, false);
    print("DEMO FLAG RESET: The demo will run on next app launch.");
  }
}
