import 'package:flutter/foundation.dart';

void log(String message) {
  if (kDebugMode) {
    print(message);
  }
}