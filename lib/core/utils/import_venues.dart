import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:the_money_gigs/core/utils/add_venues.dart';
import 'package:the_money_gigs/firebase_options.dart';

void main(List<String> args) async {
  // 1. Initialize Flutter and Firebase
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Determine the region from arguments or default
  // Usage: flutter run lib/core/utils/cli_sync.dart -d macos --args="Langhorne, PA"
  String region = args.isNotEmpty ? args.join(' ') : "Langhorne, PA";

  print("\n==============================");
  print("INITIATING FIREBASE...");

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final venueService = VenueDiscoveryService();
  await venueService.deleteSystemVenues();
  print("STARTING SEARCH FOR: $region");
  print("==============================\n");

  try {
    await venueService.syncLiveMusicVenues(region);
    print("\nSUCCESS: Sync process finished.");
  } catch (e) {
    print("\nFAILED: $e");
  }

  // Graceful shutdown for the macOS app window
  print("\nShutting down in 2 seconds...");
  await Future.delayed(const Duration(seconds: 2));
  exit(0);
}