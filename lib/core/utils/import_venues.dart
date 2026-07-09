import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:the_money_gigs/core/utils/add_venues.dart';
import 'package:the_money_gigs/firebase_options.dart';
import 'package:the_money_gigs/core/utils/logger.dart';

void main(List<String> args) async {
  // 1. Initialize Flutter and Firebase
  WidgetsFlutterBinding.ensureInitialized();

  // --- START OF SIMPLIFIED FIX ---
  // 2. Read arguments directly from the 'args' list.
  // Correct Usage: flutter run lib/core/utils/import_venues.dart -- "Your City, ST"

  log("Received arguments: $args"); // For debugging

  // If args is not empty, use it. Otherwise, use the default.
  String region = args.isNotEmpty ? args.join(' ') : "East York, Canada" ; // Changed default for clarity
//Marquette Park, Evergreen Park
  log("\n==============================");
  log("INITIATING FIREBASE...");

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final venueService = VenueDiscoveryService();
  // await venueService.deleteSystemVenues();
  log("STARTING SEARCH FOR: $region");
  log("==============================\n");

  try {
    await venueService.syncLiveMusicVenues(region);
    log("\nSUCCESS: Sync process finished.");
  } catch (e) {
    log("\nFAILED: $e");
  }

  // Graceful shutdown for the macOS app window
  log("\nShutting down in 2 seconds...");
  await Future.delayed(const Duration(seconds: 2));
  exit(0);
}