import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  print("\n\n--- SharedPreferences Inspector ---");
  if (shouldExport) {
    print("EXPORT MODE: ENABLED. Data will be saved to a file.");
  }
  print("Initializing...");

  try {
    final prefs = await SharedPreferences.getInstance();
    final allKeys = prefs.getKeys();

    if (allKeys.isEmpty) {
      print("\nRESULT: SharedPreferences is completely empty.");
      print("-------------------------------------\n\n");
      return;
    }

    print("\nFound ${allKeys.length} keys. Dumping all data:\n");
    final Map<String, dynamic> allData = {};

    for (final key in allKeys) {
      final value = prefs.get(key);
      allData[key] = value; // Store for export

      print("======================================================");
      print("🔑 KEY: '$key'");
      print("------------------------------------------------------");
      print("TYPE: ${value.runtimeType}");
      print("------------------------------------------------------");

      if (value is String && (value.trim().startsWith('{') || value.trim().startsWith('['))) {
        try {
          final prettyJson = const JsonEncoder.withIndent('  ').convert(json.decode(value));
          print("DECODED JSON VALUE:\n$prettyJson");
        } catch (e) {
          print("RAW STRING VALUE (JSON decoding failed): \n$value");
        }
      } else if (value is List<String>) {
        print("LIST<String> VALUE:");
        // Pretty-print each JSON string in the list
        for (int i = 0; i < value.length; i++) {
          try {
            final itemJson = json.decode(value[i]);
            final prettyItem = const JsonEncoder.withIndent('    ').convert(itemJson);
            print("  [$i]:\n$prettyItem");
          } catch(e) {
            print("  [$i]: ${value[i]} (not valid JSON)");
          }
        }
      } else {
        print("RAW VALUE: \n$value");
      }
      print("======================================================\n");
    }

    // if (shouldExport) {
    //   final String timestamp = DateFormat('MMddyy').format(DateTime.now());
    //   final String filename = 'moneygigs_$timestamp.json';
    //   final file = File(filename);
    //   final String jsonContent = const JsonEncoder.withIndent('  ').convert(allData);
    //
    //   await file.writeAsString(jsonContent);
    //   print("✅ SUCCESS: All SharedPreferences data exported to '$filename'");
    //   print("   File location: ${file.absolute.path}\n");
    // }

  } catch (e, s) {
    print("\n\nCRITICAL ERROR: Failed to access SharedPreferences.");
    print("Error details: $e");
    print("Stack Trace: $s");
  } finally {
    print("--- Inspection Complete ---\n\n");
  }
}
