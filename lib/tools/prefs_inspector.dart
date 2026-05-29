import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/core/utils/logger.dart';

// This is a standalone command-line tool to inspect SharedPreferences.
//
// To run and print to console:
// flutter run lib/tools/prefs_inspector.dart
//
// To run and also export to a file (e.g., moneygigs_111825.json):
// flutter run lib/tools/prefs_inspector.dart --dart-define=EXPORT_JSON=true

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Check for the export flag
  const bool shouldExport = bool.fromEnvironment('EXPORT_JSON');

  log("\n\n--- SharedPreferences Inspector ---");
  if (shouldExport) {
    log("EXPORT MODE: ENABLED. Data will be saved to a file.");
  }
  log("Initializing...");

  try {
    final prefs = await SharedPreferences.getInstance();
    final allKeys = prefs.getKeys();

    if (allKeys.isEmpty) {
      log("\nRESULT: SharedPreferences is completely empty.");
      log("-------------------------------------\n\n");
      return;
    }

    log("\nFound ${allKeys.length} keys. Dumping all data:\n");
    final Map<String, dynamic> allData = {};

    for (final key in allKeys) {
      final value = prefs.get(key);
      allData[key] = value; // Store for export

      log("======================================================");
      log("🔑 KEY: '$key'");
      log("------------------------------------------------------");
      log("TYPE: ${value.runtimeType}");
      log("------------------------------------------------------");

      if (value is String && (value.trim().startsWith('{') || value.trim().startsWith('['))) {
        try {
          final prettyJson = const JsonEncoder.withIndent('  ').convert(json.decode(value));
          log("DECODED JSON VALUE:\n$prettyJson");
        } catch (e) {
          log("RAW STRING VALUE (JSON decoding failed): \n$value");
        }
      } else if (value is List<String>) {
        log("LIST<String> VALUE:");
        // Pretty-print each JSON string in the list
        for (int i = 0; i < value.length; i++) {
          try {
            final itemJson = json.decode(value[i]);
            final prettyItem = const JsonEncoder.withIndent('    ').convert(itemJson);
            log("  [$i]:\n$prettyItem");
          } catch(e) {
            log("  [$i]: ${value[i]} (not valid JSON)");
          }
        }
      } else {
        log("RAW VALUE: \n$value");
      }
      log("======================================================\n");
    }

    // if (shouldExport) {
    //   final String timestamp = DateFormat('MMddyy').format(DateTime.now());
    //   final String filename = 'moneygigs_$timestamp.json';
    //   final file = File(filename);
    //   final String jsonContent = const JsonEncoder.withIndent('  ').convert(allData);
    //
    //   await file.writeAsString(jsonContent);
    //   log("✅ SUCCESS: All SharedPreferences data exported to '$filename'");
    //   log("   File location: ${file.absolute.path}\n");
    // }

  } catch (e, s) {
    log("\n\nCRITICAL ERROR: Failed to access SharedPreferences.");
    log("Error details: $e");
    log("Stack Trace: $s");
  } finally {
    log("--- Inspection Complete ---\n\n");
  }
}
