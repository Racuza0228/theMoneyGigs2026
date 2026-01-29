import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:the_money_gigs/core/utils/add_venues.dart';
import 'package:the_money_gigs/firebase_options.dart';

void main(List<String> args) async {
  // 1. Initialize Flutter and Firebase
  WidgetsFlutterBinding.ensureInitialized();

  // --- START OF SIMPLIFIED FIX ---
  // 2. Read arguments directly from the 'args' list.
  // Correct Usage: flutter run lib/core/utils/import_venues.dart -- "Your City, ST"

  print("Received arguments: $args"); // For debugging

  // If args is not empty, use it. Otherwise, use the default.
  String region = args.isNotEmpty ? args.join(' ') : "Thompsonville, MI"; // Changed default for clarity

  print("\n==============================");
  print("INITIATING FIREBASE...");

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final venueService = VenueDiscoveryService();
  // await venueService.deleteSystemVenues();
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