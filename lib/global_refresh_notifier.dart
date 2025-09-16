// lib/global_refresh_notifier.dart
import 'package:flutter/material.dart';

class GlobalRefreshNotifier extends ChangeNotifier {
  void notify() {
    notifyListeners();
  }
}

// Optional: You can make it a global instance for easy access,
// though using Provider is cleaner for dependency injection.
// For simplicity here, a global instance:
final GlobalRefreshNotifier globalRefreshNotifier = GlobalRefreshNotifier();